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
        .package(url: "https://github.com/asmogo/cdk-swift", revision: "66e8243fe33e8205af7f83862a5daf537317997d")
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
