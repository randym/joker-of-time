// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JokerOfTime",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "JokerOfTime",
            targets: ["JokerOfTime"]
        ),
        .executable(
            name: "LoginItemHelper",
            targets: ["LoginItemHelper"]
        )
    ],
    targets: [
        .executableTarget(
            name: "JokerOfTime",
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "LoginItemHelper",
            path: "LoginItemHelper",
            exclude: ["Info.plist"]
        )
    ]
)

