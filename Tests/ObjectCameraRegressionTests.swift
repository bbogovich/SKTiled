//
//  ObjectCameraRegressionTests.swift
//  SKTiledTests
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

import XCTest
import SpriteKit
import GameplayKit
@testable import SKTiled


/// Regression tests for tiles, vector objects, the scene and its camera.
@MainActor
final class ObjectCameraRegressionTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        TiledGlobals.default.loggingLevel = .none
    }

    /// Scenes kept alive for the test: the camera holds its world node unowned.
    private var scenes: [SKScene] = []

    override func tearDown() async throws {
        scenes.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Loads the shared test map.
    private func loadTestMap() throws -> SKTilemap {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: type(of: self))
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "test-tilemap", withExtension: "tmx"))
        return try SKTilemap.load(url: url, loggingLevel: .none)
    }

    /// A camera over a world node, inside a scene.
    private func makeCamera() -> (camera: SKTiledSceneCamera, world: SKNode, scene: SKScene) {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let scene = SKScene(size: CGSize(width: 200, height: 100))
        let world = SKNode()
        scene.addChild(world)
        let camera = SKTiledSceneCamera(view: view, world: world)
        scene.addChild(camera)
        camera.ignoreZoomClamping = true
        scenes.append(scene)
        return (camera, world, scene)
    }

    /// Returns whether the path contains a `closeSubpath` element.
    private func pathIsClosed(_ path: CGPath) -> Bool {
        var closed = false
        path.applyWithBlock { element in
            if element.pointee.type == .closeSubpath {
                closed = true
            }
        }
        return closed
    }

    // MARK: - Camera zoom

    func testZoomIsConstrainedToMinMax() {
        let (camera, world, _) = makeCamera()
        camera.setZoomConstraints(minimum: 0.5, maximum: 4)

        camera.setCameraZoom(10)
        XCTAssertEqual(camera.zoom, 4)
        XCTAssertEqual(world.xScale, 4)

        camera.setCameraZoom(0.1)
        XCTAssertEqual(camera.zoom, 0.5)

        camera.setCameraZoom(2)
        XCTAssertEqual(camera.zoom, 2)
    }

    func testIgnoringZoomConstraintsAllowsAnyZoom() {
        let (camera, _, _) = makeCamera()
        camera.setZoomConstraints(minimum: 0.5, maximum: 4)
        camera.ignoreZoomConstraints = true

        camera.setCameraZoom(10)
        XCTAssertEqual(camera.zoom, 10)
    }

    func testZoomClampingKeepsConstraints() {
        let (camera, _, _) = makeCamera()
        camera.setZoomConstraints(minimum: 0.5, maximum: 4)
        camera.zoomClamping = .half
        camera.ignoreZoomClamping = false

        // rounded to the nearest half
        camera.setCameraZoom(1.3)
        XCTAssertEqual(camera.zoom, 1.5)

        // rounding must not discard the constraint
        camera.setCameraZoom(9)
        XCTAssertEqual(camera.zoom, 4)
    }

    func testZoomAtLocationKeepsLocationFixedOnScreen() {
        let (camera, world, scene) = makeCamera()
        world.position = CGPoint(x: 13, y: -7)
        camera.position = CGPoint(x: 20, y: 10)

        let location = CGPoint(x: 60, y: 30)
        let worldPoint = world.convert(location, from: scene)
        let offsetBefore = CGPoint(x: location.x - camera.position.x, y: location.y - camera.position.y)

        camera.setCameraZoomAtLocation(scale: 2, location: location)
        XCTAssertEqual(camera.zoom, 2)

        // the same world point is still at the same offset from the camera
        let pointAfter = scene.convert(worldPoint, from: world)
        let offsetAfter = CGPoint(x: pointAfter.x - camera.position.x, y: pointAfter.y - camera.position.y)
        XCTAssertEqual(offsetAfter.x, offsetBefore.x, accuracy: 0.0001)
        XCTAssertEqual(offsetAfter.y, offsetBefore.y, accuracy: 0.0001)
    }

    func testAnimatedZoomDoesNotNotifyBeforeItFinishes() {
        let (camera, _, _) = makeCamera()
        let observer = CameraObserver()
        camera.addDelegate(observer)

        camera.setCameraZoom(2, interval: 1)
        XCTAssertTrue(observer.zooms.isEmpty)

        camera.centerOn(scenePoint: CGPoint(x: 5, y: 5), duration: 1)
        XCTAssertTrue(observer.positions.isEmpty)

        camera.setCameraZoom(3)
        XCTAssertEqual(observer.zooms, [3])
    }

    // MARK: - Scene

    func testReplacingMapClearsGraphs() throws {
        let scene = SKTiledScene(size: CGSize(width: 200, height: 100))
        scene.setup(tilemap: try loadTestMap())
        XCTAssertTrue(scene.addGraph(named: "nav", graph: GKGridGraph<GKGridGraphNode>()))

        scene.setup(tilemap: try loadTestMap())
        XCTAssertTrue(scene.graphs.isEmpty)
        XCTAssertTrue(scene.addGraph(named: "nav", graph: GKGridGraph<GKGridGraphNode>()))
    }

    func testSceneAppliesMapZoomConstraints() throws {
        let tilemap = try loadTestMap()
        tilemap.zoomConstraints.min = 0.75
        tilemap.zoomConstraints.max = 3

        let scene = SKTiledScene(size: CGSize(width: 200, height: 100))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        view.presentScene(scene)
        scene.setup(tilemap: tilemap)

        let camera = try XCTUnwrap(scene.cameraNode)
        XCTAssertEqual(camera.minZoom, 0.75)
        XCTAssertEqual(camera.maxZoom, 3)
    }

    // MARK: - Text objects

    func testTextAlignmentMapsToNSTextAlignment() {
        typealias Horizontal = TextObjectAttributes.TextAlignment.HoriztonalAlignment
        XCTAssertEqual(Horizontal.left.textAlignment, NSTextAlignment.left)
        XCTAssertEqual(Horizontal.center.textAlignment, NSTextAlignment.center)
        XCTAssertEqual(Horizontal.right.textAlignment, NSTextAlignment.right)
    }

    // MARK: - Objects

    func testGroupAcceptsSeveralProgrammaticObjects() throws {
        let tilemap = try loadTestMap()
        let group = tilemap.newObjectGroup(named: "programmatic")

        // programmatic objects all have id 0
        let first = SKTileObject(width: 8, height: 8)
        let second = SKTileObject(width: 16, height: 16)
        XCTAssertEqual(first.id, second.id)
        XCTAssertNotEqual(first, second)
        XCTAssertNotNil(group.addObject(first))
        XCTAssertNotNil(group.addObject(second))
        XCTAssertEqual(group.getObjects().count, 2)
    }

    func testRedrawingTileObjectReplacesCachedTile() throws {
        let tilemap = try loadTestMap()
        let group = tilemap.newObjectGroup(named: "tile-objects")
        let object = SKTileObject(width: 8, height: 8)
        XCTAssertNotNil(group.addObject(object))
        object.gid = 1

        object.draw()
        let firstTile = try XCTUnwrap(object.tile)
        object.draw()
        let secondTile = try XCTUnwrap(object.tile)

        let cached = try XCTUnwrap(tilemap.dataStorage).allTiles
        XCTAssertFalse(cached.contains { $0 === firstTile })
        XCTAssertTrue(cached.contains { $0 === secondTile })
        XCTAssertNil(firstTile.parent)
    }

    func testPolylineProxyIsOpenAndUnfilled() throws {
        let tilemap = try loadTestMap()
        let group = tilemap.newObjectGroup(named: "lines")

        let polyline = SKTileObject(width: 0, height: 0)
        polyline.addPoints([[0, 0], [16, 0], [16, 16]], closed: false)
        XCTAssertNotNil(group.addObject(polyline))

        let polygon = SKTileObject(width: 0, height: 0)
        polygon.addPoints([[0, 0], [16, 0], [16, 16]], closed: true)
        XCTAssertNotNil(group.addObject(polygon))

        let lineProxy = TileObjectProxy(object: polyline, visible: true)
        lineProxy.draw()
        let linePath = try XCTUnwrap(lineProxy.path)
        XCTAssertFalse(pathIsClosed(linePath))
        XCTAssertEqual(lineProxy.fillColor.alphaComponent, 0)

        let polygonProxy = TileObjectProxy(object: polygon, visible: true)
        polygonProxy.draw()
        let polygonPath = try XCTUnwrap(polygonProxy.path)
        XCTAssertTrue(pathIsClosed(polygonPath))
        XCTAssertGreaterThan(polygonProxy.fillColor.alphaComponent, 0)
    }

    // MARK: - Tiles

    func testTextureTileHasTextureSizeAndData() {
        let texture = SKTexture(data: Data(count: 16 * 8 * 4), size: CGSize(width: 16, height: 8))
        let tile = SKTile(texture: texture)
        XCTAssertEqual(tile.size, CGSize(width: 16, height: 8))
        XCTAssertEqual(tile.tileSize, CGSize(width: 16, height: 8))
        XCTAssertTrue(tile.tileData.texture === texture)

        // updating keeps the texture
        tile.update(1)
        XCTAssertTrue(tile.texture === texture)
    }

    func testTileOverlapScaleDoesNotCompound() {
        let texture = SKTexture(data: Data(count: 16 * 16 * 4), size: CGSize(width: 16, height: 16))
        let tile = SKTile(texture: texture)

        tile.setTileOverlap(1)
        XCTAssertEqual(tile.xScale, CGFloat(17) / 16, accuracy: 0.0001)
        XCTAssertEqual(tile.yScale, CGFloat(17) / 16, accuracy: 0.0001)

        tile.setTileOverlap(2)
        XCTAssertEqual(tile.xScale, CGFloat(18) / 16, accuracy: 0.0001)

        // clamped to the maximum overlap
        tile.setTileOverlap(10)
        XCTAssertEqual(tile.xScale, CGFloat(19) / 16, accuracy: 0.0001)

        // orienting keeps the overlap, and works without a tileset
        tile.orientTile()
        XCTAssertEqual(tile.xScale, CGFloat(19) / 16, accuracy: 0.0001)
        XCTAssertEqual(tile.yScale, CGFloat(19) / 16, accuracy: 0.0001)

        tile.setTileOverlap(0)
        XCTAssertEqual(tile.xScale, 1, accuracy: 0.0001)
    }

    func testTileOverlapIsAppliedToMapTiles() throws {
        let tilemap = try loadTestMap()
        let tile = try XCTUnwrap(tilemap.tileLayers().lazy.compactMap { $0.getTiles().first }.first)
        let width = try XCTUnwrap(tile.tileData.texture).size().width
        // overlap is off by default, so tiles draw at their exact size
        XCTAssertEqual(tilemap.tileOverlap, 0)
        XCTAssertEqual(abs(tile.xScale), 1, accuracy: 0.0001)

        tilemap.tileOverlap = 2
        XCTAssertEqual(abs(tile.xScale), (width + 2) / width, accuracy: 0.0001)
    }

    func testFlipFlagsBelongToEachTile() throws {
        let tilemap = try loadTestMap()
        let layer = try XCTUnwrap(tilemap.tileLayers().first)
        let gid = try XCTUnwrap(layer.getTiles().first).tileData.globalID
        let horizontalFlag = 0x80000000

        let flipped = try XCTUnwrap(layer.addTileAt(0, 0, gid: gid | horizontalFlag))
        let plain = try XCTUnwrap(layer.addTileAt(1, 0, gid: gid))

        // both tiles share one tile data, but only the first is flipped
        XCTAssertTrue(flipped.tileData === plain.tileData)
        XCTAssertTrue(flipped.flipHoriz)
        XCTAssertFalse(plain.flipHoriz)
        XCTAssertFalse(plain.tileData.flipHoriz)
        XCTAssertLessThan(flipped.xScale, 0)
        XCTAssertGreaterThan(plain.xScale, 0)
    }

    func testTileWithoutTilesetDrawsBounds() throws {
        let tilemap = try loadTestMap()
        let tile = SKTile(tileSize: CGSize(width: 8, height: 8))
        tile.layer = try XCTUnwrap(tilemap.tileLayers().first)
        XCTAssertNil(tile.tileData.tileset)

        tile.drawBounds()
        XCTAssertNotNil(tile.childNode(withName: tile.boundsKey))
        XCTAssertEqual(tile.tileOffset, .zero)
    }

    func testRenderModeRawValuesRoundTrip() {
        let modes: [TileRenderMode] = [
            .default, .static, .ignore,
            .animated(gid: nil), .animated(gid: 0), .animated(gid: 1), .animated(gid: 2),
            .animated(gid: 3), .animated(gid: 129), .animated(gid: -1)
        ]
        for mode in modes {
            XCTAssertEqual(TileRenderMode(rawValue: mode.rawValue), mode, "\(mode)")
        }
        XCTAssertEqual(Set(modes.map { $0.rawValue }).count, modes.count)

        // `renderMode` tile property values
        XCTAssertEqual(TileRenderMode(rawValue: 1), .static)
        XCTAssertEqual(TileRenderMode(rawValue: 129), .animated(gid: 129))
    }

    // MARK: - Debug

    func testAllDebugOptionsIncludeEveryOption() {
        let options: [DebugDrawOptions] = [.drawGrid, .drawBounds, .drawGraph, .drawObjectBounds,
                                           .drawTileBounds, .drawMouseOverObject, .drawBackground, .drawAnchor]
        for option in options {
            XCTAssertTrue(DebugDrawOptions.all.contains(option))
        }
    }
}


/// Records camera notifications.
@MainActor
private final class CameraObserver: SKTiledSceneCameraDelegate {
    var receiveCameraUpdates: Bool = true
    var zooms: [CGFloat] = []
    var positions: [CGPoint] = []

    func cameraZoomChanged(newZoom: CGFloat) {
        zooms.append(newZoom)
    }

    func cameraPositionChanged(newPosition: CGPoint) {
        positions.append(newPosition)
    }
}
