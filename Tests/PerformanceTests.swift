//
//  PerformanceTests.swift
//  SKTiledTests
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

import XCTest
@testable import SKTiled


/// Load times for a small map (dungeon-16x16: 22 × 21 tiles, three tilesets, CSV data) and a larger one
/// (roguelike-16x16: 42 × 42 tiles, zlib-compressed data, animated tiles), both copies of demo maps.
@MainActor
final class PerformanceTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        TiledGlobals.default.loggingLevel = .none
    }

    func testSmallMapLoadTime() throws {
        try measureLoad(of: "dungeon-16x16")
    }

    func testLargeMapLoadTime() throws {
        try measureLoad(of: "roguelike-16x16")
    }

    /// Loads the map once outside the measurement, so a missing or broken fixture fails with its real error, then
    /// measures repeated loads. Few iterations: the larger map takes seconds to load.
    private func measureLoad(of name: String) throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "tmx", subdirectory: "Fixtures/performance"),
                                "missing fixture \(name).tmx")
        let tilemap = try SKTilemap.load(url: url, loggingLevel: .none)
        XCTAssertGreaterThan(tilemap.tileCount, 0)

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(options: options) {
            XCTAssertNotNil(try? SKTilemap.load(url: url, loggingLevel: .none))
        }
    }
}
