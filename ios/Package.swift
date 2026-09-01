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
        .package(url: "https://github.com/cashubtc/cdk-swift", exact: "0.18.0-rc.3")
    ],
    targets: [
        .target(
            name: "CashuWallet",
            dependencies: [
                .product(name: "Cdk", package: "cdk-swift")
            ]
        ),
    ]
)
