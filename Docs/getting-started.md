# Getting Started

- [Requirements](#requirements)
- [Installation](#installation)
    - [Swift Package Manager](#swift-package-manager)
    - [Building the Documentation](#building-the-documentation)
- [Running the Demo](#running-the-demo)
- [tvOS Support](#tvos-support)
    - [A Note About 4K](#a-note-about-4k)
- [Adding Tiled Assets to Xcode](#adding-tiled-assets-to-xcode)
    - [Folder References](#folder-references)
    - [How File Paths Are Resolved](#how-file-paths-are-resolved)
    - [Grouped Assets](#grouped-assets)
    - [Loading from a URL](#loading-from-a-url)



**SKTiled** was designed to be flexible and easy to use. To get started, simply add the package to your Xcode project and add your Tiled assets. If you have any problems or requests, please open an issue at the [**Github page**](https://github.com/bbogovich/SKTiled/issues).


## Requirements

- iOS 17
- tvOS 17
- macOS 14
- Xcode 26 or later (swift-tools-version 6.2), Swift 6 language mode

The library is main-actor isolated: all SpriteKit nodes are main-actor types, so maps should be loaded on the main actor (for example in a scene's `didMove(to:)` method, or in a SwiftUI view).


## Installation

**SKTiled** is distributed as a Swift package. Carthage, CocoaPods and the prebuilt XCFrameworks are no longer supported.


### Swift Package Manager

In Xcode, select **File > Add Package Dependencies…** and enter the repository URL:

    https://github.com/bbogovich/SKTiled.git

Once the dependency is resolved, add the **SKTiled** library to your targets in the **Frameworks, Libraries and Embedded Content** area of the target's **General** tab.

To use **SKTiled** from another Swift package, add it to the dependencies in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/bbogovich/SKTiled.git", branch: "master")
],
targets: [
    .target(
        name: "MyGame",
        dependencies: [
            .product(name: "SKTiled", package: "SKTiled")
        ]
    )
]
```

For more information, see [**Adding package dependencies to your app**][adding-spm-url] in the Apple documentation.


### Building the Documentation

This documentation site is built with [**MkDocs**][mkdocs-url]. To preview it locally, install the requirements and run the development server from the repository root:

    pip install -r requirements-docs.txt
    mkdocs serve

The API reference is generated from the source with [**DocC**][docc-url] by the `scripts/build-docs.sh` script.


## Running the Demo

The repository includes a demo application that can be used to quickly test your own content, or simply play around with the included demo files. Open **Demo/SKTiledDemo.xcodeproj**; it is a single multiplatform SwiftUI app (macOS, iOS & tvOS) that displays an `SKTiledScene` in a `SpriteView`.

- the sidebar lists the maps bundled in the **Demo/Maps** folder
- **Open Folder…** (**⌘O** on macOS) lists the maps in any folder on disk; real Tiled project layouts load directly
- the toolbar toggles the grid, layer bounds, objects, pausing, zoom and fitting the map to the view
- the inspector shows facts about the current map and the tile coordinate under the pointer

See [**Demo App**](developer/demo-app.md) for how the demo works and how its code is organised, and [**Creating a SwiftUI App**](developer/swiftui-app.md) to set up your own project.

To run the demo on a device, select your own development team in the target's **Signing & Capabilities** tab. For more information, see the [**Apple Development Documentation**][apple-code-signing-url] on code signing requirements.



## tvOS Support

![AppleTV Devices](images/appletv-devices.png)

**SKTiled** can be built for AppleTV devices, including AppleTV 4K. tvOS 17 or later is required.

### A Note About 4K

![AppleTV 4K](images/appletv-4k-launch.png)

If you are displaying content on a 4K AppleTV, check that your Asset LaunchImage has a 2x resolution of **3840 x 2160**. This will ensure that your game runs at a full 4K resolution.



## Adding Tiled Assets to Xcode

**SKTiled** reads Tiled files exactly as **Tiled** saves them, so you don't need to rearrange your project to use it. Loading is done with the throwing `SKTilemap.load` methods; if a file can't be found or read, a [`TiledError`](troubleshooting.md#loading-errors) is thrown describing what went wrong.


### Folder References

![Referenced Assets][xcode-assets-ref-img]

The recommended way to add Tiled content is to add the folder containing it (for example, your Tiled project folder) to Xcode as a **folder reference**. The folder is copied into your app bundle with its layout intact, so the relative paths saved by **Tiled** keep working.

![Adding a Folder Reference][xcode-add-assets-ref-img]

To load a bundled map, call `SKTilemap.load(named:)` with the map's file name. Folder references are searched, so you don't need to know where the map sits in the bundle:


```swift
do {
    let tilemap = try SKTilemap.load(named: "dungeon")
    scene.addChild(tilemap)
} catch {
    print("failed to load map: \(error.localizedDescription)")
}
```

If you have maps with the same name in different folders, supply the bundle and a subdirectory:

```swift
let tilemap = try SKTilemap.load(named: "dungeon", in: .main, subdirectory: "Maps")
```


### How File Paths Are Resolved

Every `source` attribute in a Tiled file (tilesets in maps, images in tilesets, templates, image layers and collection-tileset images) is resolved relative to the file that contains it, exactly as **Tiled** does. A typical Tiled project layout works unchanged:

```
maps/level.tmx          -> ../tilesets/terrain.tsx
tilesets/terrain.tsx    -> ../images/terrain.png
images/terrain.png
```

If a file isn't found at its relative path, **SKTiled** falls back to:

1. a file with the same name in the loaded map's directory
2. a file with the same name in the `bundle` passed to the load method

Images that aren't found as files are then looked up by name in the bundle's asset catalog. Images can be in any format that ImageIO can decode (PNG, JPEG, GIF, BMP, HEIC, WebP…).


### Grouped Assets

![Grouped Assets][xcode-assets-group-img]

If you add assets to Xcode as a **group**, Xcode flattens them into a single folder in your app bundle. The relative paths saved by **Tiled** no longer match, but the file name fallbacks described above will still find your tilesets and images, so grouped assets load as well:

```swift
let tilemap = try SKTilemap.load(named: "MyTilemap")
```


### Loading from a URL

Maps can also be loaded from any file URL, such as a file in the user's documents folder. Pass a `bundle` if you want the bundle fallbacks to apply:

```swift
do {
    let tilemap = try SKTilemap.load(url: mapURL, bundle: .main)
    scene.addChild(tilemap)
} catch let error as TiledError {
    print(error.localizedDescription)
} catch {
    print("unexpected error: \(error)")
}
```

For more information, see the [**Working with Maps**][working-with-maps-url] section.


Next: [Scene Setup](scene-setup.md) - [Index](index.md)


<!--- Images --->

[xcode-assets-group-img]:images/xcode-assets-group.png
[xcode-assets-ref-img]:images/xcode-assets-referenced.png
[xcode-add-assets-ref-img]:images/xcode-add-assets-reference.png

<!--- URLs --->

[working-with-maps-url]:working-with-maps.md#loading-a-tilemap
[mkdocs-url]:https://www.mkdocs.org
[docc-url]:https://www.swift.org/documentation/docc/
[apple-code-signing-url]:https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates
[adding-spm-url]:https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app
