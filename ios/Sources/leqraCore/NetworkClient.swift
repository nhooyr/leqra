import Foundation

public struct NetworkWelcome: Decodable, Sendable {
    public let id: Int
    public let seed: UInt32?
    public var room: String?
    public let token: String?
    public let spectating: Bool
    public let localId: Int?
    public let generation: UInt64?
    public let member: UInt64?
    public let localMember: UInt64?
    public let resumed: Bool
    public let created: Bool
    public let full: Bool
    public let busy: Bool

    enum CodingKeys: String, CodingKey { case id, seed, room, token, spectating, localId, generation, member, localMember, resumed, created, full, busy }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        seed = try c.decodeIfPresent(UInt32.self, forKey: .seed)
        room = try c.decodeIfPresent(String.self, forKey: .room)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        spectating = try c.decodeIfPresent(Bool.self, forKey: .spectating) ?? false
        localId = try c.decodeIfPresent(Int.self, forKey: .localId)
        generation = try c.decodeIfPresent(UInt64.self, forKey: .generation)
        member = try c.decodeIfPresent(UInt64.self, forKey: .member)
        localMember = try c.decodeIfPresent(UInt64.self, forKey: .localMember)
        resumed = try c.decodeIfPresent(Bool.self, forKey: .resumed) ?? false
        created = try c.decodeIfPresent(Bool.self, forKey: .created) ?? false
        full = try c.decodeIfPresent(Bool.self, forKey: .full) ?? false
        busy = try c.decodeIfPresent(Bool.self, forKey: .busy) ?? false
    }
}

public struct RoomMember: Decodable, Identifiable, Sendable {
    public let id: Int
    public let member: UInt64
    public let name: String
    public let color: String
    public let kind: String
    public let connected: Bool
    public let ready: Bool
    public let spectating: Bool
    public let score: Int
    public let team: Int
    public let difficulty: String
    public let owner: Int
    public let colorIndex: Int?
    public let away: Bool
    public let hasParty: Bool
    public let rematch: Bool?
}

public struct RoomRules: Codable, Equatable, Sendable {
    public var mode = "elimination"
    public var infinity = false
    public var infinityTarget = 0
    public var infinityRandomBots = false
    public var infinityBotDifficulty = "normal"
    public var infinityRandomDifficulty = false
    public var teamMode = "ffa"
    public var mapSize = "large"
    public var portraitMaze = false
    public var scoreTarget = 5
    public var timeLimit = 75
    public var respawnSeconds = 3
    public var pickupRate = "superfast"
    public var weapons = ["rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "cannon", "ghost", "starman"]
    public var friendlyFire = false
    public var teamNames = ["Team 1", "Team 2", "Team 3", "Team 4"]
    public var teamColors = [0, 1, 2, 3]

    public init() {}

    enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, infinity, infinityTarget, infinityRandomBots, infinityBotDifficulty, infinityRandomDifficulty
        case teamMode, mapSize, portraitMaze, scoreTarget, timeLimit, respawnSeconds, pickupRate, weapons, friendlyFire, teamNames, teamColors
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? mode
        infinity = try c.decodeIfPresent(Bool.self, forKey: .infinity) ?? infinity
        infinityTarget = try c.decodeIfPresent(Int.self, forKey: .infinityTarget) ?? infinityTarget
        infinityRandomBots = try c.decodeIfPresent(Bool.self, forKey: .infinityRandomBots) ?? infinityRandomBots
        infinityBotDifficulty = try c.decodeIfPresent(String.self, forKey: .infinityBotDifficulty) ?? infinityBotDifficulty
        infinityRandomDifficulty = try c.decodeIfPresent(Bool.self, forKey: .infinityRandomDifficulty) ?? infinityRandomDifficulty
        teamMode = try c.decodeIfPresent(String.self, forKey: .teamMode) ?? teamMode
        mapSize = try c.decodeIfPresent(String.self, forKey: .mapSize) ?? mapSize
        portraitMaze = try c.decodeIfPresent(Bool.self, forKey: .portraitMaze) ?? portraitMaze
        scoreTarget = try c.decodeIfPresent(Int.self, forKey: .scoreTarget) ?? scoreTarget
        timeLimit = try c.decodeIfPresent(Int.self, forKey: .timeLimit) ?? timeLimit
        respawnSeconds = try c.decodeIfPresent(Int.self, forKey: .respawnSeconds) ?? respawnSeconds
        pickupRate = try c.decodeIfPresent(String.self, forKey: .pickupRate) ?? pickupRate
        weapons = try c.decodeIfPresent([String].self, forKey: .weapons) ?? weapons
        friendlyFire = try c.decodeIfPresent(Bool.self, forKey: .friendlyFire) ?? friendlyFire
        teamNames = try c.decodeIfPresent([String].self, forKey: .teamNames) ?? teamNames
        teamColors = try c.decodeIfPresent([Int].self, forKey: .teamColors) ?? teamColors
    }

    public func command() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return ["type": "rules", "rules": object]
    }
}

public struct RoomInfo: Decodable, Sendable {
    public let code: String
    public let host: Int
    public let phase: String
    public let players: [RoomMember]
    public let spectators: [RoomMember]
    public let canStart: Bool
    public let startError: String
    public let infinityActive: Bool
    public let infinityPublic: Bool
    public let rules: RoomRules
    public let maxPlayers: Int
    public let maxSpectators: Int
    public let sides: Int
    public let canRestartWave: Bool
    public let canStartPublicInfinity: Bool
    public let startPublicInfinityError: String
    public let queue: NativeQueueState?
    public let matchmaking: NativeMatchmakingInfo?
    public let awayMatch: String
}

public enum NetworkEvent {
    case status(String)
    case welcome(NetworkWelcome)
    case state(ArenaSnapshot)
    case room(RoomInfo)
    case infinityStarted(Bool)
    case latency(Double)
    case error(String)
    case disconnected(String?)
    case roomEvent(NativeRoomEvent)
}

public enum GameNetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unsupportedProtocol
    case unsupportedVersion(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter an HTTP or HTTPS server address."
        case .invalidResponse: return "The server sent an invalid response."
        case .unsupportedProtocol: return "This server uses an unsupported game protocol."
        case .unsupportedVersion(let version): return "This server is running leqra \(version). Update the native app before joining."
        case .timeout: return "The server stopped responding. Rejoin to play again."
        }
    }
}

/// URL construction is shared by API discovery and WebSocket connections.
public enum ServerAddress {
    public static func endpoint(_ base: URL, path: String, webSocket: Bool = false) throws -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { throw GameNetworkError.invalidURL }
        switch components.scheme?.lowercased() {
        case "https", "wss": components.scheme = webSocket ? "wss" : "https"
        case "http", "ws": components.scheme = webSocket ? "ws" : "http"
        default: throw GameNetworkError.invalidURL
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw GameNetworkError.invalidURL }
        return url
    }
}

/// Status requests share a start-to-start cadence without overlapping slow requests.
public enum NetworkRefreshCadence {
    public static let interval: TimeInterval = 1
    public static let intervalNanoseconds: UInt64 = 1_000_000_000

    public static func remainingNanoseconds(startedAt: TimeInterval, now: TimeInterval) -> UInt64 {
        guard startedAt.isFinite, now.isFinite else { return intervalNanoseconds }
        let remaining = max(0, interval - max(0, now - startedAt))
        return UInt64((remaining * 1_000_000_000).rounded())
    }
}

/// Retain a bounded set of echoes so a slow reply remains measurable at a faster cadence.
struct NetworkLatencySampler {
    private(set) var lastSent: Double?
    private var outstanding: [Double] = []

    mutating func nextPing(at now: Double) -> Double? {
        guard now.isFinite, lastSent.map({ now - $0 >= NetworkRefreshCadence.interval * 1000 }) ?? true else { return nil }
        outstanding.removeAll { now - $0 > 6000 }
        if outstanding.count >= 8 { outstanding.removeFirst() }
        outstanding.append(now)
        lastSent = now
        return now
    }

    mutating func roundTrip(echo: Double, now: Double) -> Double? {
        guard echo.isFinite, now.isFinite, let index = outstanding.firstIndex(of: echo) else { return nil }
        outstanding.remove(at: index)
        let elapsed = now - echo
        return elapsed >= 0 && elapsed <= 6000 ? elapsed : nil
    }
}

/// Native transport. All callbacks and mutations are serialized on the main actor.
/// Public Infinity connections deliberately require an explicit rejoin after loss;
/// an unauthenticated public pilot has no score-preserving resume credential.
@MainActor public final class NetworkClient {
    public static let supportedVersion = "4.49.36"
    public var onEvent: ((NetworkEvent) -> Void)?
    public private(set) var connected = false
    public private(set) var welcome: NetworkWelcome?
    public var lastInputSequence: UInt64 { sentSequence }
    public var lastLocalInputSequence: UInt64 { localSentSequence }
    public var automaticallyReconnects = true

    private struct ResumeContext {
        var baseURL: URL
        var infinity: Bool
        var code: String
        var token: String
        var name: String
        var generation: UInt64?
        var command: [String: Any] {
            var result: [String: Any] = ["type": "join", "code": code, "token": token, "name": name]
            if infinity { result["resume"] = true; result["generation"] = generation }
            return result
        }
    }

    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var epoch = UUID()
    private var isInfinity = false
    private var pendingJoin: [String: Any] = [:]
    private var lastWorld: Any?
    private var lastReceived = Date()
    private var latencySampler = NetworkLatencySampler()
    private var sentSequence: UInt64 = 0
    private var queuedSends = 0
    private var localSentSequence: UInt64 = 0
    private var currentBaseURL: URL?
    private var resumeContext: ResumeContext?
    private var reconnectDeadline: Date?
    private var reconnectAttempt = 0
    private var renameRequestID: UInt64 = 0

    public init(session: URLSession = .shared) { self.session = session }

    deinit {
        connectionTask?.cancel()
        heartbeatTask?.cancel()
        sendTask?.cancel()
        reconnectTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    public func connectPublic(baseURL: URL, name: String, colorIndex: Int, localName: String? = nil, localColorIndex: Int = 1) {
        var join: [String: Any] = ["type": "join", "name": name, "colorIndex": min(7, max(0, colorIndex))]
        if let localName { join["localName"] = localName; join["localColorIndex"] = min(7, max(0, localColorIndex)) }
        begin(baseURL: baseURL, infinity: true, join: join)
    }

    public func connectRoom(baseURL: URL, name: String, code: String? = nil, spectating: Bool = false) {
        var join: [String: Any] = ["type": code?.isEmpty == false ? "join" : "create", "name": name]
        if let code, !code.isEmpty { join["code"] = code }
        join["spectating"] = spectating
        begin(baseURL: baseURL, infinity: false, join: join)
    }

    public func connectRoomInfinity(baseURL: URL, code: String, token: String, resume: Bool = false, generation: UInt64? = nil) {
        var join: [String: Any] = ["type": "join", "code": code, "token": token]
        if resume { join["resume"] = true; join["generation"] = generation }
        begin(baseURL: baseURL, infinity: true, join: join, resuming: resume)
    }

    /// The ready-room preview never joins an arena or allocates a pilot.
    public func fetchPublicStatus(baseURL: URL) async throws -> NativePublicStatus {
        var request = URLRequest(url: try ServerAddress.endpoint(baseURL, path: "/api/infinity"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 6
        let start = ProcessInfo.processInfo.systemUptime
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 64 * 1024 else {
            throw GameNetworkError.invalidResponse
        }
        var status = try JSONDecoder().decode(NativePublicStatus.self, from: data)
        status.latencyMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        return status
    }

    public func connectPublishedRoom(baseURL: URL, code: String? = nil, rules: RoomRules, roster: [NativeSeatSpec]) {
        var join = NativeRoomCommand.preset(rules: rules, roster: roster).payload
        join["type"] = "publish"; join["code"] = code
        begin(baseURL: baseURL, infinity: false, join: join)
    }

    /// Retry an authenticated private session without issuing a destructive
    /// leave. Public standalone Infinity pilots have no resume credentials.
    public func reconnect() {
        guard resumeContext != nil else { return }
        if !scheduleReconnect(force: true) { fail("The reconnect window expired.", terminal: true) }
    }

    /// A separate room socket can rename the room while its arena socket is
    /// running. Keep the latter's in-memory resume route current as well.
    public func updateResumeRoomCode(_ code: String) {
        resumeContext?.code = code
        if welcome?.room != nil { welcome?.room = code }
    }

    /// Infinity rename acknowledgements carry request IDs, unlike room rename.
    @discardableResult public func renameInfinity(_ name: String, seat: Int = 0) -> UInt64 {
        renameRequestID &+= 1
        sendCommand(["type": "rename", "seat": seat, "name": name, "requestId": renameRequestID])
        return renameRequestID
    }

    private func begin(baseURL: URL, infinity: Bool, join: [String: Any], resuming: Bool = false) {
        if resuming {
            let old = socket
            invalidate()
            old?.cancel(with: .goingAway, reason: nil)
            reconnectTask = nil
            reconnectDeadline = reconnectDeadline ?? Date().addingTimeInterval(18)
        } else { disconnect() }
        currentBaseURL = baseURL
        if infinity, let code = join["code"] as? String, let token = join["token"] as? String {
            resumeContext = ResumeContext(baseURL: baseURL, infinity: true, code: code, token: token,
                                          name: join["name"] as? String ?? "", generation: join["generation"] as? UInt64)
        }
        isInfinity = infinity
        pendingJoin = join
        lastWorld = nil
        sentSequence = 0
        localSentSequence = 0
        lastReceived = Date()
        let current = epoch
        onEvent?(.status(resuming ? "Reconnecting…" : "Connecting…"))
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: try ServerAddress.endpoint(baseURL, path: "/api/build"))
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = resuming ? min(6, max(0.5, self.reconnectDeadline?.timeIntervalSinceNow ?? 6)) : 10
                let (data, response) = try await self.session.data(for: request)
                guard self.epoch == current, !Task.isCancelled else { return }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      data.count <= 8192,
                      let build = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let version = build["version"] as? String, !version.isEmpty, version.count <= 64 else { throw GameNetworkError.invalidResponse }
                guard version == Self.supportedVersion else { throw GameNetworkError.unsupportedVersion(version) }
                let url = try ServerAddress.endpoint(baseURL, path: infinity ? "/ws/infinite" : "/ws", webSocket: true)
                var socketRequest = URLRequest(url: url)
                // The existing server validates same-origin upgrades even for
                // native clients. URLSession does not synthesize this header.
                let origin = try ServerAddress.endpoint(baseURL, path: "").absoluteString
                socketRequest.setValue(origin, forHTTPHeaderField: "Origin")
                socketRequest.timeoutInterval = 10
                let socket = self.session.webSocketTask(with: socketRequest)
                socket.maximumMessageSize = 2 * 1024 * 1024
                self.socket = socket
                self.lastReceived = Date()
                socket.resume()
                if infinity {
                    var command = join
                    command["version"] = version
                    self.sendCommand(command)
                }
                self.startHeartbeat(epoch: current)
                while !Task.isCancelled, self.epoch == current {
                    let message = try await socket.receive()
                    guard self.epoch == current, !Task.isCancelled else { return }
                    let bytes: Data
                    switch message {
                    case .string(let text): bytes = Data(text.utf8)
                    case .data(let data): bytes = data
                    @unknown default: throw GameNetworkError.invalidResponse
                    }
                    guard bytes.count <= 2 * 1024 * 1024 else { throw GameNetworkError.invalidResponse }
                    self.lastReceived = Date()
                    try self.receive(bytes)
                }
            } catch {
                guard self.epoch == current, !Task.isCancelled else { return }
                self.fail(error.localizedDescription, terminal: error is GameNetworkError)
            }
        }
    }

    /// Input sequences belong to this socket; pause always clears held controls.
    public func sendInput(_ input: GameInput, paused: Bool = false, local: Bool = false, player: Int? = nil, member: UInt64? = nil) {
        guard connected else { return }
        var sequence = local ? localSentSequence : sentSequence
        if input.seq > 0 {
            guard input.seq > sequence else { return }
            sequence = input.seq
        } else { sequence &+= 1 }
        if local { localSentSequence = sequence } else { sentSequence = sequence }
        var command: [String: Any] = ["type": "input", "seq": sequence,
            "forward": !paused && input.forward, "reverse": !paused && input.reverse,
            "left": !paused && input.left, "right": !paused && input.right,
            "fire": !paused && input.fire, "stickX": paused ? 0 : input.stickX,
            "stickY": paused ? 0 : input.stickY, "touchAim": input.touchAim, "aimOnly": input.aimOnly]
        if isInfinity { command["paused"] = paused; if local { command["local"] = true } }
        else { command["player"] = player; command["member"] = member }
        sendCommand(command)
    }

    public func sendCommand(_ command: [String: Any]) {
        guard let socket, JSONSerialization.isValidJSONObject(command),
              let data = try? JSONSerialization.data(withJSONObject: command), data.count <= 8192,
              let text = String(data: data, encoding: .utf8) else { return }
        let current = epoch, previous = sendTask
        guard queuedSends < 120 else { fail("The connection cannot keep up. Rejoin to play again."); return }
        queuedSends += 1
        sendTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.epoch == current else { return }
            defer { if self.epoch == current { self.queuedSends -= 1 } }
            do { try await socket.send(.string(text)) }
            catch {
                guard self.epoch == current, !Task.isCancelled else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    /// Retires the pilot explicitly before closing; no credentials are persisted.
    public func disconnect() {
        let oldSocket = socket
        let wasConnected = connected
        reconnectTask?.cancel(); reconnectTask = nil
        resumeContext = nil; reconnectDeadline = nil; reconnectAttempt = 0
        currentBaseURL = nil
        invalidate()
        if let oldSocket {
            Task {
                if wasConnected { try? await oldSocket.send(.string("{\"type\":\"leave\"}")) }
                oldSocket.cancel(with: .normalClosure, reason: nil)
            }
        }
    }

    private func invalidate() {
        epoch = UUID()
        connected = false
        welcome = nil
        latencySampler = NetworkLatencySampler()
        queuedSends = 0
        connectionTask?.cancel(); connectionTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        sendTask?.cancel(); sendTask = nil
        socket = nil
    }

    private func fail(_ message: String, terminal: Bool = false) {
        if !terminal, scheduleReconnect() { return }
        let oldSocket = socket
        reconnectTask?.cancel(); reconnectTask = nil
        resumeContext = nil; reconnectDeadline = nil; reconnectAttempt = 0
        invalidate()
        oldSocket?.cancel(with: .goingAway, reason: nil)
        onEvent?(.error(message))
        onEvent?(.disconnected(message))
    }

    private func scheduleReconnect(force: Bool = false) -> Bool {
        guard automaticallyReconnects || force, let context = resumeContext else { return false }
        let now = Date(), deadline = reconnectDeadline ?? Date().addingTimeInterval(18)
        guard now < deadline else { return false }
        reconnectDeadline = deadline
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let old = socket
        invalidate()
        old?.cancel(with: .goingAway, reason: nil)
        reconnectTask?.cancel()
        let current = epoch
        onEvent?(.roomEvent(.reconnecting(attempt: attempt)))
        onEvent?(.status("Reconnecting…"))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min(2, 0.3 * Double(attempt)) * 1_000_000_000))
            guard let self, !Task.isCancelled, self.epoch == current else { return }
            guard Date() < deadline else { self.fail("The reconnect window expired. Join the room again.", terminal: true); return }
            self.begin(baseURL: context.baseURL, infinity: context.infinity, join: context.command, resuming: true)
        }
        return true
    }

    private func startHeartbeat(epoch current: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !Task.isCancelled, self.epoch == current else { return }
                let started = ProcessInfo.processInfo.systemUptime
                if let deadline = self.reconnectDeadline, Date() >= deadline, !self.connected {
                    self.fail("The reconnect window expired. Join the room again.", terminal: true); return
                }
                let elapsed = Date().timeIntervalSince(self.lastReceived)
                if elapsed > (self.connected ? 12 : 8) { self.fail(GameNetworkError.timeout.localizedDescription); return }
                if self.connected, let timestamp = self.latencySampler.nextPing(at: started * 1000) {
                    self.sendCommand(["type": "ping", "t": timestamp])
                }
                try? await Task.sleep(nanoseconds: NetworkRefreshCadence.remainingNanoseconds(startedAt: started, now: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private func receive(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { throw GameNetworkError.invalidResponse }
        switch type {
        case "server_hello":
            guard !isInfinity, let version = object["version"] as? String,
                  (object["protocol"] as? Int) == 1 else { throw GameNetworkError.unsupportedProtocol }
            guard version == Self.supportedVersion else { throw GameNetworkError.unsupportedVersion(version) }
            sendCommand(["type": "client_hello", "version": version, "protocol": 1])
            sendCommand(pendingJoin)
        case "welcome":
            let info = try JSONDecoder().decode(NetworkWelcome.self, from: data)
            welcome = info
            connected = true
            startHeartbeat(epoch: epoch)
            if let baseURL = currentBaseURL {
                if let code = info.room, let token = info.token {
                    resumeContext = ResumeContext(baseURL: baseURL, infinity: false, code: code, token: token,
                                                  name: pendingJoin["name"] as? String ?? "", generation: nil)
                } else if isInfinity, info.generation != nil { resumeContext?.generation = info.generation }
            }
            reconnectDeadline = nil; reconnectAttempt = 0; reconnectTask = nil
            onEvent?(.welcome(info))
            onEvent?(.status("Connected"))
        case "identity":
            // A room can move the primary to another tank or into spectator seats.
            var identity = object
            identity["room"] = welcome?.room
            identity["token"] = welcome?.token
            let info = try JSONDecoder().decode(NetworkWelcome.self, from: JSONSerialization.data(withJSONObject: identity))
            welcome = info
            onEvent?(.welcome(info))
        case "state":
            let normalized = try SnapshotDecoder.normalized(data: data, previousWorld: lastWorld)
            lastWorld = normalized.world
            let state = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
            onEvent?(.state(state))
        case "room":
            let room = try JSONDecoder().decode(RoomInfo.self, from: data)
            if !isInfinity { resumeContext?.code = room.code }
            onEvent?(.room(room))
        case "chat", "chat_history":
            onEvent?(.roomEvent(.chat(try JSONDecoder().decode(ChatPacket.self, from: data))))
        case "queue_catalog", "queue_status", "queue_cancelled":
            onEvent?(.roomEvent(.queue(try JSONDecoder().decode(QueuePacket.self, from: data))))
        case "room_renamed":
            let rename = try JSONDecoder().decode(RoomRename.self, from: data)
            resumeContext?.code = rename.room
            welcome?.room = rename.room
            onEvent?(.roomEvent(.roomRenamed(rename)))
        case "renamed", "rename_error":
            let rename = try JSONDecoder().decode(PilotRename.self, from: data)
            if rename.type == "renamed", rename.seat == nil || rename.seat == 0, let name = rename.name { resumeContext?.name = name }
            onEvent?(.roomEvent(.pilotRenamed(rename)))
        case "swapped", "player_kicked", "unshared":
            onEvent?(.roomEvent(.notice(try JSONDecoder().decode(ServerNotice.self, from: data))))
            if type == "unshared" { disconnect() }
        case "infinity_start": onEvent?(.infinityStarted(object["public"] as? Bool ?? false))
        case "pong":
            if let t = object["t"] as? Double,
               let elapsed = latencySampler.roundTrip(echo: t, now: ProcessInfo.processInfo.systemUptime * 1000) {
                onEvent?(.latency(elapsed))
            }
        case "error":
            let message = object["message"] as? String ?? "The server rejected this action."
            onEvent?(.roomEvent(.notice(try JSONDecoder().decode(ServerNotice.self, from: data))))
            if (object["code"] as? String) == "session_active", reconnectDeadline != nil { fail(message); return }
            if !connected || (object["code"] as? String) == "kicked" || (object["action"] as? String) == "version" {
                fail(message, terminal: true)
            } else { onEvent?(.error(message)) }
        case "server_shutdown", "kicked", "room_offline":
            onEvent?(.roomEvent(.notice(try JSONDecoder().decode(ServerNotice.self, from: data))))
            fail(object["message"] as? String ?? "The server closed this session.", terminal: true)
        default: break
        }
    }
}

/// Converts finite-maze packets to the shared native rendering model while
/// retaining the server's reliable world update between periodic snapshots.
enum SnapshotDecoder {
    static let colors = ["#d2f65a", "#ff9679", "#73cee4", "#c5a2ff", "#ffc46b", "#ff83bd", "#75f0cb", "#b7c6ee"]

    static func normalized(data: Data, previousWorld: Any?) throws -> (data: Data, world: Any?) {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tanks = object["tanks"] as? [[String: Any]],
              let bullets = object["bullets"] as? [[String: Any]] else { throw GameNetworkError.invalidResponse }
        let fixed = object["phase"] != nil
        if !fixed {
            guard object["leaderboard"] is [[String: Any]] else { throw GameNetworkError.invalidResponse }
            object["pickups"] = object["pickups"] as? [[String: Any]] ?? []
            return (try JSONSerialization.data(withJSONObject: object), nil)
        }
        let scores = object["scores"] as? [Int] ?? []
        var mappedTanks: [[String: Any]] = tanks.map { raw in
            var tank = raw
            tank["hp"] = (raw["alive"] as? Bool ?? false) ? 1 : 0
            let id = raw["id"] as? Int ?? 0
            tank["score"] = scores.indices.contains(id) ? scores[id] : 0
            tank["colorIndex"] = colors.firstIndex(of: raw["color"] as? String ?? "") ?? 0
            return tank
        }
        object["tanks"] = mappedTanks
        let ranked = mappedTanks.sorted {
            let a = $0["score"] as? Int ?? 0, b = $1["score"] as? Int ?? 0
            return a != b ? a > b : ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0)
        }
        object["leaderboard"] = ranked.map { ["id": $0["id"] ?? 0, "name": $0["name"] ?? "", "score": $0["score"] ?? 0,
            "bot": $0["bot"] ?? false, "colorIndex": $0["colorIndex"] ?? 0, "team": $0["team"] ?? 0] }
        var mappedBullets = bullets.map { raw in
            var bullet = raw
            bullet["colorIndex"] = colors.firstIndex(of: raw["color"] as? String ?? "") ?? 0
            return bullet
        }
        if let packed = object["machineBullets"] as? [[Double]] {
            for row in packed where row.count == 12 {
                guard row.allSatisfy(\.isFinite), let id = Int(exactly: row[0]), let owner = Int(exactly: row[1]),
                      let bounces = Int(exactly: row[10]), let color = Int(exactly: row[11]) else { throw GameNetworkError.invalidResponse }
                mappedBullets.append(["id": id, "owner": owner, "kind": "rapid", "x": row[4], "y": row[5],
                    "vx": row[6], "vy": row[7], "age": row[8], "life": row[9], "bounces": bounces, "colorIndex": color])
            }
        }
        object["bullets"] = mappedBullets
        let boosted = Set(object["boostedBulletIds"] as? [Int] ?? [])
        let friendlyFire = (object["rules"] as? [String: Any])?["friendlyFire"] as? Bool ?? false
        for index in mappedTanks.indices {
            let id = mappedTanks[index]["id"] as? Int ?? -1
            let owned = mappedBullets.filter { ($0["owner"] as? Int) == id }
            let grenades = owned.filter { ($0["kind"] as? String) == "grenade" }
            let power = mappedTanks[index]["power"] as? String ?? ""
            mappedTanks[index]["ammoUsed"] = power == "laser" ? max(0, 3 - (mappedTanks[index]["charges"] as? Int ?? 0))
                : owned.filter { !boosted.contains($0["id"] as? Int ?? -1) }.count
            mappedTanks[index]["grenades"] = grenades.count
            mappedTanks[index]["grenadeLife"] = grenades.map { $0["life"] as? Double ?? 0 }.max() ?? 0
            mappedTanks[index]["locked"] = mappedBullets.contains { bullet in
                let kind = bullet["kind"] as? String ?? "", owner = bullet["owner"] as? Int ?? -1
                guard owner != id, (kind == "homing" || kind == "grenade"), (bullet["target"] as? Int) == id else { return false }
                let shooter = mappedTanks.first { ($0["id"] as? Int) == owner }
                let team = shooter?["team"] as? Int ?? 0
                return friendlyFire || shooter == nil || team == 0 || team != (mappedTanks[index]["team"] as? Int ?? 0)
            }
        }
        object["tanks"] = mappedTanks
        object["effects"] = (object["events"] as? [[String: Any]] ?? []).map { raw in
            var effect = raw
            let kind = raw["type"] as? String ?? ""
            effect["kind"] = kind == "shot" ? "shot:" + (raw["text"] as? String ?? "") : kind
            return effect
        }
        object["players"] = mappedTanks.filter { !($0["bot"] as? Bool ?? false) }.count
        object["tankCount"] = mappedTanks.count
        object["pickups"] = object["pickups"] as? [[String: Any]] ?? []
        let world = object["world"] as? [String: Any] ?? previousWorld
        if let world { object["world"] = world }
        return (try JSONSerialization.data(withJSONObject: object), world)
    }
}
