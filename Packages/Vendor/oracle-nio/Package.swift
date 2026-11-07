// swift-tools-version: 6.3
// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0
//
// Zmienione dla Pelikana (2026-11): tylko biblioteka OracleNIO i jej moduł puli połączeń — bez makr (swift-syntax),
// serwera testowego, testów i benchmarków. Źródło i lista zmian: PELIKAN.md.

import PackageDescription

// Ostrzeżenia kodu biblioteki wyciszone jak przy zależności zdalnej (SwiftPM wycisza je tylko dla pakietów zdalnych);
// zmiany Pelikana (PELIKAN.md) sprawdzone bez wyciszenia.
let quiet: [SwiftSetting] = [.unsafeFlags(["-suppress-warnings"])]

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
] + quiet

let package = Package(
    name: "oracle-nio",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "OracleNIO", targets: ["OracleNIO"]),
    ],
    traits: [
        .trait(name: "_IOTracing"),
        .trait(name: "DistributedTracingSupport"),
        .default(enabledTraits: ["DistributedTracingSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.23.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.29.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.9.0"..<"6.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "_OracleConnectionPoolModule",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            path: "Sources/OracleConnectionPoolModule",
            exclude: ["LICENSE"],
            swiftSettings: quiet
        ),
        .target(
            name: "OracleNIO",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(
                    name: "Tracing",
                    package: "swift-distributed-tracing",
                    condition: .when(traits: ["DistributedTracingSupport"])
                ),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                "_OracleConnectionPoolModule",
            ],
            swiftSettings: swiftSettings,
        ),
    ]
)
