// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClaudeBell",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeBell",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "ClaudeBellTests",
            dependencies: ["ClaudeBell"],
            path: "Tests"
        ),
    ]
)
