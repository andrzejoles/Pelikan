import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Przebieg zrzutów (D196): bez ikony w Docku i paska menu — aplikacja pracuje niewidocznie w tle.
app.setActivationPolicy(AppDelegate.uiScriptURL == nil ? .regular : .accessory)
app.run()
