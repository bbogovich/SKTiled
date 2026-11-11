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


/// Level 1 of Lode Runner: arrow keys and space (dig) on a keyboard, on-screen controls on iOS, the remote on tvOS.
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

    /// Created once, when the view first appears: building the scene loads the level, textures and sounds.
    @State private var scene: LodeRunnerScene?
    @State private var held: Set<KeyEquivalent> = []
    @State private var isVisible = false
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase

    #if os(tvOS)
    /// Releases the direction a remote move command started.
    @State private var moveRelease: Task<Void, Never>?
    #endif

    /// The game runs only while its tab is shown and the app is active.
    private var isActive: Bool { isVisible && scenePhase == .active }

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene, isPaused: !isActive)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            isVisible = true
            focused = true
        }
        .onDisappear { isVisible = false }
        .onChange(of: isActive) { _, active in
            if !active { releaseAll() }
            scene?.setSuspended(!active)
        }
        .onChange(of: focused) { _, isFocused in
            // a key released while the view is not focused never reaches it
            if !isFocused { releaseAll() }
        }
        .task {
            let scene = self.scene ?? LodeRunnerScene(size: LodeRunnerScene.canvasSize)
            self.scene = scene
            #if DEBUG
            await scene.runScriptIfRequested()
            #endif
        }
        .onKeyPress(phases: .all) { press in
            handle(press)
        }
        #if os(tvOS)
        .onMoveCommand { direction in
            move(direction)
        }
        .onPlayPauseCommand {
            scene?.requestDig()
        }
        #endif
        .overlay(alignment: .top) {
            if let message = scene?.status.message {
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
            #if os(iOS)
            TouchControls(press: press, release: release, dig: { scene?.requestDig() })
                .padding(24)
            #else
            Text(Self.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            #endif
        }
    }

    #if os(tvOS)
    private static let hint = "Click or swipe to move · play/pause digs toward the way you face"
    #else
    private static let hint = "← → ↑ ↓ move · space digs toward the way you face"
    #endif

    /// Arrow keys are held (the runner moves while a key is down); space triggers one dig.
    private func handle(_ keyPress: KeyPress) -> KeyPress.Result {
        let arrows: Set<KeyEquivalent> = [.leftArrow, .rightArrow, .upArrow, .downArrow]
        if arrows.contains(keyPress.key) {
            switch keyPress.phase {
                case .down:
                    press(keyPress.key)
                case .up:
                    release(keyPress.key)
                default:
                    break
            }
            return .handled
        }
        if keyPress.key == .space {
            if keyPress.phase == .down {
                scene?.requestDig()
            }
            return .handled
        }
        return .ignored
    }

    private func press(_ key: KeyEquivalent) {
        held.insert(key)
        scene?.movementKeyPressed()
        applyHeld()
    }

    private func release(_ key: KeyEquivalent) {
        held.remove(key)
        applyHeld()
    }

    /// Lets go of every direction, e.g. when focus moves away and key-up events would be missed.
    private func releaseAll() {
        #if os(tvOS)
        moveRelease?.cancel()
        #endif
        held.removeAll()
        applyHeld()
    }

    private func applyHeld() {
        var input = LRInput()
        input.left = held.contains(.leftArrow)
        input.right = held.contains(.rightArrow)
        input.up = held.contains(.upArrow)
        input.down = held.contains(.downArrow)
        scene?.input = input
    }

    #if os(tvOS)
    /// A remote move command has no release, so it holds its direction for about one cell's worth of ticks.
    private func move(_ direction: MoveCommandDirection) {
        let key: KeyEquivalent
        switch direction {
            case .left: key = .leftArrow
            case .right: key = .rightArrow
            case .up: key = .upArrow
            case .down: key = .downArrow
            @unknown default: return
        }
        moveRelease?.cancel()
        held.removeAll()
        press(key)
        moveRelease = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            release(key)
        }
    }
    #endif
}


#if os(iOS)
/// On-screen controls: a direction pad held to move, and a dig button.
private struct TouchControls: View {

    let press: (KeyEquivalent) -> Void
    let release: (KeyEquivalent) -> Void
    let dig: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(spacing: 4) {
                pad(.upArrow, "arrowtriangle.up.fill", "Up")
                HStack(spacing: 52) {
                    pad(.leftArrow, "arrowtriangle.left.fill", "Left")
                    pad(.rightArrow, "arrowtriangle.right.fill", "Right")
                }
                pad(.downArrow, "arrowtriangle.down.fill", "Down")
            }
            Spacer()
            Button(action: dig) {
                Text("DIG")
                    .font(.headline.monospaced())
                    .frame(width: 72, height: 72)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    private func pad(_ key: KeyEquivalent, _ systemImage: String, _ label: String) -> some View {
        HoldButton(systemImage: systemImage, label: label, onPress: { press(key) }, onRelease: { release(key) })
    }
}


/// A button that reports when a touch goes down and when it lifts (or is cancelled).
private struct HoldButton: View {

    let systemImage: String
    let label: String
    let onPress: () -> Void
    let onRelease: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(.white.opacity(isPressed ? 0.35 : 0.15), in: Circle())
            .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, pressed, _ in pressed = true })
            .onChange(of: isPressed) { _, pressed in
                pressed ? onPress() : onRelease()
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}
#endif
