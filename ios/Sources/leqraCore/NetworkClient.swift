import Foundation

public struct NetworkWelcome: Decodable, Sendable {
    public let id: Int
    public let seed: UInt32?
    public var room: String?
    public let token: String?
    public let publicToken: String?
    public let localPublicToken: String?
    public let isPublic: Bool
    public let spectating: Bool
    public let following: Int?
    public let localId: Int?
    public let generation: UInt64?
    public let member: UInt64?
    public let localMember: UInt64?
    public let resumed: Bool
    public let created: Bool
    public let full: Bool
    public let busy: Bool

    enum CodingKeys: String, CodingKey {
        case id, seed, room, token, publicToken, localPublicToken, spectating, following, localId, generation, member, localMember, resumed, created, full, busy
        case isPublic = "public"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        seed = try c.decodeIfPresent(UInt32.self, forKey: .seed)
        room = try c.decodeIfPresent(String.self, forKey: .room)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        publicToken = try c.decodeIfPresent(String.self, forKey: .publicToken)
        localPublicToken = try c.decodeIfPresent(String.self, forKey: .localPublicToken)
        isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        spectating = try c.decodeIfPresent(Bool.self, forKey: .spectating) ?? false
        following = try c.decodeIfPresent(Int.self, forKey: .following)
        localId = try c.decodeIfPresent(Int.self, forKey: .localId).flatMap { $0 >= 0 ? $0 : nil }
        generation = try c.decodeIfPresent(UInt64.self, forKey: .generation)
        member = try c.decodeIfPresent(UInt64.self, forKey: .member)
        localMember = try c.decodeIfPresent(UInt64.self, forKey: .localMember).flatMap { $0 > 0 ? $0 : nil }
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
    case followed(Int)
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
    case temporarilyUnavailable
    case invalidAccountKey
    case accountKeyRevoked
    case localAccountUnconfirmed
    case localAccountMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter an HTTP or HTTPS server address."
        case .invalidResponse: return "The server sent an invalid response."
        case .unsupportedProtocol: return "This server uses an unsupported game protocol."
        case .unsupportedVersion(let version): return "This server is running leqra \(version). Update the native app before joining."
        case .timeout: return "The server stopped responding. Rejoin to play again."
        case .temporarilyUnavailable: return "The server is temporarily unavailable. Reconnecting…"
        case .invalidAccountKey: return "That account key is invalid or unavailable."
        case .accountKeyRevoked: return "The account key was reset on another device. Import its new key to sign in again."
        case .localAccountUnconfirmed: return "The server did not confirm P2's independent account. Update the server before adding P2; the saved key is unchanged."
        case .localAccountMismatch: return "This private room still uses a different P2 account. Leave and rejoin P2 to use the imported key; the saved key is unchanged."
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
/// Public identities use their own server-issued bearer credential; private
/// room reconnects retain their existing bounded reservation window.
@MainActor public final class NetworkClient {
    public static let supportedVersion = GeneratedVersion.value
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
        var spectating = false
        var target: Int?
        var publicJoin: [String: Any]? = nil
        var isPublic: Bool { publicJoin != nil }
        var command: [String: Any] {
            if let publicJoin { return publicJoin }
            var result: [String: Any] = ["type": "join", "code": code, "token": token, "name": name]
            if infinity { result["resume"] = true; result["generation"] = generation }
            if spectating { result["spectating"] = true; result["target"] = target }
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
    private var suspended = false
    /// The owner used by this transport, retained separately from room tokens.
    public private(set) var accountKey: String?
    public private(set) var localAccountKey: String?
    public private(set) var localAccountRequestKey: String?
    private var pendingLocalAccountKey: String?

    public init(session: URLSession = .shared) { self.session = session }

    deinit {
        connectionTask?.cancel()
        heartbeatTask?.cancel()
        sendTask?.cancel()
        reconnectTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    public func connectPublic(baseURL: URL, name: String, colorIndex: Int, localName: String? = nil, localColorIndex: Int = 1,
                              publicToken: String? = nil, updateNames: Bool = false,
                              localPublicToken: String? = nil, localNewAccount: Bool = false) {
        var join: [String: Any] = ["type": "join", "name": name, "colorIndex": min(7, max(0, colorIndex))]
        if let localName { join["localName"] = localName; join["localColorIndex"] = min(7, max(0, localColorIndex)) }
        if let publicToken, !publicToken.isEmpty { join["publicToken"] = publicToken; join["resume"] = true }
        if updateNames { join["updateNames"] = true }
        join["localPublicToken"] = localPublicToken
        if localNewAccount { join["localNewAccount"] = true }
        begin(baseURL: baseURL, infinity: true, join: join, resuming: publicToken?.isEmpty == false)
    }

    public func connectRoom(baseURL: URL, name: String, code: String? = nil, spectating: Bool = false, publicToken: String? = nil) {
        var join: [String: Any] = ["type": code?.isEmpty == false ? "join" : "create", "name": name]
        if let code, !code.isEmpty { join["code"] = code }
        join["spectating"] = spectating
        join["publicToken"] = publicToken
        begin(baseURL: baseURL, infinity: false, join: join)
    }

    public func connectRoomInfinity(baseURL: URL, code: String, token: String, resume: Bool = false, generation: UInt64? = nil,
                                    localPublicToken: String? = nil, localNewAccount: Bool = false, spectating: Bool = false, target: Int? = nil) {
        var join: [String: Any] = ["type": "join", "code": code, "token": token]
        if resume { join["resume"] = true; join["generation"] = generation }
        if spectating { join["spectating"] = true; if let target, target > 0 { join["target"] = target } }
        else {
            join["localPublicToken"] = localPublicToken
            if localNewAccount { join["localNewAccount"] = true }
        }
        begin(baseURL: baseURL, infinity: true, join: join, resuming: resume)
    }

    public func follow(_ target: Int) {
        guard connected, isInfinity, welcome?.spectating == true, target > 0 else { return }
        sendCommand(["type": "follow", "target": target])
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

    /// Availability never allocates or claims an identity. Only an authenticated
    /// atomic online join or rename may claim the requested names.
    public func fetchCallsignAvailability(baseURL: URL, names: [String], publicToken: String? = nil, localPublicToken: String? = nil, localNewAccount: Bool = false) async throws -> [CallsignAvailability] {
        var request = URLRequest(url: try ServerAddress.endpoint(baseURL, path: "/api/callsigns"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try PublicInfinitySession.normalizedOrigin(baseURL), forHTTPHeaderField: "Origin")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 6
        var body: [String: Any] = ["names": names]
        body["publicToken"] = publicToken
        if names.count > 1 {
            body["localPublicToken"] = localPublicToken
            body["independentAccounts"] = true
            if localNewAccount { body["localNewAccount"] = true }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 16 * 1024 else {
            throw GameNetworkError.invalidResponse
        }
        struct Result: Decodable { let names: [CallsignAvailability] }
        let result = try JSONDecoder().decode(Result.self, from: data).names
        guard result.count == names.count, result.enumerated().allSatisfy({ $0.offset == $0.element.seat }) else {
            throw GameNetworkError.invalidResponse
        }
        return result
    }

    /// Account keys travel only in the request body, never URLs or logs.
    public func generateCallsigns(baseURL: URL, requestId: UUID, accounts: [(seat: Int, publicToken: String)]) async throws -> [GeneratedCallsign] {
        guard !accounts.isEmpty, accounts.count <= 2, Set(accounts.map(\.seat)).count == accounts.count,
              Set(accounts.map(\.publicToken)).count == accounts.count,
              accounts.allSatisfy({ $0.seat == 0 || $0.seat == 1 }) else { throw GameNetworkError.invalidResponse }
        var request = URLRequest(url: try ServerAddress.endpoint(baseURL, path: "/api/callsigns/generate"))
        request.httpMethod = "POST"; request.timeoutInterval = 6; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try PublicInfinitySession.normalizedOrigin(baseURL), forHTTPHeaderField: "Origin")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["requestId": requestId.uuidString.lowercased(),
            "accounts": accounts.map { ["seat": $0.seat, "publicToken": $0.publicToken] as [String: Any] }])
        let (data, response) = try await session.data(for: request, delegate: AccountRequestRedirectGuard())
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, data.count <= 16 * 1024 else { throw GameNetworkError.invalidResponse }
        if response.statusCode == 401 { throw GameNetworkError.accountKeyRevoked }
        guard response.statusCode == 200 else { throw GameNetworkError.temporarilyUnavailable }
        struct Result: Decodable { let names: [GeneratedCallsign] }
        let names = try JSONDecoder().decode(Result.self, from: data).names
        guard names.map(\.seat).sorted() == accounts.map(\.seat).sorted(),
              names.allSatisfy({ CallsignPolicy.isGenerated($0.name) }) else { throw GameNetworkError.invalidResponse }
        return names
    }

    /// Account keys travel only in the request body, never URLs or logs.
    /// This read-only check must succeed before an imported key replaces one.
    public func fetchAccountInfo(baseURL: URL, publicToken: String) async throws -> AccountInfo {
        try JSONDecoder().decode(AccountInfo.self, from: await accountRequest(baseURL: baseURL, publicToken: publicToken, path: "/api/account"))
    }

    public func rotateAccountKey(baseURL: URL, publicToken: String, newPublicToken: String) async throws -> AccountKeyRotation {
        _ = try PublicInfinitySession(baseURL: baseURL, publicToken: newPublicToken)
        let data = try await accountRequest(baseURL: baseURL, publicToken: publicToken, path: "/api/account/rotate", replacement: newPublicToken)
        let result = try JSONDecoder().decode(AccountKeyRotation.self, from: data)
        _ = try PublicInfinitySession(baseURL: baseURL, publicToken: result.publicToken)
        guard result.publicToken == newPublicToken, result.publicToken != publicToken else { throw GameNetworkError.invalidResponse }
        return result
    }

    private func accountRequest(baseURL: URL, publicToken: String, path: String, replacement: String? = nil) async throws -> Data {
        let credential = try PublicInfinitySession(baseURL: baseURL, publicToken: publicToken)
        var request = URLRequest(url: try ServerAddress.endpoint(credential.baseURL, path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credential.origin, forHTTPHeaderField: "Origin")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 6
        var body = ["publicToken": credential.publicToken]
        body["newPublicToken"] = replacement
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request, delegate: AccountRequestRedirectGuard())
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw GameNetworkError.invalidResponse }
        if response.statusCode == 401 {
            let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if error?["code"] as? String == "account_key_revoked" { throw GameNetworkError.accountKeyRevoked }
            throw GameNetworkError.invalidAccountKey
        }
        guard response.statusCode == 200, data.count <= 16 * 1024 else { throw GameNetworkError.invalidResponse }
        return data
    }

    public func connectPublishedRoom(baseURL: URL, code: String? = nil, rules: RoomRules, roster: [NativeSeatSpec], publicToken: String? = nil,
                                     localPublicToken: String? = nil, localNewAccount: Bool = false) {
        var join = NativeRoomCommand.preset(rules: rules, roster: roster).payload
        join["type"] = "publish"; join["code"] = code
        join["publicToken"] = publicToken
        join["localPublicToken"] = localPublicToken
        if localNewAccount { join["localNewAccount"] = true }
        begin(baseURL: baseURL, infinity: false, join: join)
    }

    /// Retry the current identity without issuing a destructive leave.
    @discardableResult public func reconnect() -> Bool {
        guard resumeContext != nil else { return false }
        suspended = false
        guard scheduleReconnect(force: true) else {
            fail("The reconnect window expired.", terminal: true)
            return false
        }
        return true
    }

    /// Backgrounding must not send `leave` or allow transport callbacks to
    /// start new attempts while iOS has suspended the app.
    public func suspend() {
        suspended = true
        reconnectTask?.cancel(); reconnectTask = nil
        let old = socket
        invalidate()
        old?.cancel(with: .goingAway, reason: nil)
    }

    /// A separate room socket can rename the room while its arena socket is
    /// running. Keep the latter's in-memory resume route current as well.
    public func updateResumeRoomCode(_ code: String) {
        guard resumeContext?.isPublic != true else { return }
        resumeContext?.code = code
        if welcome?.room != nil { welcome?.room = code }
    }

    /// Infinity rename acknowledgements carry request IDs, unlike room rename.
    @discardableResult public func renameInfinity(_ name: String, seat: Int = 0) -> UInt64 {
        guard welcome?.spectating != true else { return 0 }
        renameRequestID &+= 1
        sendCommand(["type": "rename", "seat": seat, "name": name, "requestId": renameRequestID])
        return renameRequestID
    }

    private func begin(baseURL: URL, infinity: Bool, join: [String: Any], resuming: Bool = false) {
        var join = join
        join["independentAccounts"] = true
        let publicArena = infinity && join["code"] == nil
        if publicArena, join["localName"] == nil, join["localPublicToken"] == nil {
            localAccountKey = nil; localAccountRequestKey = nil
        }
        if resuming, join["spectating"] as? Bool != true, let code = join["code"] as? String, code == resumeContext?.code,
           join["localPublicToken"] == nil, let localAccountKey { join["localPublicToken"] = localAccountKey }
        if resuming {
            let old = socket
            invalidate()
            old?.cancel(with: .goingAway, reason: nil)
            reconnectTask = nil
            reconnectDeadline = publicArena ? nil : reconnectDeadline ?? Date().addingTimeInterval(18)
        } else { disconnect() }
        suspended = false
        currentBaseURL = baseURL
        if publicArena {
            resumeContext = ResumeContext(baseURL: baseURL, infinity: true, code: "", token: "",
                name: join["name"] as? String ?? "", generation: nil, publicJoin: join)
        } else if infinity, let code = join["code"] as? String, let token = join["token"] as? String {
            resumeContext = ResumeContext(baseURL: baseURL, infinity: true, code: code, token: token,
                                          name: join["name"] as? String ?? "", generation: join["generation"] as? UInt64,
                                          spectating: join["spectating"] as? Bool ?? false, target: join["target"] as? Int)
        }
        isInfinity = infinity
        pendingJoin = join
        accountKey = join["publicToken"] as? String ?? accountKey
        pendingLocalAccountKey = join["localPublicToken"] as? String
        localAccountRequestKey = pendingLocalAccountKey
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
                guard let response = response as? HTTPURLResponse else { throw GameNetworkError.invalidResponse }
                if response.statusCode == 429 || response.statusCode >= 500 { throw GameNetworkError.temporarilyUnavailable }
                guard response.statusCode == 200,
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
                let terminal: Bool
                switch error as? GameNetworkError {
                case .timeout, .temporarilyUnavailable, .none: terminal = false
                default: terminal = true
                }
                self.fail(error.localizedDescription, terminal: terminal)
            }
        }
    }

    /// Input sequences belong to this socket; pause always clears held controls.
    public func sendInput(_ input: GameInput, paused: Bool = false, local: Bool = false, player: Int? = nil, member: UInt64? = nil) {
        guard connected, welcome?.spectating != true else { return }
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
        if let key = command["localPublicToken"] as? String, key != "" { pendingLocalAccountKey = key; localAccountRequestKey = key }
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

    /// Retires the live pilot explicitly. Device credential storage belongs to
    /// the app layer and is independent of this transport's in-memory context.
    public func disconnect() {
        let oldSocket = socket
        let wasConnected = connected
        reconnectTask?.cancel(); reconnectTask = nil
        resumeContext = nil; reconnectDeadline = nil; reconnectAttempt = 0
        currentBaseURL = nil
        accountKey = nil
        localAccountKey = nil; pendingLocalAccountKey = nil; localAccountRequestKey = nil
        suspended = false
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
        guard !suspended, automaticallyReconnects || force, let context = resumeContext else { return false }
        let now = Date(), deadline = context.isPublic ? nil : reconnectDeadline ?? Date().addingTimeInterval(18)
        if let deadline, now >= deadline { return false }
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
            let backoff = context.isPublic ? min(10, 0.3 * pow(1.6, Double(min(attempt - 1, 8)))) : min(2, 0.3 * Double(attempt))
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            guard let self, !Task.isCancelled, self.epoch == current else { return }
            if let deadline, Date() >= deadline { self.fail("The reconnect window expired. Join the room again.", terminal: true); return }
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

    func receive(_ data: Data) throws {
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
            if let expected = pendingLocalAccountKey, info.localPublicToken != expected {
                guard info.localPublicToken != nil else { throw GameNetworkError.localAccountUnconfirmed }
                let roomRecoveredFreshCandidate = pendingJoin["code"] != nil && pendingJoin["localNewAccount"] as? Bool == true && info.resumed
                guard roomRecoveredFreshCandidate else { throw GameNetworkError.localAccountMismatch }
            }
            if let local = info.localPublicToken, local == info.publicToken { throw GameNetworkError.localAccountUnconfirmed }
            welcome = info
            if let key = info.publicToken { accountKey = key }
            if let key = info.localPublicToken { localAccountKey = key; pendingLocalAccountKey = nil }
            else if info.localId == nil { localAccountKey = nil; localAccountRequestKey = nil; pendingLocalAccountKey = nil }
            connected = true
            startHeartbeat(epoch: epoch)
            if let baseURL = currentBaseURL {
                if isInfinity, info.isPublic, let publicToken = info.publicToken {
                    var join = resumeContext?.publicJoin ?? pendingJoin
                    join["code"] = nil; join["token"] = nil; join["generation"] = nil
                    join["updateNames"] = nil
                    join["publicToken"] = publicToken; join["resume"] = true
                    join["independentAccounts"] = true
                    join["localPublicToken"] = info.localPublicToken
                    join["localNewAccount"] = nil
                    resumeContext = ResumeContext(baseURL: baseURL, infinity: true, code: "", token: "",
                        name: join["name"] as? String ?? "", generation: nil, publicJoin: join)
                } else if let code = info.room, let token = info.token {
                    resumeContext = ResumeContext(baseURL: baseURL, infinity: isInfinity, code: code, token: token,
                                                  name: pendingJoin["name"] as? String ?? "", generation: nil,
                                                  spectating: info.spectating)
                } else if isInfinity, info.generation != nil { resumeContext?.generation = info.generation }
            }
            reconnectDeadline = nil; reconnectAttempt = 0; reconnectTask = nil
            if isInfinity, info.spectating { resumeContext?.target = info.following }
            onEvent?(.welcome(info))
            onEvent?(.status("Connected"))
        case "identity":
            // A room can move the primary to another tank or into spectator seats.
            var identity = object
            identity["room"] = welcome?.room
            identity["token"] = welcome?.token
            let info = try JSONDecoder().decode(NetworkWelcome.self, from: JSONSerialization.data(withJSONObject: identity))
            if info.localId != nil, let expected = pendingLocalAccountKey, info.localPublicToken != expected { throw GameNetworkError.localAccountUnconfirmed }
            if let key = info.publicToken { accountKey = key }
            if let key = info.localPublicToken { localAccountKey = key; pendingLocalAccountKey = nil }
            else if info.localId == nil { localAccountKey = nil; localAccountRequestKey = nil; pendingLocalAccountKey = nil }
            welcome = info
            if !isInfinity { resumeContext?.spectating = info.spectating }
            onEvent?(.welcome(info))
        case "state":
            let normalized = try SnapshotDecoder.normalized(data: data, previousWorld: lastWorld)
            lastWorld = normalized.world
            let state = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
            if isInfinity, state.spectating { resumeContext?.target = state.following }
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
            if rename.type == "renamed", rename.seat == nil || rename.seat == 0, let name = rename.name {
                resumeContext?.name = name; resumeContext?.publicJoin?["name"] = name
            }
            onEvent?(.roomEvent(.pilotRenamed(rename)))
        case "swapped", "player_kicked", "unshared", "leaderboard_reset":
            onEvent?(.roomEvent(.notice(try JSONDecoder().decode(ServerNotice.self, from: data))))
            if type == "unshared" { disconnect() }
        case "infinity_start": onEvent?(.infinityStarted(object["public"] as? Bool ?? false))
        case "followed":
            guard let following = object["following"] as? Int, following >= 0 else { throw GameNetworkError.invalidResponse }
            if isInfinity, welcome?.spectating == true { resumeContext?.target = following }
            onEvent?(.followed(following))
        case "pong":
            if let t = object["t"] as? Double,
               let elapsed = latencySampler.roundTrip(echo: t, now: ProcessInfo.processInfo.systemUptime * 1000) {
                onEvent?(.latency(elapsed))
            }
        case "error":
            let message = object["message"] as? String ?? "The server rejected this action."
            let code = object["code"] as? String
            if resumeContext?.isPublic == true {
                if code == "public_resume_invalid", (object["seat"] as? Int ?? 0) == 0, pendingJoin["publicToken"] != nil,
                   let context = resumeContext, var join = context.publicJoin {
                    join["publicToken"] = nil; join["resume"] = nil
                    begin(baseURL: context.baseURL, infinity: true, join: join, resuming: true)
                    return
                }
                if ["server_shutdown", "server_busy", "full", "arena_full", "busy", "session_active"].contains(code ?? "") {
                    fail(message); return
                }
            }
            let noticeEpoch = epoch
            onEvent?(.roomEvent(.notice(try JSONDecoder().decode(ServerNotice.self, from: data))))
            guard epoch == noticeEpoch else { return }
            if (object["code"] as? String) == "session_active", reconnectDeadline != nil { fail(message); return }
            if !connected || code == "kicked" || code == "session_replaced" || code == "account_key_revoked" || (object["action"] as? String) == "version" {
                fail(message, terminal: true)
            } else if (object["action"] as? String) != "follow" { onEvent?(.error(message)) }
        case "server_shutdown", "kicked", "room_offline":
            if type == "server_shutdown", resumeContext?.isPublic == true { fail("Reconnecting after server restart…"); return }
            onEvent?(.roomEvent(.notice(try JSONDecoder().decode(ServerNotice.self, from: data))))
            fail(object["message"] as? String ?? "The server closed this session.", terminal: true)
        default: break
        }
    }
}

/// A key is scoped to the exact configured origin. Never forward its POST body
/// through an HTTP redirect, even if a server was misconfigured.
private final class AccountRequestRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
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
