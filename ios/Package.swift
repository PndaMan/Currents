// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Currents",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "Currents", targets: ["Currents"])
    ],
    dependencies: [
        // Local database
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // Image caching
        .package(url: "https://github.com/kean/Nuke.git", from: "12.0.0"),
    ],
    targets: [
        .target(
            name: "Currents",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
            ],
            path: "Currents"
        ),
        .testTarget(
            name: "CurrentsTests",
            dependencies: ["Currents"],
            path: "Tests"
        ),
    ]
)
