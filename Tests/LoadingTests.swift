//
//  LoadingTests.swift
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


/// Loading maps from real Tiled folder layouts, and the errors thrown for broken ones.
@MainActor
final class LoadingTests: XCTestCase {

    private var fixtures: URL {
        return Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    }

    private func fixture(_ path: String) -> URL {
        return fixtures.appendingPathComponent(path)
    }

    private func load(_ path: String) throws -> SKTilemap {
        return try SKTilemap.load(url: fixture(path), loggingLevel: .none)
    }

    /// Asserts the complete fixture map: two tilesets, both image kinds, the template and the `class` attribute.
    private func assertLevelIsComplete(_ tilemap: SKTilemap, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(tilemap.tilesets.count, 2, "template tileset should be shared with the map", file: file, line: line)

        let environment = tilemap.getTileset(named: "environment")
        XCTAssertEqual(environment?.dataCount, 45, file: file, line: line)
        XCTAssertEqual(environment?.getTileData(localID: 0)?.texture.size(), CGSize(width: 8, height: 8), file: file, line: line)

        let collection = tilemap.getTileset(named: "items-collection")
        XCTAssertEqual(collection?.isImageCollection, true, file: file, line: line)
        XCTAssertEqual(collection?.getTileData(localID: 0)?.texture.size(), CGSize(width: 128, height: 8), file: file, line: line)

        let backdrop = tilemap.getLayers(named: "backdrop").first as? SKImageLayer
        XCTAssertNotNil(backdrop?.image, file: file, line: line)

        XCTAssertNotNil(tilemap.tileAt(0, 0, inLayer: "ground"), file: file, line: line)

        XCTAssertEqual(tilemap.getObjects(ofType: "spawn").count, 1, "Tiled 1.9 `class` should be read as the object type", file: file, line: line)
        let chest = tilemap.getObjects().first { $0.id == 2 }
        XCTAssertEqual(chest?.type, "chest", "template attributes should be applied", file: file, line: line)
        XCTAssertNotNil(chest?.tileData, "template tile should be resolved", file: file, line: line)
    }

    // MARK: - Layouts

    func testNestedTiledLayoutLoads() throws {
        assertLevelIsComplete(try load("nested/maps/level.tmx"))
    }

    func testFlattenedLayoutLoadsByFileNameFallback() throws {
        assertLevelIsComplete(try load("flattened/level.tmx"))
    }

    func testJPEGSpriteSheetLoads() throws {
        let tilemap = try load("jpeg/level.tmx")
        let environment = tilemap.getTileset(named: "environment")
        XCTAssertEqual(environment?.dataCount, 45)
        XCTAssertNotNil(tilemap.tileAt(1, 0, inLayer: "ground"))
    }

    func testLoadNamedSearchesBundleSubdirectories() throws {
        let tilemap = try SKTilemap.load(named: "level", in: .module, subdirectory: "Fixtures/nested/maps", loggingLevel: .none)
        assertLevelIsComplete(tilemap)

        XCTAssertNoThrow(try SKTilemap.load(named: "test-tilemap.tmx", in: .module, loggingLevel: .none))
    }

    func testLoadNamedThrowsWhenMissing() {
        XCTAssertThrowsError(try SKTilemap.load(named: "does-not-exist", in: .module, loggingLevel: .none)) { error in
            guard case TiledError.resourceNotFound(let name, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(name, "does-not-exist")
        }
    }

    func testTilesetsLoadInRequestedOrderAndAreReused() throws {
        let urls = [fixture("nested/tilesets/items-collection.tsx"), fixture("nested/tilesets/environment.tsx")]
        let tilesets = try SKTileset.load(urls: urls, loggingLevel: .none)
        XCTAssertEqual(tilesets.map { $0.name }, ["items-collection", "environment"])

        let tilemap = try SKTilemap.load(url: fixture("nested/maps/level.tmx"), withTilesets: tilesets, loggingLevel: .none)
        XCTAssertTrue(tilemap.tilesets.contains(tilesets[1]), "preloaded tileset should be used by the map")
    }

    func testEachMapCachesOnlyItsOwnTiles() throws {
        let first = try load("nested/maps/level.tmx")
        let firstCount = first.dataStorage?.allTiles.count
        _ = try load("flattened/level.tmx")
        XCTAssertEqual(first.dataStorage?.allTiles.count, firstCount, "loading a second map must not add tiles to the first map's cache")
    }

    func testMapIsReleasedWhenNoLongerReferenced() throws {
        weak var released: SKTilemap?
        try autoreleasepool {
            let tilemap = try load("nested/maps/level.tmx")
            released = tilemap
            XCTAssertNotNil(released)
        }
        XCTAssertNil(released, "layers and tilesets must not keep their map alive")
    }

    func testDebugDrawingOnALoadedMap() throws {
        let tilemap = try load("nested/maps/level.tmx")
        tilemap.debugDrawOptions = [.drawGrid, .drawBounds]
        tilemap.showObjects = true
        XCTAssertTrue(tilemap.debugDrawOptions.contains(.drawGrid))
    }

    // MARK: - Errors

    func testMissingImageThrows() {
        XCTAssertThrowsError(try load("errors/missing-image.tmx")) { error in
            guard case TiledError.imageNotFound(let source, let referencedBy) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(source, "does-not-exist.png")
            XCTAssertEqual(referencedBy.lastPathComponent, "missing-image.tsx")
        }
    }

    func testMissingTilesetThrows() {
        XCTAssertThrowsError(try load("errors/missing-tileset.tmx")) { error in
            guard case TiledError.fileNotFound(let url, let referencedBy) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(url.lastPathComponent, "does-not-exist.tsx")
            XCTAssertEqual(referencedBy?.lastPathComponent, "missing-tileset.tmx")
        }
    }

    func testMalformedXMLThrows() {
        XCTAssertThrowsError(try load("errors/malformed.tmx")) { error in
            guard case TiledError.invalidXML(let url, let line, _, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(url.lastPathComponent, "malformed.tmx")
            XCTAssertGreaterThan(line, 0)
        }
    }

    func testUnsupportedFeaturesThrow() {
        for path in ["errors/infinite.tmx", "errors/zstd.tmx"] {
            XCTAssertThrowsError(try load(path), path) { error in
                guard case TiledError.unsupportedFeature = error else {
                    return XCTFail("\(path): unexpected error: \(error)")
                }
            }
        }
    }

    func testMissingFileThrows() {
        XCTAssertThrowsError(try load("does-not-exist.tmx")) { error in
            guard case TiledError.fileNotFound(_, nil) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testErrorsDescribeTheFile() {
        let error = TiledError.imageNotFound(source: "tiles.png", referencedBy: URL(fileURLWithPath: "/maps/level.tsx"))
        XCTAssertEqual(error.localizedDescription, "image \"tiles.png\" (referenced by \"level.tsx\") was not found.")
    }
}
