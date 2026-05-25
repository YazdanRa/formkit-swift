// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FormKitSwift",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "FormKitSwift",
            targets: ["FormKitSwift"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ajevans99/swift-json-schema.git", from: "0.11.2"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "FormKitSwift",
            dependencies: [
                .product(name: "JSONSchema", package: "swift-json-schema")
            ]
        ),
        .testTarget(
            name: "FormKitSwiftTests",
            dependencies: ["FormKitSwift"]
        )
    ],
    swiftLanguageModes: [.v6]
)
