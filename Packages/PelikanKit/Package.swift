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
        .library(name: "PelikanThin", targets: ["PelikanThin"]),
        .library(name: "PelikanAgent", targets: ["PelikanAgent"]),
        .library(name: "PelikanRemote", targets: ["PelikanRemote"]),
        .library(name: "PelikanProC", targets: ["PelikanProC"]),
        .library(name: "PelikanBridgeKit", targets: ["PelikanBridgeKit"]),
        .executable(name: "pelikan-mcp", targets: ["pelikan-mcp"]),
    ],
    dependencies: [
        // Sterownik „thin” w czystym Swifcie (Apache 2.0) — commit z main po 1.0.0-rc.4 (poprawka dla Swift 6.4, D20).
        .package(url: "https://github.com/lovetodream/oracle-nio.git", revision: "7cda9e0c416a0cb21acf070ba70ce4ff575121b0"),
        // SHA-256 pobranych wydań utPLSQL na Linuksie (na macOS CryptoKit); już w grafie zależności przez OracleNIO.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"6.0.0"),
        // Serwer MCP agentów (oficjalne SDK, jak w Bifoldzie — D33); tylko macOS.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
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
        // Sterownik „thin”: OracleNIO (bez Instant Client).
        .target(name: "PelikanThin", dependencies: ["PelikanDB", .product(name: "OracleNIO", package: "oracle-nio")], swiftSettings: strict),
        // Model stanu aplikacji i rejestr komend — bez AppKit.
        .target(name: "PelikanWorkspace", dependencies: ["PelikanDB", "PelikanSQL",
                                                         .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))],
                swiftSettings: strict),

        // Kanał agentów AI (PROMPT §7): most stdio ↔ gniazdo Unix, serwer MCP, polityka uprawnień — tylko macOS.
        .target(name: "PelikanBridgeKit", swiftSettings: strict),
        .executableTarget(name: "pelikan-mcp", dependencies: ["PelikanBridgeKit"], swiftSettings: strict),
        .target(name: "PelikanAgent", dependencies: ["PelikanWorkspace", "PelikanBridgeKit",
                                                     .product(name: "MCP", package: "swift-sdk", condition: .when(platforms: [.macOS]))],
                swiftSettings: strict),

        // Zdalny build Pro*C (Etap P): ssh/scp przez posix_spawn, warstwa przejęta z Bifolda — tylko macOS.
        .target(name: "PelikanRemote", swiftSettings: strict),
        // Pro*C: cele SSH (bez sekretów w plikach), test połączenia, parsery błędów proc/xlc.
        .target(name: "PelikanProC", dependencies: ["PelikanWorkspace", "PelikanRemote"], swiftSettings: strict),

        .testTarget(name: "PelikanSQLTests", dependencies: ["PelikanSQL"], swiftSettings: strict),
        .testTarget(name: "PelikanDBTests", dependencies: ["PelikanDB", "PelikanODPI", "PelikanThin", "PelikanWorkspace", "PelikanSQL"], swiftSettings: strict),
        .testTarget(name: "PelikanWorkspaceTests", dependencies: ["PelikanWorkspace"], swiftSettings: strict),
        .testTarget(name: "PelikanAgentTests", dependencies: ["PelikanAgent", "pelikan-mcp"], swiftSettings: strict),
        .testTarget(name: "PelikanRemoteTests", dependencies: ["PelikanRemote"], swiftSettings: strict),
        .testTarget(name: "PelikanProCTests", dependencies: ["PelikanProC", "PelikanRemote"], swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
