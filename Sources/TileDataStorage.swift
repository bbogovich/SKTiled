//
//  SKTilemap+DataStorage.swift
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


typealias TileList      = ReferenceArray<SKTile>
typealias ObjectsList   = ReferenceArray<SKTileObject>

typealias DataCache     = [SKTilesetData: TileList]
typealias ActionsCache  = [SKTilesetData: SKAction]


internal enum CacheIsolationMode: Int {
    case none
    case `default`
    case ignored
    case `static`
    case animated
}


/// Data structure for storing and recalling tile data efficiently.

internal class TileDataStorage: Loggable {
    weak var tilemap: SKTilemap?

    var staticTileCache:   DataCache = [:]
    var animatedTileCache: DataCache = [:]
    var actionsCache:      ActionsCache = [:]
    
    var objectsList: ObjectsList
    var blockNotifications: Bool = true

    var isolationMode: CacheIsolationMode = CacheIsolationMode.none {
        didSet {
            guard oldValue != isolationMode else { return }
            self.isolateTilesAction()
        }
    }

    init(map: SKTilemap) {
        tilemap = map
        objectsList  = ObjectsList()
    }

    /// Returns an array of all stored tiles.
    var allTiles: [SKTile] {
        var result: [SKTile] = []
        for items in staticTileCache.enumerated() {
            result.append(contentsOf: items.element.value.array)
        }

        for items in animatedTileCache.enumerated() {
            result.append(contentsOf: items.element.value.array)
        }

        return result
    }

    // MARK: - Updates

    // The map's nodes call these directly, so each map only ever sees its own tiles and objects.

    /// Adds a tile to the cache for its tile data.
    func tileAdded(_ tile: SKTile) {
        addTileToCache(tile: tile)
    }

    /// Removes a tile from whichever cache holds it (a tile may have moved between caches when its
    /// render mode changed), so removed tiles are neither updated nor kept alive.
    func tileRemoved(_ tile: SKTile) {
        for list in staticTileCache.values {
            list.remove(where: { $0 === tile })
        }
        for list in animatedTileCache.values {
            list.remove(where: { $0 === tile })
        }
    }

    /// Adds an object to the objects list.
    func objectAdded(_ object: SKTileObject) {
        guard objectsList.contains(where: { $0 == object }) == false else {
            return
        }
        objectsList.append(object)
    }

    /// Called when a tileset's spritesheet is replaced; rebuilds the animations that use it.
    ///
    /// - parameter tileset: `SKTileset` tileset.
    /// - parameter animatedTiles: `[SKTilesetData]` animated tile data in the tileset.
    func tilesetSpriteSheetUpdated(_ tileset: SKTileset, animatedTiles: [SKTilesetData]) {
        for data in animatedTiles {
            data.removeAnimation()
            data._frames.forEach { frame in
                if let frameData = tileset.getTileData(localID: frame.id) {
                    frame.texture = frameData.texture
                }
            }
            data.runAnimation()
        }
    }

    /// Called when a tile's render mode is changed.
    ///
    /// - parameter tile: `SKTile` tile.
    /// - parameter oldMode: `TileRenderMode` previous render mode.
    func tileRenderModeChanged(_ tile: SKTile, from oldMode: TileRenderMode) {
        guard let tilemap = tilemap else {
            return
        }


        let tileData = tile.tileData
        tile.drawBounds(withColor: nil, zpos: nil, duration: 0)

        // indicates the tile has an animation override
        let tileHadOverridenAnimation = (oldMode.rawValue > 2) || (oldMode.rawValue < 0)
        // indicates we need to update the tile (ie pop from one list to another)
        var needToUpdateTile = false
        if (tileHadOverridenAnimation == true) {
            moveTileFrom(tile: tile, globalID: oldMode.rawValue)
        }

        
        switch tile.renderMode {

        // tile should not animate
        case .static:
            tile.removeAnimationActions(restore: false)
            needToUpdateTile = true
    
            
        // tile will ignore it's tile data
        case .ignore:
            let existingList: TileList = (tileData.isAnimated == true) ? animatedCacheForTileData(tileData) : cacheForTileData(tileData)
            // remove the tile from the current list
            existingList.remove(where: { $0 == tile })

        // tile has requested new tile data
        case .animated(let gid):
            guard let globalID = gid else {
                break
            }

            var newDataIsAnimated = false

            if let newTileData = tilemap.getTileData(globalID: globalID) {
                let existingList: TileList = (tileData.isAnimated == true) ? animatedCacheForTileData(tileData) : cacheForTileData(tileData)

                // remove the tile from the current list
                existingList.remove(where: { $0 == tile })

                newDataIsAnimated = newTileData.isAnimated
                let nextList: TileList = (newDataIsAnimated == true) ? animatedCacheForTileData(newTileData) : cacheForTileData(newTileData)

                nextList.append(tile)
            }

        default:
            needToUpdateTile = true
        }
        
        
        // refresh the tile's texture
        if (needToUpdateTile == true) {
            
            // turn off notifications for the tile while it is updated
            tile.blockNotifications = true
            
            // update the tile with the current texture
            if let currentTexture = tile.tileData.texture {
                tile.texture = currentTexture
                tile.size = currentTexture.size()
            }

            // turn notifications back on
            tile.blockNotifications = false
        }
    }

    /// Called when a tile data's animation `SKAction` is created.
    ///
    /// - parameter tileData: `SKTilesetData` tile data.
    /// - parameter action: `SKAction` animation action.
    func tileDataActionAdded(_ tileData: SKTilesetData, action: SKAction) {
        actionsCache[tileData] = action
    }

    /// Called when a tile data's texture is replaced; updates every tile that uses it.
    ///
    /// - parameter tileData: `SKTilesetData` tile data.
    func tileDataTextureChanged(_ tileData: SKTilesetData) {
        // if we're in dynamic mode, all of the textures need to be updated in static...
        guard let newTexture = tileData.texture else {
            self.log("invalid texture for data: \(tileData.globalID)", level: .warning)
            return
        }

        let currentTiles = (tileData.isAnimated == true) ? animatedCacheForTileData(tileData) : cacheForTileData(tileData)

        // update every tile that uses this texture
        currentTiles.forEach { tile in

            switch tile.renderMode {
            case .ignore: break
            default:
                // turn off notifications for the tile while it is updated
                tile.blockNotifications = true
                tile.texture = newTexture
                tile.size = newTexture.size()
                tile.blockNotifications = false
            }
        }
    }

    /// Removes an object from the objects list.
    func objectRemoved(_ object: SKTileObject) {
        objectsList.remove(where: { $0 == object}) { obj in
            self.log("object removed: \(obj)", level: .debug)
            self.tilemap?.objectsOverlay.initialized = false
        }
    }

    // MARK: - Caching
    
    /// Add a tile to storage.
    ///
    /// - parameter tile: `SKTile` tile being added.
    /// - parameter data: `SKTilesetData?` optional tile data.
    /// - parameter cache: `TileList?` optional tile list.
    func addTileToCache(tile: SKTile, data: SKTilesetData? = nil, cache: TileList? = nil) {
        let tileData = data ?? tile.tileData
        let currentCache: TileList = (cache != nil) ? cache! : (tileData.isAnimated == true) ? animatedCacheForTileData(tileData) : cacheForTileData(tileData)
        currentCache.append(tile)
        //tile.draw()
    }

    /// Return or create a tile list for the changed data.
    ///
    /// - parameter data: `SKTilesetData` tile data.
    /// - returns `TileList` tile list.
    func tileAnimationAction(for data: SKTilesetData) -> SKAction? {
        guard let savedAction = actionsCache[data] else {
            return nil
        }
        return savedAction
    }

    // MARK: - Helpers

    /// Return or create a tile list for the static data.
    ///
    /// - parameter data: `SKTilesetData` tile data.
    /// - returns `TileList` tile list.
    private func cacheForTileData(_ data: SKTilesetData) -> TileList {
        guard let existingCache = staticTileCache[data] else {
            let newCache = TileList()
            staticTileCache[data] = newCache
            return newCache
        }
        return existingCache
    }

    /// Return or create a tile list for the animated data.
    ///
    /// - parameter data: `SKTilesetData` tile data.
    /// - returns `TileList` tile list.
    private func animatedCacheForTileData(_ data: SKTilesetData) -> TileList {
        guard let existingCache = animatedTileCache[data] else {
            let newCache = TileList()
            animatedTileCache[data] = newCache
            return newCache
        }
        return existingCache
    }

    /// Move tile from one data list to another.
    ///
    /// - parameter tile: `SKTile` tile.
    /// - parameter from: `DataCache` source cache.
    /// - parameter to:   `DataCache` destination cache.
    /// - returns `(sucess: Bool, cache: DataCache, removed: DataCache?)` data was succesfully moved.
    private func moveTileFrom(tile: SKTile, globalID: Int) {
        guard let tilemap = tilemap else {
            return
        }

        if let oldTileData = tilemap.getTileData(globalID: globalID) {
            let nextTileData = tile.tileData
            
            // move tile out of an animated data list
            // put it into another
            let existingList: TileList = (oldTileData.isAnimated == true) ? animatedCacheForTileData(oldTileData) : cacheForTileData(oldTileData)
            
            // remove the tile from the current list
            existingList.remove(where: { $0 == tile })
            let nextDataIsAnimated = nextTileData.isAnimated
            let nextList: TileList = (nextDataIsAnimated == true) ? animatedCacheForTileData(nextTileData) : cacheForTileData(nextTileData)
            nextList.append(tile)
        }
    }
    
    
    /// Move tile data from one cache to another.
    ///
    ///  - parameter data: `SKTilesetData` tile data removed.
    ///  - parameter from: `DataCache` source cache.
    ///  - parameter to:   `DataCache` destination cache.
    ///  - returns `(sucess: Bool, cache: DataCache, removed: DataCache?)` data was succesfully moved.
    private func moveDataFrom(data: SKTilesetData, from sourceCache: inout DataCache, to destCache: inout DataCache) -> (sucess: Bool, cache: DataCache, removed: DataCache?) {
        guard let sourceIndex = sourceCache.index(forKey: data),
            (sourceCache != destCache) else {
            return (false, sourceCache, nil)
        }

        // get the list of associated tiles
        let removedList = sourceCache.remove(at: sourceIndex).value
        if let destIndex = destCache.index(forKey: data) {
            let existingList = destCache.remove(at: destIndex).value
            for tile in existingList {
                removedList.append(tile)
            }
        }
        destCache[data] = removedList
        return (true, destCache, sourceCache)
    }

    /// Build animation frames for the data.
    ///
    /// - parameter data: `SKTilesetData` tile data.
    func buildAnimationForData(data: SKTilesetData) {
        data.removeAnimation()
        data._frames.forEach { frame in
            if let frameData = data.tileset.getTileData(localID: frame.id) {
                frame.texture = frameData.texture
            }
        }
        data.runAnimation()
    }

    /// Isolation mode updated.
    func isolateTilesAction() {

        for tile in allTiles {

            // true if mode is anything but 'none'
            var doHideTile = (isolationMode != .none)

            switch tile.renderMode {

            case .animated(gid: _):
                doHideTile = (doHideTile == true) && (isolationMode != .animated)

            case .ignore:
                doHideTile = (doHideTile == true) && (isolationMode != .ignored)

            case .static:
                doHideTile = (doHideTile == true) && (isolationMode != .static)

            default:
                doHideTile = (doHideTile == true) && (isolationMode != .default)
            }

            tile.isHidden = doHideTile
        }

        NotificationCenter.default.post(
            name: Notification.Name.DataStorage.IsolationModeChanged,
            object: nil,
            userInfo: nil
        )
    }
}


/// :nodoc:
extension TileDataStorage: CustomStringConvertible, CustomDebugStringConvertible, CustomDebugReflectable {
    
    var description: String {
        let staticCount = staticTileCache.count
        let animatedCount = animatedTileCache.count
        return "Tile Data Storage: static: \(staticCount), animated: \(animatedCount)"
    }
    
    var debugDescription: String {
        return description
    }
    
    
    func dumpStatistics() {
        let output = "\n----------- Tile Data Storage -----------"
        var staticOutput = underlined(for: "Static")
        var animatedOutput = underlined(for: "Animated")
        
        for item in staticTileCache.enumerated() {
            let tileData = item.element.key
            let tileList = item.element.value.array
            let tileDataHeader = "\n   - tile data: \(tileData.globalID) (\(tileList.count) tiles):"
            staticOutput += tileDataHeader
            
        }
        
        for item in animatedTileCache.enumerated() {
            let tileData = item.element.key
            let tileList = item.element.value.array
            let tileDataHeader = "\n   - tile data: \(tileData.globalID) (\(tileList.count) tiles):"
            animatedOutput += tileDataHeader
        }
        
        print("\n\(output)\n\(staticOutput)\n\(animatedOutput)")
    }
}


extension TileDataStorage: CustomReflectable {
    
    public var customMirror: Mirror {
        var staticDataCount = 0
        var animatedDataCount = 0
        var staticTileCount = 0
        var animatedTileCount = 0
        
        for (_, item) in staticTileCache.enumerated() {
            staticDataCount += 1
            staticTileCount += item.value.count
        }
        
        for (_, item) in animatedTileCache.enumerated() {
            animatedDataCount += 1
            animatedTileCount += item.value.count
        }
        
        let staticData: [String: Any] = ["data": staticDataCount, "tiles": staticTileCount]
        let animatedData: [String: Any] = ["data": animatedDataCount, "tiles": animatedTileCount]
        
        return Mirror(TileDataStorage.self, children:
                    ["static": staticData,
                     "animated": animatedData,
                     "objects": objectsList.count]
        )
    }
}



// MARK: - Extensions


extension CacheIsolationMode {
    static var all: [CacheIsolationMode] = [.default, .ignored, .static, .animated]
}
