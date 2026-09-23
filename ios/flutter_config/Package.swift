// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_config",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-config", targets: ["flutter_config"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_config",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            exclude: [
                "BuildDotenvConfig.rb",
                "BuildDotenvPlist.rb",
                "BuildXCConfig.rb",
                "ReadDotEnv.rb"
            ],
            cSettings: [
                .headerSearchPath("include/flutter_config")
            ]
        )
    ]
)
