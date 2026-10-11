//
//  LodeRunnerScene.swift
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

import AVFoundation
import ImageIO
import Observation
import SpriteKit
import SKTiled


/// State the SwiftUI view shows around the game.
@Observable
final class LodeRunnerStatus {
    var message: String?
    var score = 0
    var lives = LodeRunnerScene.startingLives
}


/// Plays level 1 of Lode Runner on a map loaded with SKTiled.
///
/// The scene shows how game features map onto SKTiled and SpriteKit:
///
/// - **Level data from the map.** Terrain codes come from the `terrain` tile layer, and the runner, guard and gold
///   positions from the `objects` layer's tile objects.
/// - **Destructible bricks.** Digging replaces the brick's tile with a sequence of damaged-brick tiles, then removes
///   the tile; when the hole's timer runs out, refill tiles are shown and the brick tile is put back.
/// - **Map objects.** Gold is the map's own tile objects: collected gold is removed from the object layer, and gold a
///   guard carries is hidden and moved to where the guard drops it.
/// - **Sprites.** The runner and guards are sprites whose animation frames follow their direction of travel.
/// - **Collision detection.** Gold pickup and being caught by a guard are sprite-frame intersection tests.
/// - **Tile animations.** Hole refills, guard respawns and the escape ladders appearing are animated on specific cells.
/// - **Pixel scaling.** The 560 × 384 playfield is scaled by the largest whole number that fits the view.
/// - **Sound.** Game events play the original sound effects.
final class LodeRunnerScene: SKScene {

    static let startingLives = 5

    /// Folder with the imported assets (see `Demo/LodeRunner/README.md`).
    static var assetsURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("LodeRunner")
    }

    static var mapURL: URL? {
        assetsURL?.appendingPathComponent("maps/level_001.tmx")
    }

    /// Whether the copyrighted assets have been imported into the app.
    static var assetsInstalled: Bool {
        guard let url = mapURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: Canvas

    /// The original screen at the asset scale (2 × 2 per Apple II pixel): playfield 560 × 352, status line below.
    static let canvasSize = CGSize(width: 560, height: 384)
    static let cellSize = CGSize(width: 20, height: 22)

    /// Sub-step offsets from a cell's position, in canvas pixels (x right, y down), for sub-steps 0...4.
    static let xOffsets: [CGFloat] = [-8, -4, 0, 4, 8]
    static let yOffsets: [CGFloat] = [-10, -6, 0, 4, 8]

    // Terrain tile gids in the map: gid = map code + 1.
    static let brickGID = 2
    static let ladderGID = 4

    // Shape indices in shapes.png (see Retro2Arcade's sprites.json).
    static let digBrickShapes = [31, 31, 32, 32, 33, 33, 34, 34, 35, 35, 36, 36]
    static let digDebrisLeft = [27, 27, 28, 28, 29, 29, 30, 30, 0, 0, 0, 0]
    static let digDebrisRight = [38, 38, 39, 39, 29, 29, 30, 30, 0, 0, 0, 0]
    static let holeRefillShapes = [55, 56]
    static let respawnShapes = [57, 58]

    let status = LodeRunnerStatus()

    /// Everything scaled together: the map, the actors and the status line.
    private let canvas = SKNode()
    private let actors = SKNode()
    private let statusLine = SKNode()

    private var tilemap: SKTilemap?
    private var terrain: SKTileLayer?
    private var objects: SKObjectGroup?

    private var game: LodeRunnerGame?
    private var runnerSprite = SKSpriteNode()
    private var guardSprites: [SKSpriteNode] = []

    /// Gold objects lying on the map, by cell, and the ones guards are carrying.
    private var goldOnMap: [LRCellPosition: SKTileObject] = [:]
    private var goldCarried: [Int: (object: SKTileObject, from: LRCellPosition)] = [:]

    private var runnerFrames: [SKTexture] = []
    private var guardFrames: [SKTexture] = []
    private var shapes: [SKTexture] = []
    private var glyphs: [Character: SKTexture] = [:]
    private let sounds = LodeRunnerSounds()

    private enum Phase {
        case ready, playing, dying, complete, gameOver
    }
    private var phase = Phase.ready

    /// Held arrow keys, set by the view.
    var input = LRInput()
    private var digRequested = false

    private var lastUpdate: TimeInterval?
    private var tickTime: TimeInterval = 0
    private var bankedScore = 0
    private var lives = LodeRunnerScene.startingLives

    // MARK: - Setup

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        addChild(canvas)
        loadTextures()
        loadLevel()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutCanvas()
    }

    /// Scales the canvas by the largest whole number that fits, so every Apple II pixel is the same size.
    private func layoutCanvas() {
        let fit = min(size.width / Self.canvasSize.width, size.height / Self.canvasSize.height)
        let scale = fit >= 1 ? floor(fit) : fit
        canvas.setScale(scale)
        canvas.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func loadTextures() {
        guard let folder = Self.assetsURL?.appendingPathComponent("sprites") else { return }
        runnerFrames = Self.frames(from: folder.appendingPathComponent("runner.png"), columns: 18, rows: 1)
        guardFrames = Self.frames(from: folder.appendingPathComponent("guard.png"), columns: 16, rows: 1)
        shapes = Self.frames(from: folder.appendingPathComponent("shapes.png"), columns: 16, rows: 7)
        let fontFrames = Self.frames(from: folder.appendingPathComponent("font.png"), columns: 43, rows: 1)
        for (index, character) in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ>.()/-<".enumerated() where index < fontFrames.count {
            glyphs[character] = fontFrames[index]
        }
    }

    /// Cuts a sprite sheet of 20 × 22 frames into textures, left to right and top to bottom.
    private static func frames(from url: URL, columns: Int, rows: Int) -> [SKTexture] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let sheet = SKTexture(cgImage: image)
        sheet.filteringMode = .nearest
        let width = CGFloat(image.width), height = CGFloat(image.height)
        var textures: [SKTexture] = []
        for row in 0..<rows {
            for column in 0..<columns {
                // texture coordinates start at the bottom left
                let rect = CGRect(x: CGFloat(column) * cellSize.width / width,
                                  y: 1 - CGFloat(row + 1) * cellSize.height / height,
                                  width: cellSize.width / width,
                                  height: cellSize.height / height)
                let texture = SKTexture(rect: rect, in: sheet)
                texture.filteringMode = .nearest
                textures.append(texture)
            }
        }
        return textures
    }

    /// Loads (or reloads) level 1 from the map and builds the sprites.
    private func loadLevel() {
        tilemap?.removeFromParent()
        actors.removeAllChildren()
        actors.removeFromParent()
        statusLine.removeFromParent()
        goldOnMap = [:]
        goldCarried = [:]

        guard let url = Self.mapURL,
              let tilemap = try? SKTilemap.load(url: url, loggingLevel: .warning),
              let terrain = tilemap.tileLayers(named: "terrain").first,
              let objects = tilemap.objectGroups(named: "objects").first else {
            status.message = "The Lode Runner map could not be loaded."
            return
        }

        // the playfield is the top 352 pixels of the canvas; the map's contents are centered on its node
        tilemap.position = CGPoint(x: 0, y: (Self.canvasSize.height - tilemap.sizeInPoints.height) / 2)
        canvas.addChild(tilemap)
        self.tilemap = tilemap
        self.terrain = terrain
        self.objects = objects

        // actors draw above every map layer
        actors.zPosition = tilemap.lastZPosition + tilemap.zDeltaForLayers
        tilemap.addChild(actors)

        let level = readLevel(tilemap: tilemap, terrain: terrain, objects: objects)
        let game = LodeRunnerGame(level: level)
        self.game = game

        runnerSprite = SKSpriteNode(texture: runnerFrames.first)
        actors.addChild(runnerSprite)
        guardSprites = game.guards.map { _ in
            let sprite = SKSpriteNode(texture: guardFrames.first)
            actors.addChild(sprite)
            return sprite
        }
        syncSprites()

        buildStatusLine()
        canvas.addChild(statusLine)
        layoutCanvas()

        // wait for the player, with the runner blinking, as the original does
        phase = .ready
        status.message = "\(Self.movePrompt) to start"
        runnerSprite.run(.repeatForever(.sequence([.fadeOut(withDuration: 0.25), .fadeIn(withDuration: 0.25)])), withKey: "blink")
    }

    /// Builds the rules' view of the level from the map: terrain codes from the tile layer, spawns and gold from the
    /// object layer.
    private func readLevel(tilemap: SKTilemap, terrain: SKTileLayer, objects: SKObjectGroup) -> LRLevel {
        let columns = Int(tilemap.size.width), rows = Int(tilemap.size.height)
        var cells = Array(repeating: Array(repeating: LRCell.empty, count: columns), count: rows)
        for row in 0..<rows {
            for col in 0..<columns {
                // the tileset's local tile id is the map code
                if let code = terrain.tileAt(col, row)?.tileData.id, let cell = LRCell(rawValue: code) {
                    cells[row][col] = cell
                }
            }
        }

        var hidden: [LRCellPosition] = []
        if let ladders = tilemap.tileLayers(named: "escape_ladders").first {
            for row in 0..<rows {
                for col in 0..<columns where ladders.tileAt(col, row) != nil {
                    hidden.append(LRCellPosition(col: col, row: row))
                }
            }
        }

        var gold: [LRCellPosition] = []
        var guards: [LRCellPosition] = []
        var runner = LRCellPosition(col: 0, row: 0)
        for object in objects.getObjects() {
            guard let col = object.intForKey("col"), let row = object.intForKey("row") else { continue }
            let cell = LRCellPosition(col: col, row: row)
            switch object.type {
                case "gold":
                    gold.append(cell)
                    goldOnMap[cell] = object
                case "guard":
                    guards.append(cell)
                    object.isHidden = true      // guards are our sprites
                case "player":
                    runner = cell
                    object.isHidden = true      // so is the runner
                default:
                    break
            }
        }
        return LRLevel(terrain: cells, hiddenLadders: hidden, gold: gold, runner: runner, guards: guards)
    }

    // MARK: - Input

    #if os(macOS)
    private static let movePrompt = "Press an arrow key"
    #else
    private static let movePrompt = "Move"
    #endif

    /// Starts a dig on the next tick, toward the way the runner faces.
    func requestDig() {
        digRequested = true
        startIfReady()
    }

    /// Called when a movement key is pressed.
    func movementKeyPressed() {
        startIfReady()
    }

    private func startIfReady() {
        switch phase {
            case .ready:
                phase = .playing
                status.message = nil
                runnerSprite.removeAction(forKey: "blink")
                runnerSprite.alpha = 1
            case .gameOver:
                bankedScore = 0
                lives = Self.startingLives
                updateStatus()
                loadLevel()
            default:
                break
        }
    }

    // MARK: - Game Loop

    /// Pauses the game, silences it and drops held input (`true`), or carries on (`false`). Called when the game's
    /// view disappears or the app leaves the foreground.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isPaused else { return }
        isPaused = suspended
        input = LRInput()
        digRequested = false
        if suspended {
            sounds.stopAll()
        } else if phase == .playing, game?.isRunnerFalling == true {
            // the fall sound loops for as long as the runner falls
            sounds.play("fall", loops: true)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard let lastUpdate, !isPaused else { return }
        tilemap?.update(currentTime)

        // run the rules at the original's fixed tick rate
        tickTime += min(currentTime - lastUpdate, 0.25)
        let period = 1 / LodeRunnerGame.ticksPerSecond
        while tickTime >= period {
            tickTime -= period
            if phase == .playing {
                step()
            }
        }
    }

    private func step() {
        guard var game else { return }
        var commands = input
        commands.dig = digRequested
        digRequested = false

        let before = game.runner
        var events = game.tick(commands)
        self.game = game
        syncSprites()

        // collision tests on the drawn sprites
        let runnerMoved = before.col != game.runner.col || before.row != game.runner.row
            || before.xsub != game.runner.xsub || before.ysub != game.runner.ysub
        let tookGold = collectTouchedGold(&events)
        if runnerMoved, !tookGold, runnerTouchesGuard() {
            events += self.game?.runnerCaught() ?? []
        }

        for event in events {
            present(event)
        }
        updateStatus()
    }

    // MARK: - Collision Detection

    /// A sprite's frame in the actors node's coordinates, shrunk by an inset.
    private func hitBox(of node: SKNode, inset: CGSize) -> CGRect {
        guard let parent = node.parent else { return .null }
        let frame = node.calculateAccumulatedFrame()
        let lower = actors.convert(CGPoint(x: frame.minX, y: frame.minY), from: parent)
        let upper = actors.convert(CGPoint(x: frame.maxX, y: frame.maxY), from: parent)
        return CGRect(x: lower.x, y: lower.y, width: upper.x - lower.x, height: upper.y - lower.y)
            .insetBy(dx: inset.width, dy: inset.height)
    }

    /// Takes any gold object the runner's sprite overlaps. Returns true if gold was taken.
    private func collectTouchedGold(_ events: inout [LREvent]) -> Bool {
        // the inner part of each sprite, so gold is taken near the cell's centre, as in the original
        let runnerBox = hitBox(of: runnerSprite, inset: CGSize(width: 6, height: 7))
        for (cell, gold) in goldOnMap where !gold.isHidden {
            guard runnerBox.intersects(hitBox(of: gold, inset: CGSize(width: 6, height: 7))) else { continue }
            // an overlapped object whose cell holds no gold in the rules (yet) does not end the search
            let taken = game?.collectGold(at: cell) ?? []
            if !taken.isEmpty {
                events += taken
                return true
            }
        }
        return false
    }

    private func runnerTouchesGuard() -> Bool {
        let runnerBox = hitBox(of: runnerSprite, inset: CGSize(width: 4, height: 3))
        for (index, sprite) in guardSprites.enumerated() where !sprite.isHidden {
            guard game?.guards[index].respawn == 0 else { continue }
            if runnerBox.intersects(hitBox(of: sprite, inset: CGSize(width: 4, height: 3))) {
                return true
            }
        }
        return false
    }

    // MARK: - Presentation

    /// The centre of an actor's sprite in the actors node's coordinates.
    private func position(of actor: LRActor) -> CGPoint {
        position(of: actor.cell, xsub: actor.xsub, ysub: actor.ysub)
    }

    private func position(of cell: LRCellPosition, xsub: Int = 2, ysub: Int = 2) -> CGPoint {
        guard let terrain, let tilemap else { return .zero }
        let center = tilemap.convert(terrain.pointForCoordinate(coord: CGPoint(x: cell.col, y: cell.row)), from: terrain)
        // Tiled's y axis points down, SpriteKit's up
        return CGPoint(x: center.x + Self.xOffsets[xsub], y: center.y - Self.yOffsets[ysub])
    }

    /// Places the sprites and picks each one's animation frame from the rules' state.
    private func syncSprites() {
        guard let game else { return }
        runnerSprite.position = position(of: game.runner)
        if runnerFrames.indices.contains(game.runner.frame) {
            runnerSprite.texture = runnerFrames[game.runner.frame]
        }
        for (index, guardian) in game.guards.enumerated() where index < guardSprites.count {
            let sprite = guardSprites[index]
            sprite.isHidden = guardian.respawn > 0
            sprite.position = position(of: guardian.actor)
            if guardFrames.indices.contains(guardian.actor.frame) {
                sprite.texture = guardFrames[guardian.actor.frame]
            }
        }
    }

    private func shape(_ index: Int) -> SKTexture? {
        shapes.indices.contains(index) ? shapes[index] : nil
    }

    /// Shows a shape in a terrain cell by replacing that cell's tile (or removes the tile for shape 0).
    private func setCell(_ cell: LRCellPosition, shape index: Int) {
        guard let terrain else { return }
        if index == 0 {
            _ = terrain.removeTileAt(cell.col, cell.row)
        } else {
            _ = terrain.addTileAt(cell.col, cell.row, texture: shape(index))
        }
    }

    private func present(_ event: LREvent) {
        #if DEBUG
        if scriptDirectory != nil { print("event:", event) }
        #endif
        guard let terrain else { return }
        switch event {
            case .runnerFell:
                sounds.play("fall", loops: true)

            case .runnerLanded:
                sounds.stop("fall")
                sounds.play("land")

            case .digStarted:
                sounds.play("dig")

            case let .digStep(brick, debris, step):
                // the brick crumbles in stages, and debris flies up beside the runner
                setCell(brick, shape: Self.digBrickShapes[step])
                let debrisShapes = (debris.col < (game?.runner.col ?? 0)) ? Self.digDebrisLeft : Self.digDebrisRight
                setCell(debris, shape: debrisShapes[step])

            case let .digAborted(brick, debris):
                sounds.stop("dig")
                _ = terrain.addTileAt(brick.col, brick.row, gid: Self.brickGID)
                setCell(debris, shape: 0)

            case let .holeOpened(cell):
                // the brick's tile is removed entirely: the cell is now a hole
                setCell(cell, shape: 0)

            case let .holeRefill(cell, stage):
                setCell(cell, shape: Self.holeRefillShapes[stage - 1])

            case let .holeClosed(cell):
                _ = terrain.addTileAt(cell.col, cell.row, gid: Self.brickGID)

            case let .goldTaken(cell):
                sounds.play("gold_pickup")
                // collected gold leaves the map's object layer
                if let gold = goldOnMap.removeValue(forKey: cell) {
                    _ = objects?.removeObject(gold)
                    gold.removeFromParent()
                }

            case let .guardTookGold(index, cell):
                if let gold = goldOnMap.removeValue(forKey: cell) {
                    gold.isHidden = true
                    goldCarried[index] = (gold, cell)
                }

            case let .guardDroppedGold(index, cell):
                if let (gold, from) = goldCarried.removeValue(forKey: index) {
                    // move the same map object to where the guard dropped it
                    gold.position.x += CGFloat(cell.col - from.col) * Self.cellSize.width
                    gold.position.y -= CGFloat(cell.row - from.row) * Self.cellSize.height
                    gold.isHidden = false
                    goldOnMap[cell] = gold
                }

            case let .guardLostGold(index):
                if let (gold, _) = goldCarried.removeValue(forKey: index) {
                    _ = objects?.removeObject(gold)
                    gold.removeFromParent()
                }

            case let .guardTrapped(index, _):
                sounds.play("guard_trapped")
                // a trapped guard flashes briefly
                guardSprites[index].run(.sequence([.fadeAlpha(to: 0.3, duration: 0.08), .fadeAlpha(to: 1, duration: 0.08)]))

            case .guardKilled:
                break

            case let .guardRespawning(_, cell, stage):
                // the guard materialises on its respawn cell in two stages
                setCell(cell, shape: Self.respawnShapes[stage - 1])

            case let .guardRespawned(index):
                sounds.play("guard_respawn")
                if let cell = game?.guards[index].actor.cell {
                    setCell(cell, shape: 0)
                }

            case let .laddersRevealed(cells):
                // the escape ladders appear, each tile fading in
                for cell in cells {
                    let tile = terrain.addTileAt(cell.col, cell.row, gid: Self.ladderGID)
                    tile?.alpha = 0
                    tile?.run(.fadeIn(withDuration: 0.4))
                }

            case .runnerDied:
                runnerDied()

            case .levelComplete:
                levelComplete()
        }
    }

    // MARK: - Death and Completion

    private func runnerDied() {
        phase = .dying
        sounds.stopAll()
        sounds.play("death")
        runnerSprite.run(.sequence([
            .repeat(.sequence([.fadeOut(withDuration: 0.1), .fadeIn(withDuration: 0.1)]), count: 5),
            .run { [weak self] in self?.afterDeath() }
        ]))
    }

    private func afterDeath() {
        bankedScore += game?.score ?? 0
        lives -= 1
        if lives <= 0 {
            phase = .gameOver
            status.message = "Game over. \(Self.movePrompt) to play again"
        } else {
            loadLevel()
        }
        updateStatus()
    }

    private func levelComplete() {
        phase = .complete
        sounds.stopAll()
        sounds.play("level_complete")
        status.message = "Level complete!"
        run(.sequence([.wait(forDuration: 2.5), .run { [weak self] in self?.afterLevelComplete() }]))
    }

    private func afterLevelComplete() {
        // this demo has one level: play it again with the extra life
        bankedScore += game?.score ?? 0
        lives = min(lives + 1, 255)
        loadLevel()
        updateStatus()
    }

    // MARK: - Scripted Run

    #if DEBUG
    /// With `SKTILED_LR_SCRIPT=<directory>`, plays a scripted sequence, logs events, saves snapshots and quits.
    private var scriptDirectory: URL? {
        ProcessInfo.processInfo.environment["SKTILED_LR_SCRIPT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Plays a scripted sequence by running game ticks directly (independent of the display), logging events and
    /// saving snapshots, then quits.
    func runScriptIfRequested() async {
        guard let directory = scriptDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func ticks(_ count: Int, _ keys: LRInput = LRInput()) {
            input = keys
            for _ in 0..<count where phase == .playing { step() }
        }
        func snapshot(_ name: String) {
            print("snapshot \(name): runner \(game.map { "\($0.runner.cell) sub \($0.runner.xsub),\($0.runner.ysub) frame \($0.runner.frame)" } ?? "-") guards \(game?.guards.map { "\($0.actor.cell)/\($0.state)" } ?? []) score \(totalScore) gold left \(game?.goldRemaining ?? -1) lives \(lives) holes \(game?.holes.count ?? 0)")
            guard let view, let texture = view.texture(from: self) else { return }
            let url = directory.appendingPathComponent("\(name).png")
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, texture.cgImage(), nil)
                CGImageDestinationFinalize(destination)
            }
        }
        var right = LRInput(); right.right = true
        var left = LRInput(); left.left = true

        try? await Task.sleep(for: .seconds(1))
        snapshot("0-start")
        movementKeyPressed()
        ticks(8, right); snapshot("1-running-right")
        ticks(8, right); snapshot("2-after-gold")
        requestDig(); ticks(6); snapshot("3-digging")
        ticks(8); snapshot("4-hole-open")
        ticks(60, left); snapshot("5-later")
        ticks(120); snapshot("6-end")
        exit(0)
    }
    #endif

    // MARK: - Status Line

    private var totalScore: Int { bankedScore + (game?.score ?? 0) }

    private func updateStatus() {
        status.score = totalScore
        status.lives = lives
        let text = "SCORE" + String(format: "%07d", min(totalScore, 9_999_999)) + " MEN" + String(format: "%03d", lives)
            + " LEVEL" + "001"
        for (index, character) in text.enumerated() {
            (statusLine.children[safe: index] as? SKSpriteNode)?.texture = glyphs[character]
        }
    }

    /// The status line, drawn with the game's own font at the original's layout: SCORE at column 0, the score from
    /// column 5, MEN at 13, lives at 16, LEVEL at 20 and the level number at 25.
    private func buildStatusLine() {
        statusLine.removeAllChildren()
        let y = Self.canvasSize.height / 2 - 362 - Self.cellSize.height / 2
        for column in 0..<28 {
            let glyph = SKSpriteNode(color: .clear, size: Self.cellSize)
            glyph.position = CGPoint(x: -Self.canvasSize.width / 2 + CGFloat(column) * Self.cellSize.width + Self.cellSize.width / 2, y: y)
            statusLine.addChild(glyph)
        }
        updateStatus()
    }
}


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}


/// The game's sound effects, one player per file so effects can overlap.
@MainActor
final class LodeRunnerSounds {

    private var players: [String: AVAudioPlayer] = [:]

    init() {
        guard let folder = LodeRunnerScene.assetsURL?.appendingPathComponent("audio") else { return }
        for name in ["death", "dig", "fall", "gold_pickup", "guard_respawn", "guard_trapped", "land", "level_complete"] {
            if let player = try? AVAudioPlayer(contentsOf: folder.appendingPathComponent("\(name).wav")) {
                player.prepareToPlay()
                players[name] = player
            }
        }
    }

    func play(_ name: String, loops: Bool = false) {
        guard let player = players[name] else { return }
        player.numberOfLoops = loops ? -1 : 0
        player.currentTime = 0
        player.play()
    }

    func stop(_ name: String) {
        players[name]?.stop()
    }

    func stopAll() {
        players.values.forEach { $0.stop() }
    }
}
