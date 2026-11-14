import SwiftUI
import SpriteKit
import QuartzCore
import leqraCore

private enum AccountActionError: LocalizedError {
    case finishOnline, serverChanged, keychain, duplicateAccount
    var errorDescription: String? {
        switch self {
        case .finishOnline: return "Return to the offline ready room before changing account keys."
        case .serverChanged: return "The server changed. Check the account key again."
        case .keychain: return "The pending key could not be saved in Keychain. Your current key is unchanged."
        case .duplicateAccount: return "P1 and P2 need different account keys. This key is already assigned to the other local player."
        }
    }
}

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
    @Published private(set) var spectating = false
    @Published private(set) var followingID = 0
    @Published private(set) var followError = ""
    @Published var showScores = false
    @Published var showSettings = false { didSet { refreshStarmanActivity() } }
    @Published var showAccount = false { didSet { refreshStarmanActivity() } }
    @Published var accountSeatContext = 0
    @Published var accountInfo: AccountInfo?
    @Published var accountStatus = ""
    @Published var accountBusy = false
    @Published var accountRecoveryKeyPending = false
    @Published var accountPendingKeyVerified = false
    @Published var accountSavedActivationCount = 0
    @Published var showRules = false { didSet { refreshStarmanActivity() } }
    @Published var showControls = false { didSet { refreshStarmanActivity() } }
    @Published var showSidebar = false { didSet { refreshStarmanActivity() } }
    @Published var showJoin = false { didSet { refreshStarmanActivity() } }
    @Published var showChat = false { didSet { refreshStarmanActivity() } }
    @Published var showQueues = false { didSet { refreshStarmanActivity() } }
    @Published var showPresets = false { didSet { refreshStarmanActivity() } }
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
    @Published var callsignFeedback = ""
    @Published var localCallsignFeedback = ""
    @Published var callsignChecking = false
    @Published var callsignGenerating = false
    @Published var callsignReserved = false
    @Published var localCallsignReserved = false
    @Published var localCallsignTaken = false
    @Published var godlikeNotice = ""
    @Published var callsign: String {
        didSet {
            guard oldValue != callsign else { return }
            if !applyingGeneratedCallsign { callsignDrafts.editorChanged(from: oldValue, to: callsign, seat: 0) }
            scheduleCallsignAvailability()
        }
    }
    @Published var localCallsign: String {
        didSet {
            guard oldValue != localCallsign else { return }
            if !applyingGeneratedCallsign { callsignDrafts.editorChanged(from: oldValue, to: localCallsign, seat: 1) }
        }
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
    private let publicSessions: PublicInfinitySessionStoring
    private let callsignDrafts: CallsignDraftStore
    private var applyingGeneratedCallsign = false
    private var nextAutomaticGeneration = 0.0
    private var pendingOnlineAction: UUID?
    private var spawnNotices = GodlikeSpawnNotices()
    private var spawnNoticeTask: Task<Void, Never>?
    private var spawnNoticeOrigin: String?
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
    private var previousPresentedPhase = ""
    private var weaponsLiveRemaining = 0.0
    private var modeProfiles: [String: RoomRules] = [:]
    private var frameProfiler: FrameProfiler?
    private var publicIdentityActive = false
    private var publicRecoveryPending = false
    private var publicResumePaused = false
    private var publicSuspended = false
    private var lifecycleInactive = false
    private var audioStateFresh = false
    @Published private(set) var presentingFinalShot = false
    private var roomInfinityEntryWanted = false
    private var spectatorRecoveryPending = false
    private var spectatorResumePaused = false
    private var resumeAfterActivation = false
    private var publicScoreResetPending = false
    private var callsignCheckTask: Task<Void, Never>?
    private var callsignTaken = false
    private var rejectedCallsignMessage: String?
    private var accountTask: Task<Void, Never>?
    private var accountOperation = UUID()

    init(publicSessions: PublicInfinitySessionStoring? = nil) {
        let sessions = publicSessions ?? KeychainPublicInfinitySessions.applicationStore()
        self.publicSessions = sessions
        let drafts = CallsignDraftStore()
        let server = URL(string: UserDefaults.standard.string(forKey: "serverURL") ?? "https://leqra.com")
        let unowned = Set((0...1).filter { seat in server.map { !sessions.hasStoredCredential(for: $0, seat: seat) } ?? false })
        drafts.migrateLegacyDefaults { !unowned.contains($0) }
        callsignDrafts = drafts
        callsign = drafts.name(seat: 0); localCallsign = drafts.name(seat: 1)
        localRules.infinity = false
        if let data = UserDefaults.standard.data(forKey: "nativePresets"), let presets = try? JSONDecoder().decode([LocalPreset].self, from: data) { savedPresets = presets }
        for index in savedPresets.indices {
            if let roster = savedPresets[index].roster {
                savedPresets[index].roster = CallsignPolicy.migratingLegacyRoster(roster, primaryName: callsign, secondaryName: localCallsign, unownedSeats: unowned)
            }
        }
        if !savedPresets.isEmpty { UserDefaults.standard.set(try? JSONEncoder().encode(savedPresets), forKey: "nativePresets") }
        scene.scaleMode = .resizeFill
        scene.onFrame = { [weak self] dt in self?.frame(dt) }
        roomClient.onEvent = { [weak self] event in self?.receive(event, arena: false) }
        arenaClient.onEvent = { [weak self] event in self?.receive(event, arena: true) }
        if ProcessInfo.processInfo.arguments.contains("--native-performance-probe") {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.leave(clearPublicIntent: false)
                let profiler = FrameProfiler(arguments: ProcessInfo.processInfo.arguments)
                self.frameProfiler = profiler
                self.practice = PracticeArena(seed: 42, name: "PROBE PILOT", colorIndex: 0, botCount: 0)
                self.maze = profiler.maze; self.localID = 1
                self.localRules.infinity = true; self.publicInfinitySelected = false
                self.scene.profilesRendering = true
                self.screen = .playing
                UIApplication.shared.isIdleTimerDisabled = true
                self.applyAudioSetting()
            }
        } else if ProcessInfo.processInfo.arguments.contains("--native-render-probe") {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.publicInfinitySelected = false
                self.localRules.infinity = true
                self.localRules.infinityRandomBots = true
                self.startLocal()
            }
        } else if !ProcessInfo.processInfo.arguments.contains("--skip-public-session-restore") {
            Task { @MainActor [weak self] in self?.restorePublicSessionIfNeeded() }
        }
        if !ProcessInfo.processInfo.arguments.contains("--native-performance-probe"), !ProcessInfo.processInfo.arguments.contains("--native-render-probe") {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let pending = [0, 1].filter { self.callsignDrafts.automaticPending(seat: $0) }
                if !pending.isEmpty { await self.generateCallsigns(seats: pending, automatic: true) }
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
    var canFollowTanks: Bool { arenaActive && spectating && !disconnected && arenaClient.connected }
    var followingName: String? {
        guard followingID > 0 else { return nil }
        if let entry = standings.first(where: { $0.id == followingID }) { return CallsignPolicy.displayName(entry.name, bot: entry.bot) }
        return lastSnapshot.tanks.first(where: { $0.id == followingID }).map { CallsignPolicy.displayName($0.name, bot: $0.bot) }
    }
    var spectatorFollowingLabel: String { followingName.map { "FOLLOWING " + $0 } ?? "WAITING FOR TANKS" }
    func localPilotSeat(_ id: Int) -> Int? {
        guard !spectating, id >= 0 else { return nil }
        if id == localID { return 1 }
        if id == secondaryAudioPilotID { return 2 }
        return nil
    }
    func followTank(_ id: Int) {
        guard canFollowTanks, id > 0, standings.contains(where: { $0.id == id }) else { return }
        followError = ""
        arenaClient.follow(id)
    }
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
    var hasModal: Bool { showSettings || showAccount || showRules || showControls || showSidebar || showJoin || showChat || showPresets || showQueues }
    var canImportAccount: Bool {
        screen == .menu && room == nil && !arenaActive && !publicIdentityActive && !publicRecoveryPending
            && !roomClient.connected && !arenaClient.connected && !pendingShare
    }
    var accountOrigin: String { accountServer.flatMap { try? PublicInfinitySession.normalizedOrigin($0) } ?? "Invalid server address" }
    var accountLocalPlayer: RoomMember? { room?.players.first { $0.kind == "local" && $0.owner == welcome?.id } }
    var accountContextIdentity: String {
        accountSeatContext == 1 ? (accountLocalPlayer?.name ?? accountInfo?.publicProfile?.name ?? localCallsign) + " (P2)" : identity
    }
    var accountHasKey: Bool { accountServer.map { accountSession(for: $0, seat: accountSeatContext) != nil || publicSessions.pendingKey(for: $0, seat: accountSeatContext) != nil } ?? false }
    var accountCanCopyKey: Bool {
        accountPendingKeyVerified || (accountServer.map { accountSession(for: $0, seat: accountSeatContext) != nil && (accountInfo != nil || !publicSessions.registrationPending(for: $0, seat: accountSeatContext)) } ?? false)
    }
    var accountCanResetKey: Bool { accountServer.map { accountHasKey && !publicSessions.registrationPending(for: $0, seat: accountSeatContext) } ?? false }
    private var accountServer: URL? {
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              (try? PublicInfinitySession.normalizedOrigin(url)) != nil else { return nil }
        return url
    }

    struct CheckedAccount {
        let credential: PublicInfinitySession
        let info: AccountInfo
        let seat: Int
    }

    private func accountSession(for server: URL, seat: Int = 0) -> PublicInfinitySession? { publicSessions.session(for: server, seat: seat) }
    private func checkedAccountSession(for server: URL, seat: Int = 0) throws -> PublicInfinitySession? {
        let saved = accountSession(for: server, seat: seat)
        guard saved != nil || !publicSessions.hasStoredCredential(for: server, seat: seat) else { throw GameNetworkError.invalidAccountKey }
        return saved
    }

    private func prepareLocalAccount(for server: URL) throws -> (key: String, fresh: Bool) {
        if let existing = accountSession(for: server, seat: 1) {
            guard existing.publicToken != accountSession(for: server)?.publicToken else { throw AccountActionError.duplicateAccount }
            return (existing.publicToken, publicSessions.registrationPending(for: server, seat: 1))
        }
        guard !publicSessions.hasStoredCredential(for: server, seat: 1) else { throw GameNetworkError.invalidAccountKey }
        let candidate = try KeychainPublicInfinitySessions.newCredential(for: server)
        guard publicSessions.rememberNew(candidate, seat: 1) else { throw AccountActionError.keychain }
        return (candidate.publicToken, true)
    }

    func generateRandomCallsign(seat: Int = 0) {
        Task { @MainActor [weak self] in await self?.generateCallsigns(seats: [seat == 1 ? 1 : 0], automatic: false) }
    }

    private func generateCallsigns(seats: [Int], automatic: Bool, offlineRepair: Bool = true) async {
        guard !callsignGenerating, let server = accountServer else { return }
        if automatic {
            guard readyRoom, room == nil, ProcessInfo.processInfo.systemUptime >= nextAutomaticGeneration else { return }
            nextAutomaticGeneration = ProcessInfo.processInfo.systemUptime + 5
        }
        let address = serverAddress
        callsignGenerating = true
        defer { callsignGenerating = false }
        var pendingAttempt: CallsignGenerationAttempt?
        var pendingCredentials: [(seat: Int, credential: PublicInfinitySession)] = []
        do {
            var requested = seats
            // Preferences may be fresh after reinstall while Keychain still
            // contains an account. Recover its name instead of renaming it.
            if automatic {
                let draft = try callsignDrafts.begin(server: server, seats: requested)
                for seat in requested {
                    if let credential = accountSession(for: server, seat: seat), !publicSessions.registrationPending(for: server, seat: seat),
                       let info = try? await arenaClient.fetchAccountInfo(baseURL: server, publicToken: credential.publicToken), let name = info.preferredCallsign,
                       serverAddress == address, accountSession(for: server, seat: seat) == credential,
                       callsignDrafts.apply(name, seat: seat, attempt: draft) {
                        if let previous = draft.drafts.first(where: { $0.seat == seat })?.name { updateGeneratedPresets(seat: seat, previous: previous, claimed: name) }
                        applyingGeneratedCallsign = true
                        if seat == 1 { localCallsign = name } else { callsign = name }
                        applyingGeneratedCallsign = false
                    }
                }
                requested = requested.filter { callsignDrafts.automaticPending(seat: $0) }
                if requested.isEmpty { callsignDrafts.complete(draft); return }
            }
            var credentials: [(seat: Int, credential: PublicInfinitySession)] = []
            for seat in requested {
                let credential: PublicInfinitySession
                if let saved = accountSession(for: server, seat: seat) { credential = saved }
                else {
                    guard !publicSessions.hasStoredCredential(for: server, seat: seat) else { throw GameNetworkError.invalidAccountKey }
                    credential = try KeychainPublicInfinitySessions.newCredential(for: server)
                    guard publicSessions.rememberNew(credential, seat: seat) else { throw AccountActionError.keychain }
                }
                guard credential.publicToken != accountSession(for: server, seat: seat == 1 ? 0 : 1)?.publicToken else { throw AccountActionError.duplicateAccount }
                credentials.append((seat, credential))
            }
            // Persist the UUID and both independent keys before contacting the
            // atomic endpoint; ambiguous failures retry this exact request.
            let attempt = try callsignDrafts.begin(server: server, seats: requested)
            pendingAttempt = attempt; pendingCredentials = credentials
            let names = try await arenaClient.generateCallsigns(baseURL: server, requestId: attempt.requestId,
                accounts: credentials.map { ($0.seat, $0.credential.publicToken) })
            guard serverAddress == address else { return }
            if automatic, !readyRoom || room != nil { return }
            for generated in names {
                guard let saved = credentials.first(where: { $0.seat == generated.seat }),
                      accountSession(for: server, seat: generated.seat) == saved.credential else { continue }
                if generated.seat == 0, !publicSessions.confirm(saved.credential, requested: saved.credential.publicToken, seat: 0) { throw AccountActionError.keychain }
                guard callsignDrafts.apply(generated.name, seat: generated.seat, attempt: attempt) else { continue }
                if automatic, let previous = attempt.drafts.first(where: { $0.seat == generated.seat })?.name {
                    updateGeneratedPresets(seat: generated.seat, previous: previous, claimed: generated.name)
                }
                applyingGeneratedCallsign = true
                if generated.seat == 1 { localCallsign = generated.name } else { callsign = generated.name }
                applyingGeneratedCallsign = false
                if !automatic {
                    if generated.seat == 0 { callsignTaken = false; saveCallsign() }
                    else if let local = accountLocalPlayer { send(.renameLocal(target: local.id, member: local.member, name: generated.name)) }
                }
            }
            callsignDrafts.complete(attempt)
            scheduleCallsignAvailability(localName: localCallsign)
        } catch {
            if !automatic, serverAddress == address {
                let unavailable = (error as? URLError).map { [.notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost, .timedOut].contains($0.code) } ?? false
                if offlineRepair, unavailable, let attempt = pendingAttempt {
                    for saved in pendingCredentials where accountSession(for: server, seat: saved.seat) == saved.credential {
                        if let name = try? callsignDrafts.provisionalName(seat: saved.seat, attempt: attempt) {
                            applyingGeneratedCallsign = true
                            if saved.seat == 1 { localCallsign = name } else { callsign = name }
                            applyingGeneratedCallsign = false
                            if saved.seat == 0, offline { saveCallsign() }
                        }
                    }
                    scheduleCallsignAvailability(localName: localCallsign)
                    status = "Random callsign ready offline. Connect to reserve it before going online."
                } else {
                    let message = error.localizedDescription
                    if seats.contains(0) { callsignFeedback = message } else { localCallsignFeedback = message }
                }
            }
        }
    }

    private func finishPendingCallsigns(seats: [Int], action: @escaping @MainActor () -> Void) -> Bool {
        let pending = seats.filter { callsignDrafts.automaticPending(seat: $0) }
        guard !pending.isEmpty else { return false }
        let operation = UUID(); pendingOnlineAction = operation
        status = "Reserving the random callsign before going online…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.callsignGenerating {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard self.pendingOnlineAction == operation else { return }
            }
            await self.generateCallsigns(seats: pending, automatic: false, offlineRepair: false)
            guard self.pendingOnlineAction == operation else { return }
            self.pendingOnlineAction = nil
            if pending.allSatisfy({ !self.callsignDrafts.automaticPending(seat: $0) }) { action() }
            else { self.status = "Connect to reserve the generated callsign before going online." }
        }
        return true
    }

    private func installAuthoritativeCallsign(_ name: String, seat: Int) {
        callsignDrafts.edited(name, seat: seat)
        applyingGeneratedCallsign = true
        if seat == 1 { localCallsign = name } else { callsign = name }
        applyingGeneratedCallsign = false
        scheduleCallsignAvailability(localName: localCallsign)
    }

    private func validPlayerCallsign(_ name: String, seat: Int) -> Bool {
        guard CallsignPolicy.reservedForBots(name) else { return true }
        if seat == 1 { localCallsignReserved = true; localCallsignFeedback = "Reserved for bots." }
        else { callsignReserved = true; callsignFeedback = "Reserved for bots." }
        return false
    }

    func openAccount(seat: Int = 0) {
        accountSeatContext = seat == 1 ? 1 : 0
        let slot = accountSeatContext
        // A rejected join may leave an inactive route object behind. It must
        // not block account import after the client has returned to the menu.
        if screen == .menu, room == nil, !roomClient.connected, !arenaClient.connected, !publicRecoveryPending {
            roomClient.disconnect(); arenaClient.disconnect()
            arenaActive = false; publicIdentityActive = false
            if slot == 0 { publicSessions.activate(nil) }
        }
        showSettings = false; showAccount = true
        let operation = UUID(); accountOperation = operation
        accountTask?.cancel(); accountInfo = nil; accountStatus = ""
        guard let server = accountServer else { accountStatus = "Enter a valid online server address in Settings."; return }
        accountSavedActivationCount = savedAccountActivations(for: server, seat: slot).count
        accountRecoveryKeyPending = publicSessions.pendingKey(for: server, seat: slot) != nil
        accountPendingKeyVerified = false
        guard let credential = accountSession(for: server, seat: slot) ?? publicSessions.pendingKey(for: server, seat: slot)?.previous else {
            accountStatus = publicSessions.hasStoredCredential(for: server, seat: slot) ? GameNetworkError.invalidAccountKey.localizedDescription
                : slot == 1 ? "Import P2's key, or add P2 to an online room to create its own account." : "Go online once to create an account key, or import one below."
            return
        }
        accountBusy = true
        accountTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let pending = self.publicSessions.pendingKey(for: server, seat: slot) {
                    do {
                        let info = try await self.arenaClient.fetchAccountInfo(baseURL: server, publicToken: pending.replacement.publicToken)
                        guard !Task.isCancelled else { return }
                        self.finishAccountReset(pending, info: info, seat: slot, operation: operation)
                        if self.accountOperation == operation { self.accountBusy = false }; return
                    } catch GameNetworkError.invalidAccountKey {
                        // No committed replacement exists yet. Keep both keys
                        // safely in Keychain and permit retrying this candidate.
                    }
                }
                let info = try await self.arenaClient.fetchAccountInfo(baseURL: server, publicToken: credential.publicToken)
                guard !Task.isCancelled, self.accountOperation == operation, let current = self.accountServer, credential.matches(current), self.showAccount else { return }
                if slot == 0, self.publicSessions.registrationPending(for: server, seat: slot), self.publicSessions.session(for: server, seat: slot) == credential {
                    self.publicSessions.remember(credential, seat: slot)
                }
                self.accountInfo = info; self.accountBusy = false
                if self.accountRecoveryKeyPending { self.accountStatus = "A key reset is pending. Retry reset to finish it safely." }
            } catch {
                guard !Task.isCancelled, self.accountOperation == operation, self.showAccount else { return }
                if case GameNetworkError.accountKeyRevoked = error {
                    await self.resolveRevokedAccount(credential, seat: slot, operation: operation)
                    if self.accountOperation == operation { self.accountBusy = false }
                    return
                }
                self.accountBusy = false
                if case GameNetworkError.invalidAccountKey = error, self.publicSessions.registrationPending(for: server, seat: slot) {
                    self.accountStatus = "This P2 key is saved securely and awaits activation. Go online with P2 to finish registering it."
                } else { self.accountStatus = error.localizedDescription }
            }
        }
    }

    func closeAccount() {
        accountOperation = UUID()
        accountTask?.cancel(); accountBusy = false; showAccount = false
    }

    func copyAccountKey() {
        let slot = accountSeatContext
        guard let server = accountServer,
              let credential = accountPendingKeyVerified ? publicSessions.pendingKey(for: server, seat: slot)?.replacement : accountSession(for: server, seat: slot) else { return }
        UIPasteboard.general.setItems([["public.utf8-plain-text": credential.publicToken]],
                                     options: [.localOnly: false, .expirationDate: Date().addingTimeInterval(600)])
        accountStatus = "Account key copied. Paste it only on a device you trust."
    }

    private func savedAccountActivations(for server: URL, seat: Int) -> [PublicInfinitySession] {
        let selected = accountSession(for: server, seat: seat)
        return publicSessions.registrationCandidates(for: server, seat: seat).filter { $0 != selected }
    }

    func checkSavedActivation(_ index: Int) async throws -> CheckedAccount {
        guard canImportAccount, let server = accountServer else { throw AccountActionError.finishOnline }
        let saved = savedAccountActivations(for: server, seat: accountSeatContext)
        guard saved.indices.contains(index) else { throw GameNetworkError.invalidResponse }
        return try await checkAccountKey(saved[index].publicToken)
    }

    func checkAccountKey(_ draft: String) async throws -> CheckedAccount {
        let slot = accountSeatContext
        guard slot == accountSeatContext, canImportAccount, !accountRecoveryKeyPending, let server = accountServer else { throw AccountActionError.finishOnline }
        let credential = try PublicInfinitySession(baseURL: server, publicToken: draft.trimmingCharacters(in: .whitespacesAndNewlines))
        guard accountSession(for: server, seat: 1 - slot)?.publicToken != credential.publicToken else { throw AccountActionError.duplicateAccount }
        let info = try await arenaClient.fetchAccountInfo(baseURL: server, publicToken: credential.publicToken)
        guard slot == accountSeatContext, canImportAccount, let configured = accountServer, credential.matches(configured) else { throw AccountActionError.serverChanged }
        return CheckedAccount(credential: credential, info: info, seat: slot)
    }

    @discardableResult func useAccount(_ checked: CheckedAccount) async -> Bool {
        let slot = checked.seat
        guard slot == accountSeatContext, canImportAccount, !accountRecoveryKeyPending, let server = accountServer, checked.credential.matches(server) else {
            accountStatus = AccountActionError.finishOnline.localizedDescription; return false
        }
        let info: AccountInfo
        do {
            info = try await arenaClient.fetchAccountInfo(baseURL: server, publicToken: checked.credential.publicToken)
            try Task.checkCancellation()
            guard slot == accountSeatContext, canImportAccount, let current = accountServer, checked.credential.matches(current) else { throw AccountActionError.serverChanged }
        } catch { accountStatus = error.localizedDescription; return false }
        guard publicSessions.remember(checked.credential, seat: slot) else {
            accountStatus = "The account key could not be saved in Keychain. Your previous key is unchanged."; return false
        }
        clearAccountIntent(for: checked.credential, seat: slot)
        accountInfo = info
        if let name = info.preferredCallsign { installAuthoritativeCallsign(name, seat: slot) }
        accountSavedActivationCount = savedAccountActivations(for: server, seat: slot).count
        scheduleCallsignAvailability()
        accountStatus = "Account imported. PLAY will use its callsign and server score."
        return true
    }

    func resetAccountKey() async {
        let slot = accountSeatContext
        guard canImportAccount, !accountBusy, let server = accountServer,
              !publicSessions.registrationPending(for: server, seat: slot),
              let previous = accountSession(for: server, seat: slot) ?? publicSessions.pendingKey(for: server, seat: slot)?.previous else { return }
        let operation = UUID(); accountOperation = operation
        accountBusy = true; accountStatus = "Resetting account key…"
        do {
            let pending: PendingAccountKey
            if let existing = publicSessions.pendingKey(for: server, seat: slot) { pending = existing }
            else {
                pending = PendingAccountKey(previous: previous, replacement: try KeychainPublicInfinitySessions.replacement(for: previous))
                guard clearAccountIntent(for: previous, seat: slot), publicSessions.rememberPendingKey(pending, seat: slot) else {
                    throw AccountActionError.keychain
                }
            }
            accountRecoveryKeyPending = true
            // A lost HTTP response or process termination cannot lose the new
            // key: its candidate was committed to Keychain before this request.
            let info: AccountInfo
            do {
                info = try await arenaClient.fetchAccountInfo(baseURL: server, publicToken: pending.replacement.publicToken)
            } catch GameNetworkError.invalidAccountKey {
                info = try await arenaClient.rotateAccountKey(baseURL: server, publicToken: pending.previous.publicToken,
                                                             newPublicToken: pending.replacement.publicToken).account
            }
            finishAccountReset(pending, info: info, seat: slot, operation: operation)
        } catch {
            guard accountOperation == operation else { return }
            if case GameNetworkError.accountKeyRevoked = error { await resolveRevokedAccount(previous, seat: slot, operation: operation) }
            else {
                accountStatus = accountRecoveryKeyPending
                    ? "Reset could not be confirmed. Both keys are saved securely; reopen Account key or retry reset."
                    : error.localizedDescription
            }
        }
        if accountOperation == operation { accountBusy = false }
    }

    private func finishAccountReset(_ pending: PendingAccountKey, info: AccountInfo, seat slot: Int, operation: UUID) {
        let saved = publicSessions.session(for: pending.replacement.baseURL, seat: slot)
        let latest = publicSessions.pendingKey(for: pending.replacement.baseURL, seat: slot)
        guard (latest?.replacement == pending.replacement || latest == nil && saved == pending.replacement),
              saved == nil || saved == pending.previous || saved == pending.replacement else { return }
        if accountOperation == operation { accountPendingKeyVerified = true }
        guard publicSessions.remember(pending.replacement, seat: slot) else {
            if accountOperation == operation { accountStatus = "The new key is saved as pending, but could not be activated. Retry reset to finish saving it." }
            return
        }
        publicSessions.clearPendingKey(pending.replacement.baseURL, ifMatching: pending.replacement.publicToken, seat: slot)
        clearAccountIntent(for: pending.replacement, seat: slot)
        guard accountOperation == operation else { return }
        accountRecoveryKeyPending = accountServer.flatMap { publicSessions.pendingKey(for: $0, seat: accountSeatContext) } != nil
        accountPendingKeyVerified = false
        if let current = accountServer, pending.replacement.matches(current) {
            accountInfo = info
            if let name = info.preferredCallsign { installAuthoritativeCallsign(name, seat: slot) }
            scheduleCallsignAvailability()
        }
        accountStatus = "New account key saved for \(pending.replacement.origin). All other devices are signed out; names and scores are unchanged."
    }

    private func resolveRevokedAccount(_ credential: PublicInfinitySession, seat slot: Int, operation: UUID) async {
        guard let pending = publicSessions.pendingKey(for: credential.baseURL, seat: slot) else {
            discardRevokedAccount(credential, seat: slot)
            accountStatus = GameNetworkError.accountKeyRevoked.localizedDescription
            return
        }
        do {
            // The first candidate check may have raced the original commit.
            // Check again after learning that the old key was revoked.
            let info = try await arenaClient.fetchAccountInfo(baseURL: credential.baseURL, publicToken: pending.replacement.publicToken)
            finishAccountReset(pending, info: info, seat: slot, operation: operation)
        } catch GameNetworkError.invalidAccountKey {
            discardRevokedAccount(credential, seat: slot, clearingCandidate: pending.replacement.publicToken)
            if accountOperation == operation { accountStatus = GameNetworkError.accountKeyRevoked.localizedDescription }
        } catch GameNetworkError.accountKeyRevoked {
            discardRevokedAccount(credential, seat: slot, clearingCandidate: pending.replacement.publicToken)
            if accountOperation == operation { accountStatus = GameNetworkError.accountKeyRevoked.localizedDescription }
        } catch {
            discardRevokedAccount(credential, seat: slot)
            if accountOperation == operation { accountStatus = "The old key was reset. Its pending replacement is saved securely; reopen Account key to finish checking it." }
        }
    }

    private func discardRevokedAccount(_ credential: PublicInfinitySession, seat slot: Int, clearingCandidate: String? = nil) {
        if publicSessions.session(for: credential.baseURL, seat: slot)?.publicToken == credential.publicToken {
            publicSessions.forget(credential.baseURL, ifMatching: credential.publicToken, seat: slot)
            clearAccountIntent(for: credential, seat: slot)
            accountInfo = nil
        }
        if let clearingCandidate, let pending = publicSessions.pendingKey(for: credential.baseURL, seat: slot), pending.previous == credential {
            publicSessions.clearPendingKey(credential.baseURL, ifMatching: clearingCandidate, seat: slot)
        }
        accountRecoveryKeyPending = accountServer.flatMap { publicSessions.pendingKey(for: $0, seat: accountSeatContext) } != nil
        accountPendingKeyVerified = false
    }

    @discardableResult private func clearAccountIntent(for credential: PublicInfinitySession, seat: Int) -> Bool {
        guard let active = publicSessions.activeServer, credential.matches(active) else { return true }
        return seat == 1 ? publicSessions.activate(active, local: false) : publicSessions.activate(nil)
    }

    var currentReadout: PilotReadout {
        let tank = localTank ?? ArenaTank(hp: 0)
        return PilotReadout(tank: tank, snapshot: snapshot, infinity: isInfinity, paused: paused, online: !offline)
    }
    var inviteURL: URL {
        let base = URL(string: serverAddress) ?? URL(string: "https://leqra.com")!
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        if let code = room?.code { parts?.queryItems = [URLQueryItem(name: "room", value: code)] }
        return parts?.url ?? base
    }
    var spectatorInviteURL: URL {
        var parts = URLComponents(url: inviteURL, resolvingAgainstBaseURL: false)
        let items = parts?.queryItems ?? []
        parts?.queryItems = items + [URLQueryItem(name: "spectate", value: "1")]
        return parts?.url ?? inviteURL
    }

    func refreshPublicStatus() async {
        let pending = [0, 1].filter { callsignDrafts.automaticPending(seat: $0) }
        if !pending.isEmpty { await generateCallsigns(seats: pending, automatic: true) }
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
    var canResume: Bool { !disconnected && (spectating || !CallsignPolicy.reservedForBots(cleanName)) }
    private var onlineTitle: String {
        arenaActive ? (room == nil || room?.infinityPublic == true ? "Public Infinity" : "Room Infinity") : "Private match"
    }

    func startPractice() {
        guard validPlayerCallsign(cleanName, seat: 0) else { return }
        leave()
        let game = PracticeArena(seed: UInt32.random(in: 1...UInt32.max), name: cleanName, colorIndex: GamePalette.index(colorIndex), botCount: 0)
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = true
        game.configure(rules: rules)
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
        guard validPlayerCallsign(cleanName, seat: 0) else { return }
        if let local = accountLocalPlayer, !validPlayerCallsign(local.name, seat: 1) { return }
        if let room {
            if room.infinityActive, let baseURL, let welcome, let token = welcome.token {
                if arenaClient.connected { screen = .playing; setPaused(false); return }
                roomInfinityEntryWanted = true
                connectRoomArena(server: baseURL, code: room.code, token: token, resume: arenaGeneration != nil)
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
        guard validPlayerCallsign(cleanName, seat: 0) else { return }
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
        let name = ["Rust", "Vapor", "Ember", "Nova", "Comet", "Onyx", "Blitz"].first { !used.contains($0.uppercased()) } ?? "Bot"
        if room != nil { roomClient.send(.add(kind: "bot", name: name, difficulty: "normal")); return }
        let capacity = !localRules.infinity && localRules.mode == "survival" ? 3 : 7
        guard localBots.count < capacity else { return }
        let id = (localBots.map(\.id).max() ?? 1) + 1
        localBots.append(LocalBot(id: id, name: name, colorIndex: (id - 1) % 8, team: localRules.teamMode == "teams" ? max(1, localTeam) : 0))
    }

    func shareRoom() {
        guard validPlayerCallsign(cleanName, seat: 0) else { return }
        if finishPendingCallsigns(seats: [0], action: { [weak self] in self?.shareRoom() }) { return }
        guard room == nil else { return }
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            error = "Enter an HTTP or HTTPS server address."; return
        }
        let queueOpen = showQueues
        let primary: PublicInfinitySession?
        do { primary = try checkedAccountSession(for: url) } catch { self.error = error.localizedDescription; return }
        let seats = [NativeSeatSpec(kind: "human", name: cleanName, team: localTeam, colorIndex: colorIndex)] + localBots.map { NativeSeatSpec(kind: "bot", name: $0.name, difficulty: $0.difficulty, team: $0.team, colorIndex: $0.colorIndex) }
        let code = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        leave()
        baseURL = url; screen = .connecting; pendingShare = true; showQueues = queueOpen
        roomClient.connectPublishedRoom(baseURL: url, code: code.isEmpty ? nil : code, rules: localRules, roster: seats,
                                        publicToken: primary?.publicToken)
    }

    func saveCallsign() {
        guard !(arenaActive && spectating) else { return }
        guard validPlayerCallsign(cleanName, seat: 0) else { return }
        if !offline, (arenaActive || room != nil), callsignDrafts.automaticPending(seat: 0) { return }
        if !offline, (arenaActive || room != nil), callsignTaken { return }
        callsign = cleanName
        if let practice { practice.configurePilot(id: localID, name: callsign, colorIndex: colorIndex, team: localTeam, difficulty: "normal") }
        else if let fixedArena { fixedArena.configurePilot(id: localID, name: callsign, colorIndex: colorIndex, team: localTeam, difficulty: "normal") }
        else if arenaActive {
            requestID += 1
            arenaClient.sendCommand(["type": "rename", "seat": 0, "name": callsign, "requestId": requestID])
        } else if room != nil { roomClient.send(.rename(callsign)) }
    }

    /// Used names remain available offline; the bot namespace is reserved. The advisory is useful before a
    /// local room is shared, while the server remains the final atomic check.
    func scheduleCallsignAvailability(localName: String? = nil) {
        callsignCheckTask?.cancel()
        callsignTaken = false; localCallsignTaken = false; callsignFeedback = ""; localCallsignFeedback = ""
        callsignReserved = CallsignPolicy.reservedForBots(cleanName)
        localCallsignReserved = CallsignPolicy.reservedForBots(localName ?? localCallsign)
        if callsignReserved { callsignFeedback = "Reserved for bots." }
        if localCallsignReserved { localCallsignFeedback = "Reserved for bots." }
        guard let server = URL(string: serverAddress), (try? PublicInfinitySession.normalizedOrigin(server)) != nil else { return }
        let name = cleanName
        let local = localName ?? room?.players.first(where: { $0.kind == "local" && $0.owner == welcome?.id })?.name
        let names = [name] + (local.map { [String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))] } ?? [])
        let token = accountSession(for: server)?.publicToken
        let localToken = accountSession(for: server, seat: 1)?.publicToken
        let localFresh = publicSessions.registrationPending(for: server, seat: 1)
        let address = serverAddress
        callsignChecking = true
        callsignCheckTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard let self else { return }
                let checks = try await self.arenaClient.fetchCallsignAvailability(baseURL: server, names: names, publicToken: token, localPublicToken: localToken, localNewAccount: localFresh)
                guard !Task.isCancelled, self.cleanName == name, self.serverAddress == address else { return }
                self.callsignChecking = false
                self.callsignTaken = checks.first?.available == false
                self.callsignFeedback = self.callsignReserved ? "Reserved for bots." : self.callsignTaken ? "Used online; offline is OK." : ""
                if let local = checks.dropFirst().first, !local.available {
                    self.localCallsignTaken = true
                    self.localCallsignFeedback = self.localCallsignReserved ? "Reserved for bots." : "Used online; offline is OK."
                } else { self.localCallsignTaken = false; self.localCallsignFeedback = self.localCallsignReserved ? "Reserved for bots." : "" }
            } catch {
                guard !Task.isCancelled, let self, self.cleanName == name, self.serverAddress == address else { return }
                self.callsignChecking = false
                if !self.callsignReserved { self.callsignFeedback = "Online availability could not be checked." }
            }
        }
    }

    private func rejectCallsigns(_ conflicts: [CallsignConflict]?, message: String?) {
        callsignCheckTask?.cancel(); callsignChecking = false
        rejectedCallsignMessage = message
        let primary = conflicts?.first(where: { $0.seat == 0 })
        if primary != nil || conflicts?.isEmpty != false {
            callsignTaken = true
            callsignReserved = CallsignPolicy.reservedForBots(primary?.name ?? callsign)
            callsignFeedback = callsignReserved ? "Reserved for bots." : "Used online; offline is OK."
        }
        if let local = conflicts?.first(where: { $0.seat == 1 }) {
            localCallsignTaken = true; localCallsignReserved = CallsignPolicy.reservedForBots(local.name)
            localCallsignFeedback = localCallsignReserved ? "Reserved for bots." : "Used online; offline is OK."
        }
        status = message ?? "Rename the indicated local players before going online."
    }

    func setPaint(_ index: Int) {
        if room != nil { roomClient.send(.paint(colorIndex: index)) }
        else { colorIndex = index }
    }

    func send(_ action: NativeRoomCommand) {
        var payload = action.payload
        let type = payload["type"] as? String
        let roster = payload["roster"] as? [[String: Any]]
        let addsLocal = type == "add" && payload["kind"] as? String == "local"
            || type == "preset" && roster?.contains(where: { $0["kind"] as? String == "local" }) == true
        if type == "add", payload["kind"] as? String == "local", payload["name"] == nil { payload["name"] = localCallsign }
        let editsLocal = ["configure", "rename_local"].contains(type ?? "") && payload["target"] as? Int == accountLocalPlayer?.id
        if addsLocal || editsLocal, finishPendingCallsigns(seats: [1], action: { [weak self] in self?.send(action) }) { return }
        if addsLocal || editsLocal {
            let name = payload["name"] as? String ?? localCallsign
            guard validPlayerCallsign(name, seat: 1) else { return }
        }
        if let roster {
            for seat in roster where seat["kind"] as? String != "bot" {
                guard validPlayerCallsign(seat["name"] as? String ?? "", seat: seat["kind"] as? String == "local" ? 1 : 0) else { return }
            }
        }
        if addsLocal || editsLocal, let server = baseURL ?? accountServer {
            do {
                let local = try prepareLocalAccount(for: server)
                payload["independentAccounts"] = true; payload["localPublicToken"] = local.key
                if local.fresh { payload["localNewAccount"] = true }
            } catch { self.error = error.localizedDescription; return }
        }
        roomClient.sendCommand(payload)
    }

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
            var seats = preset.roster ?? ([NativeSeatSpec(kind: "human", name: cleanName, team: preset.team, colorIndex: colorIndex)] + preset.bots.map { NativeSeatSpec(kind: "bot", name: $0.name, difficulty: $0.difficulty, team: $0.team, colorIndex: $0.colorIndex) })
            if let server = baseURL, accountSession(for: server, seat: 1) != nil, !publicSessions.registrationPending(for: server, seat: 1) {
                for index in seats.indices where seats[index].kind == "local" { seats[index].name = localCallsign }
            }
            send(.preset(rules: preset.rules, roster: seats))
        } else { localRules = preset.rules; localBots = preset.bots; localTeam = preset.team; publicInfinitySelected = false }
    }

    private func updateGeneratedPresets(seat: Int, previous: String, claimed: String) {
        var changed = false
        for index in savedPresets.indices {
            guard let roster = savedPresets[index].roster else { continue }
            let updated = CallsignPolicy.updatingGeneratedRoster(roster, seat: seat, previous: previous, claimed: claimed)
            if updated != roster { savedPresets[index].roster = updated; changed = true }
        }
        if changed { UserDefaults.standard.set(try? JSONEncoder().encode(savedPresets), forKey: "nativePresets") }
    }

    func connect(code: String? = nil, publicArena: Bool = false, restoringPublicSession: Bool = false, spectating: Bool = false) {
        guard validPlayerCallsign(cleanName, seat: 0) else { return }
        if !restoringPublicSession, finishPendingCallsigns(seats: [0], action: { [weak self] in self?.connect(code: code, publicArena: publicArena, spectating: spectating) }) { return }
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            error = "Enter an HTTP or HTTPS server address."; return
        }
        let restoreLocal = publicArena && restoringPublicSession && publicSessions.activeLocal
        if restoreLocal, !validPlayerCallsign(localCallsign, seat: 1) { return }
        if spawnNoticeOrigin != (try? PublicInfinitySession.normalizedOrigin(url)) {
            spawnNoticeOrigin = try? PublicInfinitySession.normalizedOrigin(url)
            spawnNotices = GodlikeSpawnNotices(); godlikeNotice = ""; spawnNoticeTask?.cancel()
        }
        let local: (key: String, fresh: Bool)?
        let primary: PublicInfinitySession?
        do { primary = try checkedAccountSession(for: url); local = restoreLocal ? try prepareLocalAccount(for: url) : nil }
        catch { self.error = error.localizedDescription; return }
        leave(clearPublicIntent: !publicArena)
        baseURL = url
        roomInfinityEntryWanted = spectating && !publicArena
        screen = .connecting
        if publicArena {
            arenaActive = true
            publicIdentityActive = true; publicRecoveryPending = true
            publicSessions.activate(url, local: restoreLocal)
            arenaClient.connectPublic(baseURL: url, name: cleanName, colorIndex: GamePalette.index(colorIndex), localName: restoreLocal ? localCallsign : nil,
                                      publicToken: primary?.publicToken, updateNames: !restoringPublicSession,
                                      localPublicToken: local?.key, localNewAccount: local?.fresh ?? false)
        } else {
            roomClient.connectRoom(baseURL: url, name: cleanName, code: code, spectating: spectating,
                                   publicToken: primary?.publicToken)
        }
    }

    private func connectRoomArena(server: URL, code: String, token: String, resume: Bool = false) {
        if spawnNoticeOrigin != (try? PublicInfinitySession.normalizedOrigin(server)) {
            spawnNoticeOrigin = try? PublicInfinitySession.normalizedOrigin(server)
            spawnNotices = GodlikeSpawnNotices(); godlikeNotice = ""; spawnNoticeTask?.cancel()
        }
        let watching = ownRoomMember?.spectating ?? welcome?.spectating ?? false
        guard !watching || room?.infinityPublic == false else { error = "Spectating is available in Room Infinity."; return }
        let needsLocal = !watching && accountLocalPlayer?.spectating == false
        do {
            let local = needsLocal ? try prepareLocalAccount(for: server) : nil
            arenaActive = true
            spectating = watching
            followingID = 0; followError = ""
            localID = watching ? -1 : localID
            audioStateFresh = false
            scene.resetControls()
            arenaClient.connectRoomInfinity(baseURL: server, code: code, token: token, resume: resume, generation: arenaGeneration,
                                            localPublicToken: local?.key, localNewAccount: local?.fresh ?? false, spectating: watching)
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult private func restorePublicSessionIfNeeded() -> Bool {
        guard let server = publicSessions.activeServer,
              let configured = URL(string: serverAddress),
              (try? PublicInfinitySession.normalizedOrigin(configured)) == (try? PublicInfinitySession.normalizedOrigin(server)) else { return false }
        let remainPaused = publicResumePaused
        connect(publicArena: true, restoringPublicSession: true)
        publicResumePaused = remainPaused
        return true
    }

    /// Suspension and force-quit preserve only the authenticated public route.
    /// A room's short-lived reservation is never used to restore public score.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background:
            audioStateFresh = false
            if !lifecycleInactive {
                lifecycleInactive = true
                resumeAfterActivation = screen == .playing && !paused && !hasModal
                    || screen == .connecting && publicIdentityActive && !publicResumePaused
                if screen == .playing { setPaused(true) }
            }
            if phase == .background, publicIdentityActive {
                publicResumePaused = !resumeAfterActivation
                publicSuspended = true; disconnected = true
                arenaClient.suspend(); roomClient.suspend()
            }
        case .active:
            lifecycleInactive = false
            if publicSuspended, publicIdentityActive {
                publicSuspended = false
                let configured = URL(string: serverAddress)
                let sameServer = baseURL.flatMap { try? PublicInfinitySession.normalizedOrigin($0) }
                    == configured.flatMap { try? PublicInfinitySession.normalizedOrigin($0) }
                if sameServer {
                    publicRecoveryPending = true
                    dropPublicRoomRoute()
                    paused = false; screen = .connecting
                    if !arenaClient.reconnect(), !restorePublicSessionIfNeeded() { leave() }
                } else { leave() }
            } else if resumeAfterActivation, screen == .playing, !disconnected {
                setPaused(false)
            }
            resumeAfterActivation = false
        @unknown default: break
        }
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
        if !offline, !disconnected, !spectating {
            let packet = timeline?.neutralPacket() ?? GameInput()
            (arenaActive ? arenaClient : roomClient).sendInput(packet, paused: value)
        }
        UIApplication.shared.isIdleTimerDisabled = screen == .playing && !value
        if value { audio.pause(fadeLoop: !lifecycleInactive) } else { applyAudioSetting() }
    }

    func setSoundVolume(_ value: Double) {
        let level = value.isFinite ? min(100, max(0, value.rounded())) : 0
        soundVolume = abs(level - 50) <= 4 ? 50 : level
    }

    func applyAudioSetting(preview: AudioCue? = nil) {
        audio.enabled = soundEnabled
        audio.volume = Float(soundVolume / 100)
        if gameplayAudioActive { audio.resume() }
        refreshStarmanActivity()
        if let preview { audio.preview(preview) }
    }

    private var gameplayAudioActive: Bool {
        screen == .playing && !paused && !hasModal && !lifecycleInactive && !disconnected && timeline?.stale != true
            && (offline || audioStateFresh)
    }

    private var secondaryAudioPilotID: Int? {
        guard !offline, !spectating else { return nil }
        return arenaActive ? arenaClient.welcome?.localId : accountLocalPlayer?.id
    }

    private func refreshStarmanActivity() {
        audio.updateStarman(snapshot: lastSnapshot, localID: localID, secondaryLocalID: secondaryAudioPilotID,
                            gameplayActive: gameplayAudioActive)
    }

    func leave(clearPublicIntent: Bool = true) {
        audioStateFresh = false
        presentingFinalShot = false
        pendingOnlineAction = nil
        if clearPublicIntent { publicSessions.activate(nil) }
        frameProfiler = nil; scene.profilesRendering = false
        audio.reset()
        scene.resetControls(); scene.resetWorld()
        roomClient.disconnect(); arenaClient.disconnect()
        practice = nil; fixedArena = nil; maze = nil; timeline = nil; world = nil; welcome = nil; room = nil
        arenaActive = false; disconnected = false; paused = false; showScores = false
        spectating = false; followingID = 0; followError = ""
        roomInfinityEntryWanted = false; spectatorRecoveryPending = false; spectatorResumePaused = false
        lastSnapshot = ArenaSnapshot(); localID = -1; latency = nil; score = 0
        snapshot = ArenaSnapshot(); standings = []; arenaGeneration = nil
        weaponsLive = false; weaponsLiveRemaining = 0; previousPresentedPhase = ""
        measuredFPS = 0; frameElapsed = 0; frameCount = 0; hudElapsed = 0; practiceElapsed = 0
        status = ""; error = nil; screen = .menu; pendingShare = false
        localTank = nil; showChat = false; showQueues = false; showJoin = false; showPresets = false
        publicIdentityActive = false; publicRecoveryPending = false; publicResumePaused = false
        publicSuspended = false; publicScoreResetPending = false
        showRules = false; showControls = false; showSidebar = false; showSettings = false; showAccount = false
        chatMessages = []; opponentMessages = []; queueState = nil; queueListings = []
        chatDraft = ""; chatPending = false; chatError = nil; pendingChatText = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func returnToRoom() {
        guard room != nil else { leave(); return }
        guard isHost else { return }
        command(["type": "lobby"])
        if publicIdentityActive { publicSessions.activate(nil); publicIdentityActive = false; publicRecoveryPending = false }
        audio.pause()
        if arenaActive { arenaClient.disconnect(); arenaActive = false }
        roomInfinityEntryWanted = false; followingID = 0; followError = ""; spectatorRecoveryPending = false
        timeline = nil; maze = nil; world = nil; paused = false; scene.resetControls(); scene.resetWorld()
        restoreRoomIdentity()
        screen = .lobby
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Exit only this pilot's Infinity run. The authenticated room remains
    /// available for its roster, chat, settings and a later arena rejoin.
    func exitArenaToRoom(keepEntryIntent: Bool = false) {
        guard room != nil else { leave(); return }
        audio.pause()
        if publicIdentityActive { publicSessions.activate(nil); publicIdentityActive = false; publicRecoveryPending = false }
        arenaClient.disconnect()
        arenaActive = false; arenaGeneration = nil
        if !keepEntryIntent { roomInfinityEntryWanted = false }
        followingID = 0; followError = ""; spectatorRecoveryPending = false
        timeline = nil; maze = nil; world = nil
        localTank = nil; snapshot = ArenaSnapshot(); lastSnapshot = snapshot; standings = []
        paused = false; disconnected = !roomClient.connected; score = 0; showScores = false
        scene.resetControls(); scene.resetWorld(); restoreRoomIdentity()
        screen = .lobby
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func reconcileRoomArenaAccess() {
        guard let room, room.infinityActive, !room.infinityPublic, roomClient.connected,
              let welcome, let own = ownRoomMember, let token = welcome.token, let server = baseURL else { return }
        if arenaActive, let arenaRole = arenaClient.welcome?.spectating, arenaRole != own.spectating {
            exitArenaToRoom(keepEntryIntent: true)
        }
        guard roomInfinityEntryWanted, !arenaActive else { return }
        connectRoomArena(server: server, code: room.code, token: token)
    }

    private func receive(_ event: NetworkEvent, arena: Bool) {
        switch event {
        case .status(let value): status = value
        case .welcome(let value):
            if arena == arenaActive { audioStateFresh = false }
            disconnected = false
            if let token = value.publicToken, let server = baseURL,
               let session = try? PublicInfinitySession(baseURL: server, publicToken: token) {
                if !publicSessions.remember(session) {
                    error = "The online identity recovery key could not be saved on this device."
                }
                if arena, value.isPublic {
                    publicIdentityActive = true
                    if !publicSessions.activate(server, local: value.localId != nil) { error = "The public session could not be saved on this device." }
                }
                scheduleCallsignAvailability()
            }
            if let token = value.localPublicToken, let server = baseURL,
               let credential = try? PublicInfinitySession(baseURL: server, publicToken: token) {
                let expected = (arena ? arenaClient : roomClient).localAccountRequestKey
                let current = accountSession(for: server, seat: 1)
                if current == nil || current?.publicToken == expected || current == credential {
                    if !publicSessions.confirm(credential, requested: expected, seat: 1) { error = "P2's account key could not be saved in Keychain." }
                }
            }
            if value.resumed { timeline = nil; scene.resetControls() }
            if !arena {
                if let oldCode = welcome?.room, oldCode != value.room {
                    chatMessages = []; opponentMessages = []; queueState = nil; chatPending = false; pendingChatText = nil; showQueues = false
                }
                welcome = value
                if !arenaActive, value.spectating, screen == .connecting { roomInfinityEntryWanted = true }
            } else { arenaGeneration = value.generation }
            // The retained room socket can update roster identity while its
            // separate Infinity socket owns a different arena tank ID.
            if !arena && arenaActive {
                if value.spectating {
                    spectating = true; localID = -1
                    timeline?.setLocalID(-1); scene.resetControls(); refreshStarmanActivity()
                }
                reconcileRoomArenaAccess(); return
            }
            spectating = value.spectating
            followingID = value.following ?? 0
            localID = value.spectating ? -1 : value.id
            timeline?.setLocalID(localID)
            if let seed = value.seed {
                maze = InfiniteMaze(seed: seed); world = nil; arenaActive = true
                timeline = makeTimeline()
                scene.resetWorld(); screen = .playing
                status = room == nil ? "Public Infinity" : "Room Infinity"
                if publicIdentityActive, publicRecoveryPending { paused = publicResumePaused }
                if spectating, spectatorRecoveryPending { paused = spectatorResumePaused }
            }
        case .room(let value):
            let endedArena = room?.infinityActive == true && !value.infinityActive
            room = value
            if !arenaActive, screen == .connecting { screen = .lobby }
            arenaClient.updateResumeRoomCode(value.code)
            queueState = value.queue
            if pendingShare, isHost {
                pendingShare = false
                roomClient.send(.publicInfinity(publicInfinitySelected))
                if showQueues { roomClient.send(.queueInfo) }
            }
            if endedArena {
                if publicIdentityActive { publicSessions.activate(nil); publicIdentityActive = false; publicRecoveryPending = false }
                audio.pause()
                arenaClient.disconnect(); arenaActive = false; arenaGeneration = nil; timeline = nil; maze = nil
                roomInfinityEntryWanted = false; followingID = 0; followError = ""; spectatorRecoveryPending = false
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
            if let local = value.players.first(where: { $0.kind == "local" && $0.owner == welcome?.id }) { localCallsign = local.name }
            reconcileRoomArenaAccess()
        case .infinityStarted:
            guard let url = baseURL, let welcome, let code = welcome.room, let token = welcome.token else { return }
            roomInfinityEntryWanted = true
            guard !arenaActive else { return }
            connectRoomArena(server: url, code: code, token: token)
        case .followed(let id):
            guard arena, spectating else { return }
            followingID = id; followError = ""
        case .state(let snapshot):
            guard arena == arenaActive else { return }
            if arena, spectating {
                followingID = snapshot.following ?? 0
                localID = -1; localTank = nil; score = 0
                spectatorRecoveryPending = false
            }
            if arena {
                let fresh = spawnNotices.accept(snapshot.godlikeSpawns, now: ProcessInfo.processInfo.systemUptime)
                let notice = spawnNotices.text(at: ProcessInfo.processInfo.systemUptime)
                if godlikeNotice != notice { godlikeNotice = notice }
                if fresh {
                    spawnNoticeTask?.cancel()
                    spawnNoticeTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        guard !Task.isCancelled, let self else { return }
                        self.godlikeNotice = self.spawnNotices.text(at: ProcessInfo.processInfo.systemUptime)
                    }
                }
            }
            if snapshot.phase == "lobby", !arena { return }
            audioStateFresh = !lifecycleInactive && UIApplication.shared.applicationState == .active
            if snapshot.generation != lastSnapshot.generation, !arena {
                scene.resetWorld()
            }
            if let fixed = snapshot.world { world = fixed }
            if timeline == nil { timeline = makeTimeline() }
            timeline?.accept(snapshot, at: ProcessInfo.processInfo.systemUptime)
            lastSnapshot = snapshot
            if publicIdentityActive, publicRecoveryPending, let tank = snapshot.tanks.first(where: { $0.id == localID }) {
                if callsign != tank.name { callsign = tank.name }
                if colorIndex != tank.colorIndex { colorIndex = GamePalette.index(tank.colorIndex) }
            }
            if publicIdentityActive, publicRecoveryPending || publicScoreResetPending {
                let recoveredPaused = publicRecoveryPending && paused
                publicRecoveryPending = false; publicScoreResetPending = false
                let visual = timeline?.render(dt: 0, input: GameInput(), now: ProcessInfo.processInfo.systemUptime) { _ in } ?? snapshot
                scene.display(snapshot: visual, localID: localID, maze: maze, fixedWalls: world?.walls ?? [])
                syncHUD(snapshot)
                if recoveredPaused { setPaused(true) }
            }
            if status == "Waiting for server…" { status = onlineTitle }
            screen = .playing
            applyAudioSetting()
            UIApplication.shared.isIdleTimerDisabled = !paused
        case .latency(let milliseconds):
            if arena == arenaActive { latency = Int(milliseconds.rounded()) }
        case .error(let message):
            if publicIdentityActive, !arena { dropPublicRoomRoute(); return }
            if rejectedCallsignMessage == message {
                rejectedCallsignMessage = nil
                if screen == .connecting { screen = room == nil ? .menu : .lobby }
                return
            }
            error = message
            if screen == .connecting { screen = room == nil ? .menu : .lobby }
        case .disconnected(let reason):
            if arena == arenaActive {
                audioStateFresh = false
                disconnected = true
                if publicIdentityActive {
                    publicRecoveryPending = false
                    paused = false; screen = .menu
                    scene.resetControls(); audio.pause()
                    UIApplication.shared.isIdleTimerDisabled = false
                } else if screen == .playing { setPaused(true) }
                else { paused = false }
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
                if rename.type == "rename_error", rename.code == "callsign_taken" {
                    rejectCallsigns(rename.conflicts, message: rename.message)
                } else if rename.type == "renamed", let name = rename.name,
                          (arena && rename.seat == 0) || (!arena && rename.id == welcome?.id) { callsign = name }
            case .roomRenamed(let rename): roomName = rename.room; welcome?.room = rename.room
            case .notice(let notice):
                if let message = notice.message { status = message }
                if notice.action == "follow" { followError = notice.message ?? "That tank is unavailable." }
                if !arena, notice.type == "unshared" || notice.type == "kicked" || notice.type == "room_offline" || notice.code == "kicked" {
                    let message = notice.message ?? "The room is no longer available."
                    leave(); error = message; return
                }
                if arena, notice.code == "room_access_changed", !publicIdentityActive {
                    let priorRole = spectating
                    exitArenaToRoom(keepEntryIntent: true)
                    if ownRoomMember?.spectating != priorRole { reconcileRoomArenaAccess() }
                    return
                }
                if notice.type == "leaderboard_reset" { publicScoreResetPending = true; status = "Public leaderboard updated." }
                if notice.code == "callsign_taken" { rejectCallsigns(notice.conflicts, message: notice.message) }
                if notice.code == "session_replaced" {
                    let slot = notice.seat == 1 ? 1 : 0
                    let client = arena ? arenaClient : roomClient
                    let key = slot == 1 ? (client.localAccountKey ?? client.localAccountRequestKey) : client.accountKey
                    let matching = baseURL.flatMap { server in key.map { publicSessions.session(for: server, seat: slot)?.publicToken == $0 } } ?? false
                    if let server = baseURL, let key, matching,
                       let credential = try? PublicInfinitySession(baseURL: server, publicToken: key) { clearAccountIntent(for: credential, seat: slot) }
                    else if slot == 0, key == nil { publicSessions.activate(nil) }
                    leave(clearPublicIntent: false)
                    error = notice.message ?? (slot == 1 ? "P2's tank was taken over on another device. P1's account key is unchanged." : "Your tank was taken over on another device. PLAY to take it back.")
                }
                if notice.code == "account_key_revoked" {
                    let slot = notice.seat == 1 ? 1 : 0
                    let client = arena ? arenaClient : roomClient
                    let oldKey = slot == 1 ? (client.localAccountKey ?? client.localAccountRequestKey) : client.accountKey
                    let matching = baseURL.flatMap { server in oldKey.map { publicSessions.session(for: server, seat: slot)?.publicToken == $0 } } ?? false
                    if matching, let server = baseURL, let oldKey,
                       let credential = try? PublicInfinitySession(baseURL: server, publicToken: oldKey) {
                        publicSessions.forget(server, ifMatching: oldKey, seat: slot)
                        clearAccountIntent(for: credential, seat: slot)
                    }
                    leave(clearPublicIntent: false)
                    error = notice.message ?? (slot == 1 ? "P2's account key was reset on another device. Import P2's new key; P1's key is unchanged." : GameNetworkError.accountKeyRevoked.localizedDescription)
                }
                if notice.action == "chat" { chatPending = false; pendingChatText = nil; chatError = notice.message }
            case .reconnecting(let attempt):
                if arena == arenaActive { audioStateFresh = false }
                if publicIdentityActive, arena {
                    if !publicRecoveryPending { publicResumePaused = lifecycleInactive ? !resumeAfterActivation : paused || hasModal }
                    publicRecoveryPending = true
                    dropPublicRoomRoute()
                    disconnected = true; paused = false; screen = .connecting
                    scene.resetControls(); timeline?.neutralize(); audio.pause()
                    showSettings = false; showAccount = false; showControls = false; showScores = false
                    showChat = false; showRules = false; showSidebar = false
                    UIApplication.shared.isIdleTimerDisabled = false
                } else if arena, spectating {
                    spectatorResumePaused = lifecycleInactive ? !resumeAfterActivation : paused || hasModal
                    spectatorRecoveryPending = true
                    disconnected = true; paused = false; screen = .connecting
                    scene.resetControls(); timeline?.neutralize(); audio.pause()
                } else { disconnected = true; setPaused(true) }
                status = "Reconnecting, attempt \(attempt)…"
            }
        }
    }

    private func dropPublicRoomRoute() {
        roomClient.suspend()
        room = nil; welcome = nil
        chatMessages = []; opponentMessages = []; queueState = nil
        chatPending = false; pendingChatText = nil; showQueues = false
    }

    private func restoreRoomIdentity() {
        spectating = ownRoomMember?.spectating ?? welcome?.spectating ?? false
        localID = spectating ? -1 : welcome?.id ?? -1
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
        let notice = spawnNotices.text(at: ProcessInfo.processInfo.systemUptime)
        if godlikeNotice != notice { godlikeNotice = notice }
        guard screen == .playing, !paused else { return }
        // A reliable room identity can revoke the actor before its roster and
        // replacement observer stream arrive. Never emit one last tank input.
        if arenaActive, spectating, arenaClient.welcome?.spectating != true { return }
        let profiling = frameProfiler != nil
        let cpuStart = profiling ? CACurrentMediaTime() : 0
        var simulationSeconds = 0.0, audioSeconds = 0.0, hudSeconds = 0.0
        defer {
            frameProfiler?.record(dt: dt, cpu: CACurrentMediaTime() - cpuStart, simulation: simulationSeconds,
                                  audio: audioSeconds, hud: hudSeconds, rendering: scene.renderMetrics)
        }
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
        let simulationStart = profiling ? CACurrentMediaTime() : 0
        var snapshot: ArenaSnapshot?
        if let frameProfiler { snapshot = frameProfiler.snapshot(dt: dt) }
        else if let practice {
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
        let finalShot = (snapshot.result != nil || snapshot.phase == "matchOver" || snapshot.phase == "roundOver")
            && (timeline?.hasPendingProjectileFlights == true || practice?.hasPendingProjectileFlights == true || fixedArena?.hasPendingProjectileFlights == true)
        if presentingFinalShot != finalShot { presentingFinalShot = finalShot }
        if profiling { simulationSeconds = CACurrentMediaTime() - simulationStart }
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
        let audioStart = profiling ? CACurrentMediaTime() : 0
        var audioSnapshot = snapshot
        if finalShot, snapshot.phase == "roundOver" { audioSnapshot.phase = "playing" }
        audio.consume(snapshot: audioSnapshot, localID: localID, infinity: isInfinity, online: !offline,
                      secondaryLocalID: secondaryAudioPilotID, gameplayActive: gameplayAudioActive)
        if profiling { audioSeconds = CACurrentMediaTime() - audioStart }
        scene.display(snapshot: snapshot, localID: localID, maze: maze, fixedWalls: world?.walls ?? [])
        hudElapsed += dt
        if hudElapsed >= 0.1 {
            let hudStart = profiling ? CACurrentMediaTime() : 0
            let authority = practice?.snapshot ?? fixedArena?.snapshot ?? timeline?.authoritativeSnapshot ?? snapshot
            hudElapsed = 0; syncHUD(authority)
            if profiling { hudSeconds = CACurrentMediaTime() - hudStart }
        }
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
