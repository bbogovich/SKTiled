# Creating a SwiftUI App

This page takes a new Xcode project to a running SwiftUI app that displays a Tiled map. Every step was checked with Xcode 27 against a project created from the **Multiplatform ▸ App** template, using the template's default build settings.

- [Requirements](#requirements)
- [1. Create the Project](#1-create-the-project)
- [2. Add the SKTiled Package](#2-add-the-sktiled-package)
- [3. Check the Build Settings](#3-check-the-build-settings)
- [4. Add Your Tiled Files](#4-add-your-tiled-files)
- [5. Show a Map](#5-show-a-map)
- [6. Run](#6-run)
- [Using Your Own Scene](#using-your-own-scene)
- [Loading Maps the User Chooses](#loading-maps-the-user-chooses)
- [Where to Go Next](#where-to-go-next)
- [Troubleshooting](#troubleshooting)


## Requirements

| Item            | Minimum                                                    |
|:----------------|:-----------------------------------------------------------|
| Xcode           | 26 (the package uses `swift-tools-version: 6.2`)            |
| Deployment      | iOS 17, macOS 14, tvOS 17                                   |
| Swift           | Swift 5 or Swift 6 language mode in your app (both verified) |
| Tiled           | Maps saved as TMX/TSX/TX (XML). JSON maps (`.tmj`, `.tsj`) are not supported. |


## 1. Create the Project

1. **File ▸ New ▸ Project…**
2. Choose **Multiplatform ▸ App** (or **iOS ▸ App** / **macOS ▸ App** for a single platform), then **Next**.
3. Enter a product name (this page uses **MyTiledGame**), keep **Interface: SwiftUI** and **Language: Swift**, set **Storage: None**, and create the project.

The template creates a source folder named after the product (`MyTiledGame/`) as a *synchronized folder*: every file inside it belongs to the app target automatically. Keep your Swift files there. **Don't put Tiled files there**; see [step 4](#4-add-your-tiled-files).

**Platforms.** The Multiplatform template targets iPhone, iPad and Mac. SKTiled is not tested on Apple Vision; remove that destination under *Target ▸ General ▸ Supported Destinations* if it is listed. For Apple TV, add it there if Xcode offers it, or add a separate tvOS App target (**File ▸ New ▸ Target… ▸ tvOS ▸ App**) and repeat steps 2–4 for it. The [demo project](demo-app.md) shows a single target building for all three platforms.


## 2. Add the SKTiled Package

**From GitHub:**

1. **File ▸ Add Package Dependencies…**
2. Paste `https://github.com/bbogovich/SKTiled` into the search field.
3. Under **Dependency Rule**, choose **Branch** and enter the branch with the 2.0 code (`modernize-2.0` until it is merged into `master`). The repository has no 2.x version tags yet, so version rules won't find it.
4. **Add Package**, then in the next sheet set **Add to Target** for the **SKTiled** product to your app target.

**From a local checkout** (to work on SKTiled and your app together):

1. **File ▸ Add Package Dependencies…**
2. Click **Add Local…** and choose the folder containing SKTiled's `Package.swift`.
3. Add the **SKTiled** product to your app target.

A local package is built from source with every app build, so edits to SKTiled appear immediately. The [demo project](demo-app.md) references the repository this way.

To confirm, open *Target ▸ General ▸ Frameworks, Libraries, and Embedded Content*: **SKTiled** should be listed.


## 3. Check the Build Settings

New projects already have compatible settings. Check these if you are adding SKTiled to an existing project:

| Setting                                  | Requirement                                                        |
|:-----------------------------------------|:-------------------------------------------------------------------|
| Minimum Deployments (*Target ▸ General*) | At least iOS 17, macOS 14, tvOS 17. Lower values fail with *"compiling for macOS 13.0, but module 'SKTiled' has a minimum deployment target of macOS 14.0"*. |
| Swift Language Version                   | 5 or 6. New projects use 5.                                        |
| Default Actor Isolation                  | `MainActor` (the new-project default) or `nonisolated`. Either works, because `SKScene` subclasses and SwiftUI views are main-actor types, which is where SKTiled must be used. |
| Member Import Visibility (upcoming feature) | On in new projects. Each file must import every module whose members it uses: `import SpriteKit` to call SpriteKit methods such as `addChild` on SKTiled's nodes, and `import SKTiled` to call SKTiled methods, even on a type declared in another file of your app. |
| App Sandbox (macOS)                      | On in new projects, with *User Selected Files: Read Only*. Maps in the app bundle need nothing more; see [Loading Maps the User Chooses](#loading-maps-the-user-chooses) for maps elsewhere. |


## 4. Add Your Tiled Files

Tiled stores each tileset, image and template path *relative to the file that references it*, for example `../tilesets/terrain.tsx`. SKTiled resolves paths the same way, so the files must reach the app bundle with their folder layout intact. That takes a **folder reference**.

1. Keep your Tiled project folder **outside** the app's source folder, for example next to it:

    ```
    MyTiledGame/                 project folder
    ├── MyTiledGame.xcodeproj
    ├── MyTiledGame/             app source folder (synchronized)
    │   └── *.swift
    └── Maps/                    Tiled project folder
        ├── maps/level.tmx
        ├── tilesets/terrain.tsx
        ├── images/terrain.png
        └── templates/chest.tx
    ```

2. Drag the `Maps` folder from Finder onto the project in Xcode's navigator (or use **File ▸ Add Files to "MyTiledGame"…**).
3. In the options sheet:
    - **Action:** *Reference files in place* (or *Copy files to destination* to copy the folder into the project folder first);
    - **Groups:** **Create folder references**;
    - **Targets:** tick your app target.
4. The folder appears in the navigator as a **blue folder**. It is copied into the app as `Maps/` with every subfolder, and files you add to it on disk later are included automatically.

You can check the result after building: the app bundle's resources (`MyTiledGame.app/Contents/Resources/` on macOS, the `.app` folder itself on iOS) should contain `Maps/maps/level.tmx`, `Maps/tilesets/terrain.tsx` and so on.

!!! warning "Don't put Tiled files in a synchronized folder or a group"
    Observed with Xcode 27: when Tiled files are inside the app's synchronized source folder (or added with *Create synchronized groups*), Xcode

    - **silently skips `.tsx` tilesets**: they are not copied and the build log doesn't mention them. Loading then fails with *"…/tilesets/terrain.tsx (referenced by "level.tmx") does not exist."*;
    - copies the remaining files into the bundle's top level, discarding the folders.

    *Create groups* also flattens folders. SKTiled's file-name fallback can cope with flattening while every file name is unique, but not with missing files. Use a folder reference.


## 5. Show a Map

Three files are enough. Replace the template's `ContentView.swift`, and adjust the app file if you renamed anything.

**GameScene.swift**: an `SKTiledScene` subclass. `SKTiledScene` provides a world node, a camera with pan and zoom input, and map loading:

```swift
import SpriteKit
import SKTiled

final class GameScene: SKTiledScene {

    static func makeScene() -> GameScene {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        scene.scaleMode = .resizeFill
        do {
            try scene.setup(named: "level")
        } catch {
            print("Could not load map: \(error.localizedDescription)")
        }
        return scene
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // enable the camera's pan and pinch gestures on iOS (off by default)
        cameraNode.allowGestures = true
    }

    override func didRenderMap(_ tilemap: SKTilemap) {
        print("rendered \(tilemap.mapName): \(tilemap.tileCount) tiles")
    }
}
```

- `setup(named:)` finds `level.tmx` anywhere in the app bundle, including inside folder references, loads it with the scene as its delegate, adds it to the world node and configures the camera from the map's properties. It can be called before the scene is on screen.
- `scaleMode = .resizeFill` keeps the scene the size of the view; the camera does the zooming.
- `SKTiledScene` creates its camera in `didMove(to:)`, so camera settings go in an override that calls `super` first. The camera's touch gestures (one-finger pan, pinch to zoom) exist on iOS but are disabled until `allowGestures` is set.
- Override the delegate methods you need (`didRenderMap(_:)`, `didAddLayer(_:)`, `objectForTileType(named:)`, …); see [Scene Setup](../scene-setup.md).

**ContentView.swift**: show the scene in a `SpriteView`:

```swift
import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var scene = GameScene.makeScene()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}
```

Keep the scene in `@State` (or in a model object) so SwiftUI does not create a new scene each time the view is re-rendered.

**MyTiledGameApp.swift**: the template's version works as it is:

```swift
import SwiftUI

@main
struct MyTiledGameApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```


## 6. Run

Choose **My Mac** or a simulator and run (**⌘R**). The map appears, and the console shows the loading steps followed by your `didRenderMap` output:

```
[SKTilemapParser]: INFO: tmx parser: reading tile map: "level.tmx"
[SKTilemapParser]: INFO: tsx parser: reading tileset: "terrain.tsx"
rendered level: 8 tiles
 ✽ Success! tilemap "level" rendered in: 0.005s
```

To make SKTiled quieter, pass `loggingLevel: .warning` to `setup(named:)`, or set `TiledGlobals.default.loggingLevel = .warning` before loading.

On a Mac, drag to move the camera and scroll to zoom. On iOS, pan with one finger and pinch to zoom (with `allowGestures` enabled as above).


## Using Your Own Scene

`SKTiledScene` is optional. A map is an ordinary `SKNode`, so it can be added to any scene:

```swift
import SpriteKit
import SKTiled

final class PlainScene: SKScene {

    private var tilemap: SKTilemap?

    override func didMove(to view: SKView) {
        let camera = SKCameraNode()
        addChild(camera)
        self.camera = camera

        do {
            let tilemap = try SKTilemap.load(named: "level")
            addChild(tilemap)
            self.tilemap = tilemap

            // the map's contents are centered on the tilemap node
            let frame = tilemap.calculateAccumulatedFrame()
            camera.position = CGPoint(x: frame.midX, y: frame.midY)
        } catch {
            print("Could not load map: \(error.localizedDescription)")
        }
    }

    override func update(_ currentTime: TimeInterval) {
        tilemap?.update(currentTime)
    }
}
```

Call `tilemap.update(_:)` from your scene's `update(_:)`. With the default `TileUpdateMode.actions`, tile animations run as SpriteKit actions and the call does little, but the `.dynamic` and `.full` modes animate tiles from it. You are responsible for camera input in your own scene.


## Loading Maps the User Chooses

To load maps from files the user picks (for example a level editor or a mod folder), let the user choose the **folder**, not the `.tmx` file: the tilesets and images next to the map must be readable too, and a sandboxed app can only read what the user selected.

```swift
import SwiftUI
import SpriteKit
import SKTiled
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var scene = GameScene.makeScene()
    @State private var isPickingFolder = false

    var body: some View {
        SpriteView(scene: scene)
            .toolbar {
                Button("Open Folder…") { isPickingFolder = true }
            }
            .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
                guard case .success(let folder) = result else { return }
                // keep access while the map's files are read; stop when the folder is no longer needed
                guard folder.startAccessingSecurityScopedResource() else { return }
                let map = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
                    .compactMap { $0 as? URL }
                    .first { $0.pathExtension == "tmx" }
                if let map {
                    _ = try? scene.setup(url: map)
                }
            }
    }
}
```

- `.folder` comes from `UniformTypeIdentifiers`, and `setup(url:)` from `SKTiled`: with member import visibility on, the file must import both.
- On macOS the template's *User Selected Files: Read Only* sandbox entitlement is sufficient.
- Pass `bundle: nil` (the default for `setup(url:)`) so SKTiled doesn't fall back to files of the same name in your app bundle.

The [demo app](demo-app.md) implements this with error display and a list of all maps in the folder.


## Where to Go Next

- [Working with Maps](../working-with-maps.md), [Layers](../working-with-layers.md), [Tiles](../working-with-tiles.md) and [Objects](../working-with-objects.md): querying and changing map content.
- [Tiled Properties](../tiled-properties.md): properties SKTiled applies automatically, and reading your own.
- [How SKTiled Works](internals.md): the library's design, if you need to extend or debug it.


## Troubleshooting

| Symptom                                                           | Cause and fix                                                                                          |
|:------------------------------------------------------------------|:-------------------------------------------------------------------------------------------------------|
| *"… .tsx (referenced by "….tmx") does not exist."*                | The Tiled files are in a synchronized folder or group, so the tilesets weren't copied. Use a folder reference ([step 4](#4-add-your-tiled-files)). |
| *"… was not found in bundle …"* (`TiledError.resourceNotFound`)   | The map isn't in the bundle: the folder reference isn't a member of the app target, or the name is misspelled. Check *Target ▸ Build Phases ▸ Copy Bundle Resources*. |
| *"compiling for macOS 13.0, but module 'SKTiled' has a minimum deployment target of macOS 14.0"* | Raise the target's Minimum Deployments to iOS 17 / macOS 14 / tvOS 17.                   |
| *"… is not available due to missing import of defining module 'SKTiled'"* (or `'SpriteKit'`, `'Foundation'`) | Member import visibility is on: add the named `import` to that file.        |
| *"Call to main actor-isolated … in a synchronous nonisolated context"* | SKTiled is main-actor isolated. Load and modify maps from the main actor: in a scene, a view, or a `@MainActor` type or function. |
| Swift Package Manager builds fail from Terminal with thousands of *"cannot find type 'CGFloat'"* errors | A non-Xcode Swift toolchain (for example one installed by swiftly) is first on `PATH`. Use `xcrun swift build`. |
| The map is tiny or off-screen in your own scene                   | The map's contents are centered on the tilemap node. Center your camera on it, and set `camera.setScale` to zoom. |

All loading errors are `TiledError` values; [Troubleshooting](../troubleshooting.md#loading-errors) lists them.
