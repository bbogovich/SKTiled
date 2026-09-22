//
//  LodeRunnerView.swift
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


/// Level 1 of Lode Runner: arrow keys to move, space to dig.
struct LodeRunnerView: View {

    var body: some View {
        if LodeRunnerScene.assetsInstalled {
            LodeRunnerGameView()
        } else {
            ContentUnavailableView {
                Label("Lode Runner Assets Not Installed", systemImage: "gamecontroller")
            } description: {
                Text("The game's graphics, sounds and level are extracted from the original disk and are not part of the repository. Run scripts/import-lode-runner-assets.sh with the path to a Retro2Arcade checkout, then rebuild the demo.")
            }
        }
    }
}


private struct LodeRunnerGameView: View {

    @State private var scene = LodeRunnerScene(size: LodeRunnerScene.canvasSize)
    @State private var held: Set<KeyEquivalent> = []
    @FocusState private var focused: Bool

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            #if DEBUG
            .task { await scene.runScriptIfRequested() }
            #endif
            .onKeyPress(phases: .all) { press in
                handle(press)
            }
            .overlay(alignment: .top) {
                if let message = scene.status.message {
                    Text(message)
                        .font(.headline.monospaced())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.top, 24)
                }
            }
            .overlay(alignment: .bottom) {
                Text("← → ↑ ↓ move · space digs toward the way you face")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
    }

    /// Arrow keys are held (the runner moves while a key is down); space triggers one dig.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let arrows: Set<KeyEquivalent> = [.leftArrow, .rightArrow, .upArrow, .downArrow]
        if arrows.contains(press.key) {
            switch press.phase {
                case .down:
                    held.insert(press.key)
                    scene.movementKeyPressed()
                case .up:
                    held.remove(press.key)
                default:
                    break
            }
            var input = LRInput()
            input.left = held.contains(.leftArrow)
            input.right = held.contains(.rightArrow)
            input.up = held.contains(.upArrow)
            input.down = held.contains(.downArrow)
            scene.input = input
            return .handled
        }
        if press.key == .space {
            if press.phase == .down {
                scene.requestDig()
            }
            return .handled
        }
        return .ignored
    }
}
