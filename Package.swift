// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "IKEADeskControl",
    platforms: [
       .macOS(.v12)
    ],
    products: [
        .executable(name: "IKEADeskControl", targets: ["IKEADeskControl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/sroebert/mqtt-nio.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "IKEADeskControl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MQTTNIO", package: "mqtt-nio"),
            ]
        ),
    ]
)
