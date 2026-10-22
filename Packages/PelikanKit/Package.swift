// swift-tools-version:6.2
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "PelikanKit",
    defaultLocalization: "pl",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PelikanSQL", targets: ["PelikanSQL"]),
        .library(name: "PelikanDB", targets: ["PelikanDB"]),
        .library(name: "PelikanODPI", targets: ["PelikanODPI"]),
        .library(name: "PelikanWorkspace", targets: ["PelikanWorkspace"]),
    ],
    targets: [
        // Lekser, dzielenie skryptów, klasyfikacja poleceń, zmienne podstawiania — czysty Swift (także Linux).
        .target(name: "PelikanSQL", swiftSettings: strict),
        // Protokoły warstwy bazy (DatabaseSession, wartości, metadane) — bez AppKit, bez sterownika.
        .target(name: "PelikanDB", dependencies: ["PelikanSQL"], swiftSettings: strict),
        // ODPI-C (oracle/odpi v26.0.0, UPL/Apache 2.0) — Instant Client ładowany dynamicznie (dlopen).
        .target(
            name: "CODPI",
            exclude: ["LICENSE.txt", "NOTICE.txt", "VENDORED.md"],
            cSettings: [.unsafeFlags(["-Wno-everything"])],
            linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux])),
                             .linkedLibrary("pthread", .when(platforms: [.linux]))]),
        // Sterownik „thick”: ODPI-C + Oracle Instant Client.
        .target(name: "PelikanODPI", dependencies: ["PelikanDB", "CODPI"], swiftSettings: strict),
        // Model stanu aplikacji i rejestr komend — bez AppKit.
        .target(name: "PelikanWorkspace", dependencies: ["PelikanDB", "PelikanSQL"], swiftSettings: strict),

        .testTarget(name: "PelikanSQLTests", dependencies: ["PelikanSQL"], swiftSettings: strict),
        .testTarget(name: "PelikanDBTests", dependencies: ["PelikanDB", "PelikanODPI", "PelikanWorkspace", "PelikanSQL"], swiftSettings: strict),
        .testTarget(name: "PelikanWorkspaceTests", dependencies: ["PelikanWorkspace"], swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
