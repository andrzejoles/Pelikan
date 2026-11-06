import AppKit
import PelikanSQL
import PelikanWorkspace
import SwiftUI

/// Podgląd kodu SQL i PL/SQL w oknach narzędzi (D218): kolorowanie składni jak w edytorze, widok sformatowany
/// (formater Pelikana z ustawieniami), kopiowanie i otwarcie w oknie SQL. Przełączniki wspólne dla wszystkich podglądów.
struct CodePreview: View {
    let text: String
    /// Okno SQL z tym tekstem (np. tekst zapytania sesji) — połączenie okna jak przy nowym oknie.
    var allowsOpen = true
    @AppStorage("codePreview.highlight") private var highlight = true
    @AppStorage("codePreview.formatted") private var formatted = false

    private var shown: String {
        guard formatted else { return text }
        let options = (NSApp.delegate as? AppDelegate)?.workspace.settings.beautifier ?? BeautifierOptions()
        return (try? Beautifier.format(text, options: options)) ?? text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Toggle(L10n.tr("Kolorowanie składni"), isOn: $highlight).toggleStyle(.checkbox)
                Toggle(L10n.tr("Sformatowany"), isOn: $formatted).toggleStyle(.checkbox)
                    .help(L10n.tr("Widok po formaterze Pelikana (Ustawienia › Formater); tekst w bazie bez zmian"))
                Spacer()
                Button { (NSApp.delegate as? AppDelegate)?.copyToClipboard(shown, html: nil) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).iconLabel(L10n.tr("Kopiuj"))
                if allowsOpen {
                    Button { openInSQLWindow() } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.borderless).iconLabel(L10n.tr("Otwórz w oknie SQL"))
                }
            }
            .controlSize(.small)
            .font(.uiSecondary)
            HighlightedCodeView(text: shown, highlight: highlight, schemeKey: Self.schemeKey)
        }
    }

    /// Motywy z ustawień (obserwowane przez SwiftUI) — zmiana motywu odświeża podgląd (D227).
    static var schemeKey: String {
        guard let st = (NSApp.delegate as? AppDelegate)?.workspace.settings else { return "" }
        return "\(st.syntaxSchemeLight)|\(st.syntaxSchemeDark)|\(st.customSyntaxSchemes.hashValue)|\(st.editorColors.hashValue)"
    }

    private func openInSQLWindow() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
        ws.perform("file.new.sql", CommandArguments(["text": .string(shown)]))
        ToolWindowController.showMainWindow()
    }
}

/// Tekst tylko do odczytu z kolorowaniem składni (NSTextView z `SyntaxHighlighter`), z zaznaczaniem i przewijaniem.
struct HighlightedCodeView: NSViewRepresentable {
    let text: String
    var highlight = true
    /// Motywy z ustawień; w kluczu odświeżenia razem z trybem systemu.
    var schemeKey = ""
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.isRichText = false
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 2, height: 3)
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.setAccessibilityLabel(L10n.tr("Kod"))
        }
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, let storage = tv.textStorage else { return }
        if let st = (NSApp.delegate as? AppDelegate)?.workspace.settings { SyntaxTheme.apply(st) }
        let key = "\(highlight)|\(schemeKey)|\(colorScheme)|\(SyntaxTheme.current.id)|\(text)"
        guard context.coordinator.last != key else { return }
        context.coordinator.last = key
        let font = InterfaceFonts.shared.code
        storage.setAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.textColor]))
        if highlight {
            SyntaxHighlighter().highlightAll(storage, font: font)
            // Przy zmianie trybu systemu SwiftUI odświeża widok, zanim tryb aplikacji (kroje z SyntaxTheme.current) jest
            // nowy — drugie kolorowanie po bieżącym obiegu pętli.
            DispatchQueue.main.async { [weak storage] in
                guard let storage, storage.string == text else { return }
                SyntaxHighlighter().highlightAll(storage, font: font)
            }
        }
        // Tło motywu (D227) — kolory jasnego motywu na tle ciemnego okna byłyby nieczytelne.
        tv.drawsBackground = highlight && SyntaxTheme.hasBackground
        tv.backgroundColor = SyntaxTheme.background
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var last = ""
    }
}
