// Okna procesu (PID) na ekranie: „numer<TAB>tytuł<TAB>szerokośćxwysokość” — do `screencapture -l`, bez aktywacji aplikacji.
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments.dropFirst().first ?? "") ?? 0
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
    let n = w[kCGWindowNumber as String] as? Int ?? 0
    let name = w[kCGWindowName as String] as? String ?? ""
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    guard !name.isEmpty, (b["Width"] ?? 0) > 200, (b["Height"] ?? 0) > 150 else { continue }
    print("\(n)\t\(name)\t\(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))")
}
