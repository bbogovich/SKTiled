//
//  LodeRunnerGame.swift
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

// The rules of Lode Runner (Broderbund, 1983), independent of SpriteKit and SKTiled.
//
// The rules follow the Retro2Arcade project's design document for the original Apple II game (section numbers
// below refer to it). The scene turns the events this model emits into tile changes, sprites and sounds.
//
// Simplifications for the demo: hold-to-move input only, no speed setting, and runner/gold and runner/guard contact
// is decided by the scene's sprite collision tests rather than inside the model.

import Foundation


/// A map code, as stored in the level (tile id = code).
enum LRCell: Int {
    case empty, brick, solid, ladder, rope, trap, hiddenLadder, gold, guardian, runner
}


/// A cell on the 28 × 16 playfield. Row 0 is the top.
struct LRCellPosition: Hashable {
    var col: Int
    var row: Int
}


/// The level as read from the map.
struct LRLevel {

    /// Terrain codes, indexed `[row][col]`: empty, brick, solid, ladder, rope or trap.
    var terrain: [[LRCell]]

    /// Cells that become ladders when all gold is taken.
    var hiddenLadders: [LRCellPosition]

    var gold: [LRCellPosition]
    var runner: LRCellPosition
    var guards: [LRCellPosition]
}


/// Commands sampled from the keyboard each tick.
struct LRInput {
    var left = false
    var right = false
    var up = false
    var down = false
    var dig = false
}


/// Which way an actor faces.
enum LRFacing {
    case left, right
}


/// A runner or guard position: a cell plus sub-steps 0...4 on each axis (2 = the cell's centre).
struct LRActor {
    var col: Int
    var row: Int
    var xsub = 2
    var ysub = 2
    var frame = 0
    var facing = LRFacing.left

    var cell: LRCellPosition { LRCellPosition(col: col, row: row) }
}


/// Something the presentation needs to show or play.
enum LREvent: Equatable {
    case runnerFell
    case runnerLanded
    case digStarted(brick: LRCellPosition, debris: LRCellPosition)
    case digStep(brick: LRCellPosition, debris: LRCellPosition, step: Int)
    case digAborted(brick: LRCellPosition, debris: LRCellPosition)
    case holeOpened(LRCellPosition)
    case holeRefill(LRCellPosition, stage: Int)
    case holeClosed(LRCellPosition)
    case goldTaken(LRCellPosition)
    case guardTookGold(guard: Int, at: LRCellPosition)
    case guardDroppedGold(guard: Int, at: LRCellPosition)
    case guardLostGold(guard: Int)
    case guardTrapped(guard: Int, hole: LRCellPosition)
    case guardKilled(guard: Int)
    case guardRespawning(guard: Int, at: LRCellPosition, stage: Int)
    case guardRespawned(guard: Int)
    case laddersRevealed([LRCellPosition])
    case runnerDied
    case levelComplete
}


/// The state and rules of one level.
struct LodeRunnerGame {

    static let columns = 28
    static let rows = 16

    // Timing and scores from the original (design doc sections 6, 7 and 10).
    static let ticksPerSecond = 22.0
    static let digSteps = 12
    static let holeTicks = 180
    static let stuckMoves = 38
    static let respawnTicks = 20
    static let goldScore = 250
    static let guardScore = 75
    static let levelBonus = 1500

    /// Guard moves per tick for three consecutive ticks, by guard count (bit count = moves), section 7.1.
    static let guardScheduleMasks: [[Int]] = [[0, 0, 0], [0, 1, 1], [1, 1, 1], [1, 3, 1], [1, 3, 3], [3, 3, 3]]

    /// Terrain and gold only.
    private(set) var base: [[LRCell]]

    /// Terrain, gold, dug holes and actors (section 3.1).
    private(set) var current: [[LRCell]]

    private(set) var runner: LRActor
    private(set) var guards: [Guard]
    private(set) var holes: [Hole] = []
    private(set) var dig: Dig?
    private(set) var goldRemaining: Int
    private(set) var score = 0
    private(set) var isRunnerDead = false
    private(set) var isLevelComplete = false

    private var hiddenLadders: [LRCellPosition]
    private var laddersPlaced: Set<LRCellPosition> = []
    private var runnerFalling = false
    private var tickCounter = 0          // the original's $53, 0...27
    private var schedulePhase = 0
    private var nextGuard = 0

    struct Guard {
        var actor: LRActor
        /// > 0: stuck in a hole (counts down per move); < 0: carrying gold (counts up per cell); 0: free.
        var state = 0
        /// Ticks until a killed guard reappears; 0 when active.
        var respawn = 0
        var carriesGold: Bool { state < 0 }
    }

    struct Hole {
        var cell: LRCellPosition
        var timer: Int
    }

    struct Dig {
        var brick: LRCellPosition
        var debris: LRCellPosition
        var facing: LRFacing
        var step = 0
    }

    init(level: LRLevel) {
        var base = level.terrain
        for gold in level.gold {
            base[gold.row][gold.col] = .gold
        }
        self.base = base
        self.current = base
        self.hiddenLadders = level.hiddenLadders
        self.goldRemaining = level.gold.count
        self.runner = LRActor(col: level.runner.col, row: level.runner.row)
        self.guards = level.guards.map { Guard(actor: LRActor(col: $0.col, row: $0.row)) }
        current[runner.row][runner.col] = .runner
        for guardian in guards {
            current[guardian.actor.row][guardian.actor.col] = .guardian
        }
    }

    // MARK: - Map Access

    private func baseAt(_ col: Int, _ row: Int) -> LRCell {
        guard (0..<Self.columns).contains(col), (0..<Self.rows).contains(row) else { return .solid }
        return base[row][col]
    }

    private func currentAt(_ col: Int, _ row: Int) -> LRCell {
        guard (0..<Self.columns).contains(col), (0..<Self.rows).contains(row) else { return .solid }
        return current[row][col]
    }

    /// What an actor leaves behind: the base value, except that a dug hole (base brick) stays open.
    private mutating func vacate(_ cell: LRCellPosition) {
        let value = base[cell.row][cell.col]
        current[cell.row][cell.col] = (value == .brick) ? .empty : value
    }

    // MARK: - Tick

    /// Advances the game by one tick (section 4) and returns what happened.
    mutating func tick(_ input: LRInput) -> [LREvent] {
        guard !isRunnerDead, !isLevelComplete else { return [] }
        var events: [LREvent] = []

        updateRunner(input, &events)
        if isRunnerDead { return events }

        if goldRemaining == 0 {
            revealLadders(&events)
        }

        if runner.row == 0, runner.ysub == 2, goldRemaining == 0 {
            isLevelComplete = true
            score += Self.levelBonus
            events.append(.levelComplete)
            return events
        }

        updateRespawns(&events)
        tickCounter = (tickCounter + 1) % 28
        updateHoles(&events)
        if isRunnerDead { return events }

        moveGuards(&events)
        return events
    }

    /// Called by the presentation when the runner's sprite touches a guard's.
    mutating func runnerCaught() -> [LREvent] {
        guard !isRunnerDead else { return [] }
        isRunnerDead = true
        return [.runnerDied]
    }

    /// Called by the presentation when the runner's sprite touches gold. Returns `.goldTaken` if gold was there.
    mutating func collectGold(at cell: LRCellPosition) -> [LREvent] {
        guard base[cell.row][cell.col] == .gold else { return [] }
        base[cell.row][cell.col] = .empty
        if current[cell.row][cell.col] == .gold {
            current[cell.row][cell.col] = .empty
        }
        goldRemaining -= 1
        score += Self.goldScore
        return [.goldTaken(cell)]
    }

    // MARK: - Runner (section 5)

    private mutating func updateRunner(_ input: LRInput, _ events: inout [LREvent]) {
        if dig != nil {
            continueDig(&events)
            return
        }

        if runnerShouldFall() {
            if !runnerFalling {
                events.append(.runnerFell)
            }
            runnerFalling = true
            runner.frame = (runner.facing == .left) ? 7 : 15
            center(&runner.xsub)
            runner.ysub += 1
            if runner.ysub > 4 {
                moveRunner(toCol: runner.col, row: runner.row + 1)
                runner.ysub = 0
            }
            return
        }

        if runnerFalling {
            runnerFalling = false
            events.append(.runnerLanded)
        }

        // the vertical command (up, down, dig) is tried first, then the horizontal one
        if input.dig, startDig(&events) { return }
        if input.up, runnerCanClimbUp() {
            center(&runner.xsub)
            runner.ysub -= 1
            if runner.ysub < 0 {
                moveRunner(toCol: runner.col, row: runner.row - 1)
                runner.ysub = 4
            }
            runner.frame = animate(runner.frame, in: 16...17)
            return
        }
        if input.down, runnerCanClimbDown() {
            center(&runner.xsub)
            runner.ysub += 1
            if runner.ysub > 4 {
                moveRunner(toCol: runner.col, row: runner.row + 1)
                runner.ysub = 0
            }
            runner.frame = animate(runner.frame, in: 16...17)
            return
        }
        if input.left, !runnerBlocked(sideways: -1) {
            runner.facing = .left
            center(&runner.ysub)
            runner.xsub -= 1
            if runner.xsub < 0 {
                moveRunner(toCol: runner.col - 1, row: runner.row)
                runner.xsub = 4
            }
            runner.frame = animate(runner.frame, in: baseAt(runner.col, runner.row) == .rope ? 3...5 : 0...2)
            return
        }
        if input.right, !runnerBlocked(sideways: 1) {
            runner.facing = .right
            center(&runner.ysub)
            runner.xsub += 1
            if runner.xsub > 4 {
                moveRunner(toCol: runner.col + 1, row: runner.row)
                runner.xsub = 0
            }
            runner.frame = animate(runner.frame, in: baseAt(runner.col, runner.row) == .rope ? 11...13 : 8...10)
        }
    }

    private func runnerShouldFall() -> Bool {
        let here = baseAt(runner.col, runner.row)
        if here == .ladder { return false }
        if here == .rope, runner.ysub == 2 { return false }
        if runner.ysub < 2 { return true }
        if runner.row == Self.rows - 1 { return false }
        let below = currentAt(runner.col, runner.row + 1)
        if below == .guardian { return false }
        if below == .empty { return true }      // a dug hole: current empty over base brick
        return [.brick, .solid, .ladder].contains(baseAt(runner.col, runner.row + 1))
            ? false : true
    }

    private func runnerBlocked(sideways dx: Int) -> Bool {
        let past = dx < 0 ? runner.xsub <= 2 : runner.xsub >= 2
        guard past else { return false }
        let next = runner.col + dx
        return !(0..<Self.columns).contains(next) || [.brick, .solid, .trap].contains(currentAt(next, runner.row))
    }

    private func runnerCanClimbUp() -> Bool {
        if baseAt(runner.col, runner.row) == .ladder {
            return runner.ysub >= 3 || (runner.row > 0 && ![.brick, .solid, .trap].contains(currentAt(runner.col, runner.row - 1)))
        }
        return runner.ysub >= 3 && baseAt(runner.col, runner.row + 1) == .ladder
    }

    private func runnerCanClimbDown() -> Bool {
        if runner.ysub >= 2 {
            return runner.row < Self.rows - 1 && ![.brick, .solid].contains(currentAt(runner.col, runner.row + 1))
        }
        return true
    }

    private mutating func moveRunner(toCol col: Int, row: Int) {
        vacate(runner.cell)
        runner.col = col
        runner.row = row
        if current[row][col] == .guardian {
            isRunnerDead = true
        }
        current[row][col] = .runner
    }

    // MARK: - Digging (section 6)

    private func digCells(facing: LRFacing) -> (brick: LRCellPosition, debris: LRCellPosition)? {
        let col = runner.col + (facing == .left ? -1 : 1)
        guard runner.row < Self.rows - 1, (0..<Self.columns).contains(col) else { return nil }
        return (LRCellPosition(col: col, row: runner.row + 1), LRCellPosition(col: col, row: runner.row))
    }

    private func canDig(_ cells: (brick: LRCellPosition, debris: LRCellPosition)) -> Bool {
        currentAt(cells.brick.col, cells.brick.row) == .brick && currentAt(cells.debris.col, cells.debris.row) == .empty
    }

    private mutating func startDig(_ events: inout [LREvent]) -> Bool {
        guard let cells = digCells(facing: runner.facing), canDig(cells) else { return false }
        dig = Dig(brick: cells.brick, debris: cells.debris, facing: runner.facing)
        events.append(.digStarted(brick: cells.brick, debris: cells.debris))
        continueDig(&events)
        return true
    }

    private mutating func continueDig(_ events: inout [LREvent]) {
        guard var current = dig else { return }
        guard canDig((current.brick, current.debris)) else {
            events.append(.digAborted(brick: current.brick, debris: current.debris))
            dig = nil
            return
        }
        center(&runner.xsub)
        center(&runner.ysub)
        let digging = current.step < 6
        runner.frame = current.facing == .left ? (digging ? 6 : 0) : (digging ? 14 : 8)
        events.append(.digStep(brick: current.brick, debris: current.debris, step: current.step))
        current.step += 1

        if current.step == Self.digSteps {
            self.current[current.brick.row][current.brick.col] = .empty
            holes.append(Hole(cell: current.brick, timer: Self.holeTicks))
            events.append(.holeOpened(current.brick))
            dig = nil
        } else {
            dig = current
        }
    }

    private mutating func updateHoles(_ events: inout [LREvent]) {
        for index in holes.indices.reversed() {
            holes[index].timer -= 1
            let cell = holes[index].cell
            switch holes[index].timer {
                case 20: events.append(.holeRefill(cell, stage: 1))
                case 10: events.append(.holeRefill(cell, stage: 2))
                case 0:
                    closeHole(cell, &events)
                    holes.remove(at: index)
                default: break
            }
        }
    }

    private mutating func closeHole(_ cell: LRCellPosition, _ events: inout [LREvent]) {
        let occupant = current[cell.row][cell.col]
        current[cell.row][cell.col] = .brick
        base[cell.row][cell.col] = .brick
        events.append(.holeClosed(cell))

        switch occupant {
            case .runner:
                isRunnerDead = true
                events.append(.runnerDied)
            case .gold:
                goldRemaining -= 1
            case .guardian:
                if let index = guards.firstIndex(where: { $0.actor.cell == cell && $0.respawn == 0 }) {
                    killGuard(index, &events)
                }
            default:
                break
        }
    }

    // MARK: - Guards (section 7)

    private mutating func moveGuards(_ events: inout [LREvent]) {
        let active = guards.count
        guard active > 0 else { return }
        let masks = Self.guardScheduleMasks[min(active, Self.guardScheduleMasks.count - 1)]
        let mask = masks[schedulePhase]
        schedulePhase = (schedulePhase + 1) % 3

        let moves = (mask & 1) + ((mask >> 1) & 1)
        for _ in 0..<moves {
            let index = nextGuard
            nextGuard = (nextGuard + 1) % guards.count
            if guards[index].respawn == 0 {
                moveGuard(index, &events)
                if isRunnerDead { return }
            }
        }
    }

    private mutating func moveGuard(_ index: Int, _ events: inout [LREvent]) {
        var guardian = guards[index]
        defer { guards[index] = guardian }

        // stuck in a hole: wait, shake, then climb out (7.2 step 1)
        var climbingOut = false
        if guardian.state > 0 {
            guardian.state -= 1
            if guardian.state >= 13 { return }
            if guardian.state >= 7 {
                guardian.actor.xsub = [2, 1, 2, 3, 2, 1][guardian.state - 7]
                return
            }
            climbingOut = baseAt(guardian.actor.col, guardian.actor.row) == .brick
        }

        // fall (7.2 step 2)
        if !climbingOut, guardShouldFall(guardian.actor) {
            guardian.actor.frame = guardian.actor.facing == .left ? 6 : 13
            center(&guardian.actor.xsub)
            guardian.actor.ysub += 1
            if guardian.actor.ysub > 4 {
                let target = LRCellPosition(col: guardian.actor.col, row: guardian.actor.row + 1)
                guardian.actor.ysub = 0
                if !enterCell(&guardian, index: index, target, &events) { return }
                if baseAt(target.col, target.row) == .brick, guardian.carriesGold {
                    dropGoldAbove(&guardian, index: index, &events)
                }
            }
            if guardian.actor.ysub == 2, baseAt(guardian.actor.col, guardian.actor.row) == .brick, guardian.state == 0 {
                guardian.state = Self.stuckMoves
                score += Self.guardScore
                events.append(.guardTrapped(guard: index, hole: guardian.actor.cell))
            }
            return
        }

        // move as the AI decides (7.2 step 3)
        let direction = climbingOut ? .up : decide(guardian)
        var actor = guardian.actor
        switch direction {
            case .left where !guardBlocked(actor, dx: -1):
                actor.facing = .left
                center(&actor.ysub)
                actor.xsub -= 1
                actor.frame = animate(actor.frame, in: baseAt(actor.col, actor.row) == .rope ? 3...5 : 0...2)
            case .right where !guardBlocked(actor, dx: 1):
                actor.facing = .right
                center(&actor.ysub)
                actor.xsub += 1
                actor.frame = animate(actor.frame, in: baseAt(actor.col, actor.row) == .rope ? 10...12 : 7...9)
            case .up where guardCanClimbUp(actor, inHole: climbingOut):
                center(&actor.xsub)
                actor.ysub -= 1
                actor.frame = animate(actor.frame, in: 14...15)
            case .down where guardCanClimbDown(actor):
                center(&actor.xsub)
                actor.ysub += 1
                actor.frame = animate(actor.frame, in: 14...15)
            default:
                if climbingOut { guardian.state += 1 }       // blocked in a hole: wait
                return
        }

        // cross into the next cell when a sub-step leaves 0...4
        var target = actor.cell
        if actor.xsub < 0 { target.col -= 1; actor.xsub = 4 }
        if actor.xsub > 4 { target.col += 1; actor.xsub = 0 }
        if actor.ysub < 0 { target.row -= 1; actor.ysub = 4 }
        if actor.ysub > 4 { target.row += 1; actor.ysub = 0 }
        guardian.actor = actor

        if target != actor.cell {
            if !enterCell(&guardian, index: index, target, &events) { return }
            carryGold(&guardian, index: index, &events)
        }

        // pick up gold at the cell centre (7.4)
        if guardian.actor.xsub == 2, guardian.actor.ysub == 2, guardian.state == 0,
           base[guardian.actor.row][guardian.actor.col] == .gold {
            base[guardian.actor.row][guardian.actor.col] = .empty
            guardian.state = -(tickCounter + 1)
            events.append(.guardTookGold(guard: index, at: guardian.actor.cell))
        }
    }

    /// Moves a guard into a new cell. Returns false if that killed the runner.
    private mutating func enterCell(_ guardian: inout Guard, index: Int, _ target: LRCellPosition, _ events: inout [LREvent]) -> Bool {
        let previous = guardian.actor.cell
        vacate(previous)
        guardian.actor.col = target.col
        guardian.actor.row = target.row
        if current[target.row][target.col] == .runner {
            current[target.row][target.col] = .guardian
            isRunnerDead = true
            events.append(.runnerDied)
            return false
        }
        current[target.row][target.col] = .guardian
        return true
    }

    private func guardShouldFall(_ actor: LRActor) -> Bool {
        let here = baseAt(actor.col, actor.row)
        if here == .ladder { return false }
        if here == .rope, actor.ysub == 2 { return false }
        if actor.ysub < 2 { return true }
        if actor.row == Self.rows - 1 { return false }
        let below = currentAt(actor.col, actor.row + 1)
        if below == .guardian { return false }
        if below == .empty || below == .runner { return true }
        return ![.brick, .solid, .ladder].contains(baseAt(actor.col, actor.row + 1))
    }

    private func guardBlocked(_ actor: LRActor, dx: Int) -> Bool {
        let past = dx < 0 ? actor.xsub <= 2 : actor.xsub >= 2
        guard past else { return false }
        let next = actor.col + dx
        return !(0..<Self.columns).contains(next)
            || [.brick, .solid, .guardian].contains(currentAt(next, actor.row))
            || baseAt(next, actor.row) == .trap
    }

    private func guardCanClimbUp(_ actor: LRActor, inHole: Bool) -> Bool {
        let blockedAbove = actor.ysub <= 2
            && (actor.row == 0 || [.brick, .solid, .trap, .guardian].contains(currentAt(actor.col, actor.row - 1)))
        if blockedAbove { return false }
        return inHole || baseAt(actor.col, actor.row) == .ladder
            || (actor.ysub >= 3 && baseAt(actor.col, actor.row + 1) == .ladder)
    }

    private func guardCanClimbDown(_ actor: LRActor) -> Bool {
        if actor.ysub >= 2 {
            return actor.row < Self.rows - 1 && ![.brick, .solid, .guardian].contains(currentAt(actor.col, actor.row + 1))
        }
        return true
    }

    // MARK: Gold carried by guards (7.5)

    private mutating func carryGold(_ guardian: inout Guard, index: Int, _ events: inout [LREvent]) {
        guard guardian.carriesGold else { return }
        guardian.state += 1
        guard guardian.state == 0 else { return }

        // drop it in the cell just left, if there is room
        let left = LRCellPosition(col: guardian.actor.col - (guardian.actor.facing == .left ? -1 : 1), row: guardian.actor.row)
        let dropCell = (0..<Self.columns).contains(left.col) ? left : guardian.actor.cell
        if baseAt(dropCell.col, dropCell.row) == .empty, currentAt(dropCell.col, dropCell.row) == .empty {
            base[dropCell.row][dropCell.col] = .gold
            current[dropCell.row][dropCell.col] = .gold
            events.append(.guardDroppedGold(guard: index, at: dropCell))
        } else {
            guardian.state = -1
        }
    }

    private mutating func dropGoldAbove(_ guardian: inout Guard, index: Int, _ events: inout [LREvent]) {
        let above = LRCellPosition(col: guardian.actor.col, row: guardian.actor.row - 1)
        if above.row >= 0, baseAt(above.col, above.row) == .empty {
            base[above.row][above.col] = .gold
            if current[above.row][above.col] == .empty {
                current[above.row][above.col] = .gold
            }
            events.append(.guardDroppedGold(guard: index, at: above))
        } else {
            goldRemaining -= 1
            events.append(.guardLostGold(guard: index))
        }
        guardian.state = 0
    }

    // MARK: Death and respawn (7.6)

    private mutating func killGuard(_ index: Int, _ events: inout [LREvent]) {
        if guards[index].carriesGold {
            goldRemaining -= 1
            events.append(.guardLostGold(guard: index))
        }
        score += Self.guardScore
        events.append(.guardKilled(guard: index))

        // reappear on row 1 at the first empty cell right of the tick counter's column
        var col = tickCounter
        var row = 1
        while baseAt(col, row) != .empty {
            col += 1
            if col >= Self.columns { col = 0; row += 1 }
            if row >= Self.rows { row = 1; col = 0; break }
        }
        tickCounter = col % 28
        guards[index].actor = LRActor(col: col, row: row)
        guards[index].state = 0
        guards[index].respawn = Self.respawnTicks
    }

    private mutating func updateRespawns(_ events: inout [LREvent]) {
        for index in guards.indices where guards[index].respawn > 0 {
            guards[index].respawn -= 1
            let cell = guards[index].actor.cell
            switch guards[index].respawn {
                case 19: events.append(.guardRespawning(guard: index, at: cell, stage: 1))
                case 10: events.append(.guardRespawning(guard: index, at: cell, stage: 2))
                case 0:
                    if current[cell.row][cell.col] == .empty {
                        current[cell.row][cell.col] = .guardian
                        events.append(.guardRespawned(guard: index))
                    } else {
                        guards[index].respawn = 1
                    }
                default: break
            }
        }
    }

    // MARK: - AI (7.3)

    private enum Direction { case none, left, right, up, down }

    private func decide(_ guardian: Guard) -> Direction {
        let g = guardian.actor
        if baseAt(g.col, g.row) == .brick, guardian.state > 0 { return .up }

        // same row: chase directly unless there is a gap to fall into on the way
        if g.row == runner.row {
            let step = runner.col > g.col ? 1 : -1
            var clear = true
            var x = g.col
            while x != runner.col {
                x += step
                let here = baseAt(x, g.row)
                if ![.ladder, .rope].contains(here), g.row < Self.rows - 1,
                   [.empty, .trap].contains(baseAt(x, g.row + 1)) {
                    clear = false
                    break
                }
            }
            if clear { return runner.col > g.col ? .right : .left }
        }

        let (spanLeft, spanRight) = walkableSpan(g)
        var best = 255
        var choice = Direction.none

        func consider(_ x: Int, _ direction: Direction?) {
            if g.row < Self.rows - 1, ![.brick, .solid].contains(baseAt(x, g.row + 1)) {
                let score = rowScore(scanDown(x, g.row), x, g)
                if score < best { best = score; choice = direction ?? .down }
            }
            if g.row > 0, baseAt(x, g.row) == .ladder {
                let score = rowScore(scanUp(x, g.row), x, g)
                if score < best { best = score; choice = direction ?? .up }
            }
        }

        consider(g.col, nil)
        for x in stride(from: spanLeft, to: g.col, by: 1) { consider(x, .left) }
        for x in stride(from: spanRight, to: g.col, by: -1) { consider(x, .right) }
        return choice
    }

    private func rowScore(_ y: Int, _ x: Int, _ g: LRActor) -> Int {
        if y == runner.row { return abs(x - g.col) }
        if y < runner.row { return 100 + (runner.row - y) }
        return 200 + (y - runner.row)
    }

    private func walkableSpan(_ g: LRActor) -> (Int, Int) {
        func extend(_ dx: Int) -> Int {
            var col = g.col
            while (0..<Self.columns).contains(col + dx) {
                let next = currentAt(col + dx, g.row)
                if [.brick, .solid].contains(next) { break }
                col += dx
                let supported = [.ladder, .rope].contains(next) || g.row == Self.rows - 1
                    || [.brick, .solid, .ladder].contains(baseAt(col, g.row + 1))
                if !supported { break }
            }
            return col
        }
        return (extend(-1), extend(1))
    }

    private func scanDown(_ x: Int, _ start: Int) -> Int {
        var y = start
        while true {
            if [.brick, .solid].contains(baseAt(x, y + 1)) { return y }
            if baseAt(x, y) != .empty {
                let exitLeft = x > 0 && (baseAt(x - 1, y) == .rope || [.brick, .solid, .ladder].contains(baseAt(x - 1, y + 1)))
                let exitRight = x < Self.columns - 1 && (baseAt(x + 1, y) == .rope || [.brick, .solid, .ladder].contains(baseAt(x + 1, y + 1)))
                if (exitLeft || exitRight) && y >= runner.row { return y }
            }
            y += 1
            if y == Self.rows { return Self.rows - 1 }
        }
    }

    private func scanUp(_ x: Int, _ start: Int) -> Int {
        var y = start
        while true {
            if baseAt(x, y) != .ladder { return y }
            y -= 1
            let exitLeft = x > 0 && ([.brick, .solid, .ladder].contains(baseAt(x - 1, y + 1)) || baseAt(x - 1, y) == .rope)
            let exitRight = x < Self.columns - 1 && ([.brick, .solid, .ladder].contains(baseAt(x + 1, y + 1)) || baseAt(x + 1, y) == .rope)
            if (exitLeft || exitRight) && y <= runner.row { return y }
            if y == 0 { return 0 }
        }
    }

    // MARK: - Escape Ladders (9.2)

    private mutating func revealLadders(_ events: inout [LREvent]) {
        var placed: [LRCellPosition] = []
        for cell in hiddenLadders where !laddersPlaced.contains(cell) && base[cell.row][cell.col] == .empty {
            base[cell.row][cell.col] = .ladder
            if current[cell.row][cell.col] == .empty {
                current[cell.row][cell.col] = .ladder
            }
            laddersPlaced.insert(cell)
            placed.append(cell)
        }
        if !placed.isEmpty {
            events.append(.laddersRevealed(placed))
        }
    }

    // MARK: - Helpers

    /// Moves a sub-step one unit toward the cell's centre.
    private func center(_ sub: inout Int) {
        if sub < 2 { sub += 1 } else if sub > 2 { sub -= 1 }
    }

    /// Advances an animation frame within a range, entering the range at its start.
    private func animate(_ frame: Int, in range: ClosedRange<Int>) -> Int {
        guard range.contains(frame) else { return range.lowerBound }
        return frame == range.upperBound ? range.lowerBound : frame + 1
    }
}
