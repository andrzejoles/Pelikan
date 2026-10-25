import Foundation

/// Dokumenty HTML pokazywane w aplikacji (podgląd danych, raporty, instrukcja): bez skryptów i zasobów zewnętrznych.
public enum LocalHTML {
    /// Meta CSP: tylko style z dokumentu i obrazy `data:`.
    public static let contentSecurityPolicy =
        "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\">"
}
