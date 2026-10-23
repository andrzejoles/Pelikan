import Foundation
import PelikanSQL
import QuickLookUI
import UniformTypeIdentifiers

/// Podgląd Quick Look plików SQL i PL/SQL z kolorami składni (MAC-QL-001): podgląd oparty na danych (HTML), bez
/// tekstów interfejsu. Duże pliki — pierwsze 2 MB (do końca linii).
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    static let limit = 2_000_000

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        var data = try Data(contentsOf: request.fileURL, options: .mappedIfSafe)
        if data.count > Self.limit {
            let head = data.prefix(Self.limit)
            data = Data(head.lastIndex(of: 0x0A).map { head[..<$0] } ?? head)
        }
        let html = CodeHTML.document(CodeHTML.decode(data), title: request.fileURL.lastPathComponent)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1000)) { _ in Data(html.utf8) }
    }
}
