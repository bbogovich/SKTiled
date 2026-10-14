//
//  LayerRegressionTests.swift
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
@testable import SKTiled


/// Regression tests for coordinate conversion, the layer tree, tile placement and object bookkeeping.
@MainActor
final class LayerRegressionTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a map from `<map>` attributes, as the parser does.
    private func makeMap(_ orientation: String, width: Int, height: Int, tileWidth: Int, tileHeight: Int,
                         extra: [String: String] = [:], file: StaticString = #filePath, line: UInt = #line) throws -> SKTilemap {
        var attributes = ["width": "\(width)", "height": "\(height)",
                          "tilewidth": "\(tileWidth)", "tileheight": "\(tileHeight)",
                          "orientation": orientation]
        attributes.merge(extra) { _, new in new }
        return try XCTUnwrap(SKTilemap(attributes: attributes), file: file, line: line)
    }

    /// Asserts that every tile's center point converts back to its own coordinate.
    private func assertRoundTrip(_ tilemap: SKTilemap, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        var failures: [String] = []
        for y in 0..<Int(tilemap.size.height) {
            for x in 0..<Int(tilemap.size.width) {
                let coord = CGPoint(x: x, y: y)
                let point = tilemap.pointForCoordinate(coord: coord)
                let result = tilemap.coordinateForPoint(point)
                if (result != coord) {
                    failures.append("(\(x),\(y)) -> \(point) -> (\(result.x),\(result.y))")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(label): \(failures.count) coordinates do not round-trip, e.g. \(failures.prefix(4))",
                      file: file, line: line)
    }

    /// A small orthogonal map built in code.
    private func makeOrthogonalMap() -> SKTilemap {
        return SKTilemap(6, 4, 16, 16)
    }

    // MARK: - Coordinates

    func testIsometricRoundTrip() throws {
        let tilemap = try makeMap("isometric", width: 10, height: 10, tileWidth: 130, tileHeight: 66)
        assertRoundTrip(tilemap, "isometric 130x66")
    }

    func testStaggeredRoundTripAllAxesAndIndices() throws {
        for axis in ["x", "y"] {
            for index in ["odd", "even"] {
                let tilemap = try makeMap("staggered", width: 9, height: 11, tileWidth: 64, tileHeight: 33,
                                          extra: ["staggeraxis": axis, "staggerindex": index])
                assertRoundTrip(tilemap, "staggered axis \(axis), index \(index)")
            }
        }
    }

    func testHexagonalRoundTripAllAxesAndIndices() throws {
        for axis in ["x", "y"] {
            for index in ["odd", "even"] {
                let tilemap = try makeMap("hexagonal", width: 10, height: 10, tileWidth: 64, tileHeight: 64,
                                          extra: ["hexsidelength": "32", "staggeraxis": axis, "staggerindex": index])
                assertRoundTrip(tilemap, "hexagonal axis \(axis), index \(index)")
            }
        }
    }

    /// The demo hex map: odd tile size, y-axis, odd index.
    func testDemoHexagonalMapRoundTrip() throws {
        let tilemap = try makeMap("hexagonal", width: 10, height: 10, tileWidth: 65, tileHeight: 65,
                                  extra: ["hexsidelength": "31", "staggeraxis": "y", "staggerindex": "odd"])
        assertRoundTrip(tilemap, "hexagonal 65x65")
    }

    /// Stagger neighbours use Tiled's 0 (odd) / 1 (even) index, the same in every process.
    func testStaggerNeighboursFollowStaggerIndex() throws {
        let odd = try makeMap("staggered", width: 4, height: 4, tileWidth: 64, tileHeight: 32,
                              extra: ["staggeraxis": "y", "staggerindex": "odd"])
        let even = try makeMap("staggered", width: 4, height: 4, tileWidth: 64, tileHeight: 32,
                               extra: ["staggeraxis": "y", "staggerindex": "even"])

        // odd rows are shifted right when the index is odd
        XCTAssertEqual(odd.topLeft(2, 1), CGPoint(x: 2, y: 0))
        XCTAssertEqual(odd.bottomRight(2, 1), CGPoint(x: 3, y: 2))
        XCTAssertEqual(even.topLeft(2, 1), CGPoint(x: 1, y: 0))
        XCTAssertEqual(even.bottomRight(2, 1), CGPoint(x: 2, y: 2))

        let oddX = try makeMap("staggered", width: 4, height: 4, tileWidth: 64, tileHeight: 32,
                               extra: ["staggeraxis": "x", "staggerindex": "odd"])
        XCTAssertEqual(oddX.topRight(1, 2), CGPoint(x: 2, y: 2))
        XCTAssertEqual(oddX.bottomLeft(1, 2), CGPoint(x: 0, y: 3))
    }

    func testAddChildAtCoordinateAppliesOffsetOnce() {
        let tilemap = makeOrthogonalMap()
        let layer = tilemap.newTileLayer(named: "ground")
        let node = SKNode()
        layer.addChild(node, coord: CGPoint(x: 2, y: 1), offset: CGPoint(x: 3, y: 5))
        XCTAssertEqual(node.position, layer.pointForCoordinate(coord: CGPoint(x: 2, y: 1), offsetX: 3, offsetY: 5))
    }

    // MARK: - Map setup

    func testProgrammaticMapCanFinishRendering() {
        let tilemap = makeOrthogonalMap()
        XCTAssertNotNil(tilemap.dataStorage)
        XCTAssertNotNil(tilemap.debugNode)
        let layer = tilemap.newTileLayer(named: "ground")
        layer.didFinishRendering()
        tilemap.didFinishRendering(timeStarted: Date())
        XCTAssertTrue(tilemap.isRendered)
    }

    func testRenderQualityLimits() throws {
        let large = try makeMap("orthogonal", width: 500, height: 500, tileWidth: 32, tileHeight: 32)
        XCTAssertGreaterThanOrEqual(large.maxRenderQuality, 1)
        XCTAssertGreaterThanOrEqual(large.renderQuality, 1)

        let empty = try makeMap("orthogonal", width: 0, height: 0, tileWidth: 16, tileHeight: 16)
        XCTAssertTrue(empty.maxRenderQuality.isFinite)
        XCTAssertGreaterThanOrEqual(empty.maxRenderQuality, 1)
    }

    func testSpeedIsNotCopiedToChildren() {
        let tilemap = makeOrthogonalMap()
        let layer = tilemap.newTileLayer(named: "ground")
        tilemap.speed = 2
        XCTAssertEqual(layer.speed, 1, "SpriteKit already multiplies child speed by the parent's")
    }

    // MARK: - Layers

    func testAddAndRemoveLayer() {
        let tilemap = makeOrthogonalMap()
        let layer = tilemap.newTileLayer(named: "ground")
        XCTAssertTrue(tilemap.layers.contains(layer))

        // adding again fails without re-parenting the node (which would raise)
        let again = tilemap.addLayer(layer)
        XCTAssertFalse(again.success)
        XCTAssertTrue(layer.parent === tilemap)

        XCTAssertTrue(tilemap.removeLayer(layer) === layer)
        XCTAssertNil(layer.parent)
        XCTAssertFalse(tilemap.layers.contains(layer))
        XCTAssertNil(tilemap.removeLayer(layer))

        // it can be added back
        XCTAssertTrue(tilemap.addLayer(layer).success)
        XCTAssertTrue(layer.parent === tilemap)
        XCTAssertTrue(tilemap.layers.contains(layer))
    }

    func testRemovingLayerReleasesTilesFromStorage() throws {
        let tilemap = makeOrthogonalMap()
        let layer = tilemap.newTileLayer(named: "ground")
        let tile = try XCTUnwrap(layer.addTileAt(coord: CGPoint(x: 1, y: 1), texture: SKTexture()))
        let other = try XCTUnwrap(layer.addTileAt(coord: CGPoint(x: 2, y: 1), texture: SKTexture()))
        let storage = try XCTUnwrap(tilemap.dataStorage)
        XCTAssertTrue(storage.allTiles.contains(tile))

        _ = tilemap.removeLayer(layer)
        XCTAssertFalse(storage.allTiles.contains(tile))
        XCTAssertFalse(storage.allTiles.contains(other))
    }

    func testRemovingNestedLayer() throws {
        let tilemap = makeOrthogonalMap()
        let group = tilemap.newGroupLayer(named: "group")
        let nested = tilemap.newTileLayer(named: "nested", group: group)
        let tile = try XCTUnwrap(nested.addTileAt(coord: CGPoint(x: 0, y: 0), texture: SKTexture()))

        XCTAssertTrue(tilemap.layers.contains(nested))
        XCTAssertTrue(tilemap.removeLayer(nested) === nested)
        XCTAssertNil(nested.parent)
        XCTAssertFalse(tilemap.layers.contains(nested))
        XCTAssertFalse(try XCTUnwrap(tilemap.dataStorage).allTiles.contains(tile))
    }

    func testClearLayerReleasesTiles() throws {
        let tilemap = makeOrthogonalMap()
        let layer = tilemap.newTileLayer(named: "ground")
        let tile = try XCTUnwrap(layer.addTileAt(coord: CGPoint(x: 1, y: 1), texture: SKTexture()))
        _ = try XCTUnwrap(layer.addTileAt(coord: CGPoint(x: 2, y: 2), texture: SKTexture()))
        layer.clearLayer()
        XCTAssertNil(tile.parent)
        XCTAssertEqual(layer.tileCount, 0)
        XCTAssertTrue(try XCTUnwrap(tilemap.dataStorage).allTiles.isEmpty)
    }

    func testGetLayersReturnsEveryMatch() {
        let tilemap = makeOrthogonalMap()
        let first = tilemap.newTileLayer(named: "dup")
        let group = tilemap.newGroupLayer(named: "group")
        let nested = tilemap.newObjectGroup(named: "dup", group: group)
        tilemap.newTileLayer(named: "dup-suffix")

        let named = tilemap.getLayers(named: "dup")
        XCTAssertEqual(named.count, 2)
        XCTAssertTrue(named.first === first)
        XCTAssertTrue(named.last === nested)

        XCTAssertEqual(tilemap.getLayers(named: "dup", recursive: false).count, 1)
        XCTAssertEqual(tilemap.getLayers(withPrefix: "dup").count, 3)
        XCTAssertEqual(tilemap.getLayers(atPath: "group/dup").count, 1)
    }

    func testLayerOrderIsLowestIndexFirst() {
        let tilemap = makeOrthogonalMap()
        let a = tilemap.newTileLayer(named: "a")
        let group = tilemap.newGroupLayer(named: "group")
        let nested = tilemap.newTileLayer(named: "nested", group: group)
        let b = tilemap.newImageLayer(named: "b")

        XCTAssertEqual(tilemap.getLayers().map { $0.layerName }, ["a", "group", "nested", "b"])
        XCTAssertEqual(tilemap.getLayers(recursive: false).map { $0.layerName }, ["a", "group", "b"])
        XCTAssertEqual(tilemap.tileLayers().map { $0.layerName }, ["a", "nested"])

        // the cached order follows index changes
        a.index = 10
        XCTAssertEqual(tilemap.getLayers(recursive: false).map { $0.layerName }, ["group", "b", "a"])
        XCTAssertTrue(tilemap.layers.contains(nested))
        XCTAssertTrue(tilemap.layers.contains(b))
    }

    func testActualZPositionOfNestedLayer() {
        let tilemap = makeOrthogonalMap()
        let group = tilemap.newGroupLayer(named: "group")
        let nested = tilemap.newTileLayer(named: "nested", group: group)
        XCTAssertEqual(nested.actualZPosition, group.zPosition + nested.zPosition)
    }

    // MARK: - Tiles

    func testAddTileAtIgnoresLayerOffset() throws {
        let tilemap = makeOrthogonalMap()
        let layer = tilemap.newTileLayer(named: "ground")
        layer.offset = CGPoint(x: 7, y: 9)
        let coord = CGPoint(x: 3, y: 2)
        let tile = try XCTUnwrap(layer.addTileAt(coord: coord, texture: SKTexture()))
        XCTAssertEqual(tile.position, layer.pointForCoordinate(coord: coord), "the layer node already carries the layer offset")
    }

    func testSetTileReplacesNodeAndCache() throws {
        let tilemap = makeOrthogonalMap()
        let layer = tilemap.newTileLayer(named: "ground")
        let storage = try XCTUnwrap(tilemap.dataStorage)
        let coord = CGPoint(x: 1, y: 2)
        let original = try XCTUnwrap(layer.addTileAt(coord: coord, texture: SKTexture()))

        let replacement = SKTile(texture: SKTexture())
        XCTAssertTrue(layer.setTile(at: coord, tile: replacement) === replacement)
        XCTAssertTrue(layer.tileAt(coord: coord) === replacement)
        XCTAssertTrue(replacement.parent === layer)
        XCTAssertNil(original.parent)
        XCTAssertFalse(storage.allTiles.contains(original))
        XCTAssertTrue(storage.allTiles.contains(replacement))

        // nil removes
        XCTAssertNil(layer.setTile(1, 2, tile: nil))
        XCTAssertNil(layer.tileAt(coord: coord))
        XCTAssertNil(replacement.parent)

        // out of bounds is rejected
        XCTAssertNil(layer.setTile(99, 99, tile: SKTile()))
    }

    // MARK: - Objects

    func testProgrammaticObjectsAreAllAdded() throws {
        let tilemap = makeOrthogonalMap()
        let group = tilemap.newObjectGroup(named: "objects")
        let first = SKTileObject(width: 8, height: 8)
        let second = SKTileObject(width: 8, height: 8)

        XCTAssertNotNil(group.addObject(first))
        XCTAssertNotNil(group.addObject(second), "objects with the same id are different objects")
        XCTAssertNil(group.addObject(first), "the same object cannot be added twice")
        XCTAssertEqual(group.count, 2)

        XCTAssertTrue(group.removeObject(first) === first)
        XCTAssertNil(first.parent)
        XCTAssertEqual(group.count, 1)
        XCTAssertNil(group.removeObject(first))
    }

    func testNewTileObjectsGetUniqueIDs() {
        let tilemap = makeOrthogonalMap()
        let group = tilemap.newObjectGroup(named: "objects")
        let data = SKTilesetData()
        let first = group.newTileObject(data: data)
        let second = group.newTileObject(data: data)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertGreaterThan(first.id, 0)
        XCTAssertEqual(group.count, 2)
        XCTAssertTrue(first.parent === group)
        XCTAssertTrue(second.parent === group)
    }

    // MARK: - Animation

    func testAnimationFrameSelectionWrapsWithRemainder() throws {
        let tilemap = makeOrthogonalMap()
        let storage = try XCTUnwrap(tilemap.dataStorage)
        let frame0 = SKTexture()
        let frame1 = SKTexture()
        let data = SKTilesetData()
        _ = data.addFrame(withID: 0, interval: 100, tileTexture: frame0)
        _ = data.addFrame(withID: 1, interval: 100, tileTexture: frame1)

        let tile = SKTile()
        tile.tileData = data
        storage.tileAdded(tile)

        tilemap.updateAnimatedTiles(delta: 0.15)
        XCTAssertTrue(tile.texture === frame1)

        // 0.25s is past the 0.2s cycle: wraps to 0.05s, frame 0 (previously no frame was chosen)
        tilemap.updateAnimatedTiles(delta: 0.1)
        XCTAssertTrue(tile.texture === frame0)
        XCTAssertEqual(data.currentTime, 0.05, accuracy: 0.0001)

        tilemap.updateAnimatedTiles(delta: 0.1)
        XCTAssertTrue(tile.texture === frame1)
    }
}
