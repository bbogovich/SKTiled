# Developer Guide

For developers building apps with SKTiled, or working on the library itself.

| Page                                          | Read it to…                                                                     |
|:----------------------------------------------|:--------------------------------------------------------------------------------|
| [Creating a SwiftUI App](swiftui-app.md)      | set up a new Xcode project, add the package and your Tiled files, and show a map. |
| [Demo App](demo-app.md)                       | see how the demo is structured and implemented, file by file.                    |
| [How SKTiled Works](internals.md)             | understand loading, the node tree, coordinates, rendering, concurrency and memory. |
| [Working on SKTiled](contributing.md)         | build, test and document changes to the library.                                |

## Essentials

- **Swift Package Manager only.** Add `https://github.com/bbogovich/SKTiled` or a local checkout; minimum iOS 17, macOS 14, tvOS 17; Xcode 26 or later.
- **Main actor.** SKTiled, like SpriteKit, is used from the main actor: in scenes, SwiftUI views and `@MainActor` code.
- **Folder references for Tiled files.** Add your Tiled project folder to Xcode as a folder reference so tilesets and images keep their relative paths. Synchronized folders drop `.tsx` files.
- **Loading throws.** `SKTilemap.load(named:)`, `load(url:)` and `SKTiledScene.setup(...)` throw a `TiledError` that names the file and the problem.
- **Check before committing** with `scripts/check.sh`.
