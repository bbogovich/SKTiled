//
//  SKTiledScene.swift
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
import GameplayKit


/// ## Overview
///
/// Custom scene type for managing `SKTilemap` nodes.
///
/// Conforms to the `SKTiledSceneDelegate`, `SKTilemapDelegate` & `SKTilesetDataSource` protocols.
///
/// [SKTiledScene Hierarchy][sktiledscene-hierarchy-img-url]
///
/// ### Properties
///
/// | Property   | Description          |
/// |:-----------|:---------------------|
/// | worldNode  | Root container node. |
/// | tilemap    | Tile map object.     |
/// | cameraNode | Custom scene camera. |
///
///
/// ### Instance Methods ###
///
/// | Method                 | Description                                                  |
/// |:-----------------------|:-------------------------------------------------------------|
/// | sceneDoubleTapped      | Called when the scene receives a double-tap event (iOS only).|
/// | cameraPositionChanged  | Called when the camera positon changes.                      |
/// | cameraZoomChanged      | Called when the camera zoom changes.                         |
/// | cameraBoundsChanged    | Called when the camera bounds updated.                       |
/// | sceneDoubleClicked     | Called when the scene is double-clicked (macOS only).        |
/// | mousePositionChanged   | Called when the mouse moves in the scene (macOS only).       |
///
/// [sktiledscene-hierarchy-img-url]:https://mfessenden.github.io/SKTiled/images/scene_hierarchy.png
open class SKTiledScene: SKScene, SKPhysicsContactDelegate, SKTiledSceneDelegate, SKTilemapDelegate, SKTilesetDataSource, SKTiledSceneCameraDelegate {
    
    /// World container node.
    open var worldNode: SKNode!
    
    /// Tile map node.
    open var tilemap: SKTilemap!
    
    /// Custom scene camera.
    open var cameraNode: SKTiledSceneCamera!
    
    /// Logging verbosity level.
    open var loggingLevel: LoggingLevel = .info
    
    /// Reference to navigation graphs.
    open var graphs: [String : GKGridGraph<GKGridGraphNode>] = [:]
    
    /// Last update interval.
    private var lastUpdateTime: TimeInterval = 0
    
    /// Maximum update interval.
    private let maximumUpdateDelta: TimeInterval = 1.0 / 60.0
    
    /// Receive notifications from camera.
    open var receiveCameraUpdates: Bool = true
    
    /// Set the tilemap speed.
    override open var speed: CGFloat {
        didSet {
            guard oldValue != speed else { return }
            if let tilemap = tilemap {
                tilemap.speed = speed
            }
        }
    }
    
    // MARK: - Init
    
    /// Initialize without a tiled map.
    ///
    /// - parameter size:  `CGSize` scene size.
    /// - returns:         `SKTiledScene` scene.
    required override public init(size: CGSize) {
        super.init(size: size)
        setupWorldNode()
    }

    /// Default initializer.
    ///
    /// - Parameter aDecoder: decoder instance.
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupWorldNode()
    }

    /// Creates the world container node, so a map can be set up before the scene is presented.
    private func setupWorldNode() {
        physicsWorld.gravity = CGVector.zero
        worldNode = SKNode()
        worldNode.name = "World"
        addChild(worldNode)
    }

    
    /// Called when the parent view size changes.
    ///
    /// - Parameter oldSize: previous size.
    override open func didChangeSize(_ oldSize: CGSize) {
        updateCamera()
    }
    
    /// Called when the parent view is displayed.
    ///
    /// - Parameter view: parent view.
    override open func didMove(to view: SKView) {
        physicsWorld.contactDelegate = self

        // setup the camera once; the scene may be presented more than once
        if cameraNode == nil {
            cameraNode = SKTiledSceneCamera(view: view, world: worldNode)
            // scene should notified of camera changes
            cameraNode.addDelegate(self)
            addChild(cameraNode)
            camera = cameraNode
        }

        // a map set up before the scene was presented
        if let tilemap = tilemap {
            configureCamera(for: tilemap)
        }
    }
    
    // MARK: - Setup

    /// Loads a TMX file and makes it the scene's map, replacing the current one.
    ///
    /// - Parameters:
    ///   - url: TMX file.
    ///   - bundle: bundle used for file-name and asset catalog fallbacks, or `nil` for none.
    ///   - tilesets: tilesets loaded earlier with `SKTileset.load(urls:)`.
    ///   - ignoreProperties: don't parse custom properties.
    ///   - loggingLevel: logging verbosity.
    /// - Returns: the new map.
    /// - Throws: `TiledError`; the current map is kept if loading fails.
    @discardableResult
    open func setup(url: URL,
                    bundle: Bundle? = nil,
                    withTilesets tilesets: [SKTileset] = [],
                    ignoreProperties: Bool = false,
                    loggingLevel: LoggingLevel = TiledGlobals.default.loggingLevel) throws -> SKTilemap {

        self.loggingLevel = loggingLevel
        let tilemap = try load(url: url,
                               bundle: bundle,
                               withTilesets: tilesets,
                               ignoreProperties: ignoreProperties,
                               loggingLevel: loggingLevel)
        setup(tilemap: tilemap)
        return tilemap
    }

    /// Loads a TMX file from a bundle by name and makes it the scene's map, replacing the current one.
    ///
    /// - Parameters:
    ///   - name: map file name, with or without the `.tmx` extension.
    ///   - bundle: bundle containing the map.
    ///   - subdirectory: optional directory within the bundle's resources; the whole bundle is searched if `nil`.
    ///   - tilesets: tilesets loaded earlier with `SKTileset.load(urls:)`.
    ///   - ignoreProperties: don't parse custom properties.
    ///   - loggingLevel: logging verbosity.
    /// - Returns: the new map.
    /// - Throws: `TiledError`; the current map is kept if loading fails.
    @discardableResult
    open func setup(named name: String,
                    in bundle: Bundle = .main,
                    subdirectory: String? = nil,
                    withTilesets tilesets: [SKTileset] = [],
                    ignoreProperties: Bool = false,
                    loggingLevel: LoggingLevel = TiledGlobals.default.loggingLevel) throws -> SKTilemap {

        guard let url = bundle.tiledResourceURL(named: name, extension: "tmx", subdirectory: subdirectory) else {
            throw TiledError.resourceNotFound(name: name, bundle: bundle.bundleURL)
        }
        return try setup(url: url,
                         bundle: bundle,
                         withTilesets: tilesets,
                         ignoreProperties: ignoreProperties,
                         loggingLevel: loggingLevel)
    }

    /// Makes a loaded map the scene's map, replacing the current one.
    ///
    /// - Parameter tilemap: tile map node.
    open func setup(tilemap: SKTilemap) {
        if let current = self.tilemap {
            cameraNode?.removeDelegate(current)
            current.removeFromParent()
        }

        backgroundColor = tilemap.backgroundColor ?? SKColor.clear

        // add the tilemap to the world container node.
        worldNode.addChild(tilemap, fadeIn: 0.2)
        self.tilemap = tilemap

        // apply gravity from the tile map
        physicsWorld.gravity = tilemap.gravity

        configureCamera(for: tilemap)
    }

    /// Applies a map's camera properties; does nothing until the scene is presented and has a camera.
    private func configureCamera(for tilemap: SKTilemap) {
        guard let cameraNode = cameraNode else { return }

        // tilemap will be notified of camera changes
        cameraNode.removeDelegate(tilemap)
        cameraNode.addDelegate(tilemap)

        // camera properties inherited from tilemap
        cameraNode.allowMovement = tilemap.allowMovement
        cameraNode.allowZoom = tilemap.allowZoom
        cameraNode.maxZoom = tilemap.zoomConstraints.max

        // initial zoom level
        if tilemap.autoResize, let view = view {
            cameraNode.fitToView(newSize: view.bounds.size)
        } else {
            cameraNode.setCameraZoom(tilemap.worldScale)
        }
    }

    // MARK: - Tilemap Delegate
    
    open func didBeginParsing(_ tilemap: SKTilemap) {
        // Called when tilemap is instantiated.
    }
    
    open func didAddTileset(_ tileset: SKTileset) {
        // Called when a tileset has been added.
    }
    
    open func didAddLayer(_ layer: SKTiledLayerObject) {
        // Called when a layer has been added.
    }
    
    open func didReadMap(_ tilemap: SKTilemap) {
        // Called before layers are rendered.
    }
    
    open func didRenderMap(_ tilemap: SKTilemap) {
        // Called after layers are rendered. Perform any post-processing here.
    }
    
    open func didAddNavigationGraph(_ graph: GKGridGraph<GKGridGraphNode>) {
        // Called when a graph is added to the scene.
    }
    
    open func objectForTileType(named: String?) -> SKTile.Type {
        return SKTile.self
    }
    
    open func objectForVectorType(named: String?) -> SKTileObject.Type {
        return SKTileObject.self
    }

    open func objectForGraphType(named: String?) -> GKGridGraphNode.Type {
        return SKTiledGraphNode.self
    }
    
    // MARK: - Camera Delegate

    /// Called when the camera position changes.
    open func cameraPositionChanged(newPosition: CGPoint) {}

    /// Called when the camera zoom changes.
    open func cameraZoomChanged(newZoom: CGFloat) {}

    /// Called when the camera bounds are updated.
    open func cameraBoundsChanged(bounds: CGRect, position: CGPoint, zoom: CGFloat) {}

    #if os(macOS)
    /// Called when the scene is double-clicked (macOS only).
    open func sceneDoubleClicked(event: NSEvent) {}

    /// Called when the mouse moves in the scene (macOS only).
    open func mousePositionChanged(event: NSEvent) {}
    #endif

    #if os(iOS)
    /// Called when the scene receives a double-tap event (iOS only).
    open func sceneDoubleTapped(location: CGPoint) {}
    #endif

    // MARK: - Tileset Delegate

    open func willAddSpriteSheet(to tileset: SKTileset, fileNamed: String) -> String {
        // Called when a tileset is about to add a spritesheet image.
        return fileNamed
    }
    
    
    open func willAddImage(to tileset: SKTileset, forId: Int, fileNamed: String) -> String {
        // Called when a tileset is about to add an image to a collection.
        return fileNamed
    }
    
    // MARK: - Updating
    
    /// Called before each frame is rendered.
    ///
    /// - parameter currentTime: `TimeInterval` update interval.
    override open func update(_ currentTime: TimeInterval) {
        // Initialize lastUpdateTime if it has not already been
        if (self.lastUpdateTime == 0) {
            self.lastUpdateTime = currentTime
        }
        
        // Calculate time since last update
        var dt = currentTime - self.lastUpdateTime
        dt = dt > maximumUpdateDelta ? maximumUpdateDelta : dt
        
        self.lastUpdateTime = currentTime
        
        // update tilemap
        self.tilemap?.update(currentTime)
    }
    
    /// Update the camera bounds.
    open func updateCamera() {
        guard (view != nil) else { return }
        
        // update camera bounds
        if let cameraNode = cameraNode {
            cameraNode.setCameraBounds(bounds: CGRect(x: -(size.width / 2), y: -(size.height / 2), width: size.width, height: size.height))
        }
    }
}


// setup methods
extension SKTiledSceneDelegate where Self: SKScene {

    /// Loads a TMX file with the scene as delegate and data source, when it conforms.
    ///
    /// - Parameters:
    ///   - url: TMX file.
    ///   - bundle: bundle used for file-name and asset catalog fallbacks, or `nil` for none.
    ///   - tilesets: tilesets loaded earlier with `SKTileset.load(urls:)`.
    ///   - ignoreProperties: don't parse custom properties.
    ///   - loggingLevel: logging verbosity.
    /// - Returns: tile map node, not yet added to the scene.
    /// - Throws: `TiledError`.
    public func load(url: URL,
                     bundle: Bundle? = nil,
                     withTilesets tilesets: [SKTileset] = [],
                     ignoreProperties: Bool = false,
                     loggingLevel: LoggingLevel = TiledGlobals.default.loggingLevel) throws -> SKTilemap {

        return try SKTilemap.load(url: url,
                                  bundle: bundle,
                                  delegate: self as? SKTilemapDelegate,
                                  tilesetDataSource: self as? SKTilesetDataSource,
                                  withTilesets: tilesets,
                                  ignoreProperties: ignoreProperties,
                                  loggingLevel: loggingLevel)
    }
}


#if os(macOS)
extension SKTiledScene {
    
    /// Mouse click event handler.
    ///
    /// - Parameter event: mouse event.
    override open func mouseDown(with event: NSEvent) {
        guard let cameraNode = cameraNode else { return }
        cameraNode.mouseDown(with: event)
    }
    
    /// Mouse move event handler.
    ///
    /// - Parameter event: mouse event.
    override open func mouseMoved(with event: NSEvent) {
        guard let cameraNode = cameraNode else { return }
        cameraNode.mouseMoved(with: event)
    }
    
    /// Mouse drag event handler: pans the camera.
    ///
    /// - Parameter event: mouse event.
    override open func mouseDragged(with event: NSEvent) {
        guard let cameraNode = cameraNode else { return }
        cameraNode.scenePositionChanged(with: event)
    }

    override open func mouseUp(with event: NSEvent) {
        cameraNode?.mouseUp(with: event)
    }
    override open func mouseEntered(with event: NSEvent) {}
    override open func mouseExited(with event: NSEvent) {}
    
    /// Mouse scroll wheel event handler.
    ///
    /// - Parameter event: mouse event.
    override open func scrollWheel(with event: NSEvent) {
        guard let cameraNode = cameraNode else { return }
        cameraNode.scrollWheel(with: event)
    }
}
#endif


extension SKTiledScene: Loggable {}
