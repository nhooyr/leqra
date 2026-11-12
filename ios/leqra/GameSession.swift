import SwiftUI
import SpriteKit
import leqraCore

@MainActor
final class GameSession: ObservableObject {
    enum Screen { case menu, connecting, lobby, playing }
    @Published var screen: Screen = .menu
    @Published var room: RoomInfo?
    @Published var status = ""
    @Published var error: String?
    @Published var paused = false
    @Published var score = 0
    @Published var equipment = "Standard rounds"
    @Published var gameplayStatus = ""
    @Published var standings: [LeaderboardEntry] = []
    @Published var latency: Int?
    @Published var measuredFPS = 0
    @Published var frameRateDetails = ""
    @Published var localID = -1
    @Published var showScores = false
    @Published var showSettings = false
    @Published var showRules = false
    @Published var showControls = false
    @Published var showSidebar = false
    @Published var showJoin = false
    @Published var showChat = false
    @Published var showQueues = false
    @Published var showPresets = false
    @Published var publicInfinitySelected = true
    @Published var publicStatus: NativePublicStatus?
    @Published var showFPS = true
    @Published var fullscreen = false
    @Published var weaponsLive = false
    @Published var localRules = RoomRules.localDefaults()
    @Published var localTeam = 0
    @Published var localBots: [LocalBot] = []
    @Published var roomName = ""
    @Published var localTank: ArenaTank?
    @Published var snapshot = ArenaSnapshot()
    @Published var chatMessages: [NativeChatMessage] = []
    @Published var opponentMessages: [NativeChatMessage] = []
    @Published var chatDraft = ""
    @Published var chatPending = false
    @Published var chatError: String?
    @Published var queueListings: [NativeQueueListing] = []
    @Published var queueState: NativeQueueState?
    @Published var savedPresets: [LocalPreset] = []
    @Published var callsign = UserDefaults.standard.string(forKey: "callsign") ?? "SNOW FOX" {
        didSet { UserDefaults.standard.set(callsign, forKey: "callsign") }
    }
    @Published var colorIndex = GamePalette.index(UserDefaults.standard.integer(forKey: "tankColor")) {
        didSet { UserDefaults.standard.set(colorIndex, forKey: "tankColor") }
    }
    @Published var serverAddress = UserDefaults.standard.string(forKey: "serverURL") ?? "https://leqra.com" {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "serverURL") }
    }
    @Published var highFrameRate = UserDefaults.standard.object(forKey: "highFrameRate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(highFrameRate, forKey: "highFrameRate") }
    }
    @Published var soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var soundVolume = min(100, max(0, UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 50)) {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
            audio.volume = Float(soundVolume / 100)
        }
    }
    let scene = GameScene(size: CGSize(width: 800, height: 600))
    private let audio = GameAudio()
    private let roomClient = NetworkClient()
    private let arenaClient = NetworkClient()
    private var practice: PracticeArena?
    private var fixedArena: FixedArena?
    private var maze: InfiniteMaze?
    private var timeline: RenderTimeline?
    private var world: ArenaWorld?
    private var welcome: NetworkWelcome?
    private var arenaActive = false
    private var lastSnapshot = ArenaSnapshot()
    private var hudElapsed = 0.0
    private var frameElapsed = 0.0
    private var frameCount = 0
    private var practiceElapsed = 0.0
    private var baseURL: URL?
    private var disconnected = false
    private var pendingShare = false
    private var requestID: UInt64 = 0
    private var pendingChatText: String?
    private var arenaGeneration: UInt64?
    private var readoutGeometry: InfiniteMaze?
    private var readoutGeneration: Int?
    private var previousPresentedPhase = ""
    private var weaponsLiveRemaining = 0.0
    private var modeProfiles: [String: RoomRules] = [:]

    init() {
        localRules.infinity = false
        if let data = UserDefaults.standard.data(forKey: "nativePresets"), let presets = try? JSONDecoder().decode([LocalPreset].self, from: data) { savedPresets = presets }
        scene.scaleMode = .resizeFill
        scene.onFrame = { [weak self] dt in self?.frame(dt) }
        roomClient.onEvent = { [weak self] event in self?.receive(event, arena: false) }
        arenaClient.onEvent = { [weak self] event in self?.receive(event, arena: true) }
        if ProcessInfo.processInfo.arguments.contains("--native-render-probe") {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.publicInfinitySelected = false
                self.localRules.infinity = true
                self.localRules.infinityRandomBots = true
                self.startLocal()
            }
        }
    }

    var identity: String { "\(cleanName) (P1)" }
    var cleanName: String {
        let cleaned = callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "SNOW FOX" : String(cleaned.prefix(16))
    }
    var isHost: Bool { room == nil || room?.host == welcome?.id }
    var offline: Bool { practice != nil || fixedArena != nil }
    var isInfinity: Bool { practice != nil || arenaActive }
    var effectiveRules: RoomRules { room?.rules ?? localRules }
    var selectedMode: BattleMode { effectiveRules.infinity ? .infinity : BattleMode(rawValue: effectiveRules.mode) ?? .elimination }
    var gameTitle: String { isInfinity ? (arenaActive && (room == nil || room?.infinityPublic == true) ? "Public Infinity" : "Infinity") : selectedMode.title }
    var readyRoom: Bool { screen == .menu || screen == .lobby }
    var roomPilotID: Int? { welcome?.id }
    var roomMemberID: UInt64? { welcome?.member }
    var ownRoomMember: RoomMember? { (room.map { $0.players + $0.spectators } ?? []).first { $0.id == welcome?.id } }
    var opponentChatAvailable: Bool { room?.matchmaking != nil && (ownRoomMember?.hasParty == true || ownRoomMember?.spectating == false) }
    var roomChatAvailable: Bool { room != nil && (room?.matchmaking == nil || ownRoomMember?.hasParty == true) }
    var roomEditable: Bool { isHost && (room.map { !$0.infinityActive && ["lobby", "matchOver"].contains($0.phase) && $0.queue == nil && $0.matchmaking == nil && $0.awayMatch.isEmpty } ?? true) }
    var canLoadPreset: Bool { roomEditable && (room.map { $0.spectators.isEmpty && !$0.players.contains { $0.id != welcome?.id && $0.kind != "bot" && $0.kind != "local" } } ?? true) }
    var canConfirmQueue: Bool { queueState?.stage == "confirming" && queueState?.members.contains { $0.controller == welcome?.member && !$0.accepted } == true }
    var canCancelQueue: Bool { isHost || queueState?.members.contains { $0.controller == welcome?.member } == true }
    var canQueue: Bool { isHost && (room.map { ["lobby", "matchOver"].contains($0.phase) && !$0.infinityActive && $0.matchmaking == nil && $0.awayMatch.isEmpty } ?? true) }
    var hasModal: Bool { showSettings || showRules || showControls || showSidebar || showJoin || showChat || showPresets || showQueues }
    var currentReadout: PilotReadout {
        let tank = localTank ?? ArenaTank(hp: 0)
        if !isInfinity, (readoutGeometry == nil || readoutGeneration != snapshot.generation), let world {
            readoutGeometry = InfiniteMaze(world: world); readoutGeneration = snapshot.generation
        }
        let geometry = isInfinity ? maze : readoutGeometry
        let radius = tank.power == "laser" ? 3.0 : tank.power == "cannon" ? 14 : tank.power == "grenade" ? 6 : tank.power == "homing" ? 5 : tank.power == "rapid" ? 3.5 / 3 : 3.5
        let blocked = tank.ghostTime > 0 && geometry?.isMuzzleBlocked(x: tank.x, y: tank.y, kind: tank.power, radius: radius) == true
        return PilotReadout(tank: tank, snapshot: snapshot, infinity: isInfinity, paused: paused, muzzleBlocked: blocked, online: !offline)
    }
    var inviteURL: URL {
        let base = URL(string: serverAddress) ?? URL(string: "https://leqra.com")!
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        if let code = room?.code { parts?.queryItems = [URLQueryItem(name: "room", value: code)] }
        return parts?.url ?? base
    }

    func refreshPublicStatus() async {
        guard readyRoom, !hasModal, (room?.infinityPublic ?? publicInfinitySelected) || (showFPS && !roomClient.connected),
              let base = URL(string: serverAddress) else { return }
        let address = serverAddress
        if let value = try? await arenaClient.fetchPublicStatus(baseURL: base) {
            guard !Task.isCancelled, readyRoom, !hasModal, serverAddress == address else { return }
            publicStatus = value
            if !roomClient.connected { latency = Int(value.latencyMilliseconds.rounded()) }
        }
    }

    func performanceReadout(preview: Bool = false) -> String {
        let fps = preview ? "—" : String(measuredFPS)
        let ping = latency.map { "\($0) ms" } ?? "—"
        return "fps: \(fps)" + (preview || !offline ? ", ping: \(ping)" : "")
    }

    func preparePreview() {
        guard readyRoom else { return }
        let previewMaze = InfiniteMaze(seed: 7319)
        let preview = ArenaSnapshot(tanks: [ArenaTank(id: 1, name: cleanName, x: 126, y: 126, angle: -0.6, colorIndex: colorIndex)], pickups: [ArenaPickup(id: 1, x: 210, y: 210, type: "cannon"), ArenaPickup(id: 2, x: 42, y: 210, type: "shield")])
        scene.resetWorld()
        scene.display(snapshot: preview, localID: 1, maze: previewMaze)
    }
    var canResume: Bool { !disconnected }
    private var onlineTitle: String {
        arenaActive ? (room == nil || room?.infinityPublic == true ? "Public Infinity" : "Room Infinity") : "Private match"
    }

    func startPractice() {
        leave()
        let game = PracticeArena(seed: UInt32.random(in: 1...UInt32.max), name: cleanName, colorIndex: GamePalette.index(colorIndex))
        practice = game; maze = game.maze; localID = game.localID
        lastSnapshot = game.snapshot
        status = "Offline Infinity"
        screen = .playing
        UIApplication.shared.isIdleTimerDisabled = true
        scene.display(snapshot: game.snapshot, localID: localID, maze: maze)
        syncHUD(game.snapshot)
        applyAudioSetting()
    }

    func play() {
        if let room {
            if room.infinityActive, let baseURL, let welcome, let token = welcome.token {
                guard welcome.spectating == false else { error = "Return to a combat seat to enter Infinity."; return }
                if arenaClient.connected { screen = .playing; setPaused(false); return }
                arenaActive = true
                arenaClient.connectRoomInfinity(baseURL: baseURL, code: room.code, token: token, resume: arenaGeneration != nil, generation: arenaGeneration)
                return
            }
            if isHost { roomClient.send(room.infinityPublic ? .startPublicInfinity : .start) }
            else if let own = room.players.first(where: { $0.id == welcome?.id }) { roomClient.send(.ready(!own.ready)) }
            return
        }
        if publicInfinitySelected { connect(publicArena: true); return }
        startLocal()
    }

    func startLocal() {
        let rules = localRules
        leave()
        let seed = UInt32.random(in: 1...UInt32.max)
        if rules.infinity {
            let game = PracticeArena(seed: seed, name: cleanName, colorIndex: colorIndex, botCount: localBots.count)
            game.configure(rules: rules)
            game.configurePilot(id: game.localID, name: cleanName, colorIndex: colorIndex, team: localTeam, difficulty: "normal")
            practice = game; maze = game.maze; localID = game.localID
            for (index, bot) in localBots.enumerated() { game.configurePilot(id: index + 2, name: bot.name, colorIndex: bot.colorIndex, team: bot.team, difficulty: bot.difficulty) }
            lastSnapshot = game.snapshot
        } else {
            let game = FixedArena(rules: rules, name: cleanName, colorIndex: colorIndex, botCount: localBots.count, difficulty: "normal", seed: seed, botNames: localBots.map(\.name), botColors: localBots.map(\.colorIndex), botDifficulties: localBots.map(\.difficulty), botTeams: localBots.map(\.team), localTeam: localTeam)
            fixedArena = game; world = game.world; localID = game.localID
            lastSnapshot = game.snapshot
        }
        snapshot = lastSnapshot
        screen = .playing; status = rules.infinity ? "Offline Infinity" : selectedMode.title
        UIApplication.shared.isIdleTimerDisabled = true
        scene.display(snapshot: lastSnapshot, localID: localID, maze: maze, fixedWalls: world?.walls ?? [])
        syncHUD(lastSnapshot); applyAudioSetting()
    }

    func restartMatch(wave: Bool = false) {
        if offline {
            if let fixedArena {
                if wave { fixedArena.restartWave() } else { fixedArena.restart() }
                snapshot = fixedArena.snapshot; lastSnapshot = snapshot; paused = false; scene.resetWorld(); applyAudioSetting()
            }
            else { startLocal() }
        } else if wave, let survival = snapshot.objectives?.survival {
            roomClient.send(.restartWave(generation: snapshot.generation, wave: survival.wave))
        } else if room?.matchmaking != nil { roomClient.send(.rematch) }
        else if isHost { roomClient.send(.start) }
        else { roomClient.send(.ready(true)); screen = .lobby; paused = false }
    }

    func updateRules(_ rules: RoomRules) {
        if room != nil { roomClient.send(.rules(rules)) }
        else {
            localRules = rules
            if rules.mode == "survival" && !rules.infinity {
                localTeam = 1; localBots = Array(localBots.prefix(3)).map { var bot = $0; bot.team = 1; return bot }
            } else if rules.mode == "ctf" && !rules.infinity {
                localTeam = 1
                for i in localBots.indices { localBots[i].team = i % 2 == 0 ? 2 : 1 }
            }
        }
    }

    func selectMode(_ mode: BattleMode) {
        let rules = effectiveRules
        let context = room?.code ?? "local"
        modeProfiles[context + ":" + (rules.infinity ? "infinity" : rules.mode)] = rules
        updateRules(rules.selectingMode(mode.rawValue, remembered: modeProfiles[context + ":" + mode.rawValue]))
    }

    func togglePublic(_ value: Bool) {
        if room != nil { roomClient.send(.publicInfinity(value)) }
        else {
            publicInfinitySelected = value
            if !value && localBots.isEmpty && !localRules.infinity { for _ in 0..<3 { addBot() } }
        }
    }

    func addBot() {
        let used = Set((room?.players.map(\.name) ?? ([cleanName] + localBots.map(\.name))).map { $0.uppercased() })
        let name = ["RUST", "VAPOR", "EMBER", "NOVA", "COMET", "ONYX", "BLITZ"].first { !used.contains($0) } ?? "BOT"
        if room != nil { roomClient.send(.add(kind: "bot", name: name, difficulty: "normal")); return }
        let capacity = !localRules.infinity && localRules.mode == "survival" ? 3 : 7
        guard localBots.count < capacity else { return }
        let id = (localBots.map(\.id).max() ?? 1) + 1
        localBots.append(LocalBot(id: id, name: name, colorIndex: (id - 1) % 8, team: localRules.teamMode == "teams" ? max(1, localTeam) : 0))
    }

    func shareRoom() {
        guard room == nil else { return }
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            error = "Enter an HTTP or HTTPS server address."; return
        }
        let queueOpen = showQueues
        let seats = [NativeSeatSpec(kind: "human", name: cleanName, team: localTeam, colorIndex: colorIndex)] + localBots.map { NativeSeatSpec(kind: "bot", name: $0.name, difficulty: $0.difficulty, team: $0.team, colorIndex: $0.colorIndex) }
        let code = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        leave()
        baseURL = url; screen = .connecting; pendingShare = true; showQueues = queueOpen
        roomClient.connectPublishedRoom(baseURL: url, code: code.isEmpty ? nil : code, rules: localRules, roster: seats)
    }

    func saveCallsign() {
        callsign = cleanName
        if let practice { practice.configurePilot(id: localID, name: callsign, colorIndex: colorIndex, team: localTeam, difficulty: "normal") }
        else if let fixedArena { fixedArena.configurePilot(id: localID, name: callsign, colorIndex: colorIndex, team: localTeam, difficulty: "normal") }
        else if arenaActive {
            requestID += 1
            arenaClient.sendCommand(["type": "rename", "seat": 0, "name": callsign, "requestId": requestID])
        } else if room != nil { roomClient.send(.rename(callsign)) }
    }

    func setPaint(_ index: Int) {
        if room != nil { roomClient.send(.paint(colorIndex: index)) }
        else { colorIndex = index }
    }

    func send(_ action: NativeRoomCommand) { roomClient.send(action) }

    func openQueue() {
        if room == nil { showQueues = true; shareRoom() }
        else { showQueues = true; roomClient.send(.queueInfo) }
    }

    func sendChat(_ text: String, channel: ChatChannel) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chatPending, roomClient.connected, !value.isEmpty, value.unicodeScalars.count <= 280,
              channel == .room ? roomChatAvailable : opponentChatAvailable else { return }
        chatError = nil; chatPending = true; pendingChatText = value
        roomClient.send(.chat(value, channel: channel))
    }

    func savePreset(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, isHost else { return }
        let bots = room?.players.filter { $0.kind == "bot" }.map { LocalBot(id: $0.id, name: $0.name, colorIndex: $0.colorIndex ?? GamePalette.colors.firstIndex(of: $0.color) ?? 0, difficulty: $0.difficulty, team: $0.team) } ?? localBots
        let team = ownRoomMember?.team ?? localTeam
        var preset = LocalPreset(id: String(name.prefix(40)), rules: effectiveRules, bots: bots, team: team)
        if let room {
            preset.roster = room.players.filter { $0.id == welcome?.id || $0.kind == "bot" || $0.kind == "local" && $0.owner == welcome?.id }.map {
                NativeSeatSpec(kind: $0.id == welcome?.id ? "human" : $0.kind, name: $0.name, difficulty: $0.difficulty, team: $0.team, colorIndex: $0.colorIndex)
            }.sorted { $0.kind == "human" && $1.kind != "human" }
        }
        savedPresets.removeAll { $0.id == name }
        savedPresets.append(preset)
        savedPresets = Array(savedPresets.suffix(12))
        UserDefaults.standard.set(try? JSONEncoder().encode(savedPresets), forKey: "nativePresets")
    }

    func loadPreset(_ preset: LocalPreset) {
        guard canLoadPreset else { error = "Presets require a host-only lobby without online guests or spectators."; return }
        if room != nil {
            let seats = preset.roster ?? ([NativeSeatSpec(kind: "human", name: cleanName, team: preset.team, colorIndex: colorIndex)] + preset.bots.map { NativeSeatSpec(kind: "bot", name: $0.name, difficulty: $0.difficulty, team: $0.team, colorIndex: $0.colorIndex) })
            roomClient.send(.preset(rules: preset.rules, roster: seats))
        } else { localRules = preset.rules; localBots = preset.bots; localTeam = preset.team; publicInfinitySelected = false }
    }

    func connect(code: String? = nil, publicArena: Bool = false) {
        leave()
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            error = "Enter an HTTP or HTTPS server address."; return
        }
        baseURL = url
        screen = .connecting
        if publicArena {
            arenaActive = true
            arenaClient.connectPublic(baseURL: url, name: cleanName, colorIndex: GamePalette.index(colorIndex))
        } else { roomClient.connectRoom(baseURL: url, name: cleanName, code: code) }
    }

    func command(_ command: [String: Any]) { roomClient.sendCommand(command) }

    func changeMode(_ mode: String) {
        guard var rules = room?.rules else { return }
        rules.infinity = mode == "infinity"
        rules.mode = mode == "infinity" ? "elimination" : mode
        rules.teamMode = ["ctf", "survival"].contains(mode) ? "teams" : "ffa"
        command(rules.command())
    }

    func setPaused(_ value: Bool) {
        guard value || !disconnected else { return }
        paused = value
        scene.resetControls()
        timeline?.neutralize()
        frameElapsed = 0; frameCount = 0
        if !offline, !disconnected {
            let packet = timeline?.neutralPacket() ?? GameInput()
            (arenaActive ? arenaClient : roomClient).sendInput(packet, paused: value)
        }
        UIApplication.shared.isIdleTimerDisabled = screen == .playing && !value
        if value { audio.pause() } else { applyAudioSetting() }
    }

    func setSoundVolume(_ value: Double) {
        let level = value.isFinite ? min(100, max(0, value.rounded())) : 0
        soundVolume = abs(level - 50) <= 4 ? 50 : level
    }

    func applyAudioSetting(preview: AudioCue? = nil) {
        audio.enabled = soundEnabled
        audio.volume = Float(soundVolume / 100)
        if screen == .playing && !paused { audio.resume() }
        if let preview { audio.preview(preview) }
    }

    func leave() {
        audio.reset()
        scene.resetControls(); scene.resetWorld()
        roomClient.disconnect(); arenaClient.disconnect()
        practice = nil; fixedArena = nil; maze = nil; timeline = nil; world = nil; welcome = nil; room = nil
        arenaActive = false; disconnected = false; paused = false; showScores = false
        lastSnapshot = ArenaSnapshot(); localID = -1; latency = nil; score = 0
        snapshot = ArenaSnapshot(); standings = []; arenaGeneration = nil; readoutGeometry = nil; readoutGeneration = nil
        weaponsLive = false; weaponsLiveRemaining = 0; previousPresentedPhase = ""
        measuredFPS = 0; frameElapsed = 0; frameCount = 0; hudElapsed = 0; practiceElapsed = 0
        status = ""; error = nil; screen = .menu; pendingShare = false
        localTank = nil; showChat = false; showQueues = false; showJoin = false; showPresets = false
        showRules = false; showControls = false; showSidebar = false; showSettings = false
        chatMessages = []; opponentMessages = []; queueState = nil; queueListings = []
        chatDraft = ""; chatPending = false; chatError = nil; pendingChatText = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func returnToRoom() {
        guard room != nil else { leave(); return }
        guard isHost else { return }
        command(["type": "lobby"])
        audio.pause()
        if arenaActive { arenaClient.disconnect(); arenaActive = false }
        timeline = nil; maze = nil; world = nil; paused = false; scene.resetControls(); scene.resetWorld()
        restoreRoomIdentity()
        screen = .lobby
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Exit only this pilot's Infinity run. The authenticated room remains
    /// available for its roster, chat, settings and a later arena rejoin.
    func exitArenaToRoom() {
        guard room != nil else { leave(); return }
        audio.pause()
        arenaClient.disconnect()
        arenaActive = false; arenaGeneration = nil
        timeline = nil; maze = nil; world = nil; readoutGeometry = nil; readoutGeneration = nil
        localTank = nil; snapshot = ArenaSnapshot(); lastSnapshot = snapshot; standings = []
        paused = false; disconnected = !roomClient.connected; score = 0; showScores = false
        scene.resetControls(); scene.resetWorld(); restoreRoomIdentity()
        screen = .lobby
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func receive(_ event: NetworkEvent, arena: Bool) {
        switch event {
        case .status(let value): status = value
        case .welcome(let value):
            disconnected = false
            if value.resumed { timeline = nil; scene.resetControls() }
            if !arena {
                if let oldCode = welcome?.room, oldCode != value.room {
                    chatMessages = []; opponentMessages = []; queueState = nil; chatPending = false; pendingChatText = nil; showQueues = false
                }
                welcome = value
            } else { arenaGeneration = value.generation }
            // The retained room socket can update roster identity while its
            // separate Infinity socket owns a different arena tank ID.
            if !arena && arenaActive { return }
            localID = value.spectating ? -1 : value.id
            timeline?.setLocalID(localID)
            if let seed = value.seed {
                maze = InfiniteMaze(seed: seed); world = nil; arenaActive = true
                timeline = makeTimeline()
                scene.resetWorld(); screen = .playing
                status = room == nil ? "Public Infinity" : "Room Infinity"
            }
        case .room(let value):
            let endedArena = room?.infinityActive == true && !value.infinityActive
            room = value
            arenaClient.updateResumeRoomCode(value.code)
            queueState = value.queue
            if pendingShare, isHost {
                pendingShare = false
                roomClient.send(.publicInfinity(publicInfinitySelected))
                if showQueues { roomClient.send(.queueInfo) }
            }
            if endedArena {
                audio.pause()
                arenaClient.disconnect(); arenaActive = false; arenaGeneration = nil; timeline = nil; maze = nil
                scene.resetControls(); scene.resetWorld(); screen = .lobby; paused = false
                restoreRoomIdentity()
                UIApplication.shared.isIdleTimerDisabled = false
            } else if value.phase == "lobby", !value.infinityActive {
                audio.pause()
                screen = .lobby; paused = false
                restoreRoomIdentity()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            if let own = value.players.first(where: { $0.id == welcome?.id }) {
                callsign = own.name
                if let index = GamePalette.colors.firstIndex(of: own.color.lowercased()) { colorIndex = index }
            }
        case .infinityStarted:
            guard let url = baseURL, let welcome, let code = welcome.room, let token = welcome.token else { return }
            arenaActive = true
            arenaClient.connectRoomInfinity(baseURL: url, code: code, token: token)
        case .state(let snapshot):
            guard arena == arenaActive else { return }
            if snapshot.phase == "lobby", !arena { return }
            if snapshot.generation != lastSnapshot.generation, !arena {
                scene.resetWorld()
            }
            if let fixed = snapshot.world { world = fixed }
            if timeline == nil { timeline = makeTimeline() }
            timeline?.accept(snapshot, at: ProcessInfo.processInfo.systemUptime)
            lastSnapshot = snapshot
            if status == "Waiting for server…" { status = onlineTitle }
            screen = .playing
            applyAudioSetting()
            UIApplication.shared.isIdleTimerDisabled = !paused
        case .latency(let milliseconds):
            if arena == arenaActive { latency = Int(milliseconds.rounded()) }
        case .error(let message):
            error = message
            if screen == .connecting { screen = room == nil ? .menu : .lobby }
        case .disconnected(let reason):
            if arena == arenaActive {
                disconnected = true
                setPaused(true)
                status = reason ?? "Disconnected. Leave and rejoin to play again."
                if screen == .connecting { screen = room == nil ? .menu : .lobby }
            }
        case .roomEvent(let event):
            switch event {
            case .chat(let packet):
                guard packet.room == (room?.code ?? welcome?.room) else { return }
                let knownMessages = Set((packet.channel == .room ? chatMessages : opponentMessages).map(\.id))
                if !packet.isHistory && !showChat && packet.messages.contains(where: { !knownMessages.contains($0.id) && $0.member != welcome?.member }) {
                    audio.notifyChat()
                }
                if let text = pendingChatText, packet.messages.contains(where: { $0.member == welcome?.member && $0.text == text }) {
                    chatPending = false; pendingChatText = nil
                    if chatDraft.trimmingCharacters(in: .whitespacesAndNewlines) == text { chatDraft = "" }
                }
                if packet.channel == .room {
                    if packet.isHistory { chatMessages = packet.messages }
                    else { let known = Set(chatMessages.map(\.id)); chatMessages.append(contentsOf: packet.messages.filter { !known.contains($0.id) }) }
                    chatMessages = Array(chatMessages.suffix(200))
                } else {
                    if packet.isHistory { opponentMessages = packet.messages }
                    else { let known = Set(opponentMessages.map(\.id)); opponentMessages.append(contentsOf: packet.messages.filter { !known.contains($0.id) }) }
                    opponentMessages = Array(opponentMessages.suffix(200))
                }
            case .queue(let packet): queueListings = packet.queues.isEmpty ? queueListings : packet.queues; queueState = packet.queue
            case .pilotRenamed(let rename):
                if let name = rename.name, (arena && rename.seat == 0) || (!arena && rename.id == welcome?.id) { callsign = name }
            case .roomRenamed(let rename): roomName = rename.room; welcome?.room = rename.room
            case .notice(let notice):
                if let message = notice.message { status = message }
                if notice.action == "chat" { chatPending = false; pendingChatText = nil; chatError = notice.message }
            case .reconnecting(let attempt): disconnected = true; setPaused(true); status = "Reconnecting, attempt \(attempt)…"
            }
        }
    }

    private func restoreRoomIdentity() {
        localID = welcome?.spectating == true ? -1 : welcome?.id ?? -1
        timeline?.setLocalID(localID)
    }

    private func makeTimeline() -> RenderTimeline {
        RenderTimeline(localID: localID, initialSequence: (arenaActive ? arenaClient : roomClient).lastInputSequence, maze: maze) { [weak self] tank, input, dt in
            guard let self else { return }
            if let maze = self.maze { TankMovement.step(tank: &tank, input: input, dt: dt, maze: maze) }
            else if let world = self.world {
                TankMovement.step(tank: &tank, input: input, dt: dt, walls: world.walls, width: world.width, height: world.height)
            }
        }
    }

    private func frame(_ dt: TimeInterval) {
        guard screen == .playing, !paused else { return }
        frameElapsed += dt; frameCount += 1
        if frameElapsed >= 1 {
            measuredFPS = Int((Double(frameCount) / frameElapsed).rounded())
            let requested = scene.view?.preferredFramesPerSecond ?? 0
            let maximum = scene.view?.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
            let power = ProcessInfo.processInfo.isLowPowerModeEnabled ? ", Low Power Mode" : ""
            frameRateDetails = "Requested \(requested) FPS, display \(maximum) Hz\(power), thermal \(ProcessInfo.processInfo.thermalState.rawValue)"
            if ProcessInfo.processInfo.arguments.contains("--native-render-probe") {
                let line = "leqra render probe: \(measuredFPS) FPS, \(frameRateDetails), scene \(scene.size), view \(scene.view?.bounds ?? .zero)\n"
                FileHandle.standardOutput.write(Data(line.utf8))
            }
            frameElapsed = 0; frameCount = 0
        }
        let input = scene.input
        var snapshot: ArenaSnapshot?
        if let practice {
            practiceElapsed += min(dt, 0.1)
            while practiceElapsed + 1e-9 >= 1 / 60 {
                practice.step(input: input, dt: 1 / 60)
                practiceElapsed = max(0, practiceElapsed - 1 / 60)
            }
            snapshot = practice.presentationSnapshot(fraction: practiceElapsed * 60, localInput: input)
        } else if let fixedArena {
            practiceElapsed += min(dt, 0.1)
            while practiceElapsed + 1e-9 >= 1 / 60 {
                fixedArena.step(input: input, dt: 1 / 60)
                practiceElapsed = max(0, practiceElapsed - 1 / 60)
            }
            world = fixedArena.world
            snapshot = fixedArena.presentationSnapshot(fraction: practiceElapsed * 60, localInput: input)
        } else if let timeline, !disconnected {
            snapshot = timeline.render(dt: dt, input: input, now: ProcessInfo.processInfo.systemUptime) { [weak self] packet in
                guard let self else { return }
                (self.arenaActive ? self.arenaClient : self.roomClient).sendInput(packet, paused: false)
            }
            if timeline.stale { status = "Waiting for server…" }
        }
        guard let snapshot else { return }
        if !isInfinity, previousPresentedPhase == "countdown", snapshot.phase == "playing" {
            weaponsLive = true; weaponsLiveRemaining = 0.8
        }
        if snapshot.phase != "playing" { weaponsLive = false; weaponsLiveRemaining = 0 }
        previousPresentedPhase = snapshot.phase
        if weaponsLiveRemaining > 0 {
            weaponsLiveRemaining = max(0, weaponsLiveRemaining - dt)
            if weaponsLiveRemaining == 0 { weaponsLive = false }
        }
        lastSnapshot = snapshot
        audio.consume(snapshot: snapshot, localID: localID, infinity: isInfinity, online: !offline)
        scene.display(snapshot: snapshot, localID: localID, maze: maze, fixedWalls: world?.walls ?? [])
        hudElapsed += dt
        if hudElapsed >= 0.1 { hudElapsed = 0; syncHUD(snapshot) }
    }

    private func syncHUD(_ snapshot: ArenaSnapshot) {
        self.snapshot = snapshot
        standings = snapshot.leaderboard
        guard let tank = snapshot.tanks.first(where: { $0.id == localID }) else {
            localTank = nil; gameplayStatus = "Spectating"
            scene.configureReadiness(label: "WATCH", hint: "SPECTATING", progress: 0, locked: false)
            return
        }
        localTank = tank
        let readout = currentReadout
        scene.configureReadiness(label: readout.fireLabel, hint: readout.fireHint, progress: readout.progress, locked: readout.locked)
        score = tank.score
        colorIndex = GamePalette.index(tank.colorIndex)
        let weapons = ["rapid": "Machine gun", "scatter": "Shotgun", "homing": "Homing missile", "cannon": "Cannon", "laser": "Laser", "grenade": "Grenade"]
        equipment = weapons[tank.power] ?? "Standard rounds"
        if tank.power == "rapid" { equipment += ", \(tank.machineRounds) rounds" }
        else if !tank.power.isEmpty { equipment += ", \(tank.charges) charges" }
        if tank.starmanTime > 0 { equipment += ", Starman \(Int(ceil(tank.starmanTime)))s" }
        if tank.shieldCharges > 0 { equipment += ", Shield ×\(tank.shieldCharges)" }
        if tank.speedTime > 0 { equipment += ", Speed ×\(max(1, tank.speedStacks))" }
        if tank.ghostTime > 0 { equipment += ", Ghost \(Int(ceil(tank.ghostTime)))s" }
        if let result = snapshot.result { gameplayStatus = "\(result.name) wins, \(result.score)" }
        else if snapshot.phase == "countdown" { gameplayStatus = "Starting in \(Int(ceil(snapshot.phaseTime)))" }
        else if snapshot.phase == "matchOver" { gameplayStatus = "Match complete" }
        else if snapshot.phase == "roundOver" { gameplayStatus = "Round complete" }
        else if tank.hp <= 0 {
            gameplayStatus = tank.respawnTime > 0 ? "Respawn in \(String(format: "%.1f", tank.respawnTime))s" : "Waiting for the next round"
        } else if tank.spawnProtected { gameplayStatus = "Spawn protection" }
        else if tank.cooldown > 0 { gameplayStatus = "Reloading" }
        else { gameplayStatus = "" }
        if let survival = snapshot.objectives?.survival {
            if survival.status == "lost" { gameplayStatus = "Survival run ended, wave \(survival.wave)" }
            else if survival.status == "won" { gameplayStatus = "Survival complete, \(survival.wavesCleared) waves cleared" }
            else if snapshot.phase == "playing", tank.hp > 0 {
                gameplayStatus = survival.status == "break"
                    ? "Next wave in \(Int(ceil(survival.breakTime)))s"
                    : "Wave \(survival.wave), \(survival.enemiesRemaining) enemies"
            }
        }
    }
}
