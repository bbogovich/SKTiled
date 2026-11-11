//
//  ExtensionsRegressionTests.swift
//  SKTiledTests
//
//  Regression tests for bugs fixed in `SKTiled+Extensions.swift`.
//

import XCTest
import SpriteKit
@testable import SKTiled


@MainActor
final class ExtensionsRegressionTests: XCTestCase {

    // MARK: - Hex colors

    /// Tiled writes 8-digit colors alpha first (`#AARRGGBB`).
    func testTiledARGBHexParsing() {
        let opaque = SKColor(hexString: "#ff3271d3").integerComponents
        XCTAssertEqual([opaque.r, opaque.g, opaque.b, opaque.a], [0x32, 0x71, 0xd3, 0xff])

        let translucent = SKColor(hexString: "#80e3b447").integerComponents
        XCTAssertEqual([translucent.r, translucent.g, translucent.b, translucent.a], [0xe3, 0xb4, 0x47, 0x80])

        // without the leading `#`
        let bare = SKColor(hexString: "ff3271d3").integerComponents
        XCTAssertEqual([bare.r, bare.g, bare.b, bare.a], [0x32, 0x71, 0xd3, 0xff])
    }

    /// `hexString()` writes Tiled's format, so parsing it again yields the same color.
    func testHexStringRoundTrip() {
        XCTAssertEqual(SKColor(hexString: "#ff3271d3").hexString(), "#3271d3")
        XCTAssertEqual(SKColor(hexString: "#80e3b447").hexString(), "#80e3b447")
        XCTAssertEqual(SKColor(hexString: "#3271d3").hexString(), "#3271d3")

        for hex in ["#80e3b447", "#00000000", "#3271d3", "#01ffffff", "#fe102030"] {
            let once = SKColor(hexString: hex).hexString()
            XCTAssertEqual(SKColor(hexString: once).hexString(), once, "round trip of '\(hex)'")
        }

        let color = SKColor(red: 10, green: 20, blue: 30, alpha: 64)
        XCTAssertEqual(color.hexString(), "#400a141e")
        let parsed = SKColor(hexString: color.hexString()).integerComponents
        XCTAssertEqual([parsed.r, parsed.g, parsed.b, parsed.a], [10, 20, 30, 64])
    }

    /// Invalid input produces a clear color instead of a partially scanned value.
    func testInvalidHexStringIsClear() {
        for hex in ["#12zz56", "zzzzzz", "#12345", "", "#", "+fffff", "#1234567890"] {
            let comps = SKColor(hexString: hex).integerComponents
            XCTAssertEqual([comps.r, comps.g, comps.b, comps.a], [0, 0, 0, 0], "'\(hex)' should parse as clear")
        }
    }

    /// The validity check measures the string in UTF-16 units, as `NSRegularExpression` does.
    func testIsValidHexColorWithNonASCII() {
        XCTAssertTrue("#ff3271d3".isValidHexColor)
        XCTAssertFalse("#ff3271d3é".isValidHexColor)
        XCTAssertFalse("👍ff3271".isValidHexColor)
    }

    /// Integer components are rounded, not truncated.
    func testIntegerComponentsRound() {
        let color = SKColor(red: 0.999, green: 0.5, blue: 0.0, alpha: 1)
        let comps = color.integerComponents
        XCTAssertEqual(comps.r, 255)
        XCTAssertEqual(comps.g, 128)
    }

    // MARK: - Tile flags

    func testFlippedTileFlagsMasksAllFlagBits() {
        let gid: UInt32 = 42

        let plain = flippedTileFlags(id: gid)
        XCTAssertEqual(plain.gid, gid)
        XCTAssertFalse(plain.hflip || plain.vflip || plain.dflip)

        let flipped = flippedTileFlags(id: gid | 0x80000000 | 0x40000000 | 0x20000000)
        XCTAssertEqual(flipped.gid, gid)
        XCTAssertTrue(flipped.hflip && flipped.vflip && flipped.dflip)

        // hexagonal 120° rotation bit
        let rotated = flippedTileFlags(id: gid | 0x10000000)
        XCTAssertEqual(rotated.gid, gid)
        XCTAssertFalse(rotated.hflip || rotated.vflip || rotated.dflip)

        let all = flippedTileFlags(id: gid | 0xF0000000)
        XCTAssertEqual(all.gid, gid)
        XCTAssertTrue(all.hflip && all.vflip && all.dflip)
    }

    // MARK: - Geometry

    /// Positions snap to device pixels, not whole points, and negatives round correctly.
    func testClampedPositionAtScale2() {
        XCTAssertEqual(clampedPosition(point: CGPoint(x: 10.3, y: 10.7), scale: 2), CGPoint(x: 10.5, y: 10.5))
        XCTAssertEqual(clampedPosition(point: CGPoint(x: 10.2, y: 10.8), scale: 2), CGPoint(x: 10.0, y: 11.0))
        XCTAssertEqual(clampedPosition(point: CGPoint(x: -10.3, y: -10.7), scale: 2), CGPoint(x: -10.5, y: -10.5))
        XCTAssertEqual(clampedPosition(point: CGPoint(x: -0.2, y: -0.3), scale: 2), CGPoint(x: 0, y: -0.5))
        XCTAssertEqual(clampedPosition(point: CGPoint(x: 3.4, y: -3.6), scale: 1), CGPoint(x: 3, y: -4))
    }

    func testPolygonPathWithNoPoints() {
        XCTAssertTrue(polygonPath([]).isEmpty)
        XCTAssertTrue(polygonPath([], closed: false).isEmpty)

        let triangle = polygonPath([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10)])
        XCTAssertEqual(triangle.boundingBox, CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    // MARK: - Integers

    func testDigitCount() {
        XCTAssertEqual(0.digitCount, 1)
        XCTAssertEqual(9.digitCount, 1)
        XCTAssertEqual(10.digitCount, 2)
        XCTAssertEqual((-12345).digitCount, 5)
        XCTAssertEqual(Int.max.digitCount, 19)
        XCTAssertEqual(Int.min.digitCount, 19)
    }

    // MARK: - Actions

    /// `speed(to:duration:)` passes a nil key; it used to crash through an IUO `String!`.
    func testSpeedToDurationDoesNotCrash() {
        let node = SKNode()
        node.speed(to: 0.5, duration: 0.1)
        XCTAssertTrue(node.hasActions())

        let other = SKNode()
        other.speed(to: 2, duration: 0.1) { }
        XCTAssertTrue(other.hasActions())

        let keyed = SKNode()
        keyed.run(SKAction.wait(forDuration: 1), withKey: "KEY", completion: { })
        XCTAssertNotNil(keyed.action(forKey: "KEY"))
    }

    // MARK: - Files

    func testIsDirectory() {
        let tempDir = FileManager.default.temporaryDirectory
        XCTAssertTrue(tempDir.isDirectory)
        XCTAssertTrue(tempDir.path.isDirectory)

        let file = tempDir.appendingPathComponent("sktiled-isdir-\(UUID().uuidString).txt")
        XCTAssertNoThrow(try Data("x".utf8).write(to: file))
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(file.isDirectory)
        XCTAssertFalse(file.path.isDirectory)
    }

    // MARK: - Version

    func testFrameworkVersionIsLibraryVersion() {
        XCTAssertEqual(getSKTiledVersion(), "2.0.0")
        let version = TiledGlobals.default.version
        XCTAssertEqual(version.major, 2)
        XCTAssertEqual(version.minor, 0)
    }
}
