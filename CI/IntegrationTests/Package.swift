// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CashuWalletIntegrationTests",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/cashubtc/cdk-swift", branch: "v0.17.0-nightly.20260802.g795aec2")
    ],
    targets: [
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                .product(name: "Cdk", package: "cdk-swift")
            ],
            path: "Tests",
            exclude: [
                "AmountFormatterTests.swift",
                "CurrencyTests.swift",
                "PaymentRequestDecoderTests.swift",
                "TokenParserTests.swift"
            ],
            sources: [
                "IntegrationTestBase.swift",
                "NutshellIntegrationTests.swift"
            ]
        )
    ]
)
