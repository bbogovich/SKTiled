//
//  SKTileLayer.swift
//  SKTiled
//
//  Created by Michael Fessenden.
//
//  Web: https://github.com/mfessenden
//  Email: michael.fessenden@gmail.com
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import SpriteKit
import GameplayKit
#if os(iOS) || os(tvOS)
import UIKit
#else
import Cocoa
#endif


/// ## Overview
///
/// Subclass of `SKTiledLayerObject`, the tile layer is a container for an array of tiles (sprites). Tiles maintain a link to the map's tileset via their `SKTilesetData` property.
///
///
/// ### Properties
///
/// | Property                  | Description                                            |
/// |---------------------------|--------------------------------------------------------|
/// | tileCount                 | Returns a count of valid tiles.                        |
///
///
/// ### Instance Methods ###
///
/// | Method                    | Description                                            |
/// |---------------------------|--------------------------------------------------------|
/// | getTiles()                | Returns an array of current tiles.                     |
/// | getTiles(ofType:)         | Returns tiles of the given type.                       |
/// | getTiles(globalID:)       | Returns all tiles matching a global id.                |
/// | getTilesWithProperty(_:_) | Returns tiles matching the given property & value.     |
/// | animatedTiles()           | Returns all animated tiles.                            |
/// | getTileData(globalID:)    | Returns all tiles matching a global id.                |
/// | tileAt(coord:)            | Returns a tile at the given coordinate, if one exists. |
///
/// ### Usage
///
/// Accessing a tile at a given coordinate:
///
/// ```swift
/// let tile = tileLayer.tileAt(2, 6)!
/// ```
///
/// Query tiles of a certain type:
///
/// ```swift
/// let floorTiles = tileLayer.getTiles(ofType: "Floor")
/// ```
public class SKTileLayer: SKTiledLayerObject {
    
    fileprivate typealias TilesArray = Array2D<SKTile>
    
    /// Container for the tile sprites.
    fileprivate var tiles: TilesArray
    
    /// Returns a count of valid tiles.
    public var tileCount: Int {
        return self.getTiles().count
    }
    
    /// Tuple of layer render statistics.
    override internal var renderInfo: RenderInfo {
        var current = super.renderInfo
        current.tc = tileCount
        if let graph = graph {
            current.gn = graph.nodes?.count ?? nil
        }
        return current
    }
    
    override var layerRenderStatistics: LayerRenderStatistics {
        var current = super.layerRenderStatistics
        
        var tc: Int
        switch updateMode {
            case .full:
                tc = self.tileCount
            case .dynamic:
                tc = 0
            default:
                tc = 0
        }
        
        current.tiles = tc
        return current
    }
    
    /// Debug visualization options.
    override public var debugDrawOptions: DebugDrawOptions {
        didSet {
            guard oldValue != debugDrawOptions else { return }
            debugNode.draw()
            let doShowTileBounds = debugDrawOptions.contains(.drawTileBounds)
            tiles.forEach { $0?.showBounds = doShowTileBounds }
        }
    }
    
    /// Tile highlight duration
    override public var highlightDuration: TimeInterval {
        didSet {
            tiles.compactMap { $0 }.forEach { $0.highlightDuration = highlightDuration }
        }
    }
    
    // MARK: - Init
    /// Initialize with layer name and parent `SKTilemap`.
    ///
    /// - parameter layerName:    `String` layer name.
    /// - parameter tilemap:      `SKTilemap` parent map.
    override public init(layerName: String, tilemap: SKTilemap) {
        self.tiles = TilesArray(columns: Int(tilemap.size.width), rows: Int(tilemap.size.height))
        super.init(layerName: layerName, tilemap: tilemap)
        self.layerType = .tile
    }
    
    /// Initialize with parent `SKTilemap` and layer attributes.
    ///
    /// **Do not use this intializer directly**
    ///
    /// - parameter tilemap:      `SKTilemap` parent map.
    /// - parameter attributes:   `[String: String]` layer attributes.
    public init?(tilemap: SKTilemap, attributes: [String: String]) {
        // name, width and height are required
        guard let layerName = attributes["name"] else { return nil }
        self.tiles = TilesArray(columns: Int(tilemap.size.width), rows: Int(tilemap.size.height))
        super.init(layerName: layerName, tilemap: tilemap, attributes: attributes)
        self.layerType = .tile
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Tiles
    
    /// Returns a tile at the given coordinate, if one exists.
    ///
    /// - parameter x: `Int` y-coordinate.
    /// - parameter y: `Int` x-coordinate.
    /// - returns: `SKTile?` tile object, if it exists.
    public func tileAt(_ x: Int, _ y: Int) -> SKTile? {
        if isValid(x, y) == false { return nil }
        return tiles[x,y]
    }
    
    /// Returns a tile at the given coordinate, if one exists.
    ///
    /// - parameter coord:   `CGPoint` tile coordinate.
    /// - returns: `SKTile?` tile object, if it exists.
    public func tileAt(coord: CGPoint) -> SKTile? {
        return tileAt(Int(coord.x), Int(coord.y))
    }
    
    /// Returns a tile at the given screen position, if one exists.
    ///
    /// - parameter point:  `CGPoint` screen point.
    /// - parameter offset: `CGPoint` pixel offset.
    /// - returns: `SKTile?` tile object, if it exists.
    public func tileAt(point:  CGPoint, offset: CGPoint = CGPoint.zero) -> SKTile? {
        let coord = coordinateForPoint(point)
        return tileAt(coord: coord)
    }
    
    /// Returns an array of current tiles.
    ///
    /// - returns: `[SKTile]` array of tiles.
    public func getTiles() -> [SKTile] {
        return tiles.compactMap { $0 }
    }
    
    /// Returns tiles with a property of the given type.
    ///
    /// - parameter ofType: `String` type.
    /// - returns: `[SKTile]` array of tiles.
    public func getTiles(ofType: String) -> [SKTile] {
        return tiles.compactMap { $0 }.filter { $0.tileData.type == ofType }
    }
    
    /// Returns tiles matching the given global id.
    ///
    /// - parameter globalID: `Int` tile global id.
    /// - returns: `[SKTile]` array of tiles.
    public func getTiles(globalID: Int) -> [SKTile] {
        return tiles.compactMap { $0 }.filter { $0.tileData.globalID == globalID }
    }
    
    /// Returns tiles with a property of the given type.
    ///
    /// - returns: `[SKTile]` array of tiles.
    public func getTilesWithProperty(_ named: String, _ value: Any) -> [SKTile] {
        var result: [SKTile] = []
        for tile in tiles where tile != nil {
            if let pairValue = tile!.tileData.keyValuePair(key: named) {
                if pairValue.value == String(describing: value) {
                    result.append(tile!)
                }
            }
        }
        return result
    }
    
    /// Returns all tiles with animation.
    ///
    /// - returns: `[SKTile]` array of animated tiles.
    public func animatedTiles() -> [SKTile] {
        return getTiles().filter { $0.tileData.isAnimated == true }
    }
    
    /// Return tile data from a global id.
    ///
    /// - parameter gid: `Int` global tile id.
    /// - returns: `SKTilesetData?` tile data (for valid id).
    public func getTileData(globalID gid: Int) -> SKTilesetData? {
        return tilemap.getTileData(globalID: gid)
    }
    
    /// Returns tiles with a property of the given type.
    ///
    /// - returns: `[SKTile]` array of tiles.
    public func getTileData(withProperty named: String) -> [SKTilesetData] {
        var result: [SKTilesetData] = []
        for tile in tiles where tile != nil {
            if tile!.tileData.hasKey(named) && !result.contains(tile!.tileData) {
                result.append(tile!.tileData)
            }
        }
        return result
    }
    
    // MARK: - Layer Data
    
    /// Add tile data array to the layer and render it.
    ///
    /// - parameter data:  `[UInt32]` tile data.
    /// - parameter debug: `Bool` debug mode.
    /// - returns: `Bool` data was successfully added.
    @discardableResult
    public func setLayerData(_ data: [UInt32], debug: Bool = false) -> Bool {
        if !(data.count == size.pointCount) {
            log("invalid data size for layer \"\(self.layerName)\": \(data.count), expected: \(size.pointCount)", level: .error)
            return false
        }
        
        var errorCount: Int = 0
        for index in data.indices {
            let gid = data[index]
            
            // skip empty tiles
            if (gid == 0) { continue }
            
            let x: Int = index % Int(self.size.width)
            let y: Int = index / Int(self.size.width)
            
            let coord = CGPoint(x: CGFloat(x), y: CGFloat(y))
            
            // build the tile
            let tile = self.buildTileAt(coord: coord, id: gid)
            
            if (tile == nil) {
                errorCount += 1
            }
        }
        
        if (errorCount != 0) {
            log("layer \"\(self.layerName)\": \(errorCount) \(errorCount > 1 ? "errors" : "error") loading data.", level: .warning)
        }
        return errorCount == 0
    }
    
    /// Clear the layer of tiles.
    public func clearLayer() {
        clearTiles()
    }
    
    /// Build an empty tile at the given coordinates. Returns an existing tile if one already exists,
    /// or nil if the coordinate is invalid.
    ///
    /// - parameter coord:     `CGPoint` tile coordinate
    /// - parameter gid:       `Int?` tile id.
    /// - parameter tileType:  `String` optional tile class name.
    /// - returns: `SKTile?` tile.
    public func addTileAt(coord: CGPoint,
                          gid: Int? = nil,
                          tileType: String? = nil) -> SKTile? {
        
        guard isValid(coord: coord) else {
            return nil
        }
        
        // remove the current tile
        let existingTile = removeTileAt(coord: coord)
        
        // strip any flip flags from the gid
        let tileAttrs = gid.map { flippedTileFlags(id: UInt32(truncatingIfNeeded: $0)) }
        let tileData: SKTilesetData? = tileAttrs.flatMap { getTileData(globalID: Int($0.gid)) }
        
        let Tile = (tilemap.delegate != nil) ? tilemap.delegate!.objectForTileType(named: tileType) : SKTile.self
        let tile = Tile.init()
        tile.tileSize = tileSize
        
        if let tileData = tileData {
            tile.tileData = tileData
            tile.texture = tileData.texture
            tile.tileSize = (tileData.tileset != nil) ? tileData.tileset!.tileSize : self.tileSize
        }

        if let tileAttrs = tileAttrs {
            tile.flipHoriz = tileAttrs.hflip
            tile.flipVert  = tileAttrs.vflip
            tile.flipDiag  = tileAttrs.dflip
        }
        
        // set the tile overlap amount
        tile.setTileOverlap(tilemap.tileOverlap)
        tile.highlightColor = highlightColor
        
        // set the layer property
        tile.layer = self
        self.tiles[Int(coord.x), Int(coord.y)] = tile
        
        // set orientation & anchor point from the tile data
        if (tileData?.tileset != nil) {
            tile.orientTile()
        }
        
        // get the position in the layer, plus the tileset offset (the layer offset is applied to the layer node)
        let tileOffset = tileData?.tileset?.tileOffset ?? CGPoint.zero
        let tilePosition = pointForCoordinate(coord: coord, offsetX: tileOffset.x, offsetY: tileOffset.y)
        tile.position = tilePosition
        
        if let currentTile = existingTile {
            tile.zPosition = currentTile.zPosition
            tile.zRotation = currentTile.zRotation
        }

        addChild(tile)
        
        // add to tile cache
        tilemap?.dataStorage?.tileAdded(tile)

        // force tile redraw
        tile.draw()
        return tile
    }
    
    /// Build an empty tile at the given coordinates with a custom texture. Returns `nil` if the coordinate
    /// is invalid.
    ///
    /// - parameter coord:   `CGPoint` tile coordinate.
    /// - parameter texture: `SKTexture?` optional tile texture.
    /// - parameter tileType: `String?` optional tile type.
    /// - returns: `SKTile?` tile.
    public func addTileAt(coord: CGPoint,
                          texture: SKTexture? = nil,
                          tileType: String? = nil) -> SKTile? {
        
        guard isValid(coord: coord) else {
            return nil
        }

        // remove the current tile
        let existingTile = removeTileAt(coord: coord)

        let Tile = (tilemap.delegate != nil) ? tilemap.delegate!.objectForTileType(named: tileType) : SKTile.self
        let tile = Tile.init()

        tile.tileSize = tileSize
        tile.texture = texture

        // set the tile overlap amount
        tile.setTileOverlap(tilemap.tileOverlap)
        tile.highlightColor = highlightColor
        
        // set the layer property
        tile.layer = self
        self.tiles[Int(coord.x), Int(coord.y)] = tile
        
        // get the position in the layer (the layer offset is applied to the layer node)
        let tilePosition = pointForCoordinate(coord: coord)
        tile.position = tilePosition

        if let currentTile = existingTile {
            tile.zPosition = currentTile.zPosition
            tile.zRotation = currentTile.zRotation
        }

        addChild(tile)

        // add to tile cache
        tilemap?.dataStorage?.tileAdded(tile)

        // force tile redraw
        tile.draw()
        return tile
    }
    
    /// Build an empty tile at the given coordinates. Returns an existing tile if one already exists,
    /// or nil if the coordinate is invalid.
    ///
    /// - parameter x:   `Int` x-coordinate
    /// - parameter y:   `Int` y-coordinate
    /// - parameter gid: `Int?` tile id.
    /// - returns: `SKTile?` tile.
    public func addTileAt(_ x: Int, _ y: Int, gid: Int? = nil) -> SKTile? {
        let coord = CGPoint(x: CGFloat(x), y: CGFloat(y))
        return addTileAt(coord: coord, gid: gid)
    }
    
    /// Build an empty tile at the given coordinates with a custom texture. Returns nil is the coordinate
    /// is invalid.
    ///
    /// - parameter x:       `Int` x-coordinate
    /// - parameter y:       `Int` y-coordinate
    /// - parameter texture: `SKTexture?` optional tile texture.
    /// - returns: `SKTile?` tile.
    public func addTileAt(_ x: Int, _ y: Int, texture: SKTexture? = nil) -> SKTile? {
        let coord = CGPoint(x: CGFloat(x), y: CGFloat(y))
        return addTileAt(coord: coord, texture: texture)
    }
    
    /// Remove the tile at a given x/y coordinates.
    ///
    /// - parameter x:   `Int` x-coordinate
    /// - parameter y:   `Int` y-coordinate
    /// - returns: `SKTile?` removed tile.
    public func removeTileAt(_ x: Int, _ y: Int) -> SKTile? {
        let coord = CGPoint(x: CGFloat(x), y: CGFloat(y))
        return removeTileAt(coord: coord)
    }
    
    /// Clear all tiles.
    public func clearTiles() {
        let currentTiles = getTiles()
        currentTiles.forEach { tile in
            tile.removeAnimation()
            tile.removeFromParent()
        }
        removeTilesFromDataStorage(currentTiles)
        self.tiles = TilesArray(columns: Int(tilemap.size.width), rows: Int(tilemap.size.height))
    }
    
    /// Removes tiles from the map's tile storage in one pass over the caches.
    ///
    /// - parameter tilesToRemove: `[SKTile]` tiles to remove.
    internal func removeTilesFromDataStorage(_ tilesToRemove: [SKTile]) {
        guard let dataStorage = tilemap?.dataStorage, (tilesToRemove.isEmpty == false) else { return }
        if (tilesToRemove.count == 1) {
            dataStorage.tileRemoved(tilesToRemove[0])
            return
        }
        let removedIDs = Set(tilesToRemove.map { ObjectIdentifier($0) })
        for list in dataStorage.staticTileCache.values {
            list.array.removeAll { removedIDs.contains(ObjectIdentifier($0)) }
        }
        for list in dataStorage.animatedTileCache.values {
            list.array.removeAll { removedIDs.contains(ObjectIdentifier($0)) }
        }
    }
    
    /// Remove the tile at a given coordinate.
    ///
    /// - parameter coord:   `CGPoint` tile coordinate.
    /// - returns: `SKTile?` removed tile.
    public func removeTileAt(coord: CGPoint) -> SKTile? {
        let current = tileAt(coord: coord)
        if let current = current {
            current.removeFromParent()
            self.tiles[Int(coord.x), Int(coord.y)] = nil
            tilemap?.dataStorage?.tileRemoved(current)
        }
        return current
    }
    
    /// Build a tile at the given coordinate with the given id. Returns nil if the id cannot be resolved.
    ///
    /// - parameter coord:    `CGPoint` x&y coordinate.
    /// - parameter id:       `UInt32` tile id.
    /// - returns: `SKTile?`  tile object.
    fileprivate func buildTileAt(coord: CGPoint, id: UInt32) -> SKTile? {
        
        // get tile attributes from the current id
        let tileAttrs = flippedTileFlags(id: id)
        
        let globalId = Int(tileAttrs.gid)
        
        if let tileData = tilemap.getTileData(globalID: globalId) {
            
            // get tile object from delegate
            let Tile = (tilemap.delegate != nil) ? tilemap.delegate!.objectForTileType(named: tileData.type) : SKTile.self
            
            if let tile = Tile.init(data: tileData) {
                
                // set the flip flags for this tile
                tile.flipHoriz = tileAttrs.hflip
                tile.flipVert  = tileAttrs.vflip
                tile.flipDiag  = tileAttrs.dflip
                
                // set the tile overlap amount
                tile.setTileOverlap(tilemap.tileOverlap)
                tile.highlightColor = highlightColor
                
                // set the layer property
                tile.layer = self
                tile.highlightDuration = highlightDuration
                
                // get the position in the layer (plus tileset offset)
                let tilePosition = pointForCoordinate(coord: coord, offsetX: tileData.tileset.tileOffset.x, offsetY: tileData.tileset.tileOffset.y)
                
                // add to the layer
                addChild(tile)
                
                // set orientation & position
                tile.orientTile()
                tile.position = tilePosition
                
                // add to the tiles array
                self.tiles[Int(coord.x), Int(coord.y)] = tile
                
                // set the tile zPosition to the current y-coordinate
                //tile.zPosition = coord.y
                
                if tile.texture == nil {
                    Logger.default.log("cannot find a texture for id: \(tileAttrs.gid)", level: .warning, symbol: self.logSymbol)
                }
                
                // add to tile cache
                tilemap?.dataStorage?.tileAdded(tile)

                return tile
                
            } else {
                Logger.default.log("invalid tileset data (id: \(id))", level: .warning, symbol: self.logSymbol)
            }
            
        } else {
            // check for bad gid calls
            if !gidErrors.contains(tileAttrs.gid) {
                gidErrors.append(tileAttrs.gid)
            }
        }
        return nil
    }
    
    /// Place a tile at the given coordinate, replacing (and removing) the current tile there.
    ///
    /// - parameter x:   `Int` x-coordinate
    /// - parameter y:   `Int` y-coordinate
    /// - parameter tile: `SKTile?` tile to place, or `nil` to remove the current tile.
    /// - returns: `SKTile?` the placed tile, or `nil` if the coordinate is invalid or `tile` is `nil`.
    public func setTile(_ x: Int, _ y: Int, tile: SKTile? = nil) -> SKTile? {
        return setTile(at: CGPoint(x: CGFloat(x), y: CGFloat(y)), tile: tile)
    }
    
    /// Place a tile at the given coordinate, replacing (and removing) the current tile there.
    ///
    /// - parameter coord:   `CGPoint` tile coordinate.
    /// - parameter tile: `SKTile?` tile to place, or `nil` to remove the current tile.
    /// - returns: `SKTile?` the placed tile, or `nil` if the coordinate is invalid or `tile` is `nil`.
    public func setTile(at coord: CGPoint, tile: SKTile? = nil) -> SKTile? {
        guard isValid(coord: coord) else {
            return nil
        }
        
        // already placed here
        if let tile = tile, (tileAt(coord: coord) === tile) {
            return tile
        }
        
        // remove the current tile
        let existingTile = removeTileAt(coord: coord)
        
        guard let tile = tile else {
            return nil
        }
        
        // detach the tile from wherever it was before
        if (tile.parent != nil) {
            tile.removeFromParent()
            tilemap?.dataStorage?.tileRemoved(tile)
        }
        
        tile.layer = self
        self.tiles[Int(coord.x), Int(coord.y)] = tile
        
        // set orientation & anchor point from the tile data
        if (tile.tileData.tileset != nil) {
            tile.orientTile()
        }
        
        // position in the layer, plus the tileset offset
        let tileOffset = tile.tileData.tileset?.tileOffset ?? CGPoint.zero
        tile.position = pointForCoordinate(coord: coord, offsetX: tileOffset.x, offsetY: tileOffset.y)
        
        if let currentTile = existingTile {
            tile.zPosition = currentTile.zPosition
        }
        
        addChild(tile)
        
        // add to tile cache
        tilemap?.dataStorage?.tileAdded(tile)
        return tile
    }
    
    // MARK: - Overlap
    
    /// Set the tile overlap. Only accepts a value between 0 - 1.0
    ///
    /// - parameter overlap: `CGFloat` tile overlap value.
    public func setTileOverlap(_ overlap: CGFloat) {
        for tile in tiles where tile != nil {
            tile!.setTileOverlap(overlap)
        }
    }
    
    // MARK: - Callbacks
    /// Called when the layer is finished rendering.
    ///
    /// - parameter duration: `TimeInterval` fade-in duration.
    override public func didFinishRendering(duration: TimeInterval = 0) {
        super.didFinishRendering(duration: duration)
    }
    
    // MARK: - Shaders
    
    /// Set a shader for tiles in this layer.
    ///
    /// - parameter sktiles:      `[SKTile]` tiles to apply shader to.
    /// - parameter named:    `String` shader file name.
    /// - parameter uniforms: `[SKUniform]` array of shader uniforms.
    public func setShader(for sktiles: [SKTile], named: String, uniforms: [SKUniform] = []) {
        let shader = SKShader(fileNamed: named)
        shader.uniforms = uniforms
        for tile in sktiles {
            tile.shader = shader
        }
    }
    
    // MARK: - Debugging
    /// Visualize the layer's boundary shape.
    override public func drawBounds() {
        tiles.compactMap{ $0 }.forEach { $0.drawBounds() }
        super.drawBounds()
    }
    
    override public func debugLayer() {
        super.debugLayer()
        for tile in getTiles() {
            log(tile.debugDescription, level: .debug)
        }
    }
    
    // MARK: - Updating: Tile Layer
    
    /// Run animation actions on all tiles layer.
    override public func runAnimationAsActions() {
        super.runAnimationAsActions()
        let animatedTiles = getTiles().filter { tile in
            tile.tileData.isAnimated == true
        }
        animatedTiles.forEach { $0.runAnimationAsActions() }
    }
    
    /// Remove tile animations.
    ///
    /// - parameter restore: `Bool` restore tile/obejct texture.
    override public func removeAnimationActions(restore: Bool = false) {
        super.removeAnimationActions(restore: restore)
        let animatedTiles = getTiles().filter { tile in
            tile.tileData.isAnimated == true
        }
        animatedTiles.forEach { $0.removeAnimationActions(restore: restore) }
    }
    
    /// Update the tile layer before each frame is rendered.
    ///
    /// - parameter currentTime: `TimeInterval` update interval.
    override public func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        guard (self.updateMode != TileUpdateMode.actions) else { return }
        
    }
}




// MARK: - Extensions

extension SKTiledLayerObject {
    
    // convenience properties
    public var width: CGFloat { return tilemap.width }
    public var height: CGFloat { return tilemap.height }
    public var tileWidth: CGFloat { return tilemap.tileWidth }
    public var tileHeight: CGFloat { return tilemap.tileHeight }
    
    public var sizeHalved: CGSize { return tilemap.sizeHalved }
    public var tileWidthHalf: CGFloat { return tilemap.tileWidthHalf }
    public var tileHeightHalf: CGFloat { return tilemap.tileHeightHalf }
    public var sizeInPoints: CGSize { return tilemap.sizeInPoints }
    
    /// Layer transparency.
    public var opacity: CGFloat {
        get {
            return self.alpha
        }
        set {
            self.alpha = newValue
        }
    }
    
    /// Layer visibility.
    public var visible: Bool {
        get {
            return !self.isHidden
        }
        set {
            self.isHidden = !newValue
        }
    }
    
    /// Add a node at the given coordinates. By default, the zPositon
    /// will be higher than all of the other nodes in the layer.
    ///
    /// - parameter node:      `SKNode` object.
    /// - parameter x:         `Int` x-coordinate.
    /// - parameter y:         `Int` y-coordinate.
    /// - parameter dx:        `CGFloat` offset x-amount.
    /// - parameter dy:        `CGFloat` offset y-amount.
    /// - parameter zpos:      `CGFloat?` optional z-position.
    public func addChild(_ node: SKNode, _ x: Int, _ y: Int, dx: CGFloat = 0, dy: CGFloat = 0, zpos: CGFloat? = nil) {
        let coord = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let offset = CGPoint(x: dx, y: dy)
        addChild(node, coord: coord, offset: offset, zpos: zpos)
    }
    
    /// Returns a point for a given coordinate in the layer, with optional offset values for x/y.
    ///
    /// - parameter x:       `Int` x-coordinate.
    /// - parameter y:       `Int` y-coordinate.
    /// - parameter offsetX: `CGFloat` x-offset value.
    /// - parameter offsetY: `CGFloat` y-offset value.
    /// - returns: `CGPoint` position in layer.
    public func pointForCoordinate(_ x: Int, _ y: Int, offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> CGPoint {
        return self.pointForCoordinate(coord: CGPoint(x: CGFloat(x), y: CGFloat(y)), offsetX: offsetX, offsetY: offsetY)
    }
    
    /// Returns a point for a given coordinate in the layer, with optional offset.
    ///
    /// - parameter coord:  `CGPoint` tile coordinate.
    /// - parameter offset: `CGPoint` tile offset.
    /// - returns: `CGPoint` point in layer.
    public func pointForCoordinate(coord: CGPoint, offset: CGPoint) -> CGPoint {
        return self.pointForCoordinate(coord: coord, offsetX: offset.x, offsetY: offset.y)
    }
    
    /// Returns a point for a given coordinate in the layer, with optional offset.
    ///
    /// - parameter coord:  `CGPoint` tile coordinate.
    /// - parameter tileOffset: `TileOffset` tile offset hint.
    /// - returns: `CGPoint` point in layer.
    public func pointForCoordinate(coord: CGPoint, tileOffset: SKTiledLayerObject.TileOffset = .center) -> CGPoint {
        var offset = CGPoint(x: 0, y: 0)
        switch tileOffset {
            case .top:
                offset = CGPoint(x: 0, y: -tileHeightHalf)
            case .topLeft:
                offset = CGPoint(x: -tileWidthHalf, y: -tileHeightHalf)
            case .topRight:
                offset = CGPoint(x: tileWidthHalf, y: -tileHeightHalf)
            case .bottom:
                offset = CGPoint(x: 0, y: tileHeightHalf)
            case .bottomLeft:
                offset = CGPoint(x: -tileWidthHalf, y: tileHeightHalf)
            case .bottomRight:
                offset = CGPoint(x: tileWidthHalf, y: tileHeightHalf)
            case .left:
                offset = CGPoint(x: -tileWidthHalf, y: 0)
            case .right:
                offset = CGPoint(x: tileWidthHalf, y: 0)
            default:
                break
        }
        return self.pointForCoordinate(coord: coord, offsetX: offset.x, offsetY: offset.y)
    }
    
    /// Returns a tile coordinate for a given vector_int2 coordinate.
    ///
    /// - parameter vec2:    `int2` vector int2 coordinate.
    /// - parameter offsetX: `CGFloat` x-offset value.
    /// - parameter offsetY: `CGFloat` y-offset value.
    /// - returns: `CGPoint` position in layer.
    public func pointForCoordinate(vec2: int2, offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> CGPoint {
        return self.pointForCoordinate(coord: vec2.cgPoint, offsetX: offsetX, offsetY: offsetY)
    }
    
    /// Returns a tile coordinate for a given point in the layer.
    ///
    /// - parameter x:       `Int` x-position.
    /// - parameter y:       `Int` y-position.
    /// - returns: `CGPoint` position in layer.
    public func coordinateForPoint(_ x: Int, _ y: Int) -> CGPoint {
        return self.coordinateForPoint(CGPoint(x: CGFloat(x), y: CGFloat(y)))
    }
    
    /// Returns the center point of a layer.
    public var center: CGPoint {
        return CGPoint(x: (size.width / 2) - (size.width * anchorPoint.x), y: (size.height / 2) - (size.height * anchorPoint.y))
    }
    
    /// Calculate the distance from the layer's origin
    public func distanceFromOrigin(_ pos: CGPoint) -> CGVector {
        let dx = (pos.x - center.x)
        let dy = (pos.y - center.y)
        return CGVector(dx: dx, dy: dy)
    }
    
    nonisolated override public var description: String {
        MainActor.assumeIsolated {
            let isTopLevel = self.parents.count == 1
            let indexString = (isTopLevel == true) ? ", index: \(index)" : ""
            let layerTypeString = (layerType != TiledLayerType.none) ? layerType.stringValue.capitalized : "Background"
            return "\(layerTypeString) Layer: \"\(self.path)\"\(indexString), zpos: \(Int(self.zPosition))"
        }
    }
    
    nonisolated override public var debugDescription: String { MainActor.assumeIsolated { return "<\(description)>" } }
    
    /// Returns a value for use in a dropdown menu.
    public var menuDescription: String {
        let parentCount = parents.count
        let isGrouped: Bool = (parentCount > 1)
        var layerSymbol: String = layerType.symbol
        let isGroupNode = (layerType == TiledLayerType.group)
        let hasChildren: Bool = (childLayers.isEmpty == false)
        if (isGroupNode == true) {
            layerSymbol = (hasChildren == true) ? "▿" : "▹"
        }
        
        let filler = (isGrouped == true) ? String(repeating: "  ", count: parentCount - 1) : ""
        return "\(filler)\(layerSymbol) \(layerName)"
    }
}


extension SKTiledLayerObject {
    
    /// String representing the layer name (null if not set).
    public var layerName: String {
        return self.name ?? "null"
    }
    
    /// Returns an array of parent layers, beginning with the current.
    public var parents: [SKNode] {
        var current = self as SKNode
        var result: [SKNode] = [current]
        while current.parent != nil {
            if (current.parent! as? SKTiledLayerObject != nil) {
                result.append(current.parent!)
            }
            current = current.parent!
        }
        return result
    }
    
    /// Returns an array of child layers.
    public var childLayers: [SKNode] {
        return self.enumerate()
    }
    
    /// Returns an array of tiles/objects that conform to the `SKTiledGeometry` protocol.
    ///
    /// - returns: `[SKNode]` array of child objects.
    public func renderableObjects() -> [SKNode] {
        var result: [SKNode] = []
        enumerateChildNodes(withName: "*") { node, _ in
            if (node as? SKTiledGeometry != nil) {
                result.append(node)
            }
        }
        return result
    }
    
    /// Indicates the layer is a top-level layer.
    public var isTopLevel: Bool { return self.parents.count <= 1 }
    
    /// Translate the parent hierarchy to a path string
    public var path: String {
        let allParents: [SKNode] = self.parents.reversed()
        if (allParents.count == 1) { return self.layerName }
        return allParents.reduce("") { result, node in
            let comma = allParents.firstIndex(of: node)! < allParents.count - 1 ? "/" : ""
            return result + "\(node.name ?? "nil")" + comma
        }
    }
    
    /// Returns the actual zPosition as rendered by the scene.
    internal var actualZPosition: CGFloat {
        // `parents` begins with the layer itself
        return (isTopLevel == true) ? zPosition : parents.reduce(0, { result, parent in
            return result + parent.zPosition
        })
    }
    
    /// Returns a string array representing the current layer name & index.
    public var layerStatsDescription: [String] {
        let digitCount: Int = self.tilemap.lastIndex.digitCount + 1
        
        let parentNodes = self.parents
        let isGrouped: Bool = (parentNodes.count > 1)
        let isGroupNode: Bool = (self as? SKGroupLayer != nil)
        
        let indexString = (isGrouped == true) ? String(repeating: " ", count: digitCount) : "\(index).".zfill(length: digitCount, pattern: " ")
        let typeString = self.layerType.stringValue.capitalized.zfill(length: 6, pattern: " ", padLeft: false)
        let hasChildren: Bool = (childLayers.isEmpty == false)
        
        var layerSymbol: String = " "
        if (isGroupNode == true) {
            layerSymbol = (hasChildren == true) ? "▿" : "▹"
        }
        let filler = (isGrouped == true) ? String(repeating: "  ", count: parentNodes.count - 1) : ""
        
        let layerPathString = "\(filler)\(layerSymbol) \"\(layerName)\""
        let layerVisibilityString: String = (self.isolated == true) ? "(i)" : (self.visible == true) ? "[x]" : "[ ]"
        
        // layer position string, filters out child layers with no offset
        var positionString = self.position.shortDescription
        if (self.position.x == 0) && (self.position.y == 0) {
            positionString = ""
        }
        
        let graphStat = (renderInfo.gn != nil) ? "\(renderInfo.gn!)" : ""
        
        return [indexString, typeString, layerVisibilityString, layerPathString, positionString,
                self.sizeInPoints.shortDescription, self.offset.shortDescription,
                self.anchorPoint.shortDescription, "\(Int(self.zPosition))", self.opacity.roundTo(2), graphStat]
    }
    
    /// Recursively enumerate child nodes.
    ///
    /// - returns: `[SKNode]` child elements.
    internal func enumerate() -> [SKNode] {
        var result: [SKNode] = [self]
        for child in children {
            if let node = child as? SKTiledLayerObject {
                result += node.enumerate()
            }
        }
        return result
    }
}



extension SKTiledLayerObject.TiledLayerType {
    /// Returns a string representation of the layer type.
    internal var stringValue: String { return "\(self)".lowercased() }
    internal var symbol: String {
        switch self {
            case .tile: return "⊞"
            case .object: return "⧉"
            default: return ""
        }
    }
}

extension SKTiledLayerObject.TiledLayerType: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        switch self {
            case .none: return "none"
            case .tile: return "tile"
            case .object: return "object"
            case .image: return "image"
            case .group: return "group"
        }
    }
    
    var debugDescription: String {
        return description
    }
}



/// Initialize a color with RGB Integer values (0-255).
///
/// - parameter r: `Int` red component.
/// - parameter g: `Int` green component.
/// - parameter b: `Int` blue component.
/// - returns: `SKColor` color with given values.
internal func SKColorWithRGB(_ r: Int, g: Int, b: Int) -> SKColor {
    return SKColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: 1.0)
}


/// Initialize a color with RGBA Integer values (0-255).
///
/// - parameter r: `Int` red component.
/// - parameter g: `Int` green component.
/// - parameter b: `Int` blue component.
/// - parameter a: `Int` alpha component.
/// - returns: `SKColor` color with given values.
internal func SKColorWithRGBA(_ r: Int, g: Int, b: Int, a: Int) -> SKColor {
    return SKColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: CGFloat(a)/255.0)
}



// MARK: - Deprecated


extension SKTiledLayerObject {
}


extension SKTileLayer {
}
