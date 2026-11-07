//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// Zmienione dla Pelikana (2026-11): INTERVAL YEAR TO MONTH, UROWID i BFILE w danych wierszy; nieobsługiwany typ
// zgłasza błąd dekodowania zamiast fatalError (PELIKAN.md).
//
//===----------------------------------------------------------------------===//

import NIOConcurrencyHelpers
import NIOCore

extension OracleBackendMessage {
    struct RowData: PayloadDecodable, Sendable, Hashable {
        var columns: [ColumnStorage]

        enum ColumnStorage: Sendable, Hashable {
            case data(ByteBuffer)
            case duplicate(Int)
        }

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> RowData {
            guard let statementContext = context.statementContext else {
                preconditionFailure(
                    "RowData cannot be received without having a \(String(reflecting: StatementContext.self))"
                )
            }

            let describeInfo =
                switch context.statementContext?.type {
                case .cursor(let describeInfo, _, _):
                    describeInfo
                default:
                    context.describeInfo
                }

            let columns: [ColumnStorage]
            if let describeInfo {
                columns = try self.processRowData(
                    from: &buffer,
                    describeInfo: describeInfo,
                    context: context
                )
            } else {
                columns = try self.processBindRow(
                    from: &buffer,
                    statementContext: statementContext,
                    capabilities: context.capabilities
                )
            }

            return .init(columns: columns)
        }

        private static func isDuplicateData(
            columnNumber: UInt32, bitVector: [UInt8]?
        ) -> Bool {
            guard let bitVector else { return false }
            let byteNumber = columnNumber / 8
            let bitNumber = columnNumber % 8
            return bitVector[Int(byteNumber)] & (1 << bitNumber) == 0
        }

        private static func processRowData(
            from buffer: inout ByteBuffer,
            describeInfo: DescribeInfo,
            context: OracleBackendMessageDecoder.Context
        ) throws -> [ColumnStorage] {
            var columns = [ColumnStorage]()
            columns.reserveCapacity(describeInfo.columns.count)
            for (index, column) in describeInfo.columns.enumerated() {
                if self.isDuplicateData(
                    columnNumber: UInt32(index),
                    bitVector: context.bitVector
                ) {
                    columns.append(.duplicate(index))
                } else {
                    let data = try self.processColumnData(
                        from: &buffer,
                        oracleType: column.dataType._oracleType,
                        csfrm: column.dataType.csfrm,
                        bufferSize: column.bufferSize,
                        forBind: false,
                        capabilities: context.capabilities
                    )
                    columns.append(.data(data))
                }
            }

            // reset bit vector after usage
            context.bitVector = nil
            return columns
        }

        /// Pelikan: wartość kolumny w postaci czytanej przez `DataRow` — długość w bajcie albo porcje (UInt32) po
        /// `TNS_LONG_LENGTH_INDICATOR` dla dłuższych (UROWID do 5267 znaków, lokator BFILE z długą nazwą pliku).
        static func writeColumnValue(_ bytes: [UInt8], into buffer: inout ByteBuffer) {
            if bytes.count < Int(Constants.TNS_LONG_LENGTH_INDICATOR) {
                buffer.writeInteger(UInt8(bytes.count))
                buffer.writeBytes(bytes)
            } else {
                buffer.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
                buffer.writeInteger(UInt32(bytes.count))
                buffer.writeBytes(bytes)
                buffer.writeInteger(UInt32(0))  // chunk length of zero
            }
        }

        /// Pelikan: tekst UROWID z postaci binarnej — fizyczny (bajt 1) jak ROWID, logiczny jako „*” i base64 bez
        /// dopełnienia (python-oracledb `read_urowid`).
        static func uRowIDText(_ raw: [UInt8]) throws -> String {
            guard let kind = raw.first else {
                throw OraclePartialDecodingError.fieldNotDecodable(type: RowID.self)
            }
            if kind == 1 {
                guard raw.count >= 13 else {
                    throw OraclePartialDecodingError.fieldNotDecodable(type: RowID.self)
                }
                func be(_ range: Range<Int>) -> UInt32 { raw[range].reduce(0) { $0 << 8 | UInt32($1) } }
                guard
                    let rowID = RowID(
                        rba: be(1..<5), partitionID: UInt16(be(5..<7)), blockNumber: be(7..<11),
                        slotNumber: UInt16(be(11..<13)))
                else {
                    throw OraclePartialDecodingError.fieldNotDecodable(type: RowID.self)
                }
                return rowID.description
            }
            let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
            var out: [UInt8] = [UInt8(ascii: "*")]
            var i = 1
            while i < raw.count {
                let b0 = raw[i]
                out.append(alphabet[Int(b0 >> 2)])
                guard i + 1 < raw.count else {
                    out.append(alphabet[Int((b0 & 0x3) << 4)])
                    break
                }
                let b1 = raw[i + 1]
                out.append(alphabet[Int((b0 & 0x3) << 4 | b1 >> 4)])
                guard i + 2 < raw.count else {
                    out.append(alphabet[Int((b1 & 0xf) << 2)])
                    break
                }
                let b2 = raw[i + 2]
                out.append(alphabet[Int((b1 & 0xf) << 2 | b2 >> 6)])
                out.append(alphabet[Int(b2 & 0x3f)])
                i += 3
            }
            return String(decoding: out, as: UTF8.self)
        }

        private static func processColumnData(
            from buffer: inout ByteBuffer,
            oracleType: _TNSDataType?,
            csfrm: UInt8,
            bufferSize: UInt32,
            forBind: Bool,
            capabilities: Capabilities
        ) throws -> ByteBuffer {
            var columnValue: ByteBuffer
            if bufferSize == 0 && ![.long, .longRAW, .uRowID].contains(oracleType) {
                columnValue = ByteBuffer(bytes: [0])  // NULL indicator
                return columnValue
            }

            if [.varchar, .char, .long].contains(oracleType) {
                if csfrm == Constants.TNS_CS_NCHAR {
                    try capabilities.checkNCharsetID()
                }
                // if we need capabilities during decoding in the future, we should
                // move this to decoding too
            }

            switch oracleType {
            case .varchar, .char, .long, .raw, .longRAW, .number, .date, .timestamp,
                .timestampLTZ, .timestampTZ, .binaryDouble, .binaryFloat,
                .binaryInteger, .boolean, .intervalDS, .intervalYM:
                switch buffer.readOracleSlice() {
                case .some(let slice):
                    columnValue = slice
                case .none:
                    throw MissingDataDecodingError.Trigger()
                }
            case .rowID:
                if forBind {
                    let value = try buffer.readString()
                    let rowID = RowID(value)
                    columnValue = ByteBuffer()
                    try columnValue.writeLengthPrefixed(as: UInt8.self) {
                        $0.writeString(rowID.description)
                    }
                } else {
                    // length is not the actual length of row ids
                    let length = try buffer.throwingReadInteger(as: UInt8.self)
                    if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
                        columnValue = ByteBuffer(bytes: [0])  // NULL indicator
                    } else {
                        columnValue = ByteBuffer()
                        if let rowID = try RowID(fromWire: &buffer) {
                            try columnValue.writeLengthPrefixed(as: UInt8.self) {
                                $0.writeString(rowID.description)
                            }
                        } else {
                            columnValue = ByteBuffer(bytes: [0])  // NULL indicator
                        }
                    }
                }
            case .uRowID:
                // Pelikan: UROWID (ROWID tabel IOT i obcych) jak `read_urowid` w python-oracledb.
                if forBind {
                    switch buffer.readOracleSlice() {  // tekst
                    case .some(let slice):
                        columnValue = slice
                    case .none:
                        throw MissingDataDecodingError.Trigger()
                    }
                } else {
                    // pierwsza porcja zawiera długość (pomijana), druga — wartość; obie w postaci z sieci (porcje UB4)
                    let first = try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                    if first.readableBytes == 0 {
                        columnValue = ByteBuffer(bytes: [0])  // NULL indicator
                    } else {
                        let raw = Array(buffer: try buffer.throwingReadOracleSpecificLengthPrefixedSlice())
                        columnValue = ByteBuffer()
                        Self.writeColumnValue(Array(try Self.uRowIDText(raw).utf8), into: &columnValue)
                    }
                }
            case .bfile:
                // Pelikan: lokator BFILE — jak CLOB/BLOB, ale bez rozmiaru i wielkości porcji (python-oracledb
                // `read_lob_with_length`); w wartości kolumny rozmiar 0 i porcja 0 (LOB bez metadanych).
                let length = try buffer.throwingReadUB4()
                if length > 0 {
                    let locator = Array(buffer: try buffer.throwingReadOracleSpecificLengthPrefixedSlice())
                    // jak czyta `LOB.init(from:type:context:)`: rozmiar, porcja, lokator z długością (porcje UB4)
                    var value = ByteBuffer()
                    value.writeInteger(UInt64(0))
                    value.writeInteger(UInt32(0))
                    if locator.count < Int(Constants.TNS_LONG_LENGTH_INDICATOR) {
                        value.writeInteger(UInt8(locator.count))
                        value.writeBytes(locator)
                    } else {
                        value.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
                        value.writeUB4(UInt32(locator.count))
                        value.writeBytes(locator)
                        value.writeUB4(0)
                    }
                    columnValue = ByteBuffer()
                    Self.writeColumnValue(Array(buffer: value), into: &columnValue)
                } else {
                    columnValue = .init(bytes: [0])  // empty buffer
                }
            case .cursor:
                buffer.moveReaderIndex(forwardBy: 1)  // length (fixed value)

                let readerIndex = buffer.readerIndex
                _ = try DescribeInfo._decode(
                    from: &buffer, context: .init(capabilities: capabilities)
                )
                try buffer.throwingSkipUB2()  // cursor id
                let length = buffer.readerIndex - readerIndex
                buffer.moveReaderIndex(to: readerIndex)
                columnValue = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
                try columnValue.writeLengthPrefixed(as: UInt32.self) { base in
                    let start = base.writerIndex
                    try capabilities.encode(into: &base)
                    base.writeImmutableBuffer(buffer.readSlice(length: length)!)
                    return base.writerIndex - start
                }
                columnValue.writeInteger(0, as: UInt32.self)  // chunk length of zero
            case .clob, .blob:

                // LOB has a UB4 length indicator instead of the usual UInt8
                let length = try buffer.throwingReadUB4()
                if length > 0 {
                    let size = try buffer.throwingReadUB8()
                    let chunkSize = try buffer.throwingReadUB4()
                    var locator: ByteBuffer
                    switch buffer.readOracleSlice() {
                    case .some(let slice):
                        locator = slice
                    case .none:
                        throw MissingDataDecodingError.Trigger()
                    }
                    columnValue = ByteBuffer()
                    try columnValue.writeLengthPrefixed(as: UInt8.self) {
                        $0.writeInteger(size) + $0.writeInteger(chunkSize)
                            + $0.writeBuffer(&locator)
                    }
                } else {
                    columnValue = .init(bytes: [0])  // empty buffer
                }
            case .json:
                switch try buffer.throwingReadOSON() {
                case .some(let slice):
                    columnValue = slice
                case .none:
                    throw MissingDataDecodingError.Trigger()
                }
            case .vector:
                let length = try buffer.throwingReadUB4()
                if length > 0 {
                    try buffer.throwingSkipUB8()  // size (unused)
                    try buffer.throwingSkipUB4()  // chunk size (unused)
                    switch buffer.readOracleSlice() {
                    case .some(let slice):
                        columnValue = slice
                    case .none:
                        throw MissingDataDecodingError.Trigger()
                    }
                    if !buffer.skipRawBytesChunked() {  // LOB locator (unused)
                        throw MissingDataDecodingError.Trigger()
                    }
                } else {
                    columnValue = .init(bytes: [0])  // empty buffer
                }
            case .intNamed:
                let startIndex = buffer.readerIndex
                if try buffer.throwingReadUB4() > 0 {
                    if !buffer.skipRawBytesChunked() {  // type oid
                        throw MissingDataDecodingError.Trigger()
                    }
                }
                if try buffer.throwingReadUB4() > 0 {
                    if !buffer.skipRawBytesChunked() {  // oid
                        throw MissingDataDecodingError.Trigger()
                    }
                }
                if try buffer.throwingReadUB4() > 0 {
                    if !buffer.skipRawBytesChunked() {  // snapshot
                        throw MissingDataDecodingError.Trigger()
                    }
                }
                try buffer.throwingSkipUB2()  // version
                let dataLength = try buffer.throwingReadUB4()
                try buffer.throwingSkipUB2()  // flags
                if dataLength > 0 {
                    if !buffer.skipRawBytesChunked() {  // data
                        throw MissingDataDecodingError.Trigger()
                    }
                }
                let endIndex = buffer.readerIndex
                buffer.moveReaderIndex(to: startIndex)
                columnValue = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
                let length = (endIndex - startIndex) + (MemoryLayout<UInt32>.size * 2)
                columnValue.reserveCapacity(minimumWritableBytes: length)
                try columnValue.writeLengthPrefixed(as: UInt32.self) {
                    $0.writeImmutableBuffer(buffer.readSlice(length: endIndex - startIndex)!)
                }
                columnValue.writeInteger(0, as: UInt32.self)  // chunk length of zero
            default:
                // Pelikan: błąd dekodowania zamiast fatalError — biblioteka zamyka połączenie, proces działa dalej.
                guard let oracleType else {
                    throw OraclePartialDecodingError.fieldNotDecodable(type: _TNSDataType.self)
                }
                throw OraclePartialDecodingError.unsupportedDataType(type: oracleType)
            }

            if [.long, .longRAW].contains(oracleType) {
                try buffer.throwingSkipSB4()  // null indicator
                try buffer.throwingSkipUB4()  // return code
            }

            return columnValue
        }

        private static func processBindRow(
            from buffer: inout ByteBuffer,
            statementContext: StatementContext,
            capabilities: Capabilities
        ) throws -> [ColumnStorage] {
            let outBinds = statementContext.binds.metadata.compactMap(\.outContainer)
            guard !outBinds.isEmpty else { preconditionFailure() }
            var columns: [ColumnStorage] = []
            if statementContext.isReturning {
                for outBind in outBinds {
                    let rowCount = buffer.readUB4() ?? 0
                    if rowCount > 0 {
                        for _ in 0..<rowCount {
                            columns.append(
                                .data(
                                    try self.processBindData(
                                        from: &buffer,
                                        metadata: outBind.metadata.withLockedValue({ $0 }),
                                        capabilities: capabilities
                                    )))
                        }
                    } else {
                        // empty buffer
                        columns.append(.data(ByteBuffer(bytes: [0])))
                    }
                }
            } else {
                for outBind in outBinds {
                    columns.append(
                        .data(
                            try self.processBindData(
                                from: &buffer,
                                metadata: outBind.metadata.withLockedValue({ $0 }),
                                capabilities: capabilities
                            )))
                }
            }
            return columns
        }

        private static func processBindData(
            from buffer: inout ByteBuffer,
            metadata: OracleBindings.Metadata,
            capabilities: Capabilities
        ) throws -> ByteBuffer {
            let columnData = try self.processColumnData(
                from: &buffer,
                oracleType: metadata.dataType._oracleType,
                csfrm: metadata.dataType.csfrm,
                bufferSize: metadata.bufferSize,
                forBind: true,
                capabilities: capabilities
            )

            let actualBytesCount = buffer.readSB4() ?? 0
            if actualBytesCount < 0 && metadata.dataType._oracleType == .boolean {
                return ByteBuffer(bytes: [0])  // empty buffer
            } else if actualBytesCount != 0 && !columnData.oracleColumnIsEmpty {
                // TODO: throw this as error?
                preconditionFailure("column truncated, length: \(actualBytesCount)")
            }

            return columnData
        }
    }
}
