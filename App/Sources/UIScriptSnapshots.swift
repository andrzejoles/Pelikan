import AppKit
import WebKit

#if DEBUG
/// Zrzuty okien w procesie dla przebiegu zrzutów (D196): okna są niewidoczne (UIScriptWindows.m), więc zamiast
/// `screencapture` aplikacja rysuje ramkę każdego okna (pasek tytułu, pasek narzędzi, wstążka, widoki SwiftUI i TextKit 2)
/// do mapy bitowej, a treść WKWebView dokłada z `takeSnapshot`. Nazwy plików jak dotąd w scripts/screenshots.sh:
/// `<przedrostek>-<tytuł okna>.png`, okno główne — „glowne”, powtórzony tytuł dostaje numer.
enum UIScriptSnapshots {
    /// Pliki zapisane w tym przebiegu — powtórzony tytuł okna dostaje numer zamiast nadpisać plik.
    private static var written: Set<String> = []

    /// Okna jak w liście okien procesu dla `screencapture`: zwykły poziom, z tytułem, większe niż 200×150 pt, od przodu.
    static func windows() -> [NSWindow] {
        NSApp.windows
            .filter { $0.isVisible && $0.level == .normal && !$0.title.isEmpty && $0.frame.width > 200 && $0.frame.height > 150 }
            .sorted { $0.orderedIndex < $1.orderedIndex }
    }

    /// Nazwa pliku z tytułu okna: bez znaków diakrytycznych, małe litery, myślniki (jak `slug` w scripts/screenshots.sh).
    static func slug(_ title: String, main: Bool) -> String {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Pelikan"
        var t = main || title.hasPrefix(appName + " — ") ? "glowne" : title
        t = t.replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "Ł", with: "L")
        let ascii = String(String.UnicodeScalarView(t.decomposedStringWithCompatibilityMapping.unicodeScalars.filter(\.isASCII)))
        let s = ascii.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "okno" : s
    }

    /// Zrzuty wszystkich okien do `<przedrostek>-<tytuł>.png`; zwraca linie „plik  tytuł  szer×wys” do dziennika skryptu.
    static func snapshot(prefix: String, mainWindow: NSWindow?) async -> [String] {
        var lines: [String] = []
        for window in windows() {
            guard let png = await render(window) else { lines.append("zrzut nieudany: \(window.title)"); continue }
            let base = prefix + "-" + slug(window.title, main: window === mainWindow)
            var path = base + ".png"
            var n = 2
            while written.contains(path) { path = "\(base)-\(n).png"; n += 1 }
            written.insert(path)
            do {
                try png.write(to: URL(fileURLWithPath: path))
                lines.append("\((path as NSString).lastPathComponent)  \(window.title)  \(Int(window.frame.width))x\(Int(window.frame.height))")
            } catch {
                lines.append("zrzut \(path): \(error.localizedDescription)")
            }
        }
        return lines
    }

    /// PNG okna: widok ramki okna (z paskiem tytułu) przez `cacheDisplay`, WKWebView doklejone.
    static func render(_ window: NSWindow) async -> Data? {
        guard let content = window.contentView, let frameView = content.superview ?? Optional(content) else { return nil }
        frameView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bounds = frameView.bounds
        // Co najmniej 2× (jak na ekranie Retina) — obraz w dokumentacji nie zależy od monitora, na którym byłoby okno.
        let scale = max(window.backingScaleFactor, 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((bounds.width * scale).rounded()),
                                         pixelsHigh: Int((bounds.height * scale).rounded()), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .retagging(with: .sRGB)
        else { return nil }
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)
        let webViews = webViews(in: frameView)
        guard !webViews.isEmpty, let base = rep.cgImage else { return rep.representation(using: .png, properties: [:]) }
        // WebKit rysuje w osobnym procesie — `cacheDisplay` zostawia w miejscu WKWebView puste pole.
        let space = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        for wv in webViews {
            guard let cg = await webSnapshot(wv) else { continue }
            let r = wv.convert(wv.bounds, to: nil)  // współrzędne okna = ramki okna, początek w lewym dolnym rogu
            ctx.draw(cg, in: CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale))
        }
        guard let out = ctx.makeImage() else { return nil }
        let outRep = NSBitmapImageRep(cgImage: out)
        outRep.size = rep.size  // ta sama gęstość (DPI) co zrzut bez WKWebView
        return outRep.representation(using: .png, properties: [:])
    }

    /// Treść WKWebView z limitem czasu — zawieszony proces WebKit nie może zatrzymać przebiegu zrzutów.
    private static func webSnapshot(_ webView: WKWebView, timeout: Duration = .seconds(5)) async -> CGImage? {
        let once = Once()
        return await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            once.continuation = cont
            webView.takeSnapshot(with: nil) { image, _ in
                MainActor.assumeIsolated { once.finish(image?.cgImage(forProposedRect: nil, context: nil, hints: nil)) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.finish(nil)
            }
        }
    }

    /// Kontynuacja wznawiana raz — przez zrzut albo przez limit czasu.
    private final class Once {
        var continuation: CheckedContinuation<CGImage?, Never>?
        func finish(_ image: CGImage?) {
            continuation?.resume(returning: image)
            continuation = nil
        }
    }

    private static func webViews(in view: NSView) -> [WKWebView] {
        guard !view.isHidden else { return [] }
        return (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
    }
}
#endif
