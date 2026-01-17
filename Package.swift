// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickyNotes",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StickyNotes", targets: ["StickyNotes"])
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "StickyNotes",
            dependencies: [
            ],
            path: "Sources/StickyNotes",
            exclude: ["react-editor"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
