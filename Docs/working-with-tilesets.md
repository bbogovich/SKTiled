# Working with Tilesets

- [Accessing Tilesets](#accessing-tilesets)
- [Preloading Tilesets](#preloading-tilesets)
- [Accessing Tile Data](#accessing-tile-data)
- [Updating Tile Data](#updating-tile-data)
- [Updating Spritesheets](#updating-spritesheets)

Tile data are stored in **tileset** data structures, and stored in an array accessible with the `SKTilemap.tilesets` property.

## Accessing Tilesets

Tilesets are created automatically for you when you load a tile map file. **SKTiled** supports both *inline* (stored in the TMX file) and *external* (stored in a separate TSX file) tilesets.

To access a tileset, simply query the tilemap node:

```swift
// query any tileset
if let inlineTileset = tilemap.getTileset(named: "winter-tiles") {
    // do something with the tileset
}

// get an externally saved tileset
if let externalTileset = tilemap.getTileset(fileNamed: "winter-tiles.tsx") {
    // do something with the tileset
}
```

Another useful feature is the ability to query the tileset associated with a global id:

```swift
if let tileset = tilemap.getTileset(forTile: 102) {
    // do something with the tileset
}
```


## Preloading Tilesets

External tilesets can also be preloaded and passed to a tilemap when instantiated:

```swift
let tilesetNames = ["winter-tiles", "spring-tiles", "summer-tiles", "fall-tiles"]
let tilesetURLs = tilesetNames.compactMap { Bundle.main.url(forResource: $0, withExtension: "tsx") }

do {
    let tilesets = try SKTileset.load(urls: tilesetURLs)
    // pass preloaded tilesets to parser
    let tilemap = try SKTilemap.load(url: mapURL, withTilesets: tilesets)
    worldNode.addChild(tilemap)
} catch {
    print("failed to load map: \(error.localizedDescription)")
}
```

## Accessing Tile Data

If you need to access tile data, you can call it from either the tilemap node, or a tileset instance with a global ID:

```swift
// query global id from tilemap
let tileDataFromMap = tilemap.getTileData(globalID: 102)!
// query global id from tileset
let tileDataFromTileset = tileset.getTileData(globalID: 102)!
```

It is also possible to query tile data with an arbitrary property (regardless of the value) or via the `type` property:

```swift
let breakables = tilemap.getTileData(withProperty: "breakable")
let lights = tilemap.getTileData(ofType: "light")
```

## Updating Tile Data

If you want to change the texture of an existing tile, you can use the `SKTilesetData.setTexture` method to update the texture:

```swift
let newTexture = SKTexture(imageNamed: "updated-texture")
if let oldTexture = tileData.setTexture(newTexture) {
    self.oldTextures.append(oldTexture)
}
```

You can additionally specify a frame number if the tile data contains animation:

```swift
let newTexture = SKTexture(imageNamed: "updated-texture")
    if let _ = tileData.setTexture(newTexture, forFrame: 2) {
        // texture is updated
}
```

## Updating Spritesheets

It is also possible to replace a tileset's spritesheet with a new source image:

```swift
if let spritesheet = Bundle.main.url(forResource: "new-spritesheet", withExtension: "png") {
    try tileset.addTextures(fromSpriteSheet: spritesheet, replace: true, transparent: nil)
}
```

The method throws a [`TiledError`](troubleshooting.md#loading-errors) if the image can't be read or decoded. If you already have the image in memory, use the `addTextures(fromSpriteSheet:source:replace:transparent:)` variant, which takes a `CGImage`. Individual tile textures can be replaced from image files in the same way with `SKTileset.setDataTexture(_:url:)`, and new tiles added with `SKTileset.addTilesetTile(_:url:)`.

Doing this will update all of the current tiles, so be careful using this method. 


Next: [Working with Layers](working-with-layers.md) - [Index](index.md)
