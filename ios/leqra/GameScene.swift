import SpriteKit
import UIKit
import QuartzCore
import leqraCore

private struct ProjectileStyle: Hashable {
    let kind: String
    let colorIndex: Int
    init(_ bullet: ArenaBullet) {
        kind = bullet.kind
        colorIndex = max(0, bullet.colorIndex) % 8
    }
}

/// The playing field and controls are native SpriteKit nodes. The app supplies
/// snapshots on each display tick, independently of the server's 30 Hz stream.
@MainActor
final class GameScene: SKScene {
    struct RenderMetrics {
        var totalSeconds = 0.0
        var mapSeconds = 0.0
        var tankSeconds = 0.0
        var guideSeconds = 0.0
        var objectiveSeconds = 0.0
        var bulletSeconds = 0.0
        var warningSeconds = 0.0
        var pickupSeconds = 0.0
        var effectSeconds = 0.0
        var bullets = 0
        var effects = 0
        var projectileCreations = 0
        var effectCreations = 0
        var mapRebuilds = 0
        var mapRasterSeconds = 0.0
        var mapInstallSeconds = 0.0
    }
    var profilesRendering = false
    private(set) var renderMetrics = RenderMetrics()
    private var frameProjectileCreations = 0
    private var frameEffectCreations = 0
    private var frameMapRebuilds = 0
    private var frameMapRasterSeconds = 0.0
    private var frameMapInstallSeconds = 0.0
    enum LayoutMode { case infinity, fixed }
    var onFrame: ((TimeInterval) -> Void)?
    var input = GameInput()
    private(set) var layoutMode: LayoutMode = .infinity
    private var landscape = false
    private var fixedLoadoutHeight: CGFloat = 97

    private let world = SKNode()
    private let wallLayer = SKNode()
    private let objectiveLayer = SKNode()
    private let pickupLayer = SKNode()
    private let tankLayer = SKNode()
    private let bulletLayer = SKNode()
    private let effectLayer = SKNode()
    private let labelLayer = SKNode()
    private let controls = SKNode()
    private let grid = SKShapeNode()
    private let mapImage = SKSpriteNode()
    private let controlBar = SKShapeNode()
    private let walls = SKShapeNode()
    private let wallShadows = SKShapeNode()
    private let stickBase = SKShapeNode(circleOfRadius: 57)
    private let stickKnob = SKShapeNode(circleOfRadius: 25)
    private let fireButton = SKShapeNode(circleOfRadius: 52)
    private let fireReadyRing = SKShapeNode()
    private let fireTrackRing = SKShapeNode(circleOfRadius: 53.5)
    private let centerHint = SKLabelNode(fontNamed: "Menlo-Regular")
    private let fireZoneCaption = SKLabelNode(fontNamed: "Menlo-Regular")
    private let aimingGuide = SKShapeNode()
    private let missileWarnings = ["homing": SKShapeNode(), "grenade": SKShapeNode()]
    private let moveCaption = SKLabelNode(fontNamed: "Menlo-Bold")
    private let fireCaption = SKLabelNode(fontNamed: "Menlo-Bold")

    private var tanks: [Int: TankNode] = [:]
    private var bullets: [Int: ProjectileNode] = [:]
    private var projectilePool: [ProjectileStyle: [ProjectileNode]] = [:]
    private var pooledProjectileCount = 0
    private var projectileFrame = 0
    private var projectileRemovalIDs: [Int] = []
    private var projectileTrails: [ProjectileStyle: SKShapeNode] = [:]
    private var pickups: [Int: PickupNode] = [:]
    private var objectiveState: ArenaObjectives?
    private var objectivePaint: [Int: Int] = [:]
    private var objectiveCarriers = ""
    private var seenEffects = Set<Int>()
    private var liveEffects: [TransientEffectNode] = []
    private var effectPool: [TransientEffectNode] = []
    private var effectOrder: [Int] = []
    private var stickTouch: UITouch?
    private var fireTouch: UITouch?
    private var stickOrigin = CGPoint.zero
    private var fireOrigin = CGPoint.zero
    private var previousTime: TimeInterval = 0
    private var frameDelta: Double = 1 / 120
    private var cameraPoint = CGPoint.zero
    private var hasCamera = false
    private var zoom: CGFloat = 1
    private var cachedRegion: CGRect?
    private var mapRequest = 0
    private var mapRasterTask: Task<Void, Never>?
    private var rasterizedMap: RasterizedMap?
    private var preloadingMap: (texture: SKTexture, raster: RasterizedMap)?
    private var preparedMap: (texture: SKTexture, raster: RasterizedMap)?
    private var fixedWallCount = -1
    private var fixedWorld: ArenaWorld?
    private var fixedGeometry: InfiniteMaze?
    private var renderGeometry: InfiniteMaze?
    private var guideKey = ""
    private var renderGeneration: Int?
    private var fireTitle = "FIRE"
    private var fireHintText = "HOLD TO FIRE"
    private var fireProgress = 1.0
    private var lastLocalSpawn = -1
    private var lastLocalHP = 0
    private var currentLocalID = -1
    private var isReady = false
    private let impact = UIImpactFeedbackGenerator(style: .light)

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Palette.arena
        isUserInteractionEnabled = true
        buildScene()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        buildScene()
    }

    private func buildScene() {
        guard !isReady else { return }
        isReady = true
        addChild(world)
        world.addChild(wallLayer)
        world.addChild(objectiveLayer)
        world.addChild(pickupLayer)
        world.addChild(tankLayer)
        world.addChild(bulletLayer)
        world.addChild(effectLayer)
        world.addChild(aimingGuide)
        aimingGuide.zPosition = 15
        aimingGuide.lineWidth = 1.3
        for (kind, warning) in missileWarnings {
            warning.strokeColor = Palette.power(kind)
            warning.lineWidth = 2.5
            warning.zPosition = 50
            world.addChild(warning)
        }
        addChild(labelLayer)
        addChild(controls)
        controls.zPosition = 200
        labelLayer.zPosition = 100
        pickupLayer.zPosition = 10
        objectiveLayer.zPosition = 5
        tankLayer.zPosition = 20
        bulletLayer.zPosition = 30
        effectLayer.zPosition = 40

        grid.strokeColor = UIColor(white: 0.8, alpha: 0.035)
        grid.lineWidth = 1
        wallLayer.addChild(grid)
        wallLayer.addChild(mapImage)
        wallShadows.fillColor = UIColor(hex: 0x080e13)
        wallShadows.strokeColor = .clear
        wallShadows.position.y = -4
        wallLayer.addChild(wallShadows)
        walls.fillColor = UIColor(hex: 0x35434b)
        walls.strokeColor = UIColor(hex: 0x667773)
        walls.lineWidth = 0.8
        wallLayer.addChild(walls)

        stickBase.fillColor = UIColor(hex: 0x101a23).withAlphaComponent(0.8)
        stickBase.strokeColor = Palette.accent.withAlphaComponent(0.45)
        stickBase.lineWidth = 1.5
        stickKnob.fillColor = Palette.accent.withAlphaComponent(0.22)
        stickKnob.strokeColor = Palette.accent.withAlphaComponent(0.85)
        stickKnob.lineWidth = 1.5
        fireButton.fillColor = UIColor(hex: 0x101a23).withAlphaComponent(0.9)
        fireButton.strokeColor = Palette.accent.withAlphaComponent(0.8)
        fireButton.lineWidth = 2
        for node in [stickBase, stickKnob, fireButton] { controls.addChild(node) }
        fireReadyRing.lineWidth = 3
        fireTrackRing.lineWidth = 3
        fireTrackRing.strokeColor = UIColor(hex: 0x324249).withAlphaComponent(0.33)
        controls.addChild(fireTrackRing)
        fireReadyRing.position = fireButton.position
        controls.addChild(fireReadyRing)
        for caption in [centerHint, fireZoneCaption] {
            caption.fontSize = 10
            caption.fontColor = UIColor(hex: 0x9babbb)
            caption.verticalAlignmentMode = .center
            controls.addChild(caption)
        }
        centerHint.numberOfLines = 2
        fireZoneCaption.text = "LET IT RIP"
        controlBar.fillColor = UIColor(hex: 0x192127)
        controlBar.strokeColor = UIColor(hex: 0x34434a)
        controlBar.lineWidth = 1
        controlBar.zPosition = -1
        controls.addChild(controlBar)
        for label in [moveCaption, fireCaption] {
            label.fontSize = 11
            label.fontColor = UIColor(hex: 0xdce9ef)
            label.verticalAlignmentMode = .center
            controls.addChild(label)
        }
        moveCaption.text = "STEER"
        fireCaption.text = "FIRE"
        let crosshair = SKShapeNode()
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -7, y: -7, width: 14, height: 14))
        for axis in [-1.0, 1.0] {
            path.move(to: CGPoint(x: axis * 5.25, y: 0))
            path.addLine(to: CGPoint(x: axis * 11.375, y: 0))
            path.move(to: CGPoint(x: 0, y: axis * 5.25))
            path.addLine(to: CGPoint(x: 0, y: axis * 11.375))
        }
        crosshair.path = path
        crosshair.strokeColor = Palette.accent
        crosshair.lineWidth = 1.575
        let center = SKShapeNode(circleOfRadius: 1.75)
        center.fillColor = Palette.accent
        center.strokeColor = Palette.accent
        crosshair.addChild(center)
        crosshair.position.y = 6
        fireButton.addChild(crosshair)
        layoutControls()
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        layoutControls()
        previousTime = 0
    }

    override func willMove(from view: SKView) {
        resetControls()
        previousTime = 0
    }

    override func didChangeSize(_ oldSize: CGSize) {
        cachedRegion = nil
        layoutControls()
    }

    func configureLayout(infinity: Bool, landscape: Bool, loadoutHeight: CGFloat) {
        let mode: LayoutMode = infinity ? .infinity : .fixed
        guard layoutMode != mode || self.landscape != landscape || fixedLoadoutHeight != loadoutHeight else { return }
        layoutMode = mode
        self.landscape = landscape
        fixedLoadoutHeight = loadoutHeight
        cachedRegion = nil
        layoutControls()
    }

    func configureReadiness(label: String, hint: String, progress: Double, locked: Bool) {
        fireTitle = label
        fireHintText = hint
        fireProgress = min(1, max(0, progress))
        fireCaption.text = label
        centerHint.text = hint
        let detonate = label == "BOOM"
        let color = UIColor(hex: detonate ? 0xffc46b : 0x40d5ff)
        fireButton.strokeColor = color.withAlphaComponent(0.63)
        fireCaption.fontColor = color
        fireReadyRing.strokeColor = color
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 53.5, startAngle: .pi / 2,
                    endAngle: .pi / 2 - CGFloat(fireProgress) * .pi * 2, clockwise: true)
        fireReadyRing.path = path
        fireButton.fillTexture = NativeArt.fireButton(held: fireTouch != nil, detonate: detonate)
        fireButton.fillColor = .white
    }

    private var worldViewport: CGRect {
        let reserve = layoutMode == .fixed && !landscape ? min(max(0, size.height - 60), 119 + fixedLoadoutHeight) : 0
        return CGRect(x: 0, y: reserve, width: max(1, size.width), height: max(1, size.height - reserve))
    }

    private func layoutControls() {
        let fixedPortrait = layoutMode == .fixed && !landscape
        let bottom: CGFloat = fixedPortrait ? 59.5 : 67.5
        let left: CGFloat = fixedPortrait ? 27 : 18
        stickOrigin = CGPoint(x: left + 66, y: bottom)
        fireOrigin = CGPoint(x: size.width - left - (fixedPortrait ? 58.5 : 45.5), y: bottom)
        stickBase.path = CGPath(ellipseIn: CGRect(x: -48, y: -48, width: 96, height: 96), transform: nil)
        stickKnob.path = CGPath(ellipseIn: CGRect(x: -22, y: -22, width: 44, height: 44), transform: nil)
        fireButton.path = CGPath(ellipseIn: CGRect(x: -45.5, y: -45.5, width: 91, height: 91), transform: nil)
        stickBase.fillColor = .white
        stickBase.fillTexture = NativeArt.stickBase()
        stickBase.strokeColor = UIColor(hex: 0x506d80)
        stickKnob.fillColor = .white
        stickKnob.fillTexture = NativeArt.stickKnob()
        stickKnob.strokeColor = UIColor(hex: 0x506d80)
        fireButton.fillColor = .white
        fireButton.fillTexture = NativeArt.fireButton(held: false, detonate: fireTitle == "BOOM")
        fireButton.strokeColor = UIColor(hex: 0x40d5ff).withAlphaComponent(0.63)
        stickBase.position = stickOrigin
        if stickTouch == nil { stickKnob.position = stickOrigin }
        fireButton.position = fireOrigin
        fireReadyRing.position = fireOrigin
        fireTrackRing.position = fireOrigin
        moveCaption.fontSize = 10
        moveCaption.fontName = "Menlo-Regular"
        moveCaption.fontColor = UIColor(hex: 0x9babbb)
        moveCaption.position = CGPoint(x: stickOrigin.x, y: 8)
        fireCaption.fontSize = 10
        fireCaption.fontName = "Menlo-Regular"
        fireCaption.fontColor = UIColor(hex: 0x40d5ff)
        fireCaption.position = CGPoint(x: fireOrigin.x, y: fireOrigin.y - 18)
        centerHint.isHidden = !fixedPortrait
        centerHint.preferredMaxLayoutWidth = max(40, size.width - 260)
        centerHint.text = fireHintText
        centerHint.position = CGPoint(x: size.width / 2, y: 59)
        fireZoneCaption.isHidden = !fixedPortrait
        fireZoneCaption.position = CGPoint(x: fireOrigin.x, y: 8)
        controlBar.isHidden = !fixedPortrait
        controlBar.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width, height: 119), transform: nil)
        // A screen-space label layer keeps names readable even when the map is
        // zoomed out on a small phone or in landscape.
        zoom = min(1.2, max(0.7, min(worldViewport.width, worldViewport.height) / 420))
        world.setScale(zoom)
        configureReadiness(label: fireTitle, hint: fireHintText, progress: fireProgress, locked: false)
    }

    func resetControls() {
        stickTouch = nil
        fireTouch = nil
        input.forward = false
        input.reverse = false
        input.left = false
        input.right = false
        input.fire = false
        input.stickX = 0
        input.stickY = 0
        input.touchAim = true
        input.aimOnly = false
        stickKnob.position = stickOrigin
        fireButton.fillTexture = NativeArt.fireButton(held: false, detonate: fireTitle == "BOOM")
        fireButton.fillColor = .white
    }

    func resetWorld() {
        resetControls()
        cancelMapPrefetch()
        hasCamera = false
        cachedRegion = nil
        fixedWallCount = -1
        fixedWorld = nil
        fixedGeometry = nil
        renderGeometry = nil
        renderGeneration = nil
        guideKey = ""
        aimingGuide.path = nil
        lastLocalSpawn = -1
        lastLocalHP = 0
        currentLocalID = -1
        previousTime = 0
        tanks.values.forEach { $0.removeFromParent(); $0.identity.removeFromParent() }
        for node in bullets.values { recycleProjectile(node) }
        for trail in projectileTrails.values { trail.path = nil; trail.isHidden = true }
        pickups.values.forEach { $0.removeFromParent() }
        tanks.removeAll()
        bullets.removeAll()
        pickups.removeAll()
        objectiveLayer.removeAllChildren()
        objectiveState = nil
        objectivePaint.removeAll()
        clearEffects()
        seenEffects.removeAll()
        effectOrder.removeAll()
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed = previousTime > 0 ? max(0, currentTime - previousTime) : 1 / 120
        frameDelta = min(0.05, elapsed)
        previousTime = currentTime
        // The session measures the actual callback rate and separately bounds
        // simulation catch-up. A hitch must not inflate its reported FPS.
        onFrame?(elapsed)
    }

    func display(snapshot: ArenaSnapshot, localID: Int, maze: InfiniteMaze?, fixedWalls: [MazeWall] = []) {
        let profiled = profilesRendering
        let started = profiled ? CACurrentMediaTime() : 0
        var checkpoint = started
        var metrics = RenderMetrics()
        if profiled {
            frameProjectileCreations = 0; frameEffectCreations = 0; frameMapRebuilds = 0
            frameMapRasterSeconds = 0; frameMapInstallSeconds = 0
        }
        func elapsed() -> Double {
            guard profiled else { return 0 }
            let now = CACurrentMediaTime(), duration = now - checkpoint
            checkpoint = now
            return duration
        }
        defer {
            if profiled {
                metrics.totalSeconds = CACurrentMediaTime() - started
                metrics.bullets = bullets.count
                metrics.effects = effectLayer.children.count
                metrics.projectileCreations = frameProjectileCreations
                metrics.effectCreations = frameEffectCreations
                metrics.mapRebuilds = frameMapRebuilds
                metrics.mapRasterSeconds = frameMapRasterSeconds
                metrics.mapInstallSeconds = frameMapInstallSeconds
                renderMetrics = metrics
            }
        }
        currentLocalID = localID
        if layoutMode == .fixed, let previous = renderGeneration, previous != snapshot.generation {
            cachedRegion = nil
            guideKey = ""
            objectiveState = nil
            objectiveCarriers = ""
            seenEffects.removeAll()
            effectOrder.removeAll()
            clearEffects()
        }
        renderGeneration = snapshot.generation
        if let world = snapshot.world, world != fixedWorld {
            fixedWorld = world
            fixedGeometry = InfiniteMaze(world: world)
            cachedRegion = nil
        }
        if layoutMode == .fixed, let fixed = fixedWorld {
            let reserve: CGFloat = landscape ? 252 : 0
            zoom = max(0.05, min((worldViewport.width - reserve - 12) / fixed.width, (worldViewport.height - 12) / fixed.height))
            world.setScale(zoom)
            cameraPoint = CGPoint(x: fixed.width / 2, y: fixed.height / 2)
            hasCamera = true
        }
        let focus = snapshot.tanks.first { $0.id == localID } ?? snapshot.tanks.first
        if let focus {
            let target = CGPoint(x: focus.x, y: focus.y)
            if layoutMode == .infinity {
                cameraPoint = target
                hasCamera = true
            }
            if focus.id == localID {
                if focus.hp == 0 && lastLocalHP > 0 { impact.impactOccurred(intensity: 0.7) }
                lastLocalHP = focus.hp
                lastLocalSpawn = focus.spawnSerial
            }
        }
        world.position = CGPoint(x: worldViewport.midX - cameraPoint.x * zoom,
                                 y: worldViewport.midY + cameraPoint.y * zoom)
        renderGeometry = maze ?? fixedGeometry
        let visible = visibleWorldBounds
        updateMap(maze: maze, fixedWalls: fixedWalls, visible: visible)
        metrics.mapSeconds = elapsed()
        synchronizeTanks(snapshot.tanks, localID: localID, visible: visible)
        metrics.tankSeconds = elapsed()
        updateGuide(tank: snapshot.tanks.first { $0.id == localID }, geometry: maze ?? fixedGeometry, snapshot: snapshot)
        metrics.guideSeconds = elapsed()
        synchronizeObjectives(snapshot.objectives, tanks: snapshot.tanks)
        metrics.objectiveSeconds = elapsed()
        synchronizeBullets(snapshot.bullets, visible: visible, time: CACurrentMediaTime())
        metrics.bulletSeconds = elapsed()
        updateMissileWarnings(snapshot: snapshot, localID: localID)
        metrics.warningSeconds = elapsed()
        synchronizePickups(snapshot.pickups)
        metrics.pickupSeconds = elapsed()
        let effectTime = CACurrentMediaTime()
        for index in liveEffects.indices.reversed() where !liveEffects[index].animate(at: effectTime) {
            let node = liveEffects.remove(at: index)
            node.removeFromParent()
            if effectPool.count < 32 { effectPool.append(node) }
        }
        for effect in snapshot.effects where !seenEffects.contains(effect.id) {
            seenEffects.insert(effect.id)
            effectOrder.append(effect.id)
            showEffect(effect, time: effectTime, visible: visible)
        }
        if effectOrder.count > 512 {
            for id in effectOrder.prefix(effectOrder.count - 512) { seenEffects.remove(id) }
            effectOrder.removeFirst(effectOrder.count - 512)
        }
        metrics.effectSeconds = elapsed()
    }

    private func updateGuide(tank: ArenaTank?, geometry: InfiniteMaze?, snapshot: ArenaSnapshot) {
        guard let tank, tank.hp > 0, let geometry,
              layoutMode == .fixed || tank.power == "laser" else { aimingGuide.path = nil; guideKey = ""; return }
        let key = "\(tank.x):\(tank.y):\(tank.angle):\(tank.power):\(layoutMode)" + (layoutMode == .fixed ? snapshot.tanks.map { "\($0.id):\($0.x):\($0.y):\($0.hp)" }.joined() : "")
        guard key != guideKey else { return }
        guideKey = key
        var points: [BeamPoint]
        let radius = tank.power == "laser" ? 3.0 : tank.power == "cannon" ? 14 : tank.power == "grenade" ? 6 : tank.power == "homing" ? 5 : tank.power == "rapid" ? 3.5 / 3 : 3.5
        if tank.ghostTime > 0, geometry.isMuzzleBlocked(x: tank.x, y: tank.y, kind: tank.power, radius: radius) {
            aimingGuide.path = nil; return
        }
        if tank.power == "laser" {
            points = geometry.laserGuide(x: tank.x, y: tank.y, angle: tank.angle,
                                        range: layoutMode == .fixed ? 2 * ((fixedWorld?.width ?? 756) + (fixedWorld?.height ?? 588)) : 18 * 84)
        } else {
            points = geometry.projectileGuide(x: tank.x, y: tank.y, angle: tank.angle, kind: tank.power,
                                             range: 112, radius: radius, maxSegments: tank.power == "cannon" ? 32 : 2)
        }
        if layoutMode == .fixed {
            var clipped: [BeamPoint] = []
            if let first = points.first { clipped.append(first) }
            for (first, last) in zip(points, points.dropFirst()) {
                let dx = last.x - first.x, dy = last.y - first.y, length = dx * dx + dy * dy
                var nearest = 1.0
                if length > 0 {
                    for other in snapshot.tanks where other.id != tank.id && other.hp > 0 && other.invulnerable <= 0 &&
                        (snapshot.rules?.friendlyFire == true || tank.team == 0 || other.team != tank.team) {
                        let px = first.x - other.x, py = first.y - other.y
                        let dot = px * dx + py * dy, c = px * px + py * py - pow(17 + radius, 2)
                        let discriminant = dot * dot - length * c
                        if c <= 0 { nearest = 0 }
                        else if dot < 0 && discriminant >= 0 {
                            let at = (-dot - sqrt(discriminant)) / length
                            if at >= 0 && at < nearest { nearest = at }
                        }
                    }
                }
                clipped.append(BeamPoint(x: first.x + dx * nearest, y: first.y + dy * nearest))
                if nearest < 1 { break }
            }
            points = clipped
        }
        guard let first = points.first, points.count > 1 else { aimingGuide.path = nil; return }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: first.x, y: -first.y))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: -point.y)) }
        aimingGuide.path = path.copy(dashingWithPhase: 0, lengths: [3, 7])
        aimingGuide.strokeColor = tank.power == "laser" && layoutMode == .infinity ? Palette.power("laser") : Palette.tank(tank.colorIndex)
        aimingGuide.alpha = tank.power == "laser" ? 0.48 : 0.28
    }

    private var visibleWorldBounds: CGRect {
        CGRect(x: cameraPoint.x - worldViewport.width / (2 * zoom),
               y: cameraPoint.y - worldViewport.height / (2 * zoom),
               width: worldViewport.width / zoom, height: worldViewport.height / zoom)
    }

    private func redrawWalls(_ items: [MazeWall], in region: CGRect) {
        if profilesRendering { frameMapRebuilds += 1 }
        mapImage.texture = NativeArt.map(walls: items, region: region, fixed: layoutMode == .fixed)
        mapImage.size = region.size
        mapImage.position = CGPoint(x: region.midX, y: -region.midY)
    }

    private func updateMap(maze: InfiniteMaze?, fixedWalls: [MazeWall], visible: CGRect) {
        if cachedRegion == nil || fixedWalls.count != fixedWallCount || layoutMode == .infinity && !cachedRegion!.contains(visible) {
            // A fresh world, rotation, or teleport needs immediate coverage.
            // Bootstrap only the visible area plus a short safety margin;
            // scrolling replacements are larger and never rasterize on main.
            cancelMapPrefetch()
            let region = layoutMode == .fixed && fixedWorld != nil
                ? CGRect(x: 0, y: 0, width: fixedWorld!.width, height: fixedWorld!.height)
                : visible.insetBy(dx: -96, dy: -96)
            let items = maze?.walls(x0: region.minX, y0: region.minY, x1: region.maxX, y1: region.maxY) ?? fixedWalls
            redrawWalls(items, in: region)
            cachedRegion = region; fixedWallCount = fixedWalls.count
        }
        if let ready = preparedMap, ready.raster.request == mapRequest {
            let began = CACurrentMediaTime()
            mapImage.texture = ready.texture
            mapImage.size = ready.raster.region.size
            mapImage.position = CGPoint(x: ready.raster.region.midX, y: -ready.raster.region.midY)
            cachedRegion = ready.raster.region
            preparedMap = nil; mapRasterTask = nil
            if profilesRendering { frameMapInstallSeconds += CACurrentMediaTime() - began }
        }
        if let raster = rasterizedMap, raster.request == mapRequest {
            rasterizedMap = nil
            let began = CACurrentMediaTime()
            let texture = SKTexture(image: raster.image)
            texture.filteringMode = .linear
            preloadingMap = (texture, raster)
            if profilesRendering {
                frameMapRasterSeconds = raster.seconds
                frameMapInstallSeconds += CACurrentMediaTime() - began
            }
            // Upload/decode before replacing the displayed texture. The old
            // map still covers the camera throughout both asynchronous stages.
            let request = raster.request
            texture.preload { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.mapRequest == request, let ready = self.preloadingMap,
                          ready.raster.request == request else { return }
                    self.preparedMap = ready
                    self.preloadingMap = nil
                }
            }
        }
        guard layoutMode == .infinity, mapRasterTask == nil, let region = cachedRegion,
              !region.insetBy(dx: 192, dy: 192).contains(visible), let maze else { return }
        let next = visible.insetBy(dx: -384, dy: -384)
        let items = maze.walls(x0: next.minX, y0: next.minY, x1: next.maxX, y1: next.maxY)
        let request = mapRequest
        if profilesRendering { frameMapRebuilds += 1 }
        let work = Task.detached(priority: .userInitiated) {
            let began = CACurrentMediaTime()
            let image = MapRasterizer.image(walls: items, region: next, fixed: false)
            return RasterizedMap(image: image, region: next, request: request, seconds: CACurrentMediaTime() - began)
        }
        mapRasterTask = Task { @MainActor [weak self] in
            let result = await work.value
            guard !Task.isCancelled, let self, self.mapRequest == result.request else { return }
            self.rasterizedMap = result
        }
    }

    private func cancelMapPrefetch() {
        mapRequest &+= 1
        mapRasterTask?.cancel(); mapRasterTask = nil
        rasterizedMap = nil; preloadingMap = nil; preparedMap = nil
    }

    private func synchronizeTanks(_ items: [ArenaTank], localID: Int, visible: CGRect) {
        let liveIDs = Set(items.map(\.id))
        for id in Array(tanks.keys) where !liveIDs.contains(id) {
            tanks[id]?.identity.removeFromParent()
            tanks.removeValue(forKey: id)?.removeFromParent()
        }
        for tank in items {
            let node: TankNode
            if let existing = tanks[tank.id] { node = existing }
            else {
                node = TankNode()
                tanks[tank.id] = node
                tankLayer.addChild(node)
                labelLayer.addChild(node.identity)
            }
            node.position = CGPoint(x: tank.x, y: -tank.y)
            node.update(tank, local: tank.id == localID, zoom: zoom, infinity: layoutMode == .infinity)
            let screen = CGPoint(x: world.position.x + CGFloat(tank.x) * zoom,
                                 y: world.position.y - CGFloat(tank.y) * zoom)
            node.identity.isHidden = tank.hp <= 0 || !visible.contains(CGPoint(x: tank.x, y: tank.y))
            let halfWidth = node.identityWidth / 2
            node.identity.position = CGPoint(x: min(max(screen.x, halfWidth + 5), max(halfWidth + 5, size.width - halfWidth - 5)),
                                             y: min(worldViewport.maxY - 6 - node.identityHeight, screen.y + 32 * zoom))
        }
    }

    private func synchronizeBullets(_ items: [ArenaBullet], visible: CGRect, time: Double) {
        projectileFrame &+= 1
        // Keep enough history outside the viewport for the longest seven-step
        // trail to enter smoothly. Simulation retains every offscreen bullet.
        let padded = visible.insetBy(dx: -160, dy: -160)
        var paths: [ProjectileStyle: CGMutablePath] = [:]
        for bullet in items {
            guard padded.contains(CGPoint(x: bullet.x, y: bullet.y)) else { continue }
            let style = ProjectileStyle(bullet)
            let node: ProjectileNode
            if let existing = bullets[bullet.id], existing.style == style { node = existing }
            else {
                if let previous = bullets.removeValue(forKey: bullet.id) { recycleProjectile(previous) }
                if let pooled = projectilePool[style]?.popLast() {
                    pooledProjectileCount -= 1
                    node = pooled
                    node.resetForReuse()
                } else {
                    node = ProjectileNode(style: style)
                    if profilesRendering { frameProjectileCreations += 1 }
                }
                bullets[bullet.id] = node
                bulletLayer.addChild(node)
            }
            node.lastSeenFrame = projectileFrame
            node.update(bullet, time: time)
            if style.kind != "rapid" {
                let path: CGMutablePath
                if let existing = paths[style] { path = existing }
                else { path = CGMutablePath(); paths[style] = path }
                node.appendTrail(to: path)
            }
        }
        projectileRemovalIDs.removeAll(keepingCapacity: true)
        for (id, node) in bullets where node.lastSeenFrame != projectileFrame { projectileRemovalIDs.append(id) }
        for id in projectileRemovalIDs {
            if let node = bullets.removeValue(forKey: id) { recycleProjectile(node) }
        }
        for (style, trail) in projectileTrails where paths[style] == nil { trail.isHidden = true }
        for (style, path) in paths {
            let trail: SKShapeNode
            if let existing = projectileTrails[style] { trail = existing }
            else {
                trail = SKShapeNode()
                trail.strokeColor = Palette.tank(style.colorIndex).withAlphaComponent(0.16)
                trail.lineWidth = style.kind == "cannon" ? 12 : style.kind == "homing" ? 4 : 3
                trail.lineCap = .round
                trail.zPosition = -1
                projectileTrails[style] = trail
                bulletLayer.addChild(trail)
            }
            trail.path = path
            trail.isHidden = false
        }
    }

    private func recycleProjectile(_ node: ProjectileNode) {
        node.removeFromParent()
        guard pooledProjectileCount < 512 else { return }
        projectilePool[node.style, default: []].append(node)
        pooledProjectileCount += 1
    }

    private func synchronizePickups(_ items: [ArenaPickup]) {
        let liveIDs = Set(items.map(\.id))
        for id in Array(pickups.keys) where !liveIDs.contains(id) { pickups.removeValue(forKey: id)?.removeFromParent() }
        for pickup in items {
            let node: PickupNode
            if let existing = pickups[pickup.id], existing.kind == pickup.type { node = existing }
            else {
                pickups[pickup.id]?.removeFromParent()
                node = PickupNode(kind: pickup.type)
                pickups[pickup.id] = node
                pickupLayer.addChild(node)
            }
            node.position = CGPoint(x: pickup.x, y: -pickup.y)
            node.update(life: pickup.life, time: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func updateMissileWarnings(snapshot: ArenaSnapshot, localID: Int) {
        for warning in missileWarnings.values { warning.path = nil }
        guard let tank = snapshot.tanks.first(where: { $0.id == localID }), tank.hp > 0,
              snapshot.phase == "playing", snapshot.result == nil else { return }
        var paths: [String: CGMutablePath] = [:]
        let incoming = snapshot.bullets.filter { ($0.kind == "homing" || $0.kind == "grenade") && $0.target == localID && $0.owner != localID }
        for bullet in incoming.prefix(3) {
            let path = paths[bullet.kind] ?? CGMutablePath()
            paths[bullet.kind] = path
            let angle = atan2(bullet.y - tank.y, bullet.x - tank.x), cs = cos(angle), sn = sin(angle)
            for (index, local) in [CGPoint(x: 41, y: -6), CGPoint(x: 35, y: 0), CGPoint(x: 41, y: 6)].enumerated() {
                let x = tank.x + Double(local.x) * cs - Double(local.y) * sn
                let y = tank.y + Double(local.x) * sn + Double(local.y) * cs
                if index == 0 { path.move(to: CGPoint(x: x, y: -y)) } else { path.addLine(to: CGPoint(x: x, y: -y)) }
            }
        }
        for (kind, path) in paths { missileWarnings[kind]?.path = path }
    }

    private func synchronizeObjectives(_ objectives: ArenaObjectives?, tanks: [ArenaTank]) {
        var teamPaint: [Int: Int] = [:]
        for tank in tanks where tank.team > 0 { teamPaint[tank.team] = tank.colorIndex }
        let carries = objectives?.flags.compactMap { flag in tanks.first { $0.id == flag.carrier }.map { "\($0.id):\($0.x):\($0.y)" } }.joined() ?? ""
        guard objectives != objectiveState || teamPaint != objectivePaint || carries != objectiveCarriers else { return }
        objectiveState = objectives
        objectivePaint = teamPaint
        objectiveCarriers = carries
        objectiveLayer.removeAllChildren()
        guard let objectives, !objectives.suddenDeath else { return }
        func teamColor(_ team: Int) -> UIColor { Palette.tank(teamPaint[team] ?? max(0, team - 1)) }
        if objectives.mode == "koth" {
            let owner = objectives.owner
            let ownerColor = owner > 0 ? teamColor(owner) : owner < 0 ? Palette.tank(tanks.first { $0.id == -owner - 1 }?.colorIndex ?? 0) : UIColor(hex: 0xe7eadd)
            let color = objectives.contested ? Palette.tank(1) : ownerColor
            let hill = SKShapeNode(circleOfRadius: max(1, objectives.radius))
            hill.position = CGPoint(x: objectives.hillX, y: -objectives.hillY)
            hill.fillColor = color.withAlphaComponent(0.168)
            hill.strokeColor = color
            hill.lineWidth = 2
            objectiveLayer.addChild(hill)
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = objectives.contested ? "CONTESTED" : "HILL"
            label.fontSize = max(10, 10 / zoom)
            label.fontColor = color
            label.verticalAlignmentMode = .center
            hill.addChild(label)
            if objectives.hold > 0 {
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: objectives.radius + 4,
                            startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * min(1, objectives.hold), clockwise: true)
                let progress = SKShapeNode(path: path)
                progress.strokeColor = color
                progress.lineWidth = 4
                hill.addChild(progress)
            }
        }
        for flag in objectives.flags {
            let color = teamColor(flag.team)
            let base = SKShapeNode()
            base.path = CGPath(ellipseIn: CGRect(x: -32, y: -32, width: 64, height: 64), transform: nil).copy(dashingWithPhase: 0, lengths: [5, 4])
            base.position = CGPoint(x: flag.homeX, y: -flag.homeY)
            base.fillColor = color.withAlphaComponent(0.157)
            base.strokeColor = color
            base.lineWidth = 3
            objectiveLayer.addChild(base)
            let carrier = tanks.first { $0.id == flag.carrier }
            let ax = carrier?.x ?? flag.x, ay = carrier?.y ?? flag.y
            let scale = max(1.35, 1 / zoom)
            let width = fixedWorld?.width ?? 2000, height = fixedWorld?.height ?? 2000
            let x = min(max(ax, 40 * scale), max(40 * scale, width - 40 * scale))
            let y = min(max(ay - (carrier != nil ? 44 : 12) * scale, 26 * scale), max(26 * scale, height - 36 * scale))
            let tether = CGMutablePath()
            tether.addEllipse(in: CGRect(x: ax - 24, y: -ay - 24, width: 48, height: 48))
            tether.move(to: CGPoint(x: ax, y: -ay))
            tether.addLine(to: CGPoint(x: x, y: -y - 12 * scale))
            let line = SKShapeNode(path: tether)
            line.strokeColor = color.withAlphaComponent(0.8)
            line.lineWidth = 2 / zoom
            objectiveLayer.addChild(line)
            let marker = SKSpriteNode(texture: NativeArt.flag(team: flag.team, color: teamPaint[flag.team] ?? max(0, flag.team - 1)))
            marker.size = CGSize(width: 46 * scale, height: 48 * scale)
            marker.position = CGPoint(x: x, y: -y)
            objectiveLayer.addChild(marker)
        }
    }

    private func clearEffects() {
        for node in liveEffects {
            node.removeFromParent()
            if effectPool.count < 32 { effectPool.append(node) }
        }
        liveEffects.removeAll(keepingCapacity: true)
    }

    private func showEffect(_ effect: ArenaEffect, time: Double, visible: CGRect) {
        guard !effect.kind.hasPrefix("shot"),
              ["laser", "pickup", "shield", "hit", "blast", "impact"].contains(effect.kind) else { return }
        let padded = visible.insetBy(dx: -260, dy: -260)
        if effect.kind == "laser" {
            guard effect.points.count > 1 else { return }
            var x0 = effect.points[0].x, x1 = x0, y0 = effect.points[0].y, y1 = y0
            for point in effect.points.dropFirst() { x0 = min(x0, point.x); x1 = max(x1, point.x); y0 = min(y0, point.y); y1 = max(y1, point.y) }
            let bounds = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            guard padded.intersects(bounds.insetBy(dx: -14, dy: -14)) else { return }
        } else if !padded.contains(CGPoint(x: effect.x, y: effect.y)) { return }
        let node: TransientEffectNode
        // The browser keeps the newest 32 effects. Reusing its oldest visual
        // preserves that budget while never touching authoritative events.
        if liveEffects.count >= 32 { node = liveEffects.removeFirst() }
        else if let pooled = effectPool.popLast() { node = pooled }
        else {
            node = TransientEffectNode()
            if profilesRendering { frameEffectCreations += 1 }
        }
        node.configure(effect, geometry: renderGeometry, infinity: layoutMode == .infinity, time: time)
        if node.parent == nil { effectLayer.addChild(node) }
        liveEffects.append(node)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            if stickTouch == nil && location.x < size.width / 2 && location.y < size.height * 0.75 {
                stickTouch = touch
                updateStick(location)
            } else if fireTouch == nil && location.x >= size.width / 2 && location.y < max(210, size.height * 0.38) {
                fireTouch = touch
                input.fire = true
                fireButton.fillTexture = NativeArt.fireButton(held: true, detonate: fireTitle == "BOOM")
                impact.prepare()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touch === stickTouch { updateStick(touch.location(in: self)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch === stickTouch {
                stickTouch = nil
                input.stickX = 0
                input.stickY = 0
                stickKnob.position = stickOrigin
            }
            if touch === fireTouch {
                fireTouch = nil
                input.fire = false
                fireButton.fillTexture = NativeArt.fireButton(held: false, detonate: fireTitle == "BOOM")
            }
        }
    }

    private func updateStick(_ point: CGPoint) {
        let dx = point.x - stickOrigin.x
        let dy = point.y - stickOrigin.y
        let length = hypot(dx, dy)
        let reach: CGFloat = 29
        let divisor = max(reach, length)
        input.stickX = Double(dx / divisor)
        input.stickY = Double(-dy / divisor)
        input.touchAim = true
        input.aimOnly = false
        stickKnob.position = CGPoint(x: stickOrigin.x + dx * reach / divisor,
                                    y: stickOrigin.y + dy * reach / divisor)
    }
}

@MainActor
private final class TankNode: SKNode {
    let identity = SKNode()
    private let identityBackground = SKShapeNode()
    private let nameLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let hull = SKNode()
    private let body = SKSpriteNode()
    private let barrel = SKSpriteNode()
    private let turret = SKSpriteNode()
    private let protectionRing = SKShapeNode()
    private let localRing = SKShapeNode()
    private let ghostRing = SKShapeNode()
    private let speedLines = SKShapeNode()
    private var shieldRings: [SKShapeNode] = []
    private var starRings: [SKShapeNode] = []
    private var badges: [String: PowerBadgeNode] = [:]
    private var currentText = ""
    private var textureKey = ""
    private var previousSpeed = -1
    private var protectionRadius: CGFloat = -1
    private var fontSize: CGFloat = 0
    private(set) var paint = Palette.accent
    private(set) var identityWidth: CGFloat = 120
    private(set) var identityHeight: CGFloat = 20

    override init() {
        super.init()
        addChild(hull)
        hull.addChild(speedLines)
        hull.addChild(body)
        hull.addChild(barrel)
        hull.addChild(turret)
        body.size = CGSize(width: 48, height: 48)
        body.zPosition = 1
        barrel.size = CGSize(width: 32, height: 12)
        barrel.zPosition = 2
        barrel.anchorPoint = CGPoint(x: 0, y: 0.5)
        turret.size = CGSize(width: 24, height: 24)
        turret.zPosition = 3
        speedLines.strokeColor = Palette.power("speed")
        speedLines.lineWidth = 2
        for ring in [protectionRing, localRing, ghostRing] {
            ring.fillColor = .clear
            ring.lineWidth = 1.6
            addChild(ring)
        }
        let halo = CGPath(ellipseIn: CGRect(x: -23, y: -23, width: 46, height: 46), transform: nil)
        localRing.path = halo.copy(dashingWithPhase: 0, lengths: [3, 6])
        localRing.lineWidth = 1
        ghostRing.path = CGPath(roundedRect: CGRect(x: -23, y: -21, width: 46, height: 42), cornerWidth: 9, cornerHeight: 9, transform: nil).copy(dashingWithPhase: 0, lengths: [3, 4])
        ghostRing.strokeColor = Palette.power("ghost")
        for index in 0..<5 {
            let shield = SKShapeNode(circleOfRadius: 26 + CGFloat(index) * 4)
            shield.strokeColor = Palette.power("shield")
            shield.lineWidth = 1.6
            shield.alpha = 0.78
            addChild(shield)
            shieldRings.append(shield)
            let path = CGMutablePath()
            let start = -CGFloat(index) * .pi * 2 / 5
            path.addArc(center: .zero, radius: 24, startAngle: start, endAngle: start - .pi * 2 * 0.85 / 5, clockwise: true)
            let star = SKShapeNode(path: path)
            star.strokeColor = UIColor(hex: [0xff758f, 0xf9ed75, 0x79d878, 0x62dcff, 0xba91ff][index])
            star.lineWidth = 2.5
            addChild(star)
            starRings.append(star)
        }
        identity.addChild(identityBackground)
        identity.addChild(nameLabel)
        identityBackground.fillColor = UIColor(hex: 0x0e171d).withAlphaComponent(0.86)
        identityBackground.strokeColor = .clear
        nameLabel.numberOfLines = 0
        nameLabel.preferredMaxLayoutWidth = 180
        nameLabel.verticalAlignmentMode = .bottom
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.position.y = 3
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ tank: ArenaTank, local: Bool, zoom: CGFloat, infinity: Bool) {
        isHidden = infinity && tank.hp <= 0
        paint = Palette.tank(tank.colorIndex)
        hull.zRotation = -tank.angle
        hull.alpha = tank.hp <= 0 ? 0.6 : tank.ghostTime > 0 ? (tank.starmanTime > 0 ? 0.84 : 0.58) : 1
        let phase = ((Int(floor(tank.track / 2)) % 4) + 4) % 4
        let nextKey = "\(tank.colorIndex):\(phase):\(tank.hp > 0)"
        if textureKey != nextKey {
            textureKey = nextKey
            body.texture = tank.hp > 0 ? NativeArt.hull(color: tank.colorIndex, phase: phase) : NativeArt.wreck()
            barrel.texture = NativeArt.barrel(color: tank.colorIndex)
            turret.texture = NativeArt.turret(color: tank.colorIndex)
        }
        barrel.isHidden = tank.hp <= 0
        turret.isHidden = tank.hp <= 0
        barrel.position.x = -tank.recoil * 4
        let shields = tank.hp > 0 && tank.shield > 0 ? max(1, min(5, tank.shieldCharges)) : 0
        for (index, ring) in shieldRings.enumerated() { ring.isHidden = index >= shields }
        protectionRing.isHidden = tank.hp <= 0 || shields > 0 || tank.invulnerable <= 0
        let nextProtectionRadius: CGFloat = local && tank.invulnerable > 0 ? 34 : 25
        if protectionRadius != nextProtectionRadius {
            protectionRadius = nextProtectionRadius
            protectionRing.path = CGPath(ellipseIn: CGRect(x: -protectionRadius, y: -protectionRadius, width: protectionRadius * 2, height: protectionRadius * 2), transform: nil)
        }
        protectionRing.strokeColor = local ? paint : UIColor(hex: 0xd8e9c5)
        protectionRing.alpha = 0.55
        localRing.isHidden = !local || tank.hp <= 0 || tank.invulnerable > 0 || shields > 0
        localRing.strokeColor = paint.withAlphaComponent(0.2)
        ghostRing.isHidden = infinity || tank.ghostTime <= 0 || tank.hp <= 0
        ghostRing.zRotation = hull.zRotation
        for ring in starRings { ring.isHidden = tank.starmanTime <= 0 || tank.hp <= 0 }
        let speed = tank.hp > 0 && tank.speedTime > 0 ? max(1, min(5, tank.speedStacks)) : 0
        speedLines.isHidden = speed == 0
        if previousSpeed != speed {
            previousSpeed = speed
            let path = CGMutablePath()
            for index in 0..<speed {
                for side in [-1.0, 1] {
                    let y = side * (8 + Double(index) * 2.2)
                    path.move(to: CGPoint(x: -22, y: y))
                    path.addLine(to: CGPoint(x: -34 - Double(index) * 3, y: y))
                }
            }
            speedLines.path = path
        }
        let text = local ? tank.name + " (P1)" : tank.name
        nameLabel.fontColor = paint
        let size = max(10, infinity ? 11 * zoom : 10 * zoom)
        if currentText != text || abs(fontSize - size) > 0.01 {
            currentText = text
            fontSize = size
            nameLabel.fontName = local ? "Menlo-Bold" : "Menlo-Regular"
            nameLabel.fontSize = size
            nameLabel.fontColor = paint
            nameLabel.text = text
            identityWidth = max(36, min(190, nameLabel.frame.width + 10))
            identityHeight = nameLabel.frame.height + 7
            identityBackground.path = CGPath(roundedRect: CGRect(x: -identityWidth / 2, y: 0, width: identityWidth, height: identityHeight), cornerWidth: 3, cornerHeight: 3, transform: nil)
        }
        var kinds: [String] = []
        if !tank.power.isEmpty && tank.powerTime > 0 { kinds.append(tank.power) }
        if shields > 0 { kinds.append("shield") }
        if speed > 0 { kinds.append("speed") }
        if tank.starmanTime > 0 { kinds.append("starman") }
        else if tank.ghostTime > 0 { kinds.append("ghost") }
        for (kind, badge) in badges { badge.isHidden = !kinds.contains(kind) || tank.hp <= 0 }
        let scale = max(1, 0.72 / max(0.05, zoom))
        let badgeSize = 24 * scale, inkRadius = badgeSize * 28.5 / 64
        let radius = max(30 + inkRadius + 1.5 * scale, (inkRadius * 2 + 1.5 * scale) / (2 * sin(.pi / 8)))
        for (index, kind) in kinds.prefix(4).enumerated() {
            let badge: PowerBadgeNode
            if let existing = badges[kind] { badge = existing }
            else { badge = PowerBadgeNode(kind: kind); badge.zPosition = 5; badges[kind] = badge; addChild(badge) }
            let angle = CGFloat(index) * .pi / 4
            badge.position = CGPoint(x: cos(angle) * radius, y: -sin(angle) * radius)
            let life = kind == "shield" ? tank.shield : kind == "speed" ? tank.speedTime : kind == "ghost" ? tank.ghostTime : kind == "starman" ? tank.starmanTime : tank.powerTime + tank.starmanTime
            let count: Int? = kind == "shield" ? shields : kind == "speed" ? speed : kind == "rapid" ? tank.machineRounds : kind == tank.power ? tank.charges : nil
            badge.update(size: badgeSize, zoom: zoom, count: count, remaining: life, warning: kind == "starman" ? 1 : 3)
            badge.isHidden = tank.hp <= 0
        }
    }
}

@MainActor
private final class PowerBadgeNode: SKNode {
    private let art = SKSpriteNode()
    private let countBackground = SKShapeNode()
    private let countLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private var previousSize: CGFloat = -1
    private var previousFontSize: CGFloat = -1
    private var previousCount: Int?
    init(kind: String) {
        super.init()
        art.texture = NativeArt.badge(kind: kind)
        addChild(art)
        countBackground.fillColor = UIColor(hex: 0x08131b).withAlphaComponent(0.96)
        countBackground.strokeColor = .clear
        addChild(countBackground)
        countLabel.fontColor = UIColor(hex: 0xf3f8ff)
        countLabel.horizontalAlignmentMode = .right
        countLabel.verticalAlignmentMode = .bottom
        addChild(countLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(size: CGFloat, zoom: CGFloat, count: Int?, remaining: Double, warning: Double) {
        let nextFontSize = max(10 * size / 24, 10 / max(0.05, zoom))
        let changed = previousSize != size || previousFontSize != nextFontSize || previousCount != count
        if previousSize != size { art.size = CGSize(width: size, height: size) }
        let fade = min(1, max(0, remaining / warning))
        alpha = CGFloat(fade * fade * (3 - 2 * fade))
        countLabel.isHidden = count == nil
        countBackground.isHidden = count == nil
        if let count, changed {
            countLabel.fontSize = nextFontSize
            countLabel.text = String(count)
            countLabel.position = CGPoint(x: size / 2 - 2, y: -size / 2 + 1)
            let width = countLabel.frame.width + 4, height = countLabel.frame.height + 2
            countBackground.path = CGPath(roundedRect: CGRect(x: size / 2 - width, y: -size / 2, width: width, height: height), cornerWidth: 2, cornerHeight: 2, transform: nil)
        }
        previousSize = size; previousFontSize = nextFontSize; previousCount = count
    }
}

@MainActor
private final class ProjectileNode: SKNode {
    let style: ProjectileStyle
    var lastSeenFrame = 0
    private let glyph = SKNode()
    private let fuse = SKShapeNode()
    private let flame = SKSpriteNode()
    private var history: [CGPoint] = []
    private var previousBounce = -1
    private var lastTrailTime = -Double.infinity
    private var fuseStep = -1
    private var previousVX = Double.nan
    private var previousVY = Double.nan

    init(style: ProjectileStyle) {
        self.style = style
        super.init()
        addChild(glyph)
        let art = SKSpriteNode(texture: NativeArt.projectile(kind: style.kind, color: style.colorIndex))
        art.size = CGSize(width: style.kind == "cannon" ? 40 : 24, height: style.kind == "cannon" ? 40 : 24)
        glyph.addChild(art)
        if style.kind == "grenade" {
            fuse.strokeColor = Palette.power("grenade")
            fuse.lineWidth = 2
            glyph.addChild(fuse)
        } else if style.kind == "homing" {
            flame.texture = NativeArt.missileFlame()
            flame.anchorPoint = CGPoint(x: 1, y: 0.5)
            flame.position.x = -7
            flame.size.height = 6
            glyph.addChild(flame)
        }
        history.reserveCapacity(7)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func resetForReuse() {
        history.removeAll(keepingCapacity: true)
        previousBounce = -1
        lastTrailTime = -.infinity
        fuseStep = -1
        previousVX = .nan; previousVY = .nan
    }

    func update(_ bullet: ArenaBullet, time: Double) {
        position = CGPoint(x: bullet.x, y: -bullet.y)
        if previousVX != bullet.vx || previousVY != bullet.vy {
            previousVX = bullet.vx; previousVY = bullet.vy
            glyph.zRotation = -atan2(bullet.vy, bullet.vx)
        }
        if style.kind == "grenade" {
            // One angular step is less than a physical pixel at the fuse's
            // radius. Reuse static paths instead of retessellating every tick.
            let step = Int((min(1, max(0, bullet.life / 10)) * 256).rounded())
            if step != fuseStep { fuseStep = step; fuse.path = NativeArt.grenadeFuse(step: step) }
        } else if style.kind == "homing" {
            flame.size.width = CGFloat(9 + sin(time * 30) * 4)
        }
        if style.kind != "rapid" {
            if bullet.bounces != previousBounce { history.removeAll(keepingCapacity: true); previousBounce = bullet.bounces }
            if time - lastTrailTime >= 1 / 60 - 0.000001 {
                history.append(position)
                if history.count > 7 { history.removeFirst(history.count - 7) }
                lastTrailTime = time
            }
        }
    }

    func appendTrail(to path: CGMutablePath) {
        guard let first = history.first else { return }
        path.move(to: first)
        for point in history.dropFirst() { path.addLine(to: point) }
        path.addLine(to: position)
    }
}

@MainActor
private final class TransientEffectNode: SKNode {
    private let glow = SKShapeNode()
    private let color = SKShapeNode()
    private let core = SKShapeNode()
    private let ring = SKShapeNode()
    private static let ringPath = CGPath(ellipseIn: CGRect(x: -14, y: -14, width: 28, height: 28), transform: nil)
    private var began = 0.0
    private var duration = 0.43
    private var laser = false
    private var blast = false
    private var endScale = 1.0

    override init() {
        super.init()
        for node in [glow, color, core] { node.lineCap = .round; addChild(node) }
        core.strokeColor = UIColor(hex: 0xfff2ff)
        core.lineWidth = 2
        core.zPosition = 1
        addChild(ring)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ effect: ArenaEffect, geometry: InfiniteMaze?, infinity: Bool, time: Double) {
        began = time
        laser = effect.kind == "laser"
        blast = effect.kind == "blast"
        duration = laser ? (infinity ? 0.18 : 0.23) : 0.43
        alpha = laser ? 1 : 0.8
        setScale(1)
        position = laser ? .zero : CGPoint(x: effect.x, y: -effect.y)
        glow.isHidden = !laser; color.isHidden = !laser || infinity
        core.isHidden = !laser; ring.isHidden = laser
        if laser {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: effect.points[0].x, y: -effect.points[0].y))
            for point in effect.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: -point.y)) }
            glow.path = path; color.path = path; core.path = path
            glow.strokeColor = Palette.power("laser").withAlphaComponent(infinity ? 0.45 : 0.2)
            glow.lineWidth = infinity ? 7 : 14
            color.strokeColor = Palette.power("laser"); color.lineWidth = 6
        } else {
            let paint = effect.kind == "hit" ? UIColor(hex: 0xf7ecbb) : Palette.power(blast ? "grenade" : effect.kind)
            ring.strokeColor = paint
            ring.lineWidth = blast ? 3 : 2
            ring.fillColor = .clear
            if blast, let geometry {
                let path = CGMutablePath()
                for index in 0..<24 {
                    let angle = Double(index) * .pi * 2 / 24
                    let end = geometry.projectileGuide(x: effect.x, y: effect.y, angle: angle, kind: "", range: 220, radius: 0, maxSegments: 1).last ?? BeamPoint(x: effect.x, y: effect.y)
                    let point = CGPoint(x: end.x - effect.x, y: effect.y - end.y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath(); ring.path = path
                ring.fillColor = paint.withAlphaComponent(0.11)
                endScale = 1
                setScale(0.65)
            } else {
                ring.path = Self.ringPath
                endScale = (14 + (effect.kind == "hit" ? 56 : 35)) / 14
            }
        }
    }

    func animate(at time: Double) -> Bool {
        let age = max(0, (time - began) / duration)
        guard age < 1 else { return false }
        alpha = CGFloat((laser ? 1.0 : 0.8) * (1 - age))
        if !laser { setScale(CGFloat(blast && endScale == 1 ? 0.65 + 0.35 * age : 1 + (endScale - 1) * age)) }
        return true
    }
}

@MainActor
private final class PickupNode: SKNode {
    let kind: String
    private let halo = SKShapeNode(rectOf: CGSize(width: 36, height: 36), cornerRadius: 9)
    private let art = SKSpriteNode()
    init(kind: String) {
        self.kind = kind
        super.init()
        halo.strokeColor = Palette.power(kind).withAlphaComponent(0.2)
        halo.lineWidth = 1.5
        addChild(halo)
        art.texture = NativeArt.pickup(kind: kind)
        art.size = CGSize(width: 42, height: 42)
        art.zPosition = 1
        addChild(art)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(life: Double, time: Double) {
        let pulse = sin(time * 3 + Double(position.x)) * 0.5 + 0.5
        halo.setScale(1 + CGFloat(pulse) / 18)
        alpha = life < 3 ? CGFloat(0.5 + 0.4 * sin(time * 12)) : 1
    }
}

/// These native drawing commands mirror paintTankHull, paintTankTurret,
/// paintArenaTile and paintArenaWall in the browser client. Small repeating
/// artwork is cached as textures so it does not add dozens of shape draws per
/// tank to every ProMotion frame.
@MainActor
private enum NativeArt {
    private static var cache: [String: SKTexture] = [:]
    private static var fusePaths: [Int: CGPath] = [:]

    static func projectile(kind: String, color: Int) -> SKTexture {
        let width: CGFloat = kind == "cannon" ? 40 : 24
        return cached("projectile:\(kind):\(color)", size: CGSize(width: width, height: width)) { context in
            context.translateBy(x: width / 2, y: width / 2)
            context.scaleBy(x: 1, y: -1)
            let paint = Palette.tank(color)
            context.setFillColor((kind == "grenade" ? UIColor(hex: 0x253039) : paint).cgColor)
            let radius: CGFloat = kind == "cannon" ? 18 : kind == "grenade" ? 6 : kind == "rapid" ? 3.5 / 3 : 4.5
            if kind == "homing" {
                context.move(to: CGPoint(x: 10, y: 0))
                for point in [CGPoint(x: -4, y: 5), CGPoint(x: -8, y: 8), CGPoint(x: -6, y: 0), CGPoint(x: -8, y: -8), CGPoint(x: -4, y: -5)] { context.addLine(to: point) }
                context.closePath(); context.fillPath()
                context.setFillColor(UIColor(hex: 0xfff6e5).cgColor)
                context.fill(CGRect(x: -1, y: -1.5, width: 6, height: 3))
            } else {
                context.fillEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
                if kind == "rapid" {
                    context.setFillColor(paint.withAlphaComponent(0.55).cgColor)
                    context.fill(CGRect(x: -8, y: -3.5 / 3, width: 8, height: 3.5 * 2 / 3))
                } else if kind == "grenade" {
                    context.setStrokeColor(paint.cgColor); context.setLineWidth(2)
                    context.strokeEllipse(in: CGRect(x: -6, y: -6, width: 12, height: 12))
                    context.setFillColor(Palette.power("grenade").cgColor)
                    context.fillEllipse(in: CGRect(x: -2, y: 0, width: 4, height: 4))
                } else {
                    let core: CGFloat = kind == "cannon" ? 8.4 : 2.1
                    context.setFillColor(UIColor(hex: 0xfbffe8).cgColor)
                    context.fillEllipse(in: CGRect(x: -core, y: -core, width: core * 2, height: core * 2))
                }
            }
        }
    }

    static func missileFlame() -> SKTexture {
        cached("missileFlame", size: CGSize(width: 13, height: 6)) { context in
            context.setFillColor(Palette.power("homing").withAlphaComponent(0.8).cgColor)
            context.move(to: CGPoint(x: 13, y: 0)); context.addLine(to: CGPoint(x: 0, y: 3)); context.addLine(to: CGPoint(x: 13, y: 6))
            context.closePath(); context.fillPath()
        }
    }

    static func grenadeFuse(step: Int) -> CGPath {
        if let path = fusePaths[step] { return path }
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 10, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2 * CGFloat(step) / 256, clockwise: true)
        fusePaths[step] = path
        return path
    }

    private static func image(size: CGSize, scale: CGFloat = 3, draw: (CGContext) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let result = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        let texture = SKTexture(image: result)
        texture.filteringMode = .linear
        return texture
    }

    private static func cached(_ key: String, size: CGSize, draw: (CGContext) -> Void) -> SKTexture {
        if let texture = cache[key] { return texture }
        let texture = image(size: size, draw: draw)
        cache[key] = texture
        return texture
    }

    private static func rounded(_ context: CGContext, _ rect: CGRect, _ radius: CGFloat, _ color: UIColor) {
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }

    static func hull(color: Int, phase: Int) -> SKTexture {
        cached("hull:\(color):\(phase)", size: CGSize(width: 48, height: 48)) { context in
            context.translateBy(x: 24, y: 24)
            rounded(context, CGRect(x: -20, y: -11, width: 40, height: 31), 6, UIColor(hex: 0x02080b).withAlphaComponent(0.66))
            for side in [-1, 1] {
                rounded(context, CGRect(x: -19, y: side < 0 ? -17 : 9, width: 37, height: 9), 3, UIColor(hex: 0x0b1116))
                context.setStrokeColor(UIColor(hex: 0x849392).withAlphaComponent(0.65).cgColor)
                context.setLineWidth(1)
                for index in 0..<7 {
                    let x = -16 + index * 5 + phase
                    context.move(to: CGPoint(x: x, y: side < 0 ? -16 : 10))
                    context.addLine(to: CGPoint(x: x, y: side < 0 ? -10 : 16))
                }
                context.strokePath()
            }
            rounded(context, CGRect(x: -17, y: -12, width: 34, height: 24), 5, Palette.tank(color))
            rounded(context, CGRect(x: -15, y: -10, width: 7, height: 20), 2, UIColor.black.withAlphaComponent(0.19))
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.345).cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: -12, y: -10)); context.addLine(to: CGPoint(x: 12, y: -10)); context.strokePath()
            context.setFillColor(UIColor(hex: 0x0c1518).withAlphaComponent(0.4).cgColor)
            context.fill(CGRect(x: -12, y: -6, width: 3, height: 12))
        }
    }

    static func barrel(color: Int) -> SKTexture {
        cached("barrel:\(color)", size: CGSize(width: 32, height: 12)) { context in
            context.translateBy(x: 0, y: 6)
            rounded(context, CGRect(x: 4, y: -4.5, width: 26, height: 9), 2, UIColor(hex: 0x0a121a))
            context.setFillColor(Palette.tank(color).cgColor)
            context.fill(CGRect(x: 5, y: -3, width: 23, height: 6))
            context.setFillColor(UIColor(hex: 0xe4f0d9).withAlphaComponent(0.54).cgColor)
            context.fill(CGRect(x: 26, y: -3.5, width: 3, height: 7))
        }
    }

    static func turret(color: Int) -> SKTexture {
        cached("turret:\(color)", size: CGSize(width: 24, height: 24)) { context in
            context.translateBy(x: 12, y: 12)
            context.setFillColor(UIColor.black.withAlphaComponent(0.26).cgColor)
            context.fillEllipse(in: CGRect(x: -9.5, y: -7.5, width: 19, height: 19))
            context.setFillColor(Palette.tank(color).cgColor)
            context.setStrokeColor(UIColor(hex: 0x091219).withAlphaComponent(0.44).cgColor)
            context.setLineWidth(2)
            context.addEllipse(in: CGRect(x: -9, y: -9, width: 18, height: 18))
            context.drawPath(using: .fillStroke)
            context.setFillColor(UIColor(hex: 0x172124).cgColor)
            context.fillEllipse(in: CGRect(x: -4.2, y: -3.2, width: 6.4, height: 6.4))
        }
    }

    static func wreck() -> SKTexture {
        cached("wreck", size: CGSize(width: 48, height: 48)) { context in
            context.translateBy(x: 24, y: 24)
            rounded(context, CGRect(x: -18, y: -16, width: 36, height: 32), 5, UIColor(hex: 0x091116))
            context.setStrokeColor(UIColor(hex: 0x46545a).cgColor)
            context.setLineWidth(2)
            context.move(to: CGPoint(x: -8, y: -8)); context.addLine(to: CGPoint(x: 8, y: 8))
            context.move(to: CGPoint(x: 8, y: -8)); context.addLine(to: CGPoint(x: -8, y: 8)); context.strokePath()
        }
    }

    static func badge(kind: String) -> SKTexture {
        cached("badge:\(kind)", size: CGSize(width: 64, height: 64)) { context in
            context.translateBy(x: 32, y: 32)
            context.setFillColor(UIColor(hex: 0x0b141b).withAlphaComponent(0.91).cgColor)
            context.setStrokeColor(Palette.power(kind).cgColor)
            context.setLineWidth(3)
            context.addEllipse(in: CGRect(x: -27, y: -27, width: 54, height: 54))
            context.drawPath(using: .fillStroke)
            context.scaleBy(x: 1.38, y: 1.38)
            drawPower(kind, context)
        }
    }

    static func stickBase() -> SKTexture {
        cached("stick-base", size: CGSize(width: 96, height: 96)) { context in
            let center = CGPoint(x: 48, y: 48)
            let colors = [UIColor(hex: 0x324249).cgColor, UIColor(hex: 0x232e33).cgColor, UIColor(hex: 0x192127).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.64, 0.65])!
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 48, options: .drawsAfterEndLocation)
            context.setStrokeColor(UIColor(hex: 0x111a1f).cgColor)
            context.setLineWidth(8)
            context.strokeEllipse(in: CGRect(x: 4.5, y: 4.5, width: 87, height: 87))
            context.setStrokeColor(UIColor(hex: 0x324249).withAlphaComponent(0.165).cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: 12, y: 47)); context.addLine(to: CGPoint(x: 82, y: 47))
            context.move(to: CGPoint(x: 47, y: 12)); context.addLine(to: CGPoint(x: 47, y: 82)); context.strokePath()
        }
    }

    static func stickKnob() -> SKTexture {
        cached("stick-knob", size: CGSize(width: 44, height: 44)) { context in
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(hex: 0x324249).cgColor, UIColor(hex: 0x232e33).cgColor] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 44, y: 44), options: [])
            context.setFillColor(UIColor(hex: 0x00c8ff).withAlphaComponent(0.082).cgColor)
            context.setStrokeColor(UIColor(hex: 0x00c8ff).withAlphaComponent(0.502).cgColor)
            context.setLineWidth(1)
            context.addEllipse(in: CGRect(x: 14, y: 14, width: 16, height: 16))
            context.drawPath(using: .fillStroke)
        }
    }

    static func fireButton(held: Bool, detonate: Bool) -> SKTexture {
        cached("fire:\(held):\(detonate)", size: CGSize(width: 91, height: 91)) { context in
            let first = UIColor(hex: detonate ? 0x635036 : 0x194654)
            let last = UIColor(hex: detonate ? 0x39291d : 0x102e3d)
            if held {
                context.setFillColor(UIColor(hex: detonate ? 0x635036 : 0x087693).cgColor)
                context.fill(CGRect(x: 0, y: 0, width: 91, height: 91))
            } else {
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [first.cgColor, last.cgColor] as CFArray, locations: [0, 1])!
                context.drawRadialGradient(gradient, startCenter: CGPoint(x: 34.6, y: 27.3), startRadius: 0, endCenter: CGPoint(x: 45.5, y: 45.5), endRadius: 52, options: .drawsAfterEndLocation)
            }
            context.setStrokeColor(last.cgColor)
            context.setLineWidth(4)
            context.strokeEllipse(in: CGRect(x: 4, y: 4, width: 83, height: 83))
        }
    }

    static func pickup(kind: String) -> SKTexture {
        cached("pickup:\(kind)", size: CGSize(width: 42, height: 42)) { context in
            context.translateBy(x: 21, y: 21)
            let color = Palette.power(kind)
            context.setShadow(offset: .zero, blur: 8, color: color.withAlphaComponent(0.6).cgColor)
            rounded(context, CGRect(x: -13, y: -13, width: 26, height: 26), 6, UIColor(hex: 0x152126))
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1.5)
            context.addPath(CGPath(roundedRect: CGRect(x: -13, y: -13, width: 26, height: 26), cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.strokePath()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            drawPower(kind, context)
        }
    }

    static func flag(team: Int, color: Int) -> SKTexture {
        cached("flag:\(team):\(color)", size: CGSize(width: 46, height: 48)) { context in
            context.translateBy(x: 23, y: 24)
            rounded(context, CGRect(x: -21, y: -23, width: 42, height: 43), 8, UIColor(hex: 0x101a24).withAlphaComponent(0.93))
            context.setStrokeColor(Palette.tank(color).cgColor)
            context.setLineWidth(1.7)
            context.addPath(CGPath(roundedRect: CGRect(x: -21, y: -23, width: 42, height: 43), cornerWidth: 8, cornerHeight: 8, transform: nil))
            context.strokePath()
            context.setLineCap(.round)
            context.setStrokeColor(UIColor(hex: 0x050b13).cgColor)
            context.setLineWidth(5)
            context.move(to: CGPoint(x: -9, y: 13)); context.addLine(to: CGPoint(x: -9, y: -17)); context.strokePath()
            context.setStrokeColor(UIColor(hex: 0xfffef2).cgColor)
            context.setLineWidth(2.5)
            context.move(to: CGPoint(x: -9, y: 13)); context.addLine(to: CGPoint(x: -9, y: -17)); context.strokePath()
            context.setFillColor(Palette.tank(color).cgColor)
            context.setLineWidth(1.4)
            context.move(to: CGPoint(x: -7, y: -17)); context.addLine(to: CGPoint(x: 15, y: -13))
            context.addLine(to: CGPoint(x: 9, y: 0)); context.addLine(to: CGPoint(x: -7, y: -3)); context.closePath()
            context.drawPath(using: .fillStroke)
            let text = String(team) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 10, weight: .black), .foregroundColor: UIColor(hex: 0x0d1823)]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: 2 - size.width / 2, y: -15), withAttributes: attributes)
        }
    }

    private static func drawPower(_ kind: String, _ context: CGContext) {
        context.setFillColor(Palette.power(kind).cgColor)
        context.setStrokeColor(Palette.power(kind).cgColor)
        context.setLineWidth(2)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        func line(_ points: [CGPoint], close: Bool = false, fill: Bool = false) {
            guard let first = points.first else { return }
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            if close { context.closePath() }
            if fill { context.fillPath() } else { context.strokePath() }
        }
        switch kind {
        case "rapid":
            for index in 0..<3 {
                let y = -6 + Double(index) * 6
                line([CGPoint(x: -9, y: y), CGPoint(x: -3, y: y)])
                line([CGPoint(x: 0, y: y - 1.7), CGPoint(x: 6, y: y - 1.7), CGPoint(x: 9, y: y), CGPoint(x: 6, y: y + 1.7), CGPoint(x: 0, y: y + 1.7)], close: true, fill: true)
            }
        case "scatter":
            context.setLineWidth(2.4)
            for y in [-7.0, 0, 7] { line([CGPoint(x: -10, y: 0), CGPoint(x: -3, y: 0), CGPoint(x: 10, y: y)]) }
            context.setLineWidth(1.5)
            context.setAlpha(0.55)
            for y in [-4.0, 4] { line([CGPoint(x: -12, y: y), CGPoint(x: -7, y: y)]) }
            context.setAlpha(1)
            for y in [-7.0, 0, 7] { context.fillEllipse(in: CGRect(x: 8.65, y: y - 1.35, width: 2.7, height: 2.7)) }
        case "homing":
            line([CGPoint(x: 0, y: -9), CGPoint(x: 4, y: -2), CGPoint(x: 3, y: 5), CGPoint(x: 0, y: 3), CGPoint(x: -3, y: 5), CGPoint(x: -4, y: -2)], close: true)
            line([CGPoint(x: -3, y: 2), CGPoint(x: -7, y: 7)])
            line([CGPoint(x: 3, y: 2), CGPoint(x: 7, y: 7)])
            line([CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 9)])
        case "laser":
            context.setLineWidth(1.6)
            context.stroke(CGRect(x: -11, y: -5, width: 6, height: 10))
            context.fill(CGRect(x: -5, y: -3, width: 3, height: 6))
            line([CGPoint(x: -8, y: -2), CGPoint(x: -8, y: 2)])
            context.setAlpha(0.28); context.setLineWidth(5)
            line([CGPoint(x: -1, y: 0), CGPoint(x: 11, y: 0)])
            context.setAlpha(1); context.setLineWidth(1.8)
            line([CGPoint(x: -1, y: 0), CGPoint(x: 11, y: 0)])
        case "grenade":
            context.strokeEllipse(in: CGRect(x: -6, y: -4, width: 12, height: 12))
            context.stroke(CGRect(x: -2, y: -7, width: 4, height: 3))
            context.move(to: CGPoint(x: 1, y: -8)); context.addQuadCurve(to: CGPoint(x: 8, y: -5), control: CGPoint(x: 6, y: -11)); context.strokePath()
            context.fill(CGRect(x: -1, y: 0, width: 2, height: 4))
        case "ghost":
            context.move(to: CGPoint(x: -8, y: 9)); context.addLine(to: CGPoint(x: -8, y: -2))
            context.addCurve(to: CGPoint(x: 8, y: -2), control1: CGPoint(x: -8, y: -12), control2: CGPoint(x: 8, y: -12))
            for point in [CGPoint(x: 8, y: 9), CGPoint(x: 4, y: 6), CGPoint(x: 0, y: 9), CGPoint(x: -4, y: 6)] { context.addLine(to: point) }
            context.closePath(); context.strokePath()
            for x in [-3.0, 3] { context.fillEllipse(in: CGRect(x: x - 1.2, y: -2.2, width: 2.4, height: 2.4)) }
        case "starman":
            var points: [CGPoint] = []
            for index in 0..<10 {
                let angle = Double(index) * .pi / 5 - .pi / 2, radius = index.isMultiple(of: 2) ? 10.0 : 4.5
                points.append(CGPoint(x: cos(angle) * radius, y: sin(angle) * radius))
            }
            line(points, close: true)
        case "cannon":
            context.fillEllipse(in: CGRect(x: -1, y: -5, width: 10, height: 10))
            for y in [-4.0, 0, 4] { line([CGPoint(x: y == 0 ? -12 : -10, y: y), CGPoint(x: y == 0 ? -4 : -5, y: y)]) }
        case "speed":
            for x in [-5.0, 2] { line([CGPoint(x: x - 2, y: -7), CGPoint(x: x + 4, y: 0), CGPoint(x: x - 2, y: 7)]) }
        default:
            context.move(to: CGPoint(x: 0, y: -8)); context.addLine(to: CGPoint(x: 7, y: -5)); context.addLine(to: CGPoint(x: 6, y: 3))
            context.addQuadCurve(to: CGPoint(x: 0, y: 9), control: CGPoint(x: 4, y: 7))
            context.addQuadCurve(to: CGPoint(x: -6, y: 3), control: CGPoint(x: -4, y: 7))
            context.addLine(to: CGPoint(x: -7, y: -5)); context.closePath(); context.strokePath()
        }
    }

    static func map(walls: [MazeWall], region: CGRect, fixed: Bool) -> SKTexture {
        let texture = SKTexture(image: MapRasterizer.image(walls: walls, region: region, fixed: fixed))
        texture.filteringMode = .linear
        return texture
    }
}

/// The immutable UIImage is drawn entirely on the worker, then handed once to
/// the main actor. SpriteKit textures and scene graph mutations stay on main.
private struct RasterizedMap: @unchecked Sendable {
    let image: UIImage
    let region: CGRect
    let request: Int
    let seconds: Double
}

private enum MapRasterizer {
    static func image(walls: [MazeWall], region: CGRect, fixed: Bool) -> UIImage {
        let ratio: CGFloat = fixed ? min(1.5, sqrt(5_000_000 / max(1, region.width * region.height))) : 1
        let format = UIGraphicsImageRendererFormat()
        format.scale = ratio; format.opaque = false
        return UIGraphicsImageRenderer(size: region.size, format: format).image { result in
            let context = result.cgContext
            context.translateBy(x: -region.minX, y: -region.minY)
            context.setFillColor(UIColor(hex: 0x151f25).cgColor)
            context.fill(region)
            let firstX = Int(floor(region.minX / 84)), lastX = Int(ceil(region.maxX / 84))
            let firstY = Int(floor(region.minY / 84)), lastY = Int(ceil(region.maxY / 84))
            for row in firstY..<max(firstY + 1, lastY) {
                for col in firstX..<max(firstX + 1, lastX) {
                    let x = CGFloat(col) * 84, y = CGFloat(row) * 84
                    context.setFillColor(UIColor(hex: (col + row) % 2 == 0 ? 0x172128 : 0x182229).cgColor)
                    context.fill(CGRect(x: x + 4, y: y + 4, width: 76, height: 76))
                    context.setStrokeColor(UIColor(hex: 0xd9e6e8).withAlphaComponent(0.035).cgColor)
                    context.setLineWidth(1)
                    context.stroke(CGRect(x: x + 10, y: y + 10, width: 64, height: 64))
                    context.setFillColor(UIColor(hex: 0xa5b9b4).withAlphaComponent(0.137).cgColor)
                    for dx in [19.0, 65] { for dy in [19.0, 65] { context.fill(CGRect(x: x + dx, y: y + dy, width: 1.5, height: 1.5)) } }
                    context.setFillColor(UIColor(hex: 0xc8d9cd).withAlphaComponent(0.051).cgColor)
                    context.fill(CGRect(x: x + 40, y: y + 41.5, width: 4, height: 1))
                    context.fill(CGRect(x: x + 41.5, y: y + 40, width: 1, height: 4))
                }
            }
            for wall in walls {
                context.setFillColor(UIColor(hex: 0x080e13).cgColor)
                context.fill(CGRect(x: wall.x + 1, y: wall.y + 4, width: wall.w, height: wall.h + 2))
                context.addPath(CGPath(roundedRect: CGRect(x: wall.x, y: wall.y, width: wall.w, height: wall.h), cornerWidth: 2, cornerHeight: 2, transform: nil))
                context.setFillColor(UIColor(hex: 0x35434b).cgColor); context.fillPath()
                context.setFillColor(UIColor(hex: 0x667773).cgColor)
                context.fill(wall.axis == "h" ? CGRect(x: wall.x + 1, y: wall.y + 0.8, width: wall.w - 2, height: 1.2) : CGRect(x: wall.x + 0.8, y: wall.y + 1, width: 1.2, height: wall.h - 2))
            }
            if fixed {
                context.setStrokeColor(UIColor(hex: 0x00c8ff).withAlphaComponent(0.36).cgColor)
                context.setLineWidth(2)
                for index in stride(from: 0, to: walls.count, by: 17) {
                    let wall = walls[index]
                    if wall.axis == "h" && wall.line > 0 && wall.line < region.maxY {
                        for mark in 0..<3 {
                            context.move(to: CGPoint(x: wall.x + 31 + Double(mark) * 6, y: wall.y + 1))
                            context.addLine(to: CGPoint(x: wall.x + 35 + Double(mark) * 6, y: wall.y + 6))
                        }
                        context.strokePath()
                    }
                }
                context.setStrokeColor(UIColor(hex: 0x829285).cgColor)
                context.stroke(region.insetBy(dx: 1, dy: 1))
            }
        }
    }
}

private enum Palette {
    static let arena = UIColor(hex: 0x10181e)
    static let accent = UIColor(hex: 0x32c5ff)
    static let colors: [UInt32] = [0x32c5ff, 0xff758f, 0x3ee6c5, 0xba91ff, 0xffcb66, 0xff7bd5, 0x79d878, 0x91a9ff]
    static let names = ["Electric blue", "Coral", "Jade", "Amethyst", "Amber", "Orchid", "Leaf", "Iris"]
    private static let paints = colors.map { UIColor(hex: $0) }
    private static let powers: [String: UIColor] = ["rapid": 0x79d878, "scatter": 0xba91ff, "shield": 0x32c5ff, "homing": 0xff7bd5, "grenade": 0xffcb66, "speed": 0x3ee6c5, "laser": 0xe879ff, "cannon": 0xff9e66, "ghost": 0xcedaff, "starman": 0xf9ed75].mapValues { UIColor(hex: $0) }
    static func tank(_ index: Int) -> UIColor { paints[max(0, index) % paints.count] }
    static func colorName(_ index: Int) -> String { names[max(0, index) % names.count] }
    static func power(_ kind: String) -> UIColor {
        powers[kind] ?? accent
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255,
                  green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

// Avoid shadowing the Foundation floor function with the grid path variable.
private func floorValue(_ value: CGFloat) -> CGFloat { value.rounded(.down) }
