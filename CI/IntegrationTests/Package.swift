// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CashuWalletIntegrationTests",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/asmogo/cdk-swift", revision: "66e8243fe33e8205af7f83862a5daf537317997d")
    ],
    targets: [
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                .product(name: "CashuDevKit", package: "cdk-swift")
            ],
            path: "Tests",
            resources: [.copy("Resources")]
        )
    ]
)
