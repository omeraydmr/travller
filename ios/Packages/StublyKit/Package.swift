// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StublyKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StublyKit", targets: ["StublyKit"]),
    ],
    targets: [
        .target(name: "StublyKit", resources: [.copy("Resources/airports.tsv"), .copy("Resources/visa_rules.tsv")]),
        .testTarget(name: "StublyKitTests", dependencies: ["StublyKit"]),
    ]
)
