// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "SKTiled",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "SKTiled", targets: ["SKTiled"])
    ],
    targets: [
        .target(
            name: "SKTiled",
            path: "Sources",
            swiftSettings: [
                // SpriteKit nodes are main-actor types; the whole module runs on the main actor.
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "SKTiledTests",
            dependencies: ["SKTiled"],
            path: "Tests",
            resources: [
                .copy("Assets/test-tilemap.tmx"),
                .copy("Assets/characters-8x8.png"),
                .copy("Assets/characters-8x8.tsx"),
                .copy("Assets/environment-8x8.png"),
                .copy("Assets/environment-8x8.tsx"),
                .copy("Assets/items-8x8.png"),
                .copy("Assets/items-8x8.tsx"),
                .copy("Assets/items-alt-8x8.png"),
                .copy("Assets/monsters-16x16.png"),
                .copy("Assets/monsters-16x16.tsx"),
                .copy("Assets/portraits-8x8.png"),
                .copy("Assets/portraits-8x8.tsx"),
                .copy("Fixtures"),
            ]
        )
    ]
)
