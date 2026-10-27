import AppKit
import PelikanWorkspace
import SwiftUI

/// Wielowierszowe pole kodu w SwiftUI zamiast `TextEditor`, który dziedziczy systemowe podstawienia (inteligentne
/// cudzysłowy i myślniki, zamiana tekstu, autokorekta): `'abc'` stawało się `‘abc’` (ORA-00911), `--` — „—” (R4-07).
/// Bez podstawień, jak edytor kodu; czcionka edytora z Preferencji (`InterfaceFonts.editor`).
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var monospaced = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.font = monospaced ? InterfaceFonts.shared.editor : InterfaceFonts.shared.body
        tv.string = text
        tv.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor
        init(_ parent: CodeTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
