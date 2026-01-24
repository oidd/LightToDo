// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LightToDo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LightToDo", targets: ["LightToDo"])
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "LightToDo",
            dependencies: [
            ],
            path: "Sources/LightToDo",
            exclude: ["react-editor"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
