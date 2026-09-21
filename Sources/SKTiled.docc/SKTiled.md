# ``SKTiled``

Load maps made in the Tiled map editor into SpriteKit.

## Overview

SKTiled reads Tiled TMX maps, TSX tilesets and TX templates and builds a SpriteKit node tree: an ``SKTilemap`` containing tile layers, object groups, image layers and group layers. Orthogonal, isometric, hexagonal and staggered maps are supported.

```swift
let tilemap = try SKTilemap.load(named: "dungeon")
scene.addChild(tilemap)
```

Every `source` attribute is resolved relative to the file that contains it, as Tiled does, so a Tiled project folder can be added to Xcode as a folder reference and loaded unchanged. Loading failures throw ``TiledError`` values that name the file and the problem.

SKTiled runs on the main actor, like the SpriteKit nodes it creates.

The guides (getting started, scene setup, working with maps, tilesets, layers, tiles and objects, and troubleshooting) are published alongside this reference.

## Topics

### Loading Maps

- ``SKTilemap``
- ``SKTileset``
- ``TiledError``
- ``SKTilemapDelegate``
- ``SKTilesetDataSource``

### Scenes and Cameras

- ``SKTiledScene``
- ``SKTiledSceneCamera``
- ``SKTiledSceneDelegate``
- ``SKTiledSceneCameraDelegate``

### Layers

- ``SKTiledLayerObject``
- ``SKTileLayer``
- ``SKObjectGroup``
- ``SKImageLayer``
- ``SKGroupLayer``

### Tiles and Objects

- ``SKTile``
- ``SKTilesetData``
- ``SKTileObject``
- ``TileAnimationFrame``

### Navigation

- ``SKTiledGraphNode``
