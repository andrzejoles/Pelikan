import AppKit
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

/// Pole tekstowe z listą wyboru (D211): wartość wybiera się z listy pod przyciskiem ▾ albo wpisuje ręcznie. Tryb
/// `.list` — pole z wartościami po przecinku: wybór dopisuje pozycję albo ją usuwa (pozycje na liście mają znacznik).
/// `browse` dodaje pozycję wyboru katalogu, pliku albo aplikacji z okna macOS.
struct ChoiceField: View {
    enum Mode { case value, list }
    enum Browse { case directory, file, application }

    let title: String
    @Binding var text: String
    var prompt: String?
    var choices: [PreferenceChoice]
    var mode: Mode = .value
    var browse: Browse?
    var code = false
    /// Pole bez etykiety formularza (wiersze list z kilkoma polami — opis w podpowiedzi pola).
    var hideLabel = false

    init(_ title: String, text: Binding<String>, prompt: String? = nil, choices: [PreferenceChoice], mode: Mode = .value,
         browse: Browse? = nil, code: Bool = false, hideLabel: Bool = false) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.choices = choices
        self.mode = mode
        self.browse = browse
        self.code = code
        self.hideLabel = hideLabel
    }

    var body: some View {
        if hideLabel {
            field.help(title)
        } else {
            LabeledContent(title) { field }
        }
    }

    private var field: some View {
        HStack(spacing: 2) {
            TextField(title, text: $text, prompt: prompt.map { Text($0) })
                .labelsHidden()
                .font(code ? .code : nil)
            Menu {
                ForEach(choices, id: \.self) { c in
                    Button {
                        text = mode == .list ? PreferenceChoices.toggle(c.value, in: text) : c.value
                    } label: {
                        if mode == .list, PreferenceChoices.contains(c.value, in: text) {
                            Label(c.label, systemImage: "checkmark")
                        } else if mode == .value, c.value == text {
                            Label(c.label, systemImage: "checkmark")
                        } else {
                            Text(c.label)
                        }
                    }
                }
                if let browse {
                    if !choices.isEmpty { Divider() }
                    Button(browseTitle(browse)) { choose(browse) }
                }
                if !text.isEmpty {
                    Divider()
                    Button(L10n.tr("Wyczyść")) { text = "" }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .iconLabel(L10n.tr("Wybierz z listy"))
        }
    }

    private func browseTitle(_ b: Browse) -> String {
        switch b {
        case .directory: L10n.tr("Wybierz katalog…")
        case .file: L10n.tr("Wybierz plik…")
        case .application: L10n.tr("Wybierz aplikację…")
        }
    }

    private func choose(_ b: Browse) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = b == .directory
        panel.canChooseFiles = b != .directory
        if b == .application {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        if !text.isEmpty, b == .directory { panel.directoryURL = URL(fileURLWithPath: (text as NSString).expandingTildeInPath) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text = b == .application ? url.deletingPathExtension().lastPathComponent : url.path
    }
}

extension Binding where Value == String {
    /// Wiązanie listy napisów jako tekstu z wartościami po przecinku.
    @MainActor
    static func commaList(_ ws: Workspace, _ key: WritableKeyPath<PelikanWorkspace.Settings, [String]>,
                          transform: @escaping (String) -> String = { $0 }) -> Binding<String> {
        Binding(get: { ws.settings[keyPath: key].joined(separator: ", ") },
                set: { ws.settings[keyPath: key] = $0.split(separator: ",").map { transform($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty } })
    }
}
