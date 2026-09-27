// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PocketCardCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PocketCardCore", targets: ["PocketCardCore"])],
    targets: [
        .target(name: "PocketCardCore"),
        .testTarget(name: "PocketCardCoreTests", dependencies: ["PocketCardCore"])
    ],
    swiftLanguageModes: [.v5]
)
