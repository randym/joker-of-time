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
        )
    ],
    targets: [
        .executableTarget(
            name: "JokerOfTime",
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)

