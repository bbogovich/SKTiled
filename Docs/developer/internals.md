# How SKTiled Works

This page explains how the library is put together, for developers who extend SKTiled, debug it, or want to know what a call costs. It describes the 2.0 code in `Sources/`.

- [Source Map](#source-map)
- [Concurrency Model](#concurrency-model)
- [Loading Pipeline](#loading-pipeline)
- [Node Hierarchy](#node-hierarchy)
- [Tiles, Tilesets and Global IDs](#tiles-tilesets-and-global-ids)
- [Coordinates](#coordinates)
- [Rendering and Animation](#rendering-and-animation)
- [Scene and Camera](#scene-and-camera)
- [Custom Properties](#custom-properties)
- [Ownership and Memory](#ownership-and-memory)
- [Notifications, Logging and Globals](#notifications-logging-and-globals)
- [Extension Points](#extension-points)
- [Known Limitations](#known-limitations)


## Source Map

All sources are in one module, `Sources/`. Sizes are approximate line counts.

| Area               | File                              | Lines | Contents |
|:-------------------|:----------------------------------|------:|:---------|
| **Loading**        | `SKTilemapParser.swift`           | 1300  | `XMLParserDelegate` that reads TMX, TSX and TX files and builds nodes. |
|                    | `TiledAssetLoading.swift`         |  150  | `TiledAssetResolver` (path resolution and fallbacks), `TiledImageLoader` (ImageIO decoding, asset catalog lookup), bundle search by name. |
|                    | `TiledError.swift`                |   80  | `TiledError`, the error type every load throws. |
| **Map**            | `SKTilemap.swift`                 | 2550  | The map node: loading entry points, layers, tilesets, queries, coordinate helpers, per-frame update, debug options. |
|                    | `TileDataStorage.swift`           |  470  | Per-map caches of tiles grouped by tile data, used by the per-frame update. |
| **Layers**         | `SKTiledLayerObject.swift`        | 1020  | Base class of all layers: offsets, opacity, coordinate conversion for every orientation, debug drawing. |
|                    | `SKTileLayer.swift`               |  970  | Tile layers: builds `SKTile` nodes from layer data, tile queries. |
|                    | `SKObjectGroup.swift`             |  470  | Object layers: holds `SKTileObject`s. |
|                    | `SKImageLayer.swift`              |  150  | Image layers: one sprite. |
|                    | `SKGroupLayer.swift`              |  190  | Group layers: nested layers. |
|                    | `TiledBackgroundLayer.swift`      |   85  | `BackgroundLayer`, the map's hidden default layer (used for coordinate conversion and background color). |
| **Tiles & data**   | `SKTileset.swift`                 |  720  | Tilesets: sprite sheet slicing, image collections, tile data lookup. |
|                    | `SKTilesetData.swift`             |  400  | Per-tile-id data shared by every tile using that id: texture, type, properties, animation frames. |
|                    | `SKTile.swift`                    | 1030  | The tile sprite (`SKSpriteNode`): orientation (flips), animation, render modes, debug drawing. |
|                    | `TileAnimationFrame.swift`        |   80  | One frame of a tile animation. |
|                    | `TileCollisionShape.swift`        |   75  | Collision shapes defined on tileset tiles. |
| **Objects**        | `SKTileObject.swift`              | 1200  | Vector, tile and text objects (`SKShapeNode`). |
|                    | `TileObjectProxy.swift`, `TileObjectOverlay.swift` | 240 | Proxies that draw object bounds in an overlay when `showObjects` is on. |
| **Scene & camera** | `SKTiledScene.swift`              |  435  | Optional `SKScene` subclass with world node, camera and map setup. |
|                    | `SKTiledSceneCamera.swift`        |  820  | Camera node: zoom, clamping, mouse and gesture input, delegate notifications. |
|                    | `TiledSceneDelegate.swift`, `TiledSceneCameraDelegate.swift`, `TilemapDelegate.swift`, `TilesetDataSource.swift` | 390 | Protocols for scenes, camera observers, map loading hooks and tileset image substitution. |
| **Features**       | `SKTiled+Properties.swift`        |  350  | Applies the custom Tiled properties SKTiled understands. |
|                    | `SKTiledObject.swift`             |  280  | `SKTiledObject` protocol: uuid, type, properties, typed property accessors. |
|                    | `SKTiled+GameplayKit.swift`       |  310  | Building `GKGridGraph`s from tile layers; `SKTiledGraphNode`. |
|                    | `SKTiled+Debug.swift`, `TiledDebugDrawNode.swift`, `AnchorNode.swift` | 680 | Debug draw options and drawing (grid, bounds, graphs, anchors). |
| **Support**        | `TiledGlobals.swift`              |  520  | `TiledGlobals.default`: defaults (logging, update mode, render quality, debug colors). |
|                    | `Logging.swift`                   |  220  | `Logger` and `LoggingLevel`. |
|                    | `SKTiled+Extensions.swift`        | 2480  | Helpers on CoreGraphics, SpriteKit, String, Data (including gzip/zlib decompression), and public notification names. |
|                    | `Array2D.swift`, `ReferenceArray.swift` | 300 | Small containers. |
| **Docs**           | `SKTiled.docc/`                   |       | DocC catalog (landing page and topic groups). |


## Concurrency Model

The package sets `defaultIsolation(MainActor.self)` for the SKTiled target (`Package.swift`). Every declaration in the module is main-actor isolated unless marked otherwise. This matches SpriteKit: `SKNode` inherits from `NSResponder`/`UIResponder`, which are main-actor types, so every tile, layer and map node already is.

Consequences:

- **Loading runs on the main actor, synchronously.** Parsing, image decoding and node creation happen inside `SKTilemap.load`. Loading a large map blocks the main thread for its duration; `SKTilemap.mapRenderTime` reports how long it took.
- **No locks or dispatch queues.** Earlier versions rendered layers and updated tile textures on background queues, which mutated SpriteKit nodes off the main thread. 2.0 removed all of those queues.
- **Exceptions are marked `nonisolated`:** value-type helpers (the CoreGraphics, `String`, `Data`/gzip and `SKColor` extensions), the public notification names, and `SKTiledGraphNode` (a `GKGridGraphNode` subclass, so pathfinding can run off the main actor).
- **`NSObject` overrides** (`description`, `debugDescription`, `hash`) are `nonisolated override` and use `MainActor.assumeIsolated`, because `NSObject` declares them nonisolated. Calling them off the main thread traps.
- **No cleanup in `deinit`.** A `deinit` can't touch main-actor state, and none is needed (see [Ownership and Memory](#ownership-and-memory)).

The test target runs in Swift 6 mode too; test classes are `@MainActor`.


## Loading Pipeline

`SKTilemap.load(url:...)` creates an `SKTilemapParser` and calls its `load(url:bundle:...)`. `load(named:in:subdirectory:)` first finds the file with `Bundle.tiledResourceURL(named:extension:subdirectory:)`, which checks `subdirectory` (or the bundle's resource root) and then, when no subdirectory was given, searches the whole resource tree, shallowest match first.

### Files and the Parse Queue

The parser keeps a queue of file URLs (`fileQueue`). It starts with the map and parses one file at a time with Foundation's `XMLParser`:

1. The file's extension sets the parsing mode (`tmx`, `tsx` or `tx`), which tells element handlers what they are reading.
2. While a map is parsed, each external `<tileset source=…>` and each object `template=…` is resolved to a URL and **appended to the queue**; the tileset is created immediately (with its `firstgid`) and filled in when its file is parsed.
3. Tilesets are cached in a dictionary keyed by **standardized file path**, so a tileset referenced by the map and by a template is parsed once and shared.

### Path Resolution

Every `source` goes through `TiledAssetResolver.url(for:referencedBy:)`:

1. relative to the **directory of the file containing the attribute** (Tiled's rule), standardized so `..` components collapse;
2. otherwise, the same file name in the **directory of the map being loaded** (covers bundles whose folders were flattened);
3. otherwise, the same file name looked up in the **bundle** passed to `load` (`Bundle.url(forResource:withExtension:)`).

Images go through `TiledImageLoader.image(for:referencedBy:resolver:)`: the resolver first, then the bundle's asset catalog by name (`UIImage(named:in:with:)` / `Bundle.image(forResource:)`). Files are decoded with ImageIO (`CGImageSourceCreateImageAtIndex`), so any format ImageIO supports works.

`SKTilesetDataSource` can substitute an image first: `willAddSpriteSheet(to:fileNamed:)` and `willAddImage(to:forId:fileNamed:)` receive the raw `source` attribute, and the returned name is resolved by the same rules.

### Errors

`XMLParserDelegate` callbacks cannot throw. A handler that finds a problem calls `fail(_:_:)`, which records the **first** `TiledError` and calls `parser.abortParsing()`. When `parse()` returns `false`, the parser throws the recorded error, or `.invalidXML` with the line and column if the XML itself was malformed. Attribute parsing in the node initializers (`SKTilemap(attributes:)`, `SKTileset(attributes:)`, `SKTileObject(attributes:)` and the layer initializers) returns `nil` for invalid values instead of force-unwrapping, and the parser turns that into `.invalidContent`.

### Two Passes

Parsing builds the node tree but defers tile creation. Layer data (CSV, base64 with optional zlib/gzip, or XML `<tile>` elements) is decoded into `[UInt32]` global IDs and stored per layer. After the last file is parsed:

1. the delegate's `didReadMap(_:)` is called;
2. `didBeginRendering` walks every layer: object groups draw their objects, tile layers create their tiles from the stored IDs (`SKTileLayer.setLayerData`), and each layer finishes with `didFinishRendering(duration:)`;
3. `SKTilemap.didFinishRendering(timeStarted:)` marks the map rendered, starts tile animations, positions debug nodes, calls the delegate's `didRenderMap(_:)` and posts `Notification.Name.Map.FinishedRendering`.

`SKTilemap.load` then records `mapRenderTime` and returns the map.


## Node Hierarchy

```
SKTilemap                         (SKEffectNode)
├── BackgroundLayer               defaultLayer: coordinates, background color (index -1)
├── SKTileLayer                   (SKTiledLayerObject → SKEffectNode)
│   ├── SKTile …                  (SKSpriteNode), one per non-empty cell
│   └── SKTiledDebugDrawNode      grid / bounds / graph drawing
├── SKObjectGroup
│   └── SKTileObject …            (SKShapeNode); tile objects add an SKTile child
├── SKImageLayer
│   └── SKSpriteNode
├── SKGroupLayer
│   └── (nested layers)
├── SKTiledDebugDrawNode          map-level debug drawing
├── TileObjectOverlay             object proxies drawn when showObjects is on
└── overlay                       dims the map while it is paused
```

- Layers are direct children of the map (or of their group layer) in document order. Each layer's `zPosition` is `zDeltaForLayers × position` (default spacing 50), so later layers draw on top.
- `SKTilemap.positionLayer` offsets every layer by half the map's size, so **the map's contents are centered on the map node's position**, plus each layer's Tiled offset.
- Layers and maps are `SKEffectNode`s with effects disabled by default (`shouldEnableEffects`); enabling them renders the subtree to an offscreen buffer, which allows shaders and removes seams between tiles at a cost.


## Tiles, Tilesets and Global IDs

- A **tileset** (`SKTileset`) owns one `SKTilesetData` per tile ID. For a sprite sheet, `addTextures(fromSpriteSheet:)` decodes the image once and creates one sub-texture per tile with `SKTexture(rect:in:)`, honoring margin and spacing. For an image collection, each tile gets its own texture. All tileset textures use `.nearest` filtering (pixel art).
- A **global ID** in layer data is `tileset.firstGID + local id`, with the top three bits used as flip flags (horizontal `0x80000000`, vertical `0x40000000`, diagonal `0x20000000`). `flippedTileFlags(id:)` splits them; `SKTilemap.getTileData(globalID:)` finds the tileset whose range contains the ID.
- A **tile** (`SKTile`) is an `SKSpriteNode` with a reference to its shared `SKTilesetData`. `SKTileLayer.buildTileAt(coord:id:)` asks the map delegate for the tile class (`objectForTileType(named:)`, keyed by the tile's Tiled type), creates the tile, applies the flip flags (`orientTile()`), positions it with `pointForCoordinate`, stores it in the layer's 2-D array and registers it with the map's `TileDataStorage`.
- Tiles are individual sprites. A large map has one node per non-empty cell per layer; SpriteKit batches sprites that share a texture atlas, so one tileset per layer keeps draw counts low.


## Coordinates

Tiled uses a y-down space with tile (0, 0) at the top left; SpriteKit is y-up. `SKTiledLayerObject` converts between four spaces:

| Space  | Meaning                                                         |
|:-------|:----------------------------------------------------------------|
| tile   | Tiled's tile coordinates (column, row).                         |
| pixel  | Tiled's pixel coordinates within the map, y-down.               |
| screen | The layer's local point space with y inverted (`invertedY`).    |
| layer  | SpriteKit points in the layer node.                             |

`tileToScreenCoords`, `screenToTileCoords`, `pixelToTileCoords` and `tileToPixelCoords` implement the maths for each orientation (orthogonal, isometric, hexagonal and staggered, using the map's `staggeraxis`, `staggerindex` and `hexsidelength`). The public entry points are:

- `layer.pointForCoordinate(coord:offsetX:offsetY:)`: tile → point in the layer;
- `layer.coordinateForPoint(_:)`: point in the layer → tile;
- `tilemap.coordinate(at:in:)`: a point in any node's space (for example the scene) → tile, via the default layer;
- `tilemap.isValid(coord:)`: whether a coordinate is inside the map.


## Rendering and Animation

How animated tiles advance depends on `TileUpdateMode`, set per map (`SKTilemap.updateMode`) with the default taken from `TiledGlobals.default.updateMode`:

| Mode                  | Behaviour                                                                                         |
|:----------------------|:--------------------------------------------------------------------------------------------------|
| `.actions` (default)  | Each animated tile runs an `SKAction` built from its tile data's frames. `update(_:)` does no tile work. Cheapest. |
| `.dynamic`            | `SKTilemap.update(_:)` advances each animated tile data's clock and sets the current frame's texture on every tile using it. |
| `.full`               | Like `.dynamic`, and also re-applies textures to static tiles every frame.                       |

`TileDataStorage` makes the per-frame update proportional to the number of *distinct* tiles rather than tiles on screen: tiles are grouped by their `SKTilesetData`, in a static cache and an animated cache. The update computes each animated data's current frame once and applies it to that data's tile list. The caches are updated directly by the map's nodes: a tile added to a layer, a tile's render mode changing (`SKTile.renderMode`), a tile data's texture being replaced, or a sprite sheet being swapped.

`SKTile.renderMode` lets individual tiles opt out: `.static` stops animating, `.ignore` ignores tile data updates, and `.animated(gid:)` animates with another tile's frames.

When `TiledGlobals.default.enableRenderCallbacks` is on, the map samples render statistics every 60 frames and posts them with `Notification.Name.Map.RenderStatsUpdated`.

There is no off-screen culling: every tile's `visibleToCamera` flag is always `true`, so the update processes all tiles, and SpriteKit culls drawing.


## Scene and Camera

`SKTiledScene` is a convenience, not a requirement.

- **World node.** Created in `init`, so a map can be set up before the scene is presented. Maps are added to the world node.
- **Camera.** `SKTiledSceneCamera` is created in `didMove(to:)` once the scene has a view, set as the scene's `camera`, and given the scene as a delegate. A map set up earlier is configured when the camera appears.
- **`setup(url:)` / `setup(named:)`** load through the `SKTiledSceneDelegate.load(url:...)` default implementation, which passes the scene as the map's delegate and tileset data source when it conforms (as `SKTiledScene` does). `setup(tilemap:)` then removes the previous map, adds the new one, applies its background color and gravity, and copies camera settings from the map (`allowZoom`, `allowMovement`, zoom limits, initial zoom or fit-to-view when the map's `autoResize` property is set).
- **Input.** On macOS the scene forwards mouse down, drag, up, move and scroll-wheel events to the camera (pan, zoom at the pointer, double-click, pointer tracking). On iOS the camera installs pan, pinch and double-tap recognizers on the view, **disabled until `allowGestures` is set**. There is no tvOS input handling.
- **Camera delegates** (`SKTiledSceneCameraDelegate`) receive position, zoom and bounds changes, the set of nodes in view, and pointer events. Every method has an empty default implementation. The map is a camera delegate, to track the nodes in view.


## Custom Properties

Tiled custom properties are stored as strings in each object's `properties` dictionary and applied by `parseProperties(completion:)` after the element is read (`SKTiled+Properties.swift`). Keys are case-insensitive. Unknown keys are kept for your own use through the `SKTiledObject` accessors (`stringForKey`, `boolForKey`, `intForKey`, `doubleForKey`, array variants, …).

| Applies to | Keys SKTiled acts on |
|:-----------|:---------------------|
| Map        | `zDelta`/`zDeltaForLayers`/`layerDelta`, `debug`/`debugMode`/`debugDraw`, `gridColor`, `gridOpacity`, `frameColor`, `highlightColor`, `aspect`, `worldScale`, `allowZoom`, `allowMovement`, `zPosition`, `tileOverlap`, `minZoom`, `maxZoom`, `ignoreBackground`, `antialiasLines`, `autoResize`, `showObjects`, `xGravity`, `yGravity`, `showGrid`, `showBounds`, `overlayColor`, `objectColor`, `niceName`/`displayName`, `navigationColor`, `enableEffects`/`shouldEnableEffects` |
| Tileset    | `walkable` (list of tile IDs) |
| Layer      | `zPosition`, `color`, `backgroundColor`, `hidden`, `visible`, `antialiasing`, `drawBounds`, `navigation`/`navigationKey` |
| Object group | `lineWidth` (plus the layer keys) |
| Object     | `color`, `lineWidth`, `zPosition` |
| Tile data  | `weight`, `walkable` |

Each type also takes its Tiled `type` (or `class`) from a `type` property if the attribute is absent. [Tiled Properties](../tiled-properties.md) describes the effects.


## Ownership and Memory

The node tree owns everything: a map owns its layers (children), layers own their tiles and objects, and the map owns its tilesets and its `TileDataStorage`. Every reference *back up* the tree is weak:

| Reference                               | Kind                     |
|:----------------------------------------|:-------------------------|
| layer → map (`SKTiledLayerObject.tilemap`) | `weak`                |
| tileset → map (`SKTileset.tilemap`)     | `weak`                   |
| tile → layer, object → layer            | `weak`                   |
| tile data → tileset                     | `weak`                   |
| storage → map, debug node → layer       | `weak`                   |
| camera → delegates                      | weak boxes               |
| map → delegate                          | `weak`                   |

A map is freed as soon as nothing outside it holds it (`LoadingTests.testMapIsReleasedWhenNoLongerReferenced` checks this). The back-references are implicitly unwrapped (`SKTilemap!`), so accessing `layer.tilemap` after the map is gone traps; keep a reference to the map while you use its layers.

Each map has its own `TileDataStorage`, and nodes update their own map's storage directly, so maps never share state (`LoadingTests.testEachMapCachesOnlyItsOwnTiles`).


## Notifications, Logging and Globals

**Notifications** are for app-level observers only; the library doesn't use them internally. Each is posted with the relevant map, camera or statistics value as its `object`:

| Name                                          | Posted when                                          |
|:----------------------------------------------|:-----------------------------------------------------|
| `Notification.Name.Map.FinishedRendering`     | a map finishes rendering                             |
| `Notification.Name.Map.RenderStatsUpdated`    | render statistics are sampled (if enabled)           |
| `Notification.Name.DataStorage.IsolationModeChanged` | a map's tile isolation debug mode changes     |
| `Notification.Name.Camera.Updated`            | a camera moves, zooms or changes control mode        |

**Logging** goes through `Logger.default`, which writes a message when its level is at or below the current `loggingLevel`: fatal and error messages to standard error, the rest to standard output. The level can be set per load (`loggingLevel:` parameter) or globally with `TiledGlobals.default.loggingLevel` (default `.info`). Types adopt the internal `Loggable` protocol to log with their type name as prefix.

**`TiledGlobals.default`** holds process-wide defaults: logging level, tile update mode, render callbacks, camera callbacks, render quality (resolution of debug and text drawing) and debug colors. Change it before loading maps.


## Extension Points

| Hook                                                    | Use                                                              |
|:--------------------------------------------------------|:-----------------------------------------------------------------|
| `SKTilemapDelegate.objectForTileType(named:)`           | Return an `SKTile` subclass for tiles of a given Tiled type.     |
| `SKTilemapDelegate.objectForVectorType(named:)`         | Return an `SKTileObject` subclass for objects of a given type.   |
| `SKTilemapDelegate.objectForGraphType(named:)`          | Return a `GKGridGraphNode` subclass for navigation graphs.       |
| `SKTilemapDelegate.didBeginParsing`, `didAddTileset`, `didAddLayer`, `didReadMap`, `didRenderMap`, `didAddNavigationGraph` | Observe or adjust the map while it loads. |
| `SKTilesetDataSource.willAddSpriteSheet`, `willAddImage` | Substitute tileset images (for example seasonal variants).       |
| `SKTiledSceneCameraDelegate`                            | Observe camera movement, zoom, visible nodes and pointer events. |
| `SKTiledScene` subclass                                 | Override any of the above plus `didMove(to:)` and `update(_:)`.  |

[Extending SKTiled](../extending-sktiled.md) has examples.


## Known Limitations

These are properties of the current code, not planned behaviour:

- **Formats.** Only XML files (TMX, TSX, TX) are read; JSON (`.tmj`, `.tsj`, `.tj`) and world files are not. Infinite (chunked) maps and zstd compression throw `.unsupportedFeature`.
- **Hexagonal 120° rotation.** The fourth flip bit (`0x10000000`) used for hexagonal rotation is not masked, so tiles rotated that way in Tiled resolve to a wrong ID.
- **Flip flags are written to shared tile data.** `buildTileAt` sets the flip flags on the `SKTilesetData` that every tile with that ID shares, just before orienting the new tile. The tile is oriented correctly, but the flags on the tile data reflect the last tile built; don't rely on them afterwards.
- **Main-thread loading.** Maps load synchronously on the main actor. Separating parsing (off the main actor) from node creation would need a model layer the parser doesn't have yet.
- **No culling** of the per-frame tile update (see [Rendering and Animation](#rendering-and-animation)).
- **Multi-line string properties** (stored as element text in Tiled) are read as empty strings.
