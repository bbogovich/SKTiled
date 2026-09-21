//
//  DemoModel.swift
//  SKTiledDemo
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
import ImageIO
import Observation
import SpriteKit
import SKTiled


/// A map the demo can open.
struct MapEntry: Identifiable, Hashable {

    /// TMX file.
    let url: URL

    /// Bundle for file-name and asset catalog fallbacks; `nil` for maps opened from disk.
    let bundle: Bundle?

    var id: URL { url }

    var name: String { url.deletingPathExtension().lastPathComponent }
}


/// Facts about the loaded map, shown in the inspector.
struct MapInfo {
    let orientation: String
    let size: CGSize
    let tileSize: CGSize
    let layers: Int
    let tilesets: Int
    let tiles: Int
    let objects: Int
    let loadTime: TimeInterval
}


/// State for the demo: the map list, the scene, the loaded map and the debug toggles.
@Observable
final class DemoModel {

    /// Scene shown by the `SpriteView`; it resizes with the view.
    let scene: SKTiledScene = {
        let scene = SKTiledScene(size: CGSize(width: 1024, height: 768))
        scene.scaleMode = .resizeFill
        return scene
    }()

    /// Maps shipped in the app bundle's `Maps` folder.
    private(set) var bundledMaps: [MapEntry] = []

    /// Maps found in the folder the user opened.
    private(set) var folderMaps: [MapEntry] = []

    /// Name of the folder the user opened.
    private(set) var folderName: String?

    /// Selected map.
    var selection: MapEntry.ID? {
        didSet {
            guard selection != oldValue else { return }
            loadSelection()
        }
    }

    /// Facts about the loaded map.
    private(set) var info: MapInfo?

    /// Description of the last load failure.
    private(set) var errorMessage: String?

    /// Tile coordinate under the pointer, if it is over the map.
    private(set) var hoveredCoordinate: CGPoint?

    /// Number of tiles stacked at the hovered coordinate.
    private(set) var hoveredTileCount = 0

    /// Presents the folder importer.
    var isImportingFolder = false

    var showGrid = false {
        didSet { applyDebugOptions() }
    }

    var showBounds = false {
        didSet { applyDebugOptions() }
    }

    var showObjects = false {
        didSet { scene.tilemap?.showObjects = showObjects }
    }

    var isPaused = false {
        didSet { scene.tilemap?.isPaused = isPaused }
    }

    /// Folder whose security-scoped access is held while its maps are listed.
    private var accessedFolder: URL?

    init() {
        if let maps = Bundle.main.resourceURL?.appendingPathComponent("Maps") {
            bundledMaps = Self.findMaps(in: maps, bundle: .main)
        }
        selection = bundledMaps.first?.id
        loadSelection()
    }

    // MARK: - Maps

    /// Every map, bundled and opened from disk.
    var allMaps: [MapEntry] {
        return bundledMaps + folderMaps
    }

    /// Lists the TMX files under a directory, sorted by name.
    private static func findMaps(in directory: URL, bundle: Bundle?) -> [MapEntry] {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "tmx" } ?? []
        return files
            .map { MapEntry(url: $0, bundle: bundle) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Lists the maps in a folder the user picked. Tilesets and images may be anywhere inside it.
    func openFolder(_ folder: URL) {
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = folder.startAccessingSecurityScopedResource() ? folder : nil

        folderName = folder.lastPathComponent
        folderMaps = Self.findMaps(in: folder, bundle: nil)
        if let first = folderMaps.first {
            selection = first.id
        } else {
            errorMessage = "\"\(folder.lastPathComponent)\" contains no .tmx maps."
        }
    }

    /// Loads the selected map into the scene.
    private func loadSelection() {
        guard let entry = allMaps.first(where: { $0.id == selection }) else { return }

        do {
            let tilemap = try scene.setup(url: entry.url, bundle: entry.bundle, loggingLevel: .warning)
            errorMessage = nil
            info = MapInfo(orientation: tilemap.orientation.rawValue,
                           size: tilemap.size,
                           tileSize: tilemap.tileSize,
                           layers: tilemap.layerCount,
                           tilesets: tilemap.tilesets.count,
                           tiles: tilemap.tileCount,
                           objects: tilemap.objectCount,
                           loadTime: tilemap.mapRenderTime)
            tilemap.showObjects = showObjects
            tilemap.isPaused = isPaused
            applyDebugOptions()
            zoomToFit()
        } catch {
            info = nil
            errorMessage = error.localizedDescription
        }
        hoveredCoordinate = nil
    }

    // MARK: - Camera

    func zoomToFit() {
        scene.cameraNode?.fitToView(newSize: scene.size)
    }

    func zoom(by factor: CGFloat) {
        guard let camera = scene.cameraNode else { return }
        camera.setCameraZoom(camera.zoom * factor, interval: 0.15)
    }

    // MARK: - Pointer

    /// Updates the hovered tile from a pointer location in the `SpriteView`'s coordinate space.
    ///
    /// - Parameters:
    ///   - location: location with a top-left origin, as SwiftUI reports it; `nil` when the pointer leaves.
    ///   - viewSize: size of the `SpriteView`.
    func hover(at location: CGPoint?, in viewSize: CGSize) {
        guard let location = location, let tilemap = scene.tilemap, scene.view != nil else {
            hoveredCoordinate = nil
            return
        }

        #if os(macOS)
        // SKView is not flipped on macOS
        let viewPoint = CGPoint(x: location.x, y: viewSize.height - location.y)
        #else
        let viewPoint = location
        #endif

        let scenePoint = scene.convertPoint(fromView: viewPoint)
        let coord = tilemap.coordinate(at: scenePoint, in: scene)
        guard tilemap.isValid(coord: coord) else {
            hoveredCoordinate = nil
            return
        }
        hoveredCoordinate = coord
        hoveredTileCount = tilemap.tilesAt(coord: coord).count
    }

    // MARK: - Snapshots

    #if DEBUG
    /// Renders every bundled map to `<directory>/<map>.png`, then quits.
    ///
    /// Enabled by setting `SKTILED_DEMO_SNAPSHOTS` to a directory. Used to check that every map renders in the app.
    func writeSnapshotsIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["SKTILED_DEMO_SNAPSHOTS"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for entry in bundledMaps {
            selection = entry.id
            try? await Task.sleep(for: .seconds(1))
            let status = errorMessage ?? "rendered \(info?.tiles ?? 0) tiles"
            print("snapshot \(entry.name): \(status)")
            guard let view = scene.view, let texture = view.texture(from: scene) else { continue }
            Self.writePNG(texture.cgImage(), to: directory.appendingPathComponent("\(entry.name).png"))
        }
        exit(0)
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
    #endif

    // MARK: - Debug Drawing

    private func applyDebugOptions() {
        guard let tilemap = scene.tilemap else { return }
        var options = tilemap.debugDrawOptions
        options.remove([.drawGrid, .drawBounds])
        if showGrid { options.insert(.drawGrid) }
        if showBounds { options.insert(.drawBounds) }
        tilemap.debugDrawOptions = options
    }
}
