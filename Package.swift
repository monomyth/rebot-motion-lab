// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReBotMotionLab",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ReBotMotionLab", targets: ["ReBotMotionLab"]),
               .executable(name: "ReBotMCP", targets: ["ReBotMCP"])],
    targets: [
        .target(name: "RobotCore", resources: [.copy("Resources")]),
        .target(name: "RobotControl"),
        .executableTarget(name: "ReBotMotionLab", dependencies: ["RobotCore", "RobotControl"]),
        .executableTarget(name: "ReBotMCP", dependencies: ["RobotControl"]),
        .testTarget(name: "RobotCoreTests", dependencies: ["RobotCore"]),
        .testTarget(name: "RobotControlTests", dependencies: ["RobotControl"])
    ],
    swiftLanguageModes: [.v5]
)
