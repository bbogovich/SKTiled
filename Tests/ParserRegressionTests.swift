//
//  ParserRegressionTests.swift
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


/// Regression tests for parser, tileset and tile data fixes. Fixtures live in `Fixtures/parser`.
///
/// `sheet.tsx` slices `tiles.png` (18x13): 4x4 tiles, margin 2, spacing 1, 3 columns x 2 rows.
@MainActor
final class ParserRegressionTests: XCTestCase {

    private func fixture(_ name: String) -> URL {
        return Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
            .appendingPathComponent("parser")
            .appendingPathComponent(name)
    }

    private func load(_ name: String) throws -> SKTilemap {
        return try SKTilemap.load(url: fixture(name), loggingLevel: .none)
    }

    private func loadSheet() throws -> SKTileset {
        let tilesets = try SKTileset.load(urls: [fixture("sheet.tsx")], loggingLevel: .none)
        return try XCTUnwrap(tilesets.first)
    }

    // MARK: - Sprite sheet slicing

    func testSpriteSheetSlicingHonoursMarginAndSpacing() throws {
        let tileset = try loadSheet()
        XCTAssertEqual(tileset.dataCount, 6)
        XCTAssertEqual(tileset.columns, 3)

        let textureSize = CGSize(width: 18, height: 13)
        for id in 0..<6 {
            let col = id % 3
            let row = id / 3
            // pixel rect, y-up: row 0 sits under the 2px top margin
            let x = CGFloat(2 + col * 5)
            let y = CGFloat(13 - 2 - 4 - row * 5)
            let expected = CGRect(x: x / textureSize.width, y: y / textureSize.height,
                                  width: 4 / textureSize.width, height: 4 / textureSize.height)

            let texture = try XCTUnwrap(tileset.getTileData(localID: id)?.texture, "tile \(id)")
            let rect = texture.textureRect()
            XCTAssertEqual(rect.origin.x, expected.origin.x, accuracy: 0.0001, "tile \(id) x")
            XCTAssertEqual(rect.origin.y, expected.origin.y, accuracy: 0.0001, "tile \(id) y")
            XCTAssertEqual(rect.width, expected.width, accuracy: 0.0001, "tile \(id) width")
            XCTAssertEqual(rect.height, expected.height, accuracy: 0.0001, "tile \(id) height")
        }
    }

    func testZeroTileSizeIsRejected() throws {
        XCTAssertNil(SKTileset(attributes: ["name": "zero", "tilewidth": "0", "tileheight": "4"]))

        XCTAssertThrowsError(try load("zero-size.tmx")) { error in
            guard case TiledError.invalidContent = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        // slicing with a zero tile size must not trap
        let tileset = SKTileset(name: "empty", tileSize: .zero)
        let image = try TiledImageLoader.cgImage(contentsOf: fixture("tiles.png"))
        tileset.addTextures(fromSpriteSheet: image, source: "tiles.png")
        XCTAssertEqual(tileset.dataCount, 0)
    }

    // MARK: - Layer data

    func testXMLEncodedEmptyTilesAreGidZero() throws {
        let tilemap = try load("xml-layer.tmx")
        XCTAssertNotNil(tilemap.tileAt(0, 0, inLayer: "ground"))
        XCTAssertNil(tilemap.tileAt(1, 0, inLayer: "ground"))
        XCTAssertNil(tilemap.tileAt(0, 1, inLayer: "ground"))
        XCTAssertEqual(tilemap.tileAt(1, 1, inLayer: "ground")?.tileData.id, 4)
    }

    func testLayerDataSizeMismatchThrows() {
        XCTAssertThrowsError(try load("size-mismatch.tmx")) { error in
            guard case TiledError.invalidContent(let url, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(url.lastPathComponent, "size-mismatch.tmx")
        }
    }

    // MARK: - Properties

    func testMultiLinePropertyValueIsRead() throws {
        let tilemap = try load("xml-layer.tmx")
        XCTAssertEqual(tilemap.properties["notes"], "first line\nsecond line")
        XCTAssertEqual(tilemap.properties["single"], "one")
    }

    func testObjectPropertiesStayOnTheObject() throws {
        let tilemap = try load("xml-layer.tmx")
        let group = try XCTUnwrap(tilemap.objectGroups(named: "objects").first)
        XCTAssertEqual(group.properties["groupNote"], "group")
        XCTAssertNil(group.properties["objectNote"])

        let marker = try XCTUnwrap(tilemap.getObjects().first { $0.id == 1 })
        XCTAssertEqual(marker.properties["objectNote"], "object")
    }

    func testTilesetWalkableAndTileProperties() throws {
        let tilemap = try load("xml-layer.tmx")
        let sheet = try XCTUnwrap(tilemap.getTileset(named: "sheet"))
        let walkable = (0..<6).filter { sheet.getTileData(localID: $0)?.walkable == true }
        XCTAssertEqual(walkable, [1, 4])

        let wall = try XCTUnwrap(sheet.getTileData(localID: 2))
        XCTAssertEqual(wall.type, "wall")
        XCTAssertEqual(wall.weight, 5)
    }

    func testImageCollectionTileProperties() throws {
        let tilesets = try SKTileset.load(urls: [fixture("collection.tsx")], loggingLevel: .none)
        let crate = try XCTUnwrap(tilesets.first?.getTileData(localID: 0))
        XCTAssertEqual(crate.type, "crate")
        XCTAssertTrue(crate.walkable)
        XCTAssertEqual(crate.weight, 3)
    }

    // MARK: - Tileset ids

    func testGlobalIDRangesAndLookups() throws {
        let tilemap = try load("xml-layer.tmx")
        let sheet = try XCTUnwrap(tilemap.getTileset(named: "sheet"))
        XCTAssertEqual(sheet.firstGID, 1)
        XCTAssertEqual(sheet.lastGID, 6)
        XCTAssertEqual(sheet.globalRange, 1...6)
        XCTAssertEqual(sheet.localRange, 0...5)
        XCTAssertEqual(tilemap.lastGID, 6)

        // local -> global agrees with the tile data
        let data = try XCTUnwrap(sheet.getTileData(localID: 3))
        XCTAssertEqual(sheet.getGlobalID(forLocalID: 3), data.globalID)
        XCTAssertTrue(sheet.getTileData(globalID: data.globalID) === data)

        // an id that is already in use is rejected, a new one is added
        XCTAssertNil(sheet.addTilesetTile(3, texture: SKTexture()))
        XCTAssertNotNil(sheet.addTilesetTile(9, texture: SKTexture()))
        XCTAssertEqual(sheet.lastGID, 10)
    }

    func testEmptyTilesetRangesDoNotTrap() {
        let tileset = SKTileset(name: "empty", tileSize: CGSize(width: 8, height: 8), firstgid: 5)
        XCTAssertEqual(tileset.lastGID, 5)
        XCTAssertEqual(tileset.globalRange, 5...5)
        XCTAssertEqual(tileset.localRange, 0...0)
        XCTAssertFalse(tileset.contains(globalID: 5))
        XCTAssertNil(tileset.getTileData(globalID: 5))
    }

    func testTileDataIdentityIsStableWhenFirstGIDChanges() throws {
        let tileset = try loadSheet()
        let data = try XCTUnwrap(tileset.getTileData(localID: 2))
        let other = try XCTUnwrap(tileset.getTileData(localID: 3))
        var set: Set<SKTilesetData> = [data, other]
        tileset.firstGID = 40
        XCTAssertTrue(set.contains(data))
        XCTAssertNotNil(set.remove(data))
        XCTAssertEqual(set.count, 1)

        // equal ids in different tilesets are different tile data
        let copy = try loadSheet()
        XCTAssertNotEqual(copy.getTileData(localID: 2), data)
    }

    // MARK: - Templates

    func testTemplatesKeepFlipFlagsPropertiesAndOverrides() throws {
        let tilemap = try load("templates.tmx")
        let objects = tilemap.getObjects()

        let chest = try XCTUnwrap(objects.first { $0.id == 1 })
        XCTAssertEqual(chest.name, "chest")
        XCTAssertEqual(chest.type, "chest")
        XCTAssertEqual(chest.gid, Int(0x80000000 as UInt32) | 4, "template gid 4 is local id 3, with the horizontal flip flag")
        XCTAssertEqual(chest.tileData?.id, 3)
        XCTAssertEqual(chest.properties["loot"], "gold")
        XCTAssertEqual(chest.properties["locked"], "true")

        let openChest = try XCTUnwrap(objects.first { $0.id == 2 })
        XCTAssertEqual(openChest.name, "open chest", "instance attributes override the template")
        XCTAssertEqual(openChest.properties["locked"], "false", "instance properties override the template")
        XCTAssertEqual(openChest.properties["loot"], "gold")
        XCTAssertEqual(openChest.gid, chest.gid)
    }

    func testTemplateOnlyTilesetGetsFreeGids() throws {
        let tilemap = try load("templates.tmx")
        XCTAssertEqual(tilemap.tilesets.count, 2)

        let collection = try XCTUnwrap(tilemap.getTileset(named: "collection"))
        XCTAssertEqual(collection.firstGID, 7, "numbered after the map's own tileset (gids 1...6)")

        let crate = try XCTUnwrap(tilemap.getObjects().first { $0.id == 3 })
        XCTAssertEqual(crate.gid, 7)
        XCTAssertTrue(crate.tileData?.tileset === collection)

        // the map's own tiles are unaffected
        XCTAssertEqual(tilemap.tileAt(0, 0, inLayer: "ground")?.tileData.id, 0)
    }

    // MARK: - Shared tilesets

    func testSharedTilesetIsMatchedByURLAndNotRenumbered() throws {
        let preloaded = try loadSheet()

        let first = try SKTilemap.load(url: fixture("xml-layer.tmx"), withTilesets: [preloaded], loggingLevel: .none)
        XCTAssertTrue(first.tilesets.contains(preloaded))
        XCTAssertEqual(preloaded.firstGID, 1)

        // the second map numbers the same file from 2: it gets its own copy
        let second = try SKTilemap.load(url: fixture("shared.tmx"), withTilesets: [preloaded], loggingLevel: .none)
        XCTAssertEqual(preloaded.firstGID, 1, "the first map's tileset must keep its first gid")
        XCTAssertTrue(preloaded.tilemap === first)

        let secondSheet = try XCTUnwrap(second.getTileset(named: "sheet"))
        XCTAssertFalse(secondSheet === preloaded)
        XCTAssertEqual(secondSheet.firstGID, 2)
        XCTAssertEqual(second.tileAt(0, 0, inLayer: "ground")?.tileData.id, 0)
    }

    // MARK: - Logging

    func testLoadingRestoresTheLoggingLevel() throws {
        let logger = Logger.default
        let previous = logger.loggingLevel
        defer { logger.loggingLevel = previous }

        logger.loggingLevel = .error
        _ = try load("xml-layer.tmx")
        XCTAssertEqual(logger.loggingLevel, .error)
        _ = try SKTileset.load(urls: [fixture("sheet.tsx")], loggingLevel: .none)
        XCTAssertEqual(logger.loggingLevel, .error)
    }

    // MARK: - Globals

    func testGlobalsValueTypesAreUsable() {
        var version = TiledGlobals.Version(major: 2, minor: 1, patch: 3)
        version.suffix = "b"
        XCTAssertEqual(version.description, "2.1.3b")

        var quality = TiledGlobals.RenderQuality()
        quality.text = 12
        XCTAssertEqual(quality.text, 12)

        let filters: TiledGlobals.DebugDisplayOptions.MouseFilters = [.tileCoordinates, .tilesUnderCursor]
        XCTAssertTrue(filters.contains(.tilesUnderCursor))
    }
}
