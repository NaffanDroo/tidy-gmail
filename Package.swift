// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidyGmail",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TidyGmail", targets: ["TidyGmail"]),
    ],
    dependencies: [
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "1.7.0"),
        .package(url: "https://github.com/Quick/Quick.git", from: "7.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "14.0.0"),
    ],
    targets: [
        // Core library — all logic and UI. Imported by the executable and the test target.
        .target(
            name: "TidyGmailCore",
            dependencies: [
                .product(name: "AppAuth", package: "AppAuth-iOS"),
            ],
            path: "Sources/TidyGmailCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Thin executable entry point — just calls TidyGmailApp.main().
        .executableTarget(
            name: "TidyGmail",
            dependencies: ["TidyGmailCore"],
            path: "Sources/TidyGmail",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Test target imports TidyGmailCore (testable) — never the executable.
        // Swift 5 language mode: Quick/Nimble predate Swift 6 strict concurrency.
        // Production code (TidyGmailCore) remains Swift 6.
        .testTarget(
            name: "TidyGmailTests",
            dependencies: [
                "TidyGmailCore",
                .product(name: "Quick", package: "Quick"),
                .product(name: "Nimble", package: "Nimble"),
            ],
            path: "Tests/TidyGmailTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
