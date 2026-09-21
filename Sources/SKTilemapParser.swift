//
//  SKTilemapParser.swift
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


internal enum ParsingMode {
    case none
    case tmx
    case tsx
    case tx
}


// File types recognized by the parser
internal enum FileType: String {
    case tmx
    case tsx
    case png
    case tx
}


// Document compression type.
internal enum CompressionType: String {
    case uncompressed
    case zlib
    case gzip
    case zstd
}


/// XML parser for Tiled TMX maps, TSX tilesets and TX templates.
///
/// Not meant to be used directly: use `SKTilemap.load(url:)`, `SKTilemap.load(named:in:)` or `SKTileset.load(urls:)`.
///
/// Each file is parsed in turn. Tilesets and templates referenced by a file are queued behind it, and every `source`
/// attribute is resolved relative to the file that contains it (see `TiledAssetResolver`).
internal class SKTilemapParser: NSObject, XMLParserDelegate {

    /// Files waiting to be parsed.
    private var fileQueue: [URL] = []

    /// File currently being parsed.
    private var currentURL: URL!

    /// Standardized path of the current file; tilesets are cached under this key.
    internal var currentFilename: String {
        return currentURL.path
    }

    /// Resolves `source` attributes for the current load.
    private var resolver: TiledAssetResolver!

    /// First error raised inside a parser callback. Parsing stops when it is set.
    private var loadError: TiledError?

    internal var parsingMode: ParsingMode = ParsingMode.none           // current parsing mode
    internal var tileUpdateMode: TileUpdateMode = TileUpdateMode.full  // tile update mode

    /// Delegates
    weak var mapDelegate: SKTilemapDelegate?                           // tilemap delegate
    weak var tilesetDataSource: SKTilesetDataSource?                   // tileset delegate

    internal var tilemap: SKTilemap!

    fileprivate var encoding: TilemapEncoding = .xml                   // xml encoding
    fileprivate var tilesets: [String: SKTileset] = [:]                // tilesets keyed by standardized file path
    fileprivate var tilesetImagesAdded: Int = 0                        // for reporting the number of images added to a collections tileset

    fileprivate var loggingLevel: LoggingLevel = TiledGlobals.default.loggingLevel
    fileprivate var activeElement: String?                             // current object

    // template objects
    fileprivate var templateObjects: [SKTileObject] = []               // objects reference by template files
    fileprivate var activeTemplateTileset: SKTileset?                  // active template object tileset

    fileprivate var lastElement: AnyObject?                            // last element created
    fileprivate var elementPath: [AnyObject] = []                      // current element path

    fileprivate var currentID: Int?                                    // current tile/object ID
    fileprivate var currentType: String?                               // current tile type
    fileprivate var currentProbability: CGFloat?                       // current tile probability

    fileprivate var properties: [String: String] = [:]                 // last properties created
    fileprivate var data: [String: [UInt32]] = [:]                     // store data for tile layers to render in a second pass
    fileprivate var tileData: [UInt32] = []                            // last tile data read
    fileprivate var characterData: String = ""                         // current tile data (string)

    fileprivate var compression: CompressionType = .uncompressed       // compression type
    fileprivate var timer: Date = Date()                               // timer
    fileprivate var ignoreProperties: Bool = false                     // ignore custom properties
    fileprivate var layerIndex: Int = 0

    // MARK: - Loading

    /// Loads a TMX file, with its tilesets and templates, and renders the map.
    ///
    /// - Parameters:
    ///   - url: TMX file.
    ///   - bundle: bundle searched by file name when a `source` is not found relative to its file.
    ///   - delegate: optional tilemap delegate.
    ///   - tilesetDataSource: optional tileset data source.
    ///   - updateMode: tile update mode.
    ///   - withTilesets: tilesets loaded earlier, matched against the map's references by file path.
    ///   - noparse: ignore custom properties from Tiled.
    ///   - loggingLevel: logging verbosity.
    /// - Returns: rendered tile map.
    /// - Throws: `TiledError`.
    internal func load(url: URL,
                       bundle: Bundle?,
                       delegate: SKTilemapDelegate? = nil,
                       tilesetDataSource: SKTilesetDataSource? = nil,
                       updateMode: TileUpdateMode = TiledGlobals.default.updateMode,
                       withTilesets: [SKTileset]? = nil,
                       ignoreProperties noparse: Bool = false,
                       loggingLevel: LoggingLevel = TiledGlobals.default.loggingLevel) throws -> SKTilemap {

        Logger.default.loggingLevel = loggingLevel
        parsingMode = .tmx
        tileUpdateMode = updateMode
        mapDelegate = delegate
        self.tilesetDataSource = tilesetDataSource
        timer = Date()
        ignoreProperties = noparse
        self.loggingLevel = loggingLevel

        let url = url.standardizedFileURL
        resolver = TiledAssetResolver(rootDirectory: url.deletingLastPathComponent(), bundle: bundle)

        for tileset in withTilesets ?? [] {
            guard let filename = tileset.filename else {
                log("tileset \"\(tileset.name)\" has no filename property.", level: .error)
                continue
            }
            tilesets[URL(fileURLWithPath: filename).standardizedFileURL.path] = tileset
        }

        try parseFiles(startingWith: url)

        guard let currentMap = tilemap else {
            throw TiledError.invalidContent(url, reason: "no <map> element found.")
        }

        tilesets = [:]
        mapDelegate?.didReadMap(currentMap)
        didBeginRendering(currentMap)
        return currentMap
    }

    /// Loads TSX tileset files.
    ///
    /// - Parameters:
    ///   - urls: TSX files.
    ///   - bundle: bundle searched by file name when an image is not found relative to its tileset.
    ///   - delegate: optional tilemap delegate.
    ///   - tilesetDataSource: optional tileset data source.
    ///   - noparse: ignore custom properties from Tiled.
    ///   - loggingLevel: logging verbosity.
    /// - Returns: tilesets, in the order of `urls`.
    /// - Throws: `TiledError`.
    internal func load(tilesetURLs urls: [URL],
                       bundle: Bundle?,
                       delegate: SKTilemapDelegate? = nil,
                       tilesetDataSource: SKTilesetDataSource? = nil,
                       ignoreProperties noparse: Bool = false,
                       loggingLevel: LoggingLevel = TiledGlobals.default.loggingLevel) throws -> [SKTileset] {

        Logger.default.loggingLevel = loggingLevel
        parsingMode = .tsx
        mapDelegate = delegate
        self.tilesetDataSource = tilesetDataSource
        timer = Date()
        self.loggingLevel = loggingLevel
        ignoreProperties = noparse

        let urls = urls.map { $0.standardizedFileURL }
        guard let first = urls.first else { return [] }
        resolver = TiledAssetResolver(rootDirectory: first.deletingLastPathComponent(), bundle: bundle)

        for url in urls {
            try parseFiles(startingWith: url)
        }

        let results = urls.compactMap { tilesets[$0.path] }
        tilesets = [:]
        return results
    }

    /// Parses `url` and every file it queues.
    private func parseFiles(startingWith url: URL) throws {
        fileQueue = [url]

        while !fileQueue.isEmpty {
            let fileURL = fileQueue.removeFirst()
            currentURL = fileURL

            let fileExt = fileURL.pathExtension.lowercased()
            switch fileExt {
                case "tmx": parsingMode = .tmx
                case "tsx": parsingMode = .tsx
                case "tx":  parsingMode = .tx
                default:    parsingMode = .none
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw TiledError.fileNotFound(fileURL, referencedBy: nil)
            }

            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw TiledError.unreadableFile(fileURL, reason: error.localizedDescription)
            }

            let filetype = FileType(rawValue: fileExt)?.description ?? "file"
            log("\(parsingMode) parser: reading \(filetype): \"\(fileURL.lastPathComponent)\"", level: .info)

            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = self

            if parser.parse() == false {
                if let loadError = loadError {
                    throw loadError
                }
                throw TiledError.invalidXML(fileURL,
                                            line: parser.lineNumber,
                                            column: parser.columnNumber,
                                            reason: parser.parserError?.localizedDescription ?? "unknown error")
            }
        }
    }

    /// Records the first error and stops parsing.
    private func fail(_ error: TiledError, _ parser: XMLParser) {
        if loadError == nil {
            loadError = error
        }
        parser.abortParsing()
    }

    /// Records an invalid-content error for the current file and stops parsing.
    private func fail(_ reason: String, _ parser: XMLParser) {
        fail(.invalidContent(currentURL, reason: reason), parser)
    }

    /// Resolves an image `source` for the current file, letting the data source substitute it first.
    private func loadImage(_ source: String, _ parser: XMLParser) -> (image: CGImage, source: String)? {
        do {
            let loaded = try TiledImageLoader.image(for: source, referencedBy: currentURL, resolver: resolver)
            return (loaded.image, loaded.url?.path ?? source)
        } catch let error as TiledError {
            fail(error, parser)
        } catch {
            fail(.unreadableFile(currentURL, reason: error.localizedDescription), parser)
        }
        return nil
    }


    // MARK: - Post-Processing

    /// Renders each layer's tiles and objects, then finishes the map.
    ///
    /// - Parameters:
    ///   - tilemap: tile map node.
    ///   - duration: fade-in time for each layer.
    fileprivate func didBeginRendering(_ tilemap: SKTilemap, duration: TimeInterval = 0.025) {

        let debugLevel: Bool = (loggingLevel.rawValue < 1) ? true : false

        for layer in tilemap.getLayers(recursive: true) {

            // render object groups
            if let objectGroup = layer as? SKObjectGroup {
                objectGroup.draw()
            }

            // render tile layers
            if let tileLayer = layer as? SKTileLayer {

                // get stashed tile data
                if let tileData = self.data[tileLayer.uuid] {
                    if (tileLayer.setLayerData(tileData, debug: debugLevel) == false) {
                        self.log("layer \"\(tileLayer.layerName)\" failed to set data.", level: .warning)
                    }
                }

                // report errors
                if tileLayer.gidErrors.isEmpty == false {
                    let gidErrorString = tileLayer.gidErrors.map { "\($0)" }.joined(separator: ", ")
                    Logger.default.log("layer \"\(tileLayer.layerName)\": the following gids could not be found: \(gidErrorString)", level: .warning, symbol: self.logSymbol)
                }
            }

            layer.didFinishRendering(duration: duration)
        }

        data = [:]
        tilesets = [:]
        tilemap.didFinishRendering(timeStarted: timer)
    }


    // MARK: - XMLParserDelegate
    internal func parser(_ parser: XMLParser,
                         didStartElement elementName: String,
                         namespaceURI: String?,
                         qualifiedName qName: String?,
                         attributes attributeDict: [String: String]) {
        
        activeElement = elementName
        
        // fail on infinite (for now)
        if (elementName == "chunk") {
            fail(.unsupportedFeature(currentURL, feature: "infinite maps"), parser)
            return
        }

        
        if (elementName == "map") {
            
            // create the tilemap
            guard let tilemap = SKTilemap(attributes: attributeDict) else {
                fail("invalid <map> attributes (orientation, size or tile size).", parser)
                return
            }
            
            // initialize cache
            tilemap.dataStorage = TileDataStorage(map: tilemap)
            tilemap.receiveCameraUpdates = TiledGlobals.default.enableCameraCallbacks
            
            // initialize notifications
            tilemap.setupNotifications()
            
            // set global logging level
            tilemap.loggingLevel = self.loggingLevel
            tilemap.updateMode = self.tileUpdateMode
            
            self.tilemap = tilemap
            self.tilemap.ignoreProperties = self.ignoreProperties
            self.tilemap.delegate = self.mapDelegate
            
            // set the tilemap url property
            self.tilemap.url = currentURL
            
            if let tiledVersion = tilemap.tiledversion {
                self.log("Tiled version: \(tiledVersion)", level: .debug)
            }
            
            if (self.mapDelegate != nil) {
                self.tilemap.zDeltaForLayers = self.mapDelegate!.zDeltaForLayers
            }
            
            // get the filename to use as the map name
            let currentBasename = currentURL.deletingPathExtension().lastPathComponent

            // `SKTilemap.name` represents the tmx filename (minus .tmx extension)
            self.tilemap.name = currentBasename
            self.tilemap.displayName = currentBasename
            
            // run setup functions on tilemap
            self.mapDelegate?.didBeginParsing(tilemap)
            
            lastElement = tilemap
            elementPath.append(tilemap)
        }
        
        
        // MARK: Tilesets
        
        // external will have a 'source' attribute, otherwise 'image'
        if (elementName == "tileset") {
            
            /* inline declaration in tmx:    <tileset firstgid="1" name="ortho4-16x16" tilewidth="16" tileheight="16" tilecount="552" columns="23"> */
            /* external declaration in tmx:  <tileset firstgid="1" source="roguelike-16x16.tsx"/> */
            /* reading external tsx:         <tileset name="roguelike-16x16" tilewidth="16" tileheight="16" spacing="1" tilecount="1938" columns="57">*/
            
            // reading tmx, external tileset
            if let source = attributeDict["source"] {

                // get the first gid attribute
                guard let firstgid = attributeDict["firstgid"], let firstGID = Int(firstgid) else {
                    fail("external tileset reference \"\(source)\" has no valid firstgid.", parser)
                    return
                }

                guard let tilesetURL = resolver.url(for: source, referencedBy: currentURL) else {
                    let expected = URL(fileURLWithPath: source, relativeTo: currentURL.deletingLastPathComponent()).standardizedFileURL
                    fail(.fileNotFound(expected, referencedBy: currentURL), parser)
                    return
                }

                // check to see if tileset already exists (either an empty new tileset, or we've passed a pre-loaded tileset).
                if let existingTileset = tilesets[tilesetURL.path] {
                    // if we're in tilemap parsing mode, add the tileset to the map
                    if (parsingMode == .tmx) {
                        self.tilemap?.addTileset(existingTileset)

                        // set the first gid parameter
                        existingTileset.firstGID = firstGID

                        lastElement = existingTileset

                        // set this to nil, just in case we're looking for a collections tileset.
                        currentID = nil

                        // we're in a template
                    } else {

                        // set the current tileset
                        activeTemplateTileset = existingTileset
                    }

                } else if !fileQueue.contains(tilesetURL) {

                    // new tileset reference: parse its file after this one
                    fileQueue.append(tilesetURL)

                    // create a new tileset
                    let tileset = SKTileset(source: source, firstgid: firstGID, tilemap: self.tilemap)
                    tileset.loggingLevel = self.loggingLevel
                    tileset.ignoreProperties = self.ignoreProperties
                    tileset.url = tilesetURL

                    tilesets[tilesetURL.path] = tileset

                    // add the tileset to the tilemap
                    self.tilemap?.addTileset(tileset)
                    lastElement = tileset

                    // set this to nil, just in case we're looking for a collections tileset.
                    currentID = nil
                }
            }

            // inline tileset in TMX, or the current file **is** a tileset
            if let name = attributeDict["name"] {
                
                // update an existing tileset ( to set properties like `name`)
                if let existingTileset = tilesets[currentFilename] {
                    
                    guard let width = attributeDict["tilewidth"].flatMap({ Int($0) }),
                          let height = attributeDict["tileheight"].flatMap({ Int($0) }) else {
                        fail("tileset \"\(name)\" has no valid tilewidth/tileheight.", parser)
                        return
                    }

                    existingTileset.name = name
                    existingTileset.tileSize = CGSize(width: width, height: height)

                    // optionals
                    if let columns = attributeDict["columns"].flatMap({ Int($0) }) {
                        existingTileset.columns = columns
                    }

                    if let spacing = attributeDict["spacing"].flatMap({ Int($0) }) {
                        existingTileset.spacing = spacing
                    }

                    if let margin = attributeDict["margin"].flatMap({ Int($0) }) {
                        existingTileset.margin = margin
                    }

                    lastElement = existingTileset
                    
                } else {
                    // create inline tileset
                    guard let tileset = SKTileset(attributes: attributeDict) else {
                        fail("invalid <tileset> attributes for \"\(name)\".", parser)
                        return
                    }
                    tileset.loggingLevel = self.loggingLevel
                    tileset.ignoreProperties = self.ignoreProperties
                    
                    // add the tileset to the tilemap (if it exists)
                    self.tilemap?.addTileset(tileset)
                    
                    lastElement = tileset
                    
                    // set this to nil, just in case we're looking for a collections tileset.
                    currentID = nil
                    
                    if (parsingMode == .tsx) {
                        tileset.filename = currentFilename
                        tileset.url = currentURL
                        tilesets[currentFilename] = tileset
                    }
                }
            }
        }
        
        // draw offset for tilesets
        if elementName == "tileoffset" {
            guard let offsetx = attributeDict["x"].flatMap({ Int($0) }),
                  let offsety = attributeDict["y"].flatMap({ Int($0) }) else {
                fail("<tileoffset> has no valid x/y.", parser)
                return
            }

            if let tileset = lastElement as? SKTileset {
                tileset.tileOffset = CGPoint(x: offsetx, y: offsety)
            }
        }
        
        if elementName == "property" {
            guard let name = attributeDict["name"] else {
                fail("<property> has no name.", parser)
                return
            }

            // multi-line string properties store their value as element text; class properties have no value
            let value = attributeDict["value"] ?? ""

            // stash properties
            properties[name] = value
        }
        
        
        // 'layer' indicates a Tile layer
        if (elementName == "layer") {
            let layerName = attributeDict["name"] ?? ""
            guard let layer = SKTileLayer(tilemap: self.tilemap!, attributes: attributeDict) else {
                fail("invalid attributes for tile layer \"\(layerName)\".", parser)
                return
            }
            
            let parentElement = elementPath.last!
            if let group = parentElement as? SKGroupLayer {
                group.addLayer(layer)
                layer.rawIndex = layerIndex
                layerIndex += 1
            }
            
            if let tilemap = parentElement as? SKTilemap {
                tilemap.addLayer(layer)
                layer.rawIndex = layerIndex
                layerIndex += 1
            }
            
            
            lastElement = layer
        }
        
        // 'objectgroup' indicates an Object layer or tile collision
        if (elementName == "objectgroup") {
            
            // if tileset is last element and currentID exists....
            if let tileset = lastElement as? SKTileset {
                
                if let currentID = currentID {
                    
                    let tileID = tileset.firstGID + currentID
                    if tileset.getTileData(globalID: tileID) != nil {
                        // add to object group
                    }
                }
            } else {
                
                guard let objectsGroup = SKObjectGroup(tilemap: self.tilemap!, attributes: attributeDict) else {
                    fail("invalid attributes for object group \"\(attributeDict["name"] ?? "")\".", parser)
                    return
                }
                
                let parentElement = elementPath.last!
                
                if let group = parentElement as? SKGroupLayer {
                    group.addLayer(objectsGroup)
                    objectsGroup.rawIndex = layerIndex
                    layerIndex += 1
                }
                
                if let tilemap = parentElement as? SKTilemap {
                    tilemap.addLayer(objectsGroup)
                    objectsGroup.rawIndex = layerIndex
                    layerIndex += 1
                }
                
                lastElement = objectsGroup
            }
        }
        
        // 'imagelayer' indicates an Image layer
        if (elementName == "imagelayer") {
            guard let imageLayer = SKImageLayer(tilemap: self.tilemap!, attributes: attributeDict) else {
                fail("invalid attributes for image layer \"\(attributeDict["name"] ?? "")\".", parser)
                return
            }
            
            let parentElement = elementPath.last!
            if let group = parentElement as? SKGroupLayer {
                group.addLayer(imageLayer)
                imageLayer.rawIndex = layerIndex
                layerIndex += 1
            }
            
            if let tilemap = parentElement as? SKTilemap {
                tilemap.addLayer(imageLayer)
                imageLayer.rawIndex = layerIndex
                layerIndex += 1
            }
            
            
            lastElement = imageLayer
        }
        
        // 'group' indicates a Group layer
        if (elementName == "group") {
            guard let groupLayer = SKGroupLayer(tilemap: self.tilemap!, attributes: attributeDict) else {
                fail("invalid attributes for group layer \"\(attributeDict["name"] ?? "")\".", parser)
                return
            }
            
            let parentElement = elementPath.last!
            if let group = parentElement as? SKGroupLayer {
                group.addLayer(groupLayer)
                groupLayer.rawIndex = layerIndex
                layerIndex += 1
            }
            
            if let tilemap = parentElement as? SKTilemap {
                tilemap.addLayer(groupLayer)
                groupLayer.rawIndex = layerIndex
                layerIndex += 1
            }
            
            elementPath.append(groupLayer)
            lastElement = groupLayer
        }
        
        // look for last element to be a tileset or imagelayer
        if (elementName == "image") {
            guard let source = attributeDict["source"] else {
                fail("<image> has no source.", parser)
                return
            }

            // update an image layer
            if let imageLayer = lastElement as? SKImageLayer {
                guard let loaded = loadImage(source, parser) else { return }
                imageLayer.setLayerImage(loaded.image, source: loaded.source)
            }

            // update a tileset
            if let tileset = lastElement as? SKTileset {

                // If `currentID` == nil, image is a spritesheet so look for lastElement to be a tileset,
                // otherwise, the image is part of a collections tileset.
                if let currentID = currentID {

                    // query data source delegate for source image substitution
                    let imageSource = tilesetDataSource?.willAddImage(to: tileset, forId: currentID, fileNamed: source) ?? source
                    guard let loaded = loadImage(imageSource, parser) else { return }

                    // add an image property to the tileset collection
                    let tileData = tileset.addTilesetTile(currentID, image: loaded.image, source: loaded.source)

                    tilesetImagesAdded += 1
                    if (tileData == nil) {
                        log("\(parsingMode) parser: Warning: tile id \(currentID) is invalid.", level: .warning)
                    }
                } else {
                    // parse tileset properties
                    tileset.parseProperties(completion: nil)

                    // query data source delegate for source image substitution
                    let imageSource = tilesetDataSource?.willAddSpriteSheet(to: tileset, fileNamed: source) ?? source
                    guard let loaded = loadImage(imageSource, parser) else { return }

                    // add the tileset spritesheet image
                    tileset.addTextures(fromSpriteSheet: loaded.image, source: loaded.source, replace: false, transparent: attributeDict["trans"])

                    // delegate callback
                    tileset.setupAnimatedTileData()
                    mapDelegate?.didAddTileset(tileset)
                }
            }
        }

        // `tile` is used to flag properties in a tileset, as well as store tile layer data in an XML-formatted map.
        if elementName == "tile" {
            
            // XML layer data is stored with a `tile` tag and `gid` atribute. No other attributes will be present.
            // <tile gid="0"/>
            if let gid = attributeDict["gid"] {
                guard let value = UInt32(gid) else {
                    fail("invalid tile gid \"\(gid)\".", parser)
                    return
                }
                // just append this to the tileData property
                if (encoding == .xml) {
                    tileData.append(value)
                }
            }
                
                // otherwise, we're adding data to a tileset. Attributes can be `type` and `probability`.
            else if let id = attributeDict["id"] {

                guard let intValue = Int(id) else {
                    fail("invalid tile id \"\(id)\".", parser)
                    return
                }
                currentID = intValue


                // optional tile attributes (Tiled 1.9 wrote `class`, other versions write `type`)
                if let tileType = attributeDict["type"] ?? attributeDict["class"] {
                    currentType = tileType
                }
                
                if let tileProbabilty = attributeDict["probability"] {
                    if let doubleValue = Double(tileProbabilty) {
                        currentProbability = CGFloat(doubleValue)
                    }
                }
                
            } else {
                fail("<tile> has neither a gid nor an id.", parser)
                return
            }
        }
        
        // look for last element to be an object group
        // id, x, y required
        if (elementName == "object") {
            
            // template object inside a template file
            if (parsingMode == .tx) {
                
                // get last template object
                if let currentObject = templateObjects.popLast() {
                    
                    // set the objects initial attributes
                    currentObject.setObjectAttributes(attributes: attributeDict)
                    currentObject.visible = (currentObject.gid != nil)
                    
                    // set the last object
                    lastElement = currentObject
                    
                    // get local id with flipped flags
                    if let localID = currentObject.gid {
                        guard let templateTileset = activeTemplateTileset else {
                            log("no active tileset for this template.", level: .error)
                            return
                        }
                        
                        
                        let flipped = flippedTileFlags(id: UInt32(localID))
                        let globalId = templateTileset.getGlobalID(forLocalID: Int(flipped.gid))
                        
                        currentObject.gid = globalId
                        currentObject.tileData?.flipHoriz = flipped.hflip
                        currentObject.tileData?.flipVert = flipped.vflip
                        currentObject.tileData?.flipDiag = flipped.dflip
                    }
                }
                
            } else {
                // adding a group to tileset tile
                if let _ = lastElement as? SKTileset {}
                
                // adding a group to object layer
                if let objectGroup = lastElement as? SKObjectGroup {
                    
                    // Tiled 1.9 wrote an object's type as `class`
                    var objectAttributes = attributeDict
                    if objectAttributes["type"] == nil, let objectClass = objectAttributes["class"] {
                        objectAttributes["type"] = objectClass
                    }

                    let Object = tilemap.delegate?.objectForVectorType(named: objectAttributes["type"]) ?? SKTileObject.self

                    guard let tileObject = Object.init(attributes: objectAttributes) else {
                        fail("invalid attributes for object \"\(attributeDict["id"] ?? "?")\".", parser)
                        return
                    }
                    
                    // add the object to the layer
                    _ = objectGroup.addObject(tileObject)
                    currentID = tileObject.id
                    
                    // template object
                    if let templateFile = tileObject.template {
                        guard let templateURL = resolver.url(for: templateFile, referencedBy: currentURL) else {
                            let expected = URL(fileURLWithPath: templateFile, relativeTo: currentURL.deletingLastPathComponent()).standardizedFileURL
                            fail(.fileNotFound(expected, referencedBy: currentURL), parser)
                            return
                        }
                        fileQueue.append(templateURL)
                        tileObject.isInitialized = false
                        templateObjects.insert(tileObject, at: 0)
                    }
                }
            }
        }
        
        // special case - look for last element to be a object
        // this signifies that the object should be an ellipse
        if (elementName == "ellipse") {
            if let objectsgroup = lastElement as? SKObjectGroup {
                if (currentID != nil) {
                    if let currentObject = objectsgroup.getObject(withID: currentID!) {
                        currentObject.shapeType = .ellipse
                    }
                }
            }
        }
        
        if (elementName == "polygon") {
            
            // polygon object
            if let pointsString = attributeDict["points"] {
                var coordinates: [[CGFloat]] = []
                let points = pointsString.components(separatedBy: " ")
                for point in points {
                    let coords = point.components(separatedBy: ",").compactMap { x in Double(x) }
                    coordinates.append(coords.compactMap { CGFloat($0) })
                }
                
                if let _ = lastElement as? SKTileset {
                    
                }
                
                
                if let objectsgroup = lastElement as? SKObjectGroup {
                    if (currentID != nil) {
                        if let currentObject = objectsgroup.getObject(withID: currentID!) {
                            currentObject.addPoints(coordinates)
                        }
                    }
                }
            }
        }
        
        if (elementName == "polyline") {
            // polygon object
            if let pointsString = attributeDict["points"] {
                var coordinates: [[CGFloat]] = []
                let points = pointsString.components(separatedBy: " ")
                for point in points {
                    let coords = point.components(separatedBy: ",").compactMap { x in Double(x) }
                    coordinates.append(coords.compactMap { CGFloat($0) })
                }
                
                if let _ = lastElement as? SKTileset {}
                
                if let objectGroup = lastElement as? SKObjectGroup {
                    if (currentID != nil) {
                        if let currentObject = objectGroup.getObject(withID: currentID!) {
                            currentObject.addPoints(coordinates, closed: false)
                        }
                    }
                }
            }
        }
        
        // animated tiles
        if (elementName == "frame") {
            guard let currentID = currentID else {
                fail("<frame> outside of a <tile>.", parser)
                return
            }

            guard let id = attributeDict["tileid"].flatMap({ Int($0) }),
                  let duration = attributeDict["duration"].flatMap({ Int($0) }),
                  let tileset = lastElement as? SKTileset else {
                fail("<frame> has no valid tileid/duration.", parser)
                return
            }


            if let currentTileData = tileset.getTileData(globalID: currentID + tileset.firstGID) {

                // add the frame id to the frames property
                let animationFrame = currentTileData.addFrame(withID: id + tileset.firstGID, interval: duration)
                
                // set the texture for the frame
                if let frameData = tileset.getTileData(localID: animationFrame.id) {
                    if let frameTexture = frameData.texture {
                        animationFrame.texture = frameTexture
                    }
                }
            }
        }
        
        // text object attributes
        if (elementName == "text") {
            
            if let objectGroup = lastElement as? SKObjectGroup {
                if (currentID != nil) {
                    if let currentObject = objectGroup.getObject(withID: currentID!) {
                        // basic text attributes
                        let fontName: String = (attributeDict["fontfamily"] != nil) ? attributeDict["fontfamily"]! : "system"
                        let fontSize: CGFloat = attributeDict["pixelsize"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? 16
                        let fontColor: SKColor = (attributeDict["color"] != nil) ? SKColor(hexString: attributeDict["color"]!) : .black
                        
                        // create text attributes
                        currentObject.textAttributes = TextObjectAttributes(font: fontName, size: fontSize, color: fontColor)
                        currentObject.visible = true
                        
                        if let bold = attributeDict["bold"] {
                            currentObject.textAttributes.isBold = (bold == "1")
                        }
                        
                        if let italic = attributeDict["italic"] {
                            currentObject.textAttributes.isItalic = (italic == "1")
                        }
                        
                        if let underline = attributeDict["underline"] {
                            currentObject.textAttributes.isUnderline = (underline == "1")
                        }
                        
                        if let strikeout = attributeDict["strikeout"] {
                            currentObject.textAttributes.isStrikeout = (strikeout == "1")
                        }
                        
                        if let textWrap = attributeDict["wrap"] {
                            currentObject.textAttributes.wrap = (textWrap == "1")
                        }
                        
                        // alignment
                        if let halign = attributeDict["halign"] {
                            if let halignment = TextObjectAttributes.TextAlignment.HoriztonalAlignment(rawValue: halign) {
                                currentObject.textAttributes.alignment.horizontal = halignment
                            }
                        }
                        
                        if let valign = attributeDict["valign"] {
                            if let valignment = TextObjectAttributes.TextAlignment.VerticalAlignment(rawValue: valign) {
                                currentObject.textAttributes.alignment.vertical = valignment
                            }
                        }
                    }
                }
            }
        }
        
        // decode data here, and reset
        if (elementName == "data") {
            // get the encoding...
            if let encoding = attributeDict["encoding"] {
                guard let tilemapEncoding = TilemapEncoding(rawValue: encoding) else {
                    fail(.unsupportedFeature(currentURL, feature: "\"\(encoding)\" data encoding"), parser)
                    return
                }
                self.encoding = tilemapEncoding
            }

            // compression algorithms
            if let ctype = attributeDict["compression"] {
                guard let compression = CompressionType(rawValue: ctype), compression != .zstd else {
                    fail(.unsupportedFeature(currentURL, feature: "\"\(ctype)\" compression"), parser)
                    return
                }
                self.compression = compression
            }
        }
    }
    
    
    // Runs when parser ends a key: </key>
    internal func parser(_ parser: XMLParser,
                         didEndElement elementName: String,
                         namespaceURI: String?,
                         qualifiedName qName: String?) {
        
        // look for last element to add properties to
        if elementName == "properties" {
            
            // tilemap properties
            if let tilemap = lastElement as? SKTilemap {
                for (key, value) in properties {
                    tilemap.properties[key] = value
                }
                
                tilemap.parseProperties(completion: nil)
            }
            
            // layer properties
            if let layer = lastElement as? SKTiledLayerObject {
                if (currentID == nil) {
                    for (key, value) in properties {
                        layer.properties[key] = value
                    }
                }
                
                layer.parseProperties(completion: nil)
            }
            
            // tileset properties
            if let tileset = lastElement as? SKTileset {
                if (currentID == nil) {
                    tileset.properties = properties
                    tileset.parseProperties(completion: nil)
                    
                } else {
                    
                    let tileID = tileset.firstGID + currentID!
                    if let tileData = tileset.getTileData(globalID: tileID) {
                        for (key, value) in properties {
                            tileData.properties[key] = value
                        }
                        
                        tileData.parseProperties(completion: nil)
                        properties = [:]
                    }
                }
            }
            
            // clear if no last ID
            if currentID == nil {
                properties = [:]
            }
        }
        
        // look for last element to be a layer
        if (elementName == "data") {
            guard let tileLayer = lastElement as? SKTileLayer else {
                fail("<data> outside of a tile layer.", parser)
                return
            }
            
            switch encoding {
                case .base64:
                    guard let dataArray = decode(base64String: characterData, compression: self.compression) else {
                        fail("layer \"\(tileLayer.layerName)\" has invalid base64 tile data.", parser)
                        return
                    }
                    tileData.append(contentsOf: dataArray)

                case .csv:
                    guard let dataArray = decode(csvString: characterData) else {
                        fail("layer \"\(tileLayer.layerName)\" has invalid CSV tile data.", parser)
                        return
                    }
                    tileData.append(contentsOf: dataArray)

                case .xml:
                    break
            }

            // write data to buffer
            data[tileLayer.uuid] = tileData

            // reset for the next layer
            tileData = []
            encoding = .xml
            compression = .uncompressed
        }

        if (elementName == "tile") {
            // parse properties
            if let tileset = lastElement as? SKTileset {
                if (currentID != nil) {
                    
                    let tileID = tileset.firstGID + currentID!
                    if let currentTileData = tileset.getTileData(globalID: tileID) {
                        
                        for (key, value) in properties {
                            currentTileData.properties[key] = value
                        }
                        
                        properties = [:]
                        
                        // set the type attribute for the tile data
                        if let currentType = currentType {
                            currentTileData.type = currentType
                        }
                        
                        // set the probability attribute for the tile data
                        if let currentProbability = currentProbability {
                            currentTileData.probability = currentProbability
                        }
                    }
                }
            }
            
            // we're no longer adding attributes to a tile, so unset tile properties
            currentID = nil
            currentType = nil
            currentProbability = nil
        }
        
        // add properties to last object
        if (elementName == "object") {
            
            // if we're dealing with an object in an object layer....
            if let objectsgroup = lastElement as? SKObjectGroup {
                if (currentID != nil) {
                    if let lastObject = objectsgroup.getObject(withID: currentID!) {
                        for (key, value) in properties {
                            lastObject.properties[key] = value
                        }
                        
                        lastObject.parseProperties(completion: nil)
                        properties = [:]
                    }
                    currentID = nil
                }
            }
            
            // if we're dealing with a tile collision object...
            if (lastElement as? SKTileset) != nil {}
            //currentID = nil
        }
        
        
        if (elementName == "layer") {
            
            if let tileLayer = lastElement as? SKTileLayer {
                
                // delegate callback
                mapDelegate?.didAddLayer(tileLayer)
            }
        }
        
        if (elementName == "objectgroup") {
            if let objectGroup = lastElement as? SKObjectGroup {
                // delegate callback
                mapDelegate?.didAddLayer(objectGroup)
            }
        }
        
        if (elementName == "imagelayer") {
            if let imageLayer = lastElement as? SKImageLayer {
                // delegate callback
                mapDelegate?.didAddLayer(imageLayer)
            }
        }
        
        if (elementName == "group") {
            if let groupLayer = lastElement as? SKGroupLayer {
                // delegate callback
                mapDelegate?.didAddLayer(groupLayer)
            }
            
            // if we're closing a group layer, pop it from the element path
            _ = elementPath.popLast()
            lastElement = nil
        }
        
        // text object text
        if (elementName == "text") {
            if let objectGroup = lastElement as? SKObjectGroup {
                if (currentID != nil) {
                    if let currentObject = objectGroup.getObject(withID: currentID!) {
                        // set the object's text attribute
                        currentObject.text = characterData.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        // embedded tileset only
        if (elementName == "tileset") {
            
            if tilesetImagesAdded > 0 {
                if let tileset = lastElement as? SKTileset {
                    // Logger.default.cache(LogEvent("tileset \"\(tileset.name)\" finished, \(tilesetImagesAdded) images added.", level: .debug, caller: self.logSymbol))
                    Logger.default.log("tileset \"\(tileset.name)\" finished, \(tilesetImagesAdded) images added.", level: .debug, symbol: self.logSymbol)
                    tileset.isRendered = true
                    
                    // delegate callback
                    tileset.setupAnimatedTileData()
                    self.mapDelegate?.didAddTileset(tileset)
                }
                tilesetImagesAdded = 0
            }
            
            // important to close this here!!
            lastElement = nil
        }
        
        // template reference
        if (elementName == "template") {
            
            if let currentObject = lastElement as? SKTileObject {
                currentObject.isInitialized = true
            }
            
            lastElement = nil
            activeTemplateTileset = nil
        }
        
        
        // reset character data
        characterData = ""
    }
    
    // foundCharacters happens whenever parser enters a key poop
    internal func parser(_ parser: XMLParser, foundCharacters string: String) {
        // append data attribute
        characterData += string
    }
    
    // MARK: - Decoding
    /// Scrub CSV data.
    ///
    /// - parameter data: `String` data to decode
    /// - returns: `[UInt32]` parsed CSV data.
    fileprivate func decode(csvString data: String) -> [UInt32]? {
        var result: [UInt32] = []
        for value in data.scrub().components(separatedBy: ",") {
            guard let gid = UInt32(value) else { return nil }
            result.append(gid)
        }
        return result
    }
    
    /// Decode Base64-formatted data.
    ///
    /// - parameter data:        `String` Base64 formatted data to decode
    /// - parameter compression: `CompressionType` compression type.
    /// - returns: `[UInt32]?` parsed data.
    fileprivate func decode(base64String data: String,
                            compression: CompressionType = .uncompressed) -> [UInt32]? {
        
        guard let decodedData = Data(base64Encoded: data, options: .ignoreUnknownCharacters) else {
            log("data is not base64 encoded.", level: .error)
            return nil
        }
        
        switch compression {
            case .zlib, .gzip:
                if let decompressed = try? decodedData.gunzipped() {
                    return decompressed.toArray(type: UInt32.self)
            }
            
            case .zstd:
                log("Zstandard compression is not supported.", level: .error)
                return nil
            
            default:
                return decodedData.toArray(type: UInt32.self)
        }
        
        return nil
    }
}


// MARK: - Extensions

extension FileType: CustomStringConvertible {
    /// File type description.
    var description: String {
        switch self {
            case .tmx: return "tile map"
            case .tsx: return "tileset"
            case .png: return "image"
            case .tx:  return "template"
        }
    }
}

