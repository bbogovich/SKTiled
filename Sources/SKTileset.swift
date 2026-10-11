//
//  SKTileset.swift
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

import SpriteKit



/// ## Overview
///
/// The tileset class manages a set of `SKTilesetData` objects, which store tile data including global id, texture and animation.
///
/// Tile data is accessed via a local id, and tiles can be instantiated with the resulting `SKTilesetData` instance:
///
/// ```swift
/// if let data = tileset.getTileData(localID: 56) {
///    let tile = SKTile(data: data)
/// }
/// ```
///
/// ### Properties
///
/// | Property              | Description                                     |
/// |-----------------------|-------------------------------------------------|
/// | name                  | Tileset name.                                   |
/// | tilemap               | Reference to parent tilemap.                    |
/// | tileSize              | Tile size (in pixels).                          |
/// | columns               | Number of columns.                              |
/// | tilecount             | Tile count.                                     |
/// | firstGID              | First tile global id.                           |
/// | lastGID               | Last tile global id.                            |
/// | tileData              | Set of tile data structures.                    |
///
///
/// ### Instance Methods ###
///
/// | Method                | Description                                     |
/// |-----------------------|-------------------------------------------------|
/// | addTextures()         | Generate textures from a spritesheet image.     |
/// | addTilesetTile()      | Add & return new tile data object.              |
public class SKTileset: NSObject, SKTiledObject {

    /// Tileset url (external tileset).
    public var url: URL!

    /// Tiled tsx filename (external tileset).
    public var filename: String! = nil

    /// Unique object id.
    public var uuid: String = UUID().uuidString

    /// Tileset name
    public var name: String

    /// Object type.
    public var type: String!

    /// Custom tileset properties.
    public var properties: [String: String] = [:]

    /// Ignore custom properties.
    public var ignoreProperties: Bool = false

    /// Reference to parent tilemap.
    weak public var tilemap: SKTilemap!

    /// Tile size (in pixels).
    public var tileSize: CGSize
    
    /// Tileset logging level.
    internal var loggingLevel: LoggingLevel = LoggingLevel.warning

    /// The number of tile columns.
    public var columns: Int = 0

    /// The number of tiles contained in this set.
    public internal(set) var tilecount: Int = 0

    /// Tile data count.
    public var dataCount: Int {
        return tileData.count
    }

    /// Tile offset value.
    public var firstGID: Int = 0

    /// Returns the last global tile id in the tileset (`firstGID` if the tileset has no tile data).
    public var lastGID: Int {
        return firstGID + (maxLocalID ?? 0)
    }

    /// Returns a range of localized tile ids (`0...0` if the tileset has no tile data).
    public var localRange: ClosedRange<Int> {
        return 0...(maxLocalID ?? 0)
    }

    /// Returns a range of global tile id values (`firstGID...firstGID` if the tileset has no tile data).
    public var globalRange: ClosedRange<Int> {
        return firstGID...lastGID
    }

    // MARK: - Spacing

    /// Spritesheet spacing between tiles.
    public var spacing: Int = 0

    /// Spritesheet border margin.
    public var margin: Int = 0

    /// Offset for drawing tiles.
    public var tileOffset = CGPoint.zero

    /// Texture name (if created from source)
    public var source: String!

    /// Tile data, keyed by local id.
    private var tileDataByID: [Int: SKTilesetData] = [:]

    /// Highest local id with tile data, or `nil` if the tileset has no tile data.
    private var maxLocalID: Int?

    /// All tile data.
    private var tileData: Dictionary<Int, SKTilesetData>.Values {
        return tileDataByID.values
    }

    /// Stores tile data under its local id.
    private func insertTileData(_ data: SKTilesetData) {
        tileDataByID[data.id] = data
        maxLocalID = max(maxLocalID ?? data.id, data.id)
    }

    /// Indicates the tileset is a collection of images.
    public var isImageCollection: Bool = false

    /// The tileset is stored in an external file.
    public var isExternalTileset: Bool {
        return filename != nil
    }

    /// Source image transparency color.
    public var transparentColor: SKColor?

    /// Indicates all of the tile data textures have been set.
    public internal(set) var isRendered: Bool = false

    /// Returns the difference in tile size vs. map tile size.
    internal var mapOffset: CGPoint {
        guard let tilemap = tilemap else { return .zero }
        return CGPoint(x: tileSize.width - tilemap.tileSize.width, y: tileSize.height - tilemap.tileSize.height)
    }

    /// Scaling factor for text objects, etc.
    public var renderQuality: CGFloat = 8 {
        didSet {
            guard renderQuality != oldValue else { return }
            tileData.forEach { $0.renderQuality = renderQuality }
        }
    }

    /// Initialize with basic properties.
    ///
    /// - parameter name:     `String` tileset name.
    /// - parameter size:     `CGSize` tile size.
    /// - parameter firstgid: `Int` first gid value.
    /// - parameter columns:  `Int` number of columns.
    /// - parameter offset:   `CGPoint` tileset offset value.
    /// - returns: `SKTileset` tileset object.
    public init(name: String, tileSize size: CGSize,
                firstgid: Int = 1, columns: Int = 0,
                offset: CGPoint = CGPoint.zero) {

        self.name = name
        self.tileSize = size

        super.init()
        self.firstGID = firstgid
        self.columns = columns
        self.tileOffset = offset
    }

    /// Initialize with an external tileset (only source and first gid are given).
    ///
    /// - parameter source:   `String` source file name.
    /// - parameter firstgid: `Int` first gid value.
    /// - parameter tilemap:  `SKTilemap` parent tile map node.
    /// - parameter offset:   `CGPoint` tile drawing offset.
    public init(source: String, firstgid: Int,
                tilemap: SKTilemap, offset: CGPoint = CGPoint.zero) {


        let filepath = source.components(separatedBy: "/").last!
        self.filename = filepath

        self.firstGID = firstgid
        self.tilemap = tilemap
        self.tileOffset = offset

        // setting these here, even though it may different later
        self.name = filepath.components(separatedBy: ".")[0]
        self.tileSize = tilemap.tileSize

        super.init()
        self.ignoreProperties = tilemap.ignoreProperties
    }

    /// Initialize with attributes directly from TMX file.
    ///
    /// - parameter attributes: `[String: String]` attributes dictionary.
    /// - parameter offset:     `CGPoint` pixel offset in x/y.
    public init?(attributes: [String: String],
                 offset: CGPoint = CGPoint.zero) {

        // name, width and height are required
        guard let setName = attributes["name"],
              let width = attributes["tilewidth"].flatMap({ Int($0) }),
              let height = attributes["tileheight"].flatMap({ Int($0) }),
              width > 0, height > 0 else {
            return nil
        }

        // columns is optional in older maps
        if let columnCount = attributes["columns"].flatMap({ Int($0) }) {
            self.columns = columnCount
        }

        // first gid won't be in an external tileset
        if let firstgid = attributes["firstgid"].flatMap({ Int($0) }) {
            self.firstGID = firstgid
        }

        if let tileCount = attributes["tilecount"].flatMap({ Int($0) }) {
            self.tilecount = tileCount
        }

        // optionals
        if let spacing = attributes["spacing"].flatMap({ Int($0) }) {
            self.spacing = spacing
        }

        if let margins = attributes["margin"].flatMap({ Int($0) }) {
            self.margin = margins
        }

        self.name = setName
        self.tileSize = CGSize(width: width, height: height)

        super.init()
        self.tileOffset = offset
    }

    /// Initialize with a TSX file name.
    ///
    /// - parameter fileNamed:  `String` tileset file name.
    public init(fileNamed: String) {
        self.name = ""
        self.tileSize = CGSize.zero
        super.init()
    }

    // MARK: - Loading

    /// Loads Tiled TSX files.
    ///
    /// Pass the result to `SKTilemap.load(url:withTilesets:)` to share tilesets between maps.
    ///
    /// - Parameters:
    ///   - urls: TSX files.
    ///   - bundle: bundle used for file-name and asset catalog fallbacks, or `nil` for none.
    ///   - delegate: optional tilemap delegate.
    ///   - tilesetDataSource: optional tileset data source.
    ///   - ignoreProperties: ignore custom properties from Tiled.
    ///   - loggingLevel: logging verbosity.
    /// - Returns: tilesets, in the order of `urls`.
    /// - Throws: `TiledError` describing the file and the problem.
    public static func load(urls: [URL],
                            bundle: Bundle? = nil,
                            delegate: SKTilemapDelegate? = nil,
                            tilesetDataSource: SKTilesetDataSource? = nil,
                            ignoreProperties: Bool = false,
                            loggingLevel: LoggingLevel = TiledGlobals.default.loggingLevel) throws -> [SKTileset] {

        let startTime = Date()
        let tilesets = try SKTilemapParser().load(tilesetURLs: urls,
                                                  bundle: bundle,
                                                  delegate: delegate,
                                                  tilesetDataSource: tilesetDataSource,
                                                  ignoreProperties: ignoreProperties,
                                                  loggingLevel: loggingLevel)
        let timeStamp = String(format: "%.3f", Date().timeIntervalSince(startTime))
        Logger.default.log("\(tilesets.count) tilesets rendered in: \(timeStamp)s", level: .success)
        return tilesets
    }

    // MARK: - Textures

    /// Adds tile textures from a sprite sheet image file.
    ///
    /// - Parameters:
    ///   - url: image file (any format ImageIO can decode).
    ///   - replace: replace the textures of existing tiles instead of adding tiles.
    ///   - transparent: optional transparent color hex value.
    /// - Throws: `TiledError` if the image cannot be read.
    public func addTextures(fromSpriteSheet url: URL, replace: Bool = false, transparent: String? = nil) throws {
        let image = try TiledImageLoader.cgImage(contentsOf: url)
        addTextures(fromSpriteSheet: image, source: url.path, replace: replace, transparent: transparent)
    }

    /// Adds tile textures from a decoded sprite sheet image.
    ///
    /// - Parameters:
    ///   - image: sprite sheet image.
    ///   - source: image path or name, recorded as the tileset's `source`.
    ///   - replace: replace the textures of existing tiles instead of adding tiles.
    ///   - transparent: optional transparent color hex value.
    public func addTextures(fromSpriteSheet image: CGImage, source: String, replace: Bool = false, transparent: String? = nil) {
        let timer = Date()

        self.source = source

        // parse the transparent color
        if let transparent = transparent {
            transparentColor = SKColor(hexString: transparent)
        }

        if (replace == true) {
            self.log("replacing spritesheet with: \"\(source.url.lastPathComponent)\"", level: .info)
        }

        self.log("spritesheet: \"\(source.url.lastPathComponent)\"", level: .debug)

        // create the texture
        let sourceTexture = SKTexture(cgImage: image)
        sourceTexture.filteringMode = .nearest

        let textureWidth = Int(sourceTexture.size().width)
        let textureHeight = Int(sourceTexture.size().height)
        let tileWidth = Int(tileSize.width)
        let tileHeight = Int(tileSize.height)

        guard tileWidth > 0, tileHeight > 0, textureWidth > 0, textureHeight > 0 else {
            self.log("cannot slice spritesheet \"\(source.url.lastPathComponent)\": tile size \(tileWidth)x\(tileHeight), image size \(textureWidth)x\(textureHeight).", level: .error)
            return
        }

        // calculate the number of tiles in the texture
        let marginReal = margin * 2
        let rowTileCount = max(0, (textureHeight - marginReal + spacing) / (tileHeight + spacing))  // number of tiles (height)
        let colTileCount = max(0, (textureWidth - marginReal + spacing) / (tileWidth + spacing))    // number of tiles (width)

        // set columns property
        if columns == 0 {
            columns = colTileCount
        }

        // tile count
        let totalTileCount = colTileCount * rowTileCount
        tilecount = tilecount > 0 ? tilecount : totalTileCount

        let rectWidth = self.tileSize.width / CGFloat(textureWidth)
        let rectHeight = self.tileSize.height / CGFloat(textureHeight)

        var tilesAdded: Int = 0

        for tileID in 0..<totalTileCount {
            let col = tileID % colTileCount
            let row = tileID / colTileCount

            // texture rects are y-up: row 0 is at the top of the image, below the top margin
            let x = margin + col * (tileWidth + spacing)
            let y = textureHeight - margin - tileHeight - row * (tileHeight + spacing)

            let rectStartX = CGFloat(x) / CGFloat(textureWidth)
            let rectStartY = CGFloat(y) / CGFloat(textureHeight)

            // create texture rectangle
            let tileRect = CGRect(x: rectStartX, y: rectStartY, width: rectWidth, height: rectHeight)
            let tileTexture = SKTexture(rect: tileRect, in: sourceTexture)
            tileTexture.filteringMode = .nearest

            // add the tile data properties, or replace the texture
            if (replace == false) {
                _ = self.addTilesetTile(tileID, texture: tileTexture)
            } else {
                _ = self.setDataTexture(tileID, texture: tileTexture)
            }

            tilesAdded += 1
        }

        self.isRendered = true
        let tilesetBuildTime = Date().timeIntervalSince(timer)

        // time results
        if (replace == false) {
            let timeStamp = String(format: "%.\(String(3))f", tilesetBuildTime)
            Logger.default.log("tileset \"\(name)\" built in: \(timeStamp)s (\(tilesAdded) tiles)", level: .debug, symbol: self.logSymbol)
        } else {

            let animatedData: [SKTilesetData] = self.tileData.filter { $0.isAnimated == true }

            // update animated data
            tilemap?.dataStorage?.tilesetSpriteSheetUpdated(self, animatedTiles: animatedData)

        }
    }

    // MARK: - Tile Data

    /// Add tileset tile data attributes. Returns a new `SKTilesetData` object, or nil if tile data already exists with the given id.
    ///
    /// - parameter tileID:  `Int` local tile ID.
    /// - parameter texture: `SKTexture` texture for tile at the given id.
    /// - returns: `SKTilesetData?` tileset data (or nil if the data exists).
    public func addTilesetTile(_ tileID: Int, texture: SKTexture) -> SKTilesetData? {
        guard tileDataByID[tileID] == nil else {
            log("tile data exists at id: \(tileID)", level: .error)
            return nil
        }

        texture.filteringMode = .nearest
        let data = SKTilesetData(id: tileID, texture: texture, tileSet: self)

        // add to tile cache

        data.ignoreProperties = ignoreProperties
        insertTileData(data)
        data.parseProperties(completion: nil)
        return data
    }

    /// Adds a tile to an image collection tileset from an image file.
    ///
    /// - Parameters:
    ///   - tileID: local tile id.
    ///   - url: image file (any format ImageIO can decode).
    /// - Returns: new tile data, or `nil` if the id is already in use.
    /// - Throws: `TiledError` if the image cannot be read.
    public func addTilesetTile(_ tileID: Int, url: URL) throws -> SKTilesetData? {
        let image = try TiledImageLoader.cgImage(contentsOf: url)
        return addTilesetTile(tileID, image: image, source: url.path)
    }

    /// Adds a tile to an image collection tileset from a decoded image.
    ///
    /// - Parameters:
    ///   - tileID: local tile id.
    ///   - image: tile image.
    ///   - source: image path or name, recorded as the tile's `source`.
    /// - Returns: new tile data, or `nil` if the id is already in use.
    public func addTilesetTile(_ tileID: Int, image: CGImage, source: String) -> SKTilesetData? {
        guard tileDataByID[tileID] == nil else {
            log("tile data exists at id: \(tileID)", level: .error)
            return nil
        }

        isImageCollection = true

        let sourceTexture = SKTexture(cgImage: image)
        sourceTexture.filteringMode = .nearest
        
        // create the tile data and set the source size here (as tileset size won't be accurate)
        let data = SKTilesetData(id: tileID, texture: sourceTexture, tileSet: self)
        data.sourceSize = sourceTexture.size()
        data.ignoreProperties = ignoreProperties
        
        // add the image name to the source attribute
        data.source = source
        insertTileData(data)
        data.parseProperties(completion: nil)
        return data
    }

    /// Create new data from the given texture image path. Returns a new tileset data instance & the local id associated with it.
    ///
    /// - parameter source: source image name.
    /// - returns: local tile id & tileset data (or nil if the data exists).
    public func addTilesetTile(source: String) -> (id: UInt32, data: SKTilesetData)? {
        let nextTileId = tilecount + 1
        let nextData = SKTilesetData(id: nextTileId, texture: SKTexture(imageNamed: source), tileSet: self)
        return (UInt32(nextTileId), nextData)
    }

    /// Set(replace) the texture for a given tile id.
    ///
    /// - parameter id:      `Int` local tile id.
    /// - parameter texture: `SKTexture` texture for tile at the given id.
    /// - returns: `SKTexture?` previous tile data texture.
    @discardableResult
    public func setDataTexture(_ id: Int, texture: SKTexture) -> SKTexture? {
        guard let data = getTileData(localID: id) else {
            if (loggingLevel.rawValue <= 1) {
                log("tile data not found for id: \(id)", level: .error)
            }
            return nil
        }

        let current = data.texture.copy() as? SKTexture

        texture.filteringMode = .nearest
        data.texture = texture

        // update the tiles using this data
        tilemap?.dataStorage?.tileDataTextureChanged(data)

        return current
    }

    /// Replaces the texture for a tile with an image file.
    ///
    /// - Parameters:
    ///   - id: local tile id.
    ///   - url: image file (any format ImageIO can decode).
    /// - Returns: previous texture.
    /// - Throws: `TiledError` if the image cannot be read.
    @discardableResult
    public func setDataTexture(_ id: Int, url: URL) throws -> SKTexture? {
        let image = try TiledImageLoader.cgImage(contentsOf: url)
        return setDataTexture(id, texture: TiledImageLoader.texture(from: image))
    }

    /// Returns true if the tileset contains the given ID (local).
    ///
    /// - parameter localID:  `UInt32` local tile id.
    /// - returns: `Bool` tileset contains the local id.
    internal func contains(localID: UInt32) -> Bool {
        return (maxLocalID != nil) && (localRange ~= Int(localID))
    }

    /// Returns true if the tileset contains the global ID.
    ///
    /// - parameter gid:  `UInt32` global tile id.
    /// - returns: `Bool` tileset contains the global id.
    public func contains(globalID gid: UInt32) -> Bool {
        return (maxLocalID != nil) && (globalRange ~= Int(gid))
    }

    /// Returns tile data for the given global tile ID.
    ///
    /// ** Tiled ID == GID + 1
    ///
    /// - parameter gid: `Int` global tile id.
    /// - returns: `SKTilesetData?` tile data object.
    public func getTileData(globalID gid: Int) -> SKTilesetData? {
        // parse out flipped flags
        var id = rawTileID(id: gid)
        id = getLocalID(forGlobalID: id)
        return tileDataByID[id]
    }

    /// Returns tile data for the given local tile ID.
    ///
    /// - parameter id: `Int` local tile id.
    /// - returns: `SKTilesetData?` tile data object.
    public func getTileData(localID id: Int) -> SKTilesetData? {
        let localID = rawTileID(id: id)
        return tileDataByID[localID]
    }

    /// Returns tile data with the given property.
    ///
    /// - parameter property: `String` property name.
    /// - returns: `[SKTilesetData]` array of tile data.
    public func getTileData(withProperty property: String) -> [SKTilesetData] {
        return tileData.filter { $0.properties[property] != nil }
    }

    /// Returns tile data with the given name & animated state.
    ///
    /// - parameter name:      `String` data name.
    /// - parameter isAnimated: `Bool` filter data that is animated.
    /// - returns: `[SKTilesetData]` array of tile data.
    public func getTileData(named name: String, isAnimated: Bool = false) -> [SKTilesetData] {
        return tileData.filter {
            ($0.name == name) && ($0.isAnimated == isAnimated)
        }
    }

    /// Returns tile data with the given type.
    ///
    /// - parameter ofType: `String` data type.
    /// - returns: `[SKTilesetData]` array of tile data.
    public func getTileData(ofType: String) -> [SKTilesetData] {
        return tileData.filter { $0.type == ofType }
    }

    /// Returns tile data with the given property.
    ///
    /// - parameter property: `String` property name.
    /// - parameter value:    `AnyObject` value
    /// - returns: `[SKTilesetData]` array of tile data.
    public func getTileData(withProperty property: String, _ value: Any) -> [SKTilesetData] {
        var result: [SKTilesetData] = []
        let tiledata = getTileData(withProperty: property)
        for data in tiledata {
            if data.stringForKey(property)! == value as? String {
                result.append(data)
            }
        }
        return result
    }

    /// Returns animated tile data.
    ///
    /// - returns: `[SKTilesetData]` array of animated tile data.
    public func getAnimatedTileData() -> [SKTilesetData] {
        return tileData.filter { $0.isAnimated == true }
    }

    /// Convert a global ID to the tileset's local ID.
    ///
    /// - parameter gid: `Int` global id.
    /// - returns: `Int`  local tile ID.
    public func getLocalID(forGlobalID gid: Int) -> Int {
        // firstGID is greater than 0 only when added to a tilemap
        let id = (firstGID > 0) ? (gid - firstGID) : gid
        // if the id is less than zero, return the gid
        return (id < 0) ? gid : id
    }

    /// Convert a local ID to a global ID (the same value as `SKTilesetData.globalID`).
    ///
    /// - parameter id: `Int` local id.
    /// - returns: `Int` global tile ID.
    public func getGlobalID(forLocalID id: Int) -> Int {
        return firstGID + id
    }

    /// Check for tile ID flip flags.
    ///
    /// - parameter id: `Int` tile ID.
    /// - returns: `Int` translated ID.
    internal func rawTileID(id: Int) -> Int {
        let uid: UInt32 = UInt32(id)
        // masks for tile flipping
        let flippedDiagonalFlag: UInt32   = 0x20000000
        let flippedVerticalFlag: UInt32   = 0x40000000
        let flippedHorizontalFlag: UInt32 = 0x80000000

        let flippedAll = (flippedHorizontalFlag | flippedVerticalFlag | flippedDiagonalFlag)
        let flippedMask = ~(flippedAll)

        // get the actual gid from the mask
        let gid = uid & flippedMask
        return Int(gid)
    }


    // MARK: - Rendering

    /// Refresh textures for animated tile data.
    internal func setupAnimatedTileData() {
        let animatedData = getAnimatedTileData()
        var framesAdded = 0
        var dataFixed = 0
        if (animatedData.isEmpty == false) {
            animatedData.forEach { data in
                for frame in data.frames where frame.texture == nil{
                    if let frameData = getTileData(localID: frame.id) {
                        if frameData.texture != nil {
                            frame.texture = frameData.texture
                            framesAdded += 1
                        }
                    }
                }
                dataFixed += 1
            }
        }

        if (framesAdded > 0) {
            log("updated \(dataFixed) tile data animations for tileset: \"\(name)\"", level: .debug)
        }
    }
}




/// Tilesets are compared by identity: two tilesets with the same name are still different tilesets.
public func == (lhs: SKTileset, rhs: SKTileset) -> Bool {
    return lhs === rhs
}


extension SKTileset {

    /// Identity hash, consistent with `NSObject.isEqual` (identity) and safe to call off the main actor.
    nonisolated override public var hash: Int {
        return ObjectIdentifier(self).hashValue
    }

    /// String representation of the tileset object.
    nonisolated override public var description: String {
        MainActor.assumeIsolated {
            var desc = "Tileset: \"\(name)\" @ \(tileSize), firstgid: \(firstGID), \(dataCount) tiles"
            if tileOffset.x != 0 || tileOffset.y != 0 {
                desc += ", offset: \(tileOffset.x)x\(tileOffset.y)"
            }
            return desc
        }
    }

    nonisolated override public var debugDescription: String { MainActor.assumeIsolated { return description } }
}
