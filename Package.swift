// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StrictID",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "StrictID",
            targets: ["StrictID"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sqids/sqids-swift.git", from: "0.1.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "StrictID",
            dependencies: [
                .product(name: "sqids", package: "sqids-swift"),
            ]
        ),
        .testTarget(
            name: "StrictIDTests",
            dependencies: ["StrictID"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
