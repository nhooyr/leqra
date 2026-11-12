import Foundation

/// Movement shared by offline play and online prediction. Values and operation
/// order follow game.go's steerTank and the browser prediction implementation.
public enum TankMovement {
    public static func steer(angle: Double, input: GameInput, turnScale: Double = 1,
                             dt: Double) -> (angle: Double, throttle: Double) {
        var angle = angle
        var throttle = (input.forward ? 1.0 : 0) - (input.reverse ? 0.72 : 0)
        let magnitude = hypot(input.stickX, input.stickY)
        if magnitude > 0.1 {
            let desired = atan2(input.stickY, input.stickX)
            let difference = atan2(sin(desired - angle), cos(desired - angle))
            var rate = 5.8
            if input.touchAim && !input.aimOnly {
                rate += 3.2 * smoothStep((min(magnitude, 1) - 0.35) / 0.65)
                    * smoothStep((abs(difference) - .pi / 12) / (.pi / 2 - .pi / 12))
            }
            let limit = rate * turnScale * dt
            angle += min(max(difference, -limit), limit)
            if !input.aimOnly { throttle = min(1, magnitude) * max(0, cos(difference)) }
        } else {
            angle += ((input.right ? 1.0 : 0) - (input.left ? 1.0 : 0)) * 3.65 * turnScale * dt
        }
        return (atan2(sin(angle), cos(angle)), throttle)
    }

    public static func step(tank: inout ArenaTank, input: GameInput, dt: Double, maze: InfiniteMaze) {
        if let world = maze.world {
            step(tank: &tank, input: input, dt: dt, walls: world.walls, width: world.width, height: world.height)
            return
        }
        guard dt > 0, dt <= 0.1, tank.hp > 0 else { return }
        tank.speedTime = max(0, tank.speedTime - dt)
        if tank.speedTime <= 0 { tank.speedStacks = 0 }
        let wasGhost = tank.ghostTime > 0
        tank.ghostTime = max(0, tank.ghostTime - dt)
        if wasGhost && tank.ghostTime == 0 {
            let point = maze.phaseExit(x: tank.x, y: tank.y)
            tank.x = point.x; tank.y = point.y
        }
        let stacks = tank.speedTime > 0 ? max(1, min(5, tank.speedStacks)) : 0
        let steering = steer(angle: tank.angle, input: input, turnScale: 1 + 0.25 * Double(stacks), dt: dt)
        tank.angle = steering.angle
        let speed = 128 * (1 + 0.65 * Double(stacks)), oldX = tank.x, oldY = tank.y
        let dx = cos(tank.angle) * speed * steering.throttle * dt
        let dy = sin(tank.angle) * speed * steering.throttle * dt
        if tank.ghostTime > 0 || !maze.blocked(x: tank.x + dx, y: tank.y, radius: 17) { tank.x += dx }
        if tank.ghostTime > 0 || !maze.blocked(x: tank.x, y: tank.y + dy, radius: 17) { tank.y += dy }
        tank.track += hypot(tank.x - oldX, tank.y - oldY)
    }

    /// Prediction for fixed mazes uses the server's circle separation and map
    /// bounds, rather than Infinity's endpoint rejection.
    public static func step(tank: inout ArenaTank, input: GameInput, dt: Double,
                            walls: [MazeWall], width: Double, height: Double) {
        guard dt > 0, dt <= 0.1, tank.hp > 0, width >= 42, height >= 42 else { return }
        tank.speedTime = max(0, tank.speedTime - dt)
        if tank.speedTime <= 0 { tank.speedStacks = 0 }
        let wasGhost = tank.ghostTime > 0
        tank.ghostTime = max(0, tank.ghostTime - dt)
        if wasGhost && tank.ghostTime == 0 { finishGhost(tank: &tank, walls: walls, width: width, height: height) }
        let stacks = tank.speedTime > 0 ? max(1, min(5, tank.speedStacks)) : 0
        let steering = steer(angle: tank.angle, input: input, turnScale: 1 + 0.25 * Double(stacks), dt: dt)
        tank.angle = steering.angle
        let speed = 128 * (1 + 0.65 * Double(stacks)), oldX = tank.x, oldY = tank.y
        tank.x += cos(tank.angle) * speed * steering.throttle * dt
        if tank.ghostTime == 0 { resolveWalls(tank: &tank, walls: walls) }
        tank.y += sin(tank.angle) * speed * steering.throttle * dt
        if tank.ghostTime == 0 { resolveWalls(tank: &tank, walls: walls) }
        tank.x = min(max(tank.x, 21), width - 21)
        tank.y = min(max(tank.y, 21), height - 21)
        tank.track += hypot(tank.x - oldX, tank.y - oldY)
    }

    private static func resolveWalls(tank: inout ArenaTank, walls: [MazeWall]) {
        for _ in 0..<2 {
            for wall in walls {
                let dx = tank.x - min(max(tank.x, wall.x), wall.x + wall.w)
                let dy = tank.y - min(max(tank.y, wall.y), wall.y + wall.h)
                let distanceSquared = dx * dx + dy * dy
                guard distanceSquared < 17 * 17 else { continue }
                if distanceSquared > 0.000001 {
                    let distance = sqrt(distanceSquared), push = 17 - distance + 0.002
                    tank.x += dx / distance * push; tank.y += dy / distance * push
                } else {
                    let edges = [tank.x - wall.x, wall.x + wall.w - tank.x,
                                 tank.y - wall.y, wall.y + wall.h - tank.y]
                    let edge = edges.indices.min(by: { edges[$0] < edges[$1] })!
                    let push = edges[edge] + 17 + 0.002
                    switch edge {
                    case 0: tank.x -= push
                    case 1: tank.x += push
                    case 2: tank.y -= push
                    default: tank.y += push
                    }
                }
            }
        }
    }

    static func displace(tank: inout ArenaTank, dx: Double, dy: Double, world: ArenaWorld) {
        tank.x += dx
        if tank.ghostTime <= 0 { resolveWalls(tank: &tank, walls: world.walls) }
        tank.y += dy
        if tank.ghostTime <= 0 { resolveWalls(tank: &tank, walls: world.walls) }
        tank.x = min(max(tank.x, 21), world.width - 21)
        tank.y = min(max(tank.y, 21), world.height - 21)
    }

    static func stepBot(tank: inout ArenaTank, input: GameInput, dt: Double, world: ArenaWorld) {
        guard dt > 0, dt <= 0.1, tank.hp > 0 else { return }
        tank.speedTime = max(0, tank.speedTime - dt)
        if tank.speedTime <= 0 { tank.speedStacks = 0 }
        let wasGhost = tank.ghostTime > 0
        tank.ghostTime = max(0, tank.ghostTime - dt)
        if wasGhost && tank.ghostTime == 0 { finishGhost(tank: &tank, walls: world.walls, width: world.width, height: world.height) }
        let tuning = BotDifficulty(rawValue: tank.difficulty) ?? .normal
        let stacks = tank.speedTime > 0 ? max(1, min(5, tank.speedStacks)) : 0
        var throttle = 0.0
        let magnitude = hypot(input.stickX, input.stickY)
        if magnitude > 0.1 {
            let desired = atan2(input.stickY, input.stickX)
            let difference = atan2(sin(desired - tank.angle), cos(desired - tank.angle))
            let limit = tuning.turn * (1 + 0.25 * Double(stacks)) * dt
            tank.angle += min(max(difference, -limit), limit)
            if !input.aimOnly { throttle = min(1, magnitude) * max(0, cos(difference)) }
        }
        tank.angle = atan2(sin(tank.angle), cos(tank.angle))
        let speed = tuning.speed * (1 + 0.65 * Double(stacks)), x = tank.x, y = tank.y
        displace(tank: &tank, dx: cos(tank.angle) * speed * throttle * dt,
                 dy: sin(tank.angle) * speed * throttle * dt, world: world)
        tank.track += hypot(tank.x - x, tank.y - y)
    }

    private static func finishGhost(tank: inout ArenaTank, walls: [MazeWall], width: Double, height: Double) {
        func clear(_ x: Double, _ y: Double) -> Bool {
            guard x >= 21, x <= width - 21, y >= 21, y <= height - 21 else { return false }
            return !walls.contains { wall in
                hypot(x - min(max(x, wall.x), wall.x + wall.w), y - min(max(y, wall.y), wall.y + wall.h)) < 17.0001
            }
        }
        guard !clear(tank.x, tank.y) else { return }
        var best = Double.infinity, point = (x: tank.x, y: tank.y)
        for row in 0..<Int(height / 84) {
            for col in 0..<Int(width / 84) {
                let x = min(max(tank.x, Double(col) * 84 + 21.01), Double(col + 1) * 84 - 21.01)
                let y = min(max(tank.y, Double(row) * 84 + 21.01), Double(row + 1) * 84 - 21.01)
                let distance = (x - tank.x) * (x - tank.x) + (y - tank.y) * (y - tank.y)
                if distance < best - 1e-8 && clear(x, y) { best = distance; point = (x, y) }
            }
        }
        if best.isFinite { tank.x = point.x; tank.y = point.y }
        else { resolveWalls(tank: &tank, walls: walls) }
    }

    private static func smoothStep(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
