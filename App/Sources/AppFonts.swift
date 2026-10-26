import AppKit
import Observation
import PelikanWorkspace
import SwiftUI

/// Czcionki z Preferencji (D178): krój, grubość i wielkość osobno dla interfejsu, Object Browsera, siatki i edytora.
enum AppFonts {
    /// Czcionka z kroju (pusty — systemowa; przy `monospaced` — systemowa o stałej szerokości), grubości i wielkości.
    static func font(family: String, size: Double, weight: FontWeightChoice, monospaced: Bool = false) -> NSFont {
        let size = CGFloat(max(6, size))
        if !family.isEmpty,
           let f = NSFontManager.shared.font(withFamily: family, traits: [], weight: managerWeight(weight), size: size) ?? NSFont(name: family, size: size) {
            return f
        }
        return monospaced ? .monospacedSystemFont(ofSize: size, weight: systemWeight(weight)) : .systemFont(ofSize: size, weight: systemWeight(weight))
    }

    static func systemWeight(_ w: FontWeightChoice) -> NSFont.Weight {
        switch w {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    /// Skala grubości NSFontManager (0–15; 5 — zwykła, 9 — pogrubiona).
    static func managerWeight(_ w: FontWeightChoice) -> Int {
        switch w {
        case .light: 3
        case .regular: 5
        case .medium: 6
        case .semibold: 8
        case .bold: 9
        }
    }

    /// Rodziny czcionek zainstalowanych w systemie (bez ukrytych, zaczynających się od kropki).
    static var families: [String] {
        NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Listy rodzin liczone raz (setki krojów — Preferencje odświeżają widok przy każdej zmianie).
    @MainActor static let cachedFamilies = families
    @MainActor static let cachedMonospacedFamilies = monospacedFamilies

    /// Rodziny o stałej szerokości znaków (edytor, siatka).
    static var monospacedFamilies: [String] {
        families.filter { family in
            guard let member = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first, let name = member.first as? String else { return false }
            return NSFont(name: name, size: 12)?.isFixedPitch == true
        }
    }

    /// Wysokość wiersza listy dla czcionki (tekst + odstęp, najmniej 22 pt).
    static func rowHeight(for font: NSFont) -> CGFloat {
        max(22, ceil(font.ascender - font.descender + font.leading) + 7)
    }

    static func weightName(_ w: FontWeightChoice) -> String {
        switch w {
        case .light: L10n.tr("Cienka")
        case .regular: L10n.tr("Zwykła")
        case .medium: L10n.tr("Średnio gruba")
        case .semibold: L10n.tr("Półgruba")
        case .bold: L10n.tr("Gruba")
        }
    }
}

/// Czcionka interfejsu z Preferencji — obserwowana: widoki SwiftUI i kod AppKit w `trackChanges` odświeżają się po zmianie.
@MainActor
@Observable
final class InterfaceFonts {
    static let shared = InterfaceFonts()

    private(set) var family = ""
    private(set) var size: Double = 13
    private(set) var weight: FontWeightChoice = .regular

    func apply(_ s: PelikanWorkspace.Settings) {
        if family != s.uiFontName { family = s.uiFontName }
        if size != s.uiFontSize { size = s.uiFontSize }
        if weight != s.uiFontWeight { weight = s.uiFontWeight }
    }

    /// Tekst podstawowy.
    var body: NSFont { AppFonts.font(family: family, size: size, weight: weight) }
    /// Tekst pomocniczy: o 2 pt mniejszy (najmniej 9 pt).
    var small: NSFont { AppFonts.font(family: family, size: max(9, size - 2), weight: weight) }
    /// Podpisy przycisków wstążki i kart okien: o 1 pt mniejsze.
    var label: NSFont { AppFonts.font(family: family, size: max(9, size - 1), weight: weight) }
    var bold: NSFont { AppFonts.font(family: family, size: size, weight: .semibold) }
}

extension Font {
    @MainActor static var ui: Font { Font(InterfaceFonts.shared.body as CTFont) }
    @MainActor static var uiSecondary: Font { Font(InterfaceFonts.shared.small as CTFont) }
    @MainActor static var uiHeadline: Font { Font(InterfaceFonts.shared.bold as CTFont) }
}

extension View {
    /// Domyślna czcionka okna SwiftUI — czcionka interfejsu z Preferencji (D178).
    func interfaceFont() -> some View { font(.ui) }
}

/// Wybór kroju czcionki w Preferencjach: pozycja domyślna (systemowa / jak interfejs) i rodziny z systemu, każda
/// pokazana swoim krojem.
struct FontFamilyPicker: View {
    let title: String
    @Binding var selection: String
    let defaultLabel: String
    var defaultTag = ""
    let families: [String]

    var body: some View {
        Picker(title, selection: $selection) {
            Text(defaultLabel).tag(defaultTag)
            Divider()
            ForEach(families.filter { $0 != defaultTag }, id: \.self) { f in
                Text(f).font(.custom(f, size: 13)).tag(f)
            }
            // Krój zapisany w ustawieniach, którego nie ma w systemie, zostaje do wyboru (zamiast pustego pola).
            if !selection.isEmpty, selection != defaultTag, !families.contains(selection) {
                Text(L10n.tr("\(selection) (niezainstalowana)")).tag(selection)
            }
        }
    }
}

struct FontWeightPicker: View {
    @Binding var selection: FontWeightChoice

    var body: some View {
        Picker(L10n.tr("Styl"), selection: $selection) {
            ForEach(FontWeightChoice.allCases, id: \.self) { Text(AppFonts.weightName($0)).tag($0) }
        }
    }
}
