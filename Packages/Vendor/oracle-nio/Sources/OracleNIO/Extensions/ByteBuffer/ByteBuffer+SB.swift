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
// Zmienione dla Pelikana (2026-11): liczby SB ze znakiem i dowolnej długości jak w python-oracledb (PELIKAN.md).
//
//===----------------------------------------------------------------------===//

import NIOCore

extension ByteBuffer {
    /// Pelikan: liczba ze znakiem jak `read_sb*` w python-oracledb — znak w bicie 0x80 bajtu długości, wartość bez znaku
    /// (big endian) na pozostałej długości. Dawniej znak był gubiony, a wartość czytana jako liczba ze znakiem stałej
    /// szerokości (np. 200 jako −56, rozmiar LOB-a 40 000 jako ujemny), długości 3, 5–7 kończyły proces.
    mutating func readOracleSigned() -> Int64? {
        guard let raw = self.readInteger(as: UInt8.self) else { return nil }
        guard let magnitude = self.readOracleMagnitude(length: Int(raw & 0x7f)) else { return nil }
        let value = Int64(truncatingIfNeeded: magnitude)
        return raw & 0x80 != 0 ? 0 &- value : value
    }

    mutating func readSB2() -> Int16? {
        self.readOracleSigned().map { Int16(truncatingIfNeeded: $0) }
    }

    mutating func throwingReadSB2(
        file: String = #fileID, line: Int = #line
    ) throws -> Int16 {
        try self.readSB2().value(
            or: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<Int8>.size, actual: self.readableBytes,
                file: file, line: line
            )
        )
    }

    mutating func readSB4() -> Int32? {
        self.readOracleSigned().map { Int32(truncatingIfNeeded: $0) }
    }

    mutating func readSB8() -> Int64? {
        self.readOracleSigned()
    }

    mutating func throwingReadSB8(
        file: String = #fileID, line: Int = #line
    ) throws -> Int64 {
        try self.readSB8().value(
            or: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<Int8>.size, actual: self.readableBytes,
                file: file, line: line
            )
        )
    }

    mutating func throwingSkipSB4(file: String = #fileID, line: Int = #line) throws {
        try throwingSkipBytes(4, file: file, line: line)
    }
}
