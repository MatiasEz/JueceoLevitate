// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JueceoCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "JueceoCore", targets: ["JueceoCore"])
    ],
    targets: [
        .target(name: "JueceoCore")
    ]
)
