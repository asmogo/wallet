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
        // Local development: cdk-swift checkout whose Rust FFI is built from
        // the cdk workspace worktree at ../cdk-nostr-ffi (cdk-nostr based FFI:
        // Nostr keys, NIP-44, NIP-17 inbox).
        .package(path: "../../cdk-swift")
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
