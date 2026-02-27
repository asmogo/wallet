// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CashuWallet",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CashuWallet",
            targets: ["CashuWallet"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/cashubtc/cdk-swift", revision: "b79a160b70bcaa6aa7a98201ab1294409a97674f")
    ],
    targets: [
        .target(
            name: "CashuWallet",
            dependencies: [
                .product(name: "CashuDevKit", package: "cdk-swift")
            ]
        ),
    ]
)
