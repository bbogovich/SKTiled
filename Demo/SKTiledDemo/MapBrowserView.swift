//
//  MapBrowserView.swift
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

import SwiftUI
import SpriteKit
import UniformTypeIdentifiers


/// The first demo: browse maps and inspect them. Shows loading and rendering with SKTiled.
struct MapBrowserView: View {

    @Bindable var model: DemoModel

    var body: some View {
        NavigationSplitView {
            MapList(model: model)
        } detail: {
            MapDetail(model: model)
        }
        #if DEBUG
        .task { await model.writeSnapshotsIfRequested() }
        #endif
        #if !os(tvOS)
        .fileImporter(isPresented: $model.isImportingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result {
                model.openFolder(folder)
            }
        }
        #endif
        .alert(model.notice?.title ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.notice?.message ?? "")
        }
    }
}


/// Sidebar: bundled maps, and maps from a folder the user opened.
private struct MapList: View {

    @Bindable var model: DemoModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Demo Maps") {
                ForEach(model.bundledMaps) { entry in
                    Text(entry.name).tag(entry.id)
                }
            }
            if let folderName = model.folderName {
                Section(folderName) {
                    ForEach(model.folderMaps) { entry in
                        Text(entry.name).tag(entry.id)
                    }
                }
            }
        }
        .navigationTitle("SKTiled")
        #if os(macOS)
        .contextMenu(forSelectionType: MapEntry.ID.self) { ids in
            if let id = ids.first {
                Button("Open in Tiled", systemImage: "arrow.up.forward.app") {
                    model.openInTiled(id)
                }
            }
        }
        #endif
        #if !os(tvOS)
        .toolbar {
            ToolbarItem {
                Button("Open Folder…", systemImage: "folder") {
                    model.isImportingFolder = true
                }
            }
        }
        #endif
    }
}


/// Detail: the map, its debug toggles and an inspector overlay.
private struct MapDetail: View {

    @Bindable var model: DemoModel

    var body: some View {
        GeometryReader { geometry in
            SpriteView(scene: model.scene, debugOptions: [.showsFPS, .showsNodeCount, .showsDrawCount])
                #if os(macOS) || os(iOS)
                .onContinuousHover { phase in
                    switch phase {
                        case .active(let location):
                            model.hover(at: location, in: geometry.size)
                        case .ended:
                            model.hover(at: nil, in: geometry.size)
                    }
                }
                #endif
        }
        .ignoresSafeArea()
        .overlay {
            if let message = model.errorMessage {
                ContentUnavailableView("Map Failed to Load", systemImage: "exclamationmark.triangle", description: Text(message))
                    .background(.regularMaterial)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let info = model.info, model.errorMessage == nil {
                MapInspector(info: info, coordinate: model.hoveredCoordinate, tileCount: model.hoveredTileCount)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle("Grid", systemImage: "grid", isOn: $model.showGrid)
                Toggle("Bounds", systemImage: "square.dashed", isOn: $model.showBounds)
                Toggle("Objects", systemImage: "cube", isOn: $model.showObjects)
                Toggle("Pause", systemImage: "pause", isOn: $model.isPaused)
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { model.zoom(by: 0.8) }
                Button("Zoom In", systemImage: "plus.magnifyingglass") { model.zoom(by: 1.25) }
                Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { model.zoomToFit() }
            }
        }
    }
}


/// Map facts and the tile under the pointer.
private struct MapInspector: View {

    let info: MapInfo
    let coordinate: CGPoint?
    let tileCount: Int

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Orientation", info.orientation)
            row("Size", "\(Int(info.size.width)) × \(Int(info.size.height)) tiles")
            row("Tile size", "\(Int(info.tileSize.width)) × \(Int(info.tileSize.height)) px")
            row("Contents", "\(info.layers) layers, \(info.tilesets) tilesets, \(info.tiles) tiles, \(info.objects) objects")
            row("Load time", String(format: "%.0f ms", info.loadTime * 1000))
            if let coordinate = coordinate {
                row("Pointer", "\(Int(coordinate.x)), \(Int(coordinate.y)) · \(tileCount) tiles")
            }
        }
        .font(.caption.monospacedDigit())
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
