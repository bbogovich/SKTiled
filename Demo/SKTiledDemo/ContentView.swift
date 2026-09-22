//
//  ContentView.swift
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


/// The demo's two examples, in order of complexity: rendering maps, then a playable game built on a map.
struct ContentView: View {

    @Bindable var model: DemoModel

    /// The selected example. Debug builds can start on the game with `SKTILED_DEMO_TAB=lodeRunner`.
    @State private var selection = ProcessInfo.processInfo.environment["SKTILED_DEMO_TAB"] ?? "maps"

    var body: some View {
        TabView(selection: $selection) {
            MapBrowserView(model: model)
                .tabItem { Label("Maps", systemImage: "map") }
                .tag("maps")

            LodeRunnerView()
                .tabItem { Label("Lode Runner", systemImage: "gamecontroller") }
                .tag("lodeRunner")
        }
    }
}
