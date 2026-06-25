// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CashuWalletIntegrationTests",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/cashubtc/cdk-swift", exact: "0.17.1")
    ],
    targets: [
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                .product(name: "Cdk", package: "cdk-swift")
            ],
            path: "Tests",
            resources: [.copy("Resources")]
        )
    ]
)
