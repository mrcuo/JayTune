// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JayTune",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "JayTune",
            dependencies: [],
            path: "JayTune/JayTune"
        ),
        .testTarget(
            name: "JayTuneTests",
            dependencies: ["JayTune"],
            path: "JayTuneTests"
        )
    ]
)
