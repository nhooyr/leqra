package com.leqra.android

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.leqra.android.accounts.*
import com.leqra.android.audio.AudioCue
import com.leqra.android.network.*
import com.leqra.core.*
import java.security.SecureRandom
import kotlin.math.*
import org.json.JSONArray
import org.json.JSONObject

internal enum class Screen {
    READY,
    CONNECTING,
    PLAYING,
}

private data class PendingOnlineAction(val includeLocal: Boolean, val run: () -> Unit)

/**
 * Main-thread owner of simulation, transport and presentation. Scores never leave via client
 * commands.
 */
internal class GameSession(context: Context) {
    private val prefs = context.getSharedPreferences("leqra-settings", Context.MODE_PRIVATE)
    val store: AccountStore = EncryptedAccountStore(context)
    val accounts = AccountService(store)
    val network = NativeNetworkClient(store, { networkEvent(it, false) })
    val arenaNetwork = NativeNetworkClient(store, { networkEvent(it, true) })
    private var arenaActive = false
    private val activeNetwork: NativeNetworkClient
        get() = if (arenaActive) arenaNetwork else network

    val canImportAccount: Boolean
        get() =
            screen == Screen.READY &&
                !releasingCallsign &&
                !online &&
                !network.connected &&
                !arenaNetwork.connected &&
                store.activeIntent() == null

    var changed: (Boolean) -> Unit = {}
    var present: (ArenaSnapshot, InfiniteMaze?, Int, Int?, Boolean) -> Unit = { _, _, _, _, _ -> }
    var notifyError: (String) -> Unit = {}
    var emitAudioCue: (AudioCue) -> Unit = {}
    var server =
        prefs.getString("server", null)?.let { address ->
            runCatching { ServerAddress.configuredOrigin(address, BuildConfig.DEBUG) }.getOrNull()
        } ?: defaultServer
        private set

    init {
        // A saved battle can resume only on the server selected in Controls.
        if (store.activeIntent()?.origin?.let { it != server } == true) store.setActiveIntent(null)
    }

    private val bootstrapNames =
        listOf(prefs.getString("callsign", null), prefs.getString("localCallsign", null))
            .mapIndexed { seat, name ->
                name.takeUnless {
                    LegacyCallsignDefaults.shouldGenerate(it, store.selected(server, seat) != null)
                }
            }
    private val nameDrafts =
        CallsignDrafts(
            bootstrapNames,
            (0..1).map {
                if (bootstrapNames[it] != null && prefs.contains("autoPending$it"))
                    prefs.getBoolean("autoPending$it", false)
                else null
            },
            (0..1).map {
                if (bootstrapNames[it] != null) prefs.getString("autoRequest$it", null) else null
            },
        )
    var callsign: String
        get() = nameDrafts.name(0)
        set(value) {
            if (!releasingCallsign) nameDrafts.edit(0, value)
        }

    var localCallsign: String
        get() = nameDrafts.name(1)
        set(value) {
            if (!releasingCallsign) nameDrafts.edit(1, value)
        }

    private val committedCallsigns = arrayOf(callsign, localCallsign)
    private var switchingCallsign = false
    var releasingCallsign = false
        private set

    private var onlineIdentityReady = false

    init {
        for (seat in 0..1) {
            val key = store.selected(server, seat)?.key
            accounts
                .savedCallsigns(server)
                .firstOrNull { it.key == key }
                ?.let { committedCallsigns[seat] = it.name }
        }
    }

    var colorIndex = prefs.getInt("color", 0)
    var localColorIndex = prefs.getInt("localColor", 1)
    var localSelected = prefs.getBoolean("localSelected", false)
        set(value) {
            if (rejectSurvivalRosterChange(mode, rules.infinity, value)) return
            if (field != value) configurationError = null
            field = value
        }

    var publicSelected = prefs.getBoolean("publicSelected", true)
    var mode = prefs.getString("mode", "elimination")!!.takeIf { it in modes } ?: "elimination"
    var rules =
        runCatching {
            prefs.getString("rules", null)?.let { SnapshotDecoder.rules(JSONObject(it)) }
        }
            .getOrNull() ?: RoomRules.localDefaults(mode)
    private var savedLocalRules = rules.copy()
    private var savedLocalMode = mode
    private var savedLocalPublic = publicSelected
    private var savedLocalSelected = localSelected
    private val modeProfiles = mutableMapOf<String, RoomRules>()
    private val mutableLocalBots = mutableListOf<LocalBot>()
    val localBots: List<LocalBot>
        get() = mutableLocalBots

    private val mutablePresets = readPresets()
    val presets: List<RoomPreset>
        get() = mutablePresets

    val localStartError: String?
        get() =
            if (online || publicSelected) null
            else
                rules.infinityStartError(
                    listOf(localTeam) +
                        (if (localSelected) listOf(secondLocalTeam) else emptyList()) +
                        localBots.map { it.team },
                )

    var botCount: Int
        get() = mutableLocalBots.size
        set(value) {
            val count = value.coerceIn(0, maxLocalBots)
            if (count != mutableLocalBots.size) configurationError = null
            resizeBots(count)
        }

    var localTeam = prefs.getInt("localTeam", 1).coerceIn(1, 4)
    var secondLocalTeam = prefs.getInt("secondLocalTeam", 1).coerceIn(1, 4)
    var difficulty =
        prefs.getString("difficulty", "normal")?.takeIf { it in BotDifficulty.names } ?: "normal"
    var roomName = ""
    var muted = prefs.getBoolean("muted", false)
    var volume = prefs.getFloat("volume", .5f)
    var highRefresh = prefs.getBoolean("highRefresh", true)
    var keyboardBindings =
        NativeControlBindings.decode(prefs.getString(NativeControlBindings.storageKey, null))
    var mouseAim = prefs.getBoolean("mouseAim", true)
    var mouseFire = prefs.getBoolean("mouseFire", true)
    var gamepadSupport = prefs.getBoolean("gamepadSupport", true)
    var showFPS = prefs.getBoolean("showPerformanceReadout", true)
    var screen = Screen.READY
        private set

    var paused = false
        private set

    var online = false
        private set

    val audioSceneActive: Boolean
        get() =
            active &&
                screen == Screen.PLAYING &&
                !paused &&
                (!online ||
                    activeNetwork.connected &&
                        !timeline.stale &&
                        audioStateOwner === activeNetwork &&
                        audioStateConnection == activeNetwork.connectionGeneration)

    val audioGameplayActive: Boolean
        get() = audioSceneActive && hasLocalPlayer

    var infinity = true
        private set

    var room: JSONObject? = null
        private set

    var status = "Local play is ready. Share to invite online friends."
        private set

    var configurationError: String? = null
        private set

    var latency: Double? = null
        private set

    var publicStatus: PublicStatus? = null
        private set

    var snapshot = ArenaSnapshot()
        private set

    var localID = 1
        private set

    var localID2: Int? = null
        private set

    val roomSpectating: Boolean
        get() = online && network.welcome?.spectating == true

    val spectating: Boolean
        get() =
            online && (roomSpectating || arenaActive && arenaNetwork.welcome?.spectating == true)

    val canControlSecondary: Boolean
        get() = localID2 != null && (!spectating || !arenaActive)

    val hasLocalPlayer: Boolean
        get() = !spectating || canControlSecondary

    var followingID = 0
        private set

    fun followTank(id: Int) {
        if (
            !spectating ||
                !arenaActive ||
                !arenaNetwork.connected ||
                id <= 0 ||
                snapshot.leaderboard.none { it.id == id }
        )
            return
        arenaNetwork.send(JSONObject().put("type", "follow").put("target", id))
    }

    var maze: InfiniteMaze? = null
        private set

    var queuePacket: JSONObject? = null
        private set

    private val spawnNotices = GodlikeSpawnNotices()
    val encounterNotice: String?
        get() =
            if (online && activeNetwork.isPublic) spawnNotices.current(System.nanoTime() / 1e9)
            else null

    private val fireFeedback = PressFireFeedback()
    private val localFireFeedback = PressFireFeedback()
    private var observedFire = false
    private var observedLocalFire = false
    var previewRecoil = 0.0
        private set

    var localPreviewRecoil = 0.0
        private set

    var fireFeedbackAllowed: () -> Boolean = { true }
    var input = GameInput()
        set(value) {
            field = value
            observeFire(false, value.fire, System.nanoTime())
        }

    var input2 = GameInput()
        set(value) {
            field = value
            observeFire(true, value.fire, System.nanoTime())
        }

    private var practice: PracticeArena? = null
    private var fixed: FixedArena? = null
    private var previousFrame = 0L
    private var accumulator = 0.0
    private var uiElapsed = 0.0
    private val offlineInputs = HashMap<Int, GameInput>(2)
    private var offlinePrimary = Int.MIN_VALUE
    private var offlineSecondary: Int? = null
    private val renameNames = arrayOfNulls<String>(2)
    private val renameRequests = LongArray(2)
    private var active = true
    private var timeline = OnlinePresentation()
    private var timelineOwner: NativeNetworkClient? = null
    private var timelineConnection = -1L
    private var audioStateOwner: NativeNetworkClient? = null
    private var audioStateConnection = -1L
    private var pendingQueue = false
    private var pendingPublicSelection = false
    private var pendingLocalJoin = false
    private var spectatorAutoEnter = true
    private val main = Handler(Looper.getMainLooper())
    private var nameRequest: CancelRequest? = null
    private var nameRequestEpoch = 0L
    private var nextNameAttempt = 0L
    private var pendingOnlineAction: PendingOnlineAction? = null
    private var statusRequest: CancelRequest? = null
    private var statusInFlight = false
    private var statusEpoch = 0L
    private val statusTicker =
        object : Runnable {
            override fun run() {
                if (active) {
                    refreshStatus()
                    main.postDelayed(this, 1000)
                }
            }
        }
    val isHost: Boolean
        get() = room == null || room?.optInt("host") == network.welcome?.id

    val roomSetupOpen: Boolean
        get() =
            room?.let {
                screen == Screen.READY &&
                    !it.optBoolean("infinityActive") &&
                    it.optString("phase") in setOf("lobby", "matchOver") &&
                    it.isNull("queue") &&
                    it.isNull("matchmaking") &&
                    it.optString("awayMatch").isEmpty()
            } == true

    val roomLocalPilot: JSONObject?
        get() {
            val controller = network.welcome?.id ?: return null
            return room?.roomRosterMembers()?.firstOrNull {
                it.optString("kind") == "local" && it.optInt("owner", -1) == controller
            }
        }

    val canAddRoomLocalPilot: Boolean
        get() =
            room?.let { current ->
                isHost &&
                    roomSetupOpen &&
                    !releasingCallsign &&
                    (current.optJSONArray("players")?.length() ?: 0) <
                        current.optInt("maxPlayers", 8) &&
                    current.roomRosterMembers().none { it.optString("kind") == "local" }
            } == true

    val roomCode: String?
        get() = room?.optString("code")?.takeIf { it.isNotBlank() } ?: network.welcome?.room

    val identity: String
        get() = "$callsign (P1)"

    val maxLocalBots: Int
        get() = rules.botCapacity(if (localSelected) 2 else 1)

    val modeTitle: String
        get() = modes[if (infinity && screen == Screen.PLAYING) "infinity" else mode] ?: "Infinity"

    init {
        mode = if (rules.infinity) "infinity" else rules.mode
        savedLocalMode = mode
        runCatching {
            prefs.getString("modeProfiles", null)?.let { encoded ->
                val profiles = JSONObject(encoded)
                modes.keys.forEach { key ->
                    profiles.optJSONObject(key)?.let {
                        modeProfiles["local:$key"] = SnapshotDecoder.rules(it)
                    }
                }
            }
        }
        runCatching {
            prefs.getString("localBots", null)?.let { encoded ->
                val rows = JSONArray(encoded)
                repeat(minOf(rows.length(), 7)) { index ->
                    val bot = rows.getJSONObject(index)
                    mutableLocalBots.add(
                        LocalBot(
                            index + 2,
                            Callsigns.limit(bot.optString("name", "BOT")).ifBlank { "BOT" },
                            GamePalette.index(bot.optInt("colorIndex", index + 1)),
                            bot.optString("difficulty", "normal").takeIf {
                                it in BotDifficulty.names
                            } ?: "normal",
                            bot.optInt("team").coerceIn(0, 4),
                        ),
                    )
                }
            }
                ?: resizeBots(
                    prefs.getInt("bots", if (publicSelected) 0 else 3).coerceIn(0, maxLocalBots),
                )
        }
            .onFailure {
                mutableLocalBots.clear()
                resizeBots(3.coerceAtMost(maxLocalBots))
            }
        normalizeLocalTeams(resetCTF = false)
        if (!prefs.contains("color")) randomizePilotColor(0)
        if (!prefs.contains("localColor")) randomizePilotColor(1)
        preparePreview()
        save()
        persistNameDrafts()
    }

    private val profileContext: String
        get() = roomCode?.takeIf { online } ?: if (online) "online" else "local"

    fun automaticNamePending(seat: Int) = nameDrafts.pending(seat)

    private fun persistNameDrafts() {
        val editor = prefs.edit()
        for (seat in 0..1) {
            if (!Callsigns.botReserved(nameDrafts.name(seat)))
                editor.putString(
                    if (seat == 0) "callsign" else "localCallsign",
                    nameDrafts.name(seat),
                )
            editor
                .putBoolean("autoPending$seat", nameDrafts.pending(seat))
                .putString("autoRequest$seat", nameDrafts.requestID(seat))
        }
        check(editor.commit()) {
            "Callsign settings could not be saved. Retry before going online."
        }
    }

    fun releaseCallsign(key: String, completed: (Result<Unit>) -> Unit) {
        if (!canImportAccount || switchingCallsign) {
            completed(
                Result.failure(
                    IllegalStateException("Return to the local room before releasing a callsign."),
                ),
            )
            return
        }
        val origin = server
        val seats = (0..1).filter { store.selected(origin, it)?.key == key }
        val replacements = seats.associateWith { AccountKeys.create() }
        try {
            replacements.forEach { (seat, replacement) ->
                store.savePending(
                    origin,
                    AccountKeys.pending(seat, replacement, purpose = "release-replacement"),
                )
            }
        } catch (error: Exception) {
            completed(Result.failure(error))
            return
        }
        switchingCallsign = true
        releasingCallsign = true
        for (seat in 0..1) accounts.invalidate(origin, seat)
        val previousStatus = status
        status = "Releasing callsign…"
        changed(false)
        runCatching {
            accounts.release(origin, key) { result ->
                switchingCallsign = false
                releasingCallsign = false
                if (server == origin) status = previousStatus
                val finished = result.mapCatching {
                    replacements.forEach { (seat, replacement) ->
                        if (store.selected(origin, seat) == null) {
                            store.select(origin, seat, replacement, registrationPending = true)
                            if (server == origin) {
                                val name = CallsignDrafts.randomName()
                                committedCallsigns[seat] = name
                                if (seat == 0) callsign = name else localCallsign = name
                            }
                        }
                    }
                    if (server == origin) {
                        save()
                        preparePreview()
                        changed(true)
                    }
                }
                changed(false)
                completed(finished)
            }
        }
            .onFailure { error ->
                switchingCallsign = false
                releasingCallsign = false
                if (server == origin) status = previousStatus
                changed(false)
                completed(Result.failure(error))
            }
    }

    fun accountImported(seat: Int) {
        if (releasingCallsign) return
        committedCallsigns[seat] = nameDrafts.name(seat)
        nameDrafts.cancel(seat)
        persistNameDrafts()
    }

    private fun randomizePilotColor(seat: Int) {
        val other = if (seat == 0) localColorIndex else colorIndex
        val bots =
            if (online)
                room
                    ?.roomRosterMembers()
                    .orEmpty()
                    .filter { it.optString("kind") == "bot" }
                    .map {
                        GamePalette.index(
                            it.optInt(
                                "colorIndex",
                                GamePalette.colors.indexOf(it.optString("color")),
                            ),
                        )
                    }
            else localBots.map { it.colorIndex }
        val current = if (seat == 0) colorIndex else localColorIndex
        val next = GamePalette.randomPilotColor(current, bots + other)
        if (seat == 0) colorIndex = next else localColorIndex = next
    }

    fun generateCallsign(seat: Int) {
        require(seat in 0..1)
        if (switchingCallsign || releasingCallsign) return
        val origin = server
        val previousName = committedCallsigns[seat]
        val previousKey = store.selected(origin, seat)?.key
        val sourceScreen = screen
        val sourceOnline = online
        val stamp = nameDrafts.request(seat, origin, previousKey.orEmpty())
        fun unchanged() =
            !releasingCallsign &&
                screen == sourceScreen &&
                online == sourceOnline &&
                nameDrafts.isCurrent(stamp, server, store.selected(server, seat)?.key.orEmpty())
        store.selected(origin, seat)?.let {
            accounts.rememberCallsign(origin, seat, previousName, it.key)
        }
        switchingCallsign = true
        accounts.generate(
            origin,
            listOf(seat),
            java.util.UUID.randomUUID().toString(),
            freshAccount = true,
            canCommit = ::unchanged,
        ) { result ->
            switchingCallsign = false
            result
                .onSuccess { rows ->
                    val row = rows.single()
                    if (server != origin || !row.selected) return@onSuccess
                    committedCallsigns[seat] = row.name
                    if (seat == 0) callsign = row.name else localCallsign = row.name
                    randomizePilotColor(seat)
                    nameDrafts.cancel(seat)
                    save()
                    leave()
                }
                .onFailure { failure ->
                    if (!unchanged()) return@onFailure
                    val canStageOffline =
                        !online &&
                            unchanged() &&
                            (failure as? NetworkFailure)?.code in
                                setOf("network", "server_busy", "server_error")
                    if (!canStageOffline) {
                        error(failure.message)
                        return@onFailure
                    }
                    var name = CallsignDrafts.randomName()
                    val otherName = if (seat == 0) localCallsign else callsign
                    while (name == otherName) name = CallsignDrafts.randomName()
                    // A lost generation response may already own its name; use a separate key
                    // for the local fallback and retain the earlier candidate for recovery.
                    accounts.switchCallsign(origin, seat, name, previousName, localOnly = true) {
                        local ->
                        local
                            .onSuccess {
                                committedCallsigns[seat] = name
                                if (seat == 0) callsign = name else localCallsign = name
                                randomizePilotColor(seat)
                                nameDrafts.cancel(seat)
                                save()
                                leave()
                            }
                            .onFailure { error(it.message) }
                    }
                }
        }
    }

    private fun validHumanNames(includeLocal: Boolean = localSelected): Boolean {
        if (
            Callsigns.botReserved(callsign) || includeLocal && Callsigns.botReserved(localCallsign)
        ) {
            error(Callsigns.botNamespaceMessage)
            return false
        }
        return true
    }

    private fun pendingHumanNames(includeLocal: Boolean): Boolean =
        nameDrafts.pending(0) || includeLocal && nameDrafts.pending(1)

    private fun awaitDefaultNames(
        includeLocal: Boolean = localSelected,
        action: () -> Unit,
    ): Boolean {
        if (online || !pendingHumanNames(includeLocal)) return false
        pendingOnlineAction = PendingOnlineAction(includeLocal, action)
        screen = Screen.CONNECTING
        status = "Choosing available callsigns…"
        nextNameAttempt = 0
        ensureDefaultNames()
        changed(true)
        return true
    }

    private fun ensureDefaultNames() {
        if (
            !active ||
                releasingCallsign ||
                nameRequest != null ||
                System.nanoTime() < nextNameAttempt
        )
            return
        pendingOnlineAction
            ?.takeUnless { pendingHumanNames(it.includeLocal) }
            ?.let {
                pendingOnlineAction = null
                screen = Screen.READY
                it.run()
            }
        val requested = (0..1).filter { nameDrafts.pending(it) }
        if (requested.isEmpty()) return
        val requestID = nameDrafts.requestID(requested.first())
        val seats = requested.filter { nameDrafts.requestID(it) == requestID }
        val origin = server
        val epoch = ++nameRequestEpoch
        runCatching {
            persistNameDrafts()
            val stamps = seats.associateWith {
                nameDrafts.request(
                    it,
                    origin,
                    (store.selected(origin, it) ?: store.prepareRegistration(origin, it)).key,
                )
            }
            nameRequest =
                accounts.generate(origin, seats, requestID) { result ->
                    if (epoch != nameRequestEpoch) return@generate
                    nameRequest = null
                    nextNameAttempt = System.nanoTime() + 3_000_000_000L
                    if (origin != server) return@generate
                    result
                        .onSuccess { rows ->
                            var updated = false
                            rows.forEach { row ->
                                val stamp = stamps.getValue(row.seat)
                                if (
                                    row.selected &&
                                        nameDrafts.complete(
                                            stamp,
                                            server,
                                            store.selected(server, row.seat)?.key,
                                            row.name,
                                        )
                                ) {
                                    committedCallsigns[row.seat] = row.name
                                    if (row.seat == 0) callsign = row.name
                                    else localCallsign = row.name
                                    updated = true
                                }
                            }
                            persistNameDrafts()
                            if (updated) changed(true)
                            nextNameAttempt = 0
                            ensureDefaultNames()
                        }
                        .onFailure {
                            if (
                                (it as? NetworkFailure)?.code in
                                    setOf(
                                        "account_key_revoked",
                                        "invalid_account_key",
                                        "account_invalid",
                                        "invalid_key",
                                    )
                            ) {
                                seats.forEach { seat -> nameDrafts.cancel(seat) }
                                persistNameDrafts()
                                pendingOnlineAction = null
                                screen = Screen.READY
                                error(it.message)
                            }
                        }
                }
        }
            .onFailure {
                nextNameAttempt = System.nanoTime() + 3_000_000_000L
                status = it.message ?: "Callsign settings could not be saved."
            }
    }

    fun save() {
        if (!online) {
            botCount = botCount.coerceIn(0, maxLocalBots)
            savedLocalRules = rules.copy()
            savedLocalMode = mode
            savedLocalPublic = publicSelected
            savedLocalSelected = localSelected
            modeProfiles["local:${if(rules.infinity) "infinity" else rules.mode}"] = rules.copy()
        }
        val profiles = JSONObject()
        modes.keys.forEach { key ->
            modeProfiles["local:$key"]?.let { profiles.put(key, rulesJson(it)) }
        }
        prefs
            .edit()
            .apply {
                if (!Callsigns.botReserved(callsign))
                    putString("callsign", Callsigns.limit(callsign.trim()))
                if (!Callsigns.botReserved(localCallsign))
                    putString("localCallsign", Callsigns.limit(localCallsign.trim()))
                for (seat in 0..1) putBoolean("autoPending$seat", nameDrafts.pending(seat))
                    .putString("autoRequest$seat", nameDrafts.requestID(seat))
            }
            .putInt("color", colorIndex)
            .putInt("localColor", localColorIndex)
            .putString("mode", savedLocalMode)
            .putString("rules", rulesJson(savedLocalRules).toString())
            .putString("modeProfiles", profiles.toString())
            .putBoolean("publicSelected", savedLocalPublic)
            .putBoolean("localSelected", savedLocalSelected)
            .putInt("bots", botCount)
            .putString(
                "localBots",
                JSONArray()
                    .apply {
                        mutableLocalBots.forEach { bot ->
                            put(
                                JSONObject()
                                    .put("name", bot.name)
                                    .put("colorIndex", bot.colorIndex)
                                    .put("difficulty", bot.difficulty)
                                    .put("team", bot.team),
                            )
                        }
                    }
                    .toString(),
            )
            .putInt("localTeam", localTeam)
            .putInt("secondLocalTeam", secondLocalTeam)
            .putString("difficulty", difficulty)
            .putBoolean("muted", muted)
            .putFloat("volume", volume)
            .putBoolean("highRefresh", highRefresh)
            .putString(NativeControlBindings.storageKey, keyboardBindings.encode())
            .putBoolean("mouseAim", mouseAim)
            .putBoolean("mouseFire", mouseFire)
            .putBoolean("gamepadSupport", gamepadSupport)
            .putBoolean("showPerformanceReadout", showFPS)
            .apply()
    }

    fun setServer(address: String) {
        val normalized = ServerAddress.configuredOrigin(address, BuildConfig.DEBUG)
        if (normalized == server) return
        check(!releasingCallsign) {
            "Wait for the callsign release to finish before changing servers."
        }
        if (online || screen == Screen.CONNECTING) leave()
        else if (store.activeIntent() != null) store.setActiveIntent(null)
        val previousServer = server
        server = normalized
        onlineIdentityReady = false
        nameRequest?.cancel()
        nameRequest = null
        nameRequestEpoch++
        nextNameAttempt = 0
        val savedNames = accounts.savedCallsigns(server)
        for (seat in 0..1) {
            accounts.invalidate(previousServer, seat)
            val key = store.selected(server, seat)?.key
            committedCallsigns[seat] =
                if (key == null) nameDrafts.name(seat)
                else savedNames.firstOrNull { it.key == key }?.name.orEmpty()
        }
        prefs.edit().putString("server", server).apply()
        statusRequest?.cancel()
        statusRequest = null
        statusInFlight = false
        statusEpoch++
        publicStatus = null
        latency = null
        refreshStatus()
        changed(true)
    }

    fun selectMode(value: String) {
        if (value !in modes) return
        if (rejectSurvivalRosterChange(value, value == "infinity", localSelected)) return
        modeProfiles["$profileContext:${if(rules.infinity) "infinity" else rules.mode}"] =
            rules.copy()
        val selected = rules.selectingMode(value, modeProfiles["$profileContext:$value"])
        if (online) {
            command("rules", "rules" to rulesJson(selected))
            return
        }
        val enteringLocal = publicSelected
        if (value != mode) configurationError = null
        rules = selected
        mode = value
        normalizeLocalTeams()
        if (enteringLocal && localBots.isEmpty()) resizeBots(3.coerceAtMost(maxLocalBots))
        publicSelected = false
        save()
        changed(true)
    }

    fun changeRules(value: RoomRules) {
        if (rejectSurvivalRosterChange(value.mode, value.infinity, localSelected)) return
        val updated =
            value.copy(
                teamMode =
                    if (!value.infinity && value.mode in listOf("ctf", "survival")) "teams"
                    else value.teamMode,
            )
        if (online) {
            command("rules", "rules" to rulesJson(updated))
            return
        }
        if (value != rules) configurationError = null
        rules = updated
        mode = if (rules.infinity) "infinity" else rules.mode
        publicSelected = false
        normalizeLocalTeams()
        modeProfiles["$profileContext:$mode"] = rules.copy()
        save()
        changed(true)
    }

    private fun rejectSurvivalRosterChange(
        mode: String,
        infinity: Boolean,
        paired: Boolean,
    ): Boolean {
        if (
            online || infinity || mode != "survival" || localBots.size + (if (paired) 2 else 1) <= 4
        )
            return false
        configurationError =
            "Survival supports up to four squad tanks. Remove a bot or a local pilot first."
        changed(true)
        return true
    }

    fun togglePublic(enabled: Boolean) {
        configurationError = null
        publicSelected = enabled
        if (online) command("select_public_infinity", "enabled" to enabled)
        else if (!enabled && !rules.infinity && localBots.isEmpty())
            resizeBots(3.coerceAtMost(maxLocalBots))
        save()
        changed(true)
    }

    private fun resizeBots(count: Int) {
        while (mutableLocalBots.size > count) mutableLocalBots.removeAt(mutableLocalBots.lastIndex)
        while (mutableLocalBots.size < count) {
            val id = (mutableLocalBots.maxOfOrNull { it.id } ?: 1) + 1
            val name =
                BotNames.next(mutableLocalBots.map { it.name } + callsign + localCallsign, id)
            mutableLocalBots.add(
                LocalBot(
                    id,
                    name,
                    GamePalette.index(id - 1),
                    difficulty,
                    nextLocalBotTeam(),
                ),
            )
        }
    }

    private fun nextLocalBotTeam(): Int {
        if (!rules.infinity && rules.mode == "survival") return 1
        if (rules.teamMode != "teams") return 0
        val first = localBots.count { it.team == 1 } + (if (localTeam == 1) 1 else 0)
        val second = localBots.count { it.team == 2 } + (if (localTeam == 2) 1 else 0)
        return if (first <= second) 1 else 2
    }

    private fun normalizeLocalTeams(resetCTF: Boolean = true) {
        if (!rules.infinity && rules.mode == "survival") {
            localTeam = 1
            secondLocalTeam = 1
            mutableLocalBots.indices.forEach { index ->
                mutableLocalBots[index] = mutableLocalBots[index].copy(team = 1)
            }
        } else if (!rules.infinity && rules.mode == "ctf") {
            localTeam = if (resetCTF) 1 else localTeam.coerceIn(1, 2)
            secondLocalTeam = secondLocalTeam.coerceIn(1, 2)
            mutableLocalBots.indices.forEach { index ->
                mutableLocalBots[index] =
                    mutableLocalBots[index].copy(
                        team =
                            if (resetCTF) if (index % 2 == 0) 2 else 1
                            else mutableLocalBots[index].team.coerceIn(1, 2),
                    )
            }
        }
        resizeBots(botCount.coerceAtMost(maxLocalBots))
    }

    fun addLocalBot() {
        if (botCount < maxLocalBots) {
            resizeBots(botCount + 1)
            save()
            changed(true)
        }
    }

    fun removeLocalBot(id: Int) {
        configurationError = null
        mutableLocalBots.removeAll { it.id == id }
        save()
        changed(true)
    }

    fun updateLocalBot(
        id: Int,
        name: String? = null,
        colorIndex: Int? = null,
        difficulty: String? = null,
        team: Int? = null,
    ) {
        val index = mutableLocalBots.indexOfFirst { it.id == id }
        if (index < 0) return
        val old = mutableLocalBots[index]
        val side =
            if (!rules.infinity && rules.mode == "survival") 1
            else team?.coerceIn(0, if (!rules.infinity && rules.mode == "ctf") 2 else 4) ?: old.team
        mutableLocalBots[index] =
            old.copy(
                name = name?.let { Callsigns.limit(it.trim()).ifBlank { "BOT" } } ?: old.name,
                colorIndex = colorIndex?.let(GamePalette::index) ?: old.colorIndex,
                difficulty = difficulty?.takeIf { it in BotDifficulty.names } ?: old.difficulty,
                team = side,
            )
        save()
        changed(true)
    }

    private fun preparePreview() {
        fixed = null
        practice = null
        localID = 1
        localID2 = null
        accumulator = 0.0
        previousFrame = 0
        maze = InfiniteMaze(7319)
        snapshot =
            ArenaSnapshot(
                tanks =
                    listOf(
                        ArenaTank(
                            id = localID,
                            name = callsign,
                            x = 126.0,
                            y = 126.0,
                            angle = -.6,
                            colorIndex = colorIndex,
                        ),
                    ),
                pickups =
                    listOf(
                        ArenaPickup(id = 1, x = 210.0, y = 210.0, type = "cannon"),
                        ArenaPickup(id = 2, x = 42.0, y = 210.0, type = "shield"),
                    ),
            )
    }

    fun play() {
        if (releasingCallsign) return
        if (
            !online &&
                publicSelected &&
                !nameDrafts.pending(0) &&
                prepareIdentityForOnline { play() }
        )
            return
        if (!validHumanNames()) return
        localStartError?.let {
            error(it)
            return
        }
        if (!online && publicSelected && awaitDefaultNames { play() }) return
        save()
        neutral()
        if (online) {
            if (room?.optBoolean("infinityActive") == true) {
                spectatorAutoEnter = true
                if (!arenaNetwork.connected)
                    attachRoomArena(room?.optBoolean("infinityPublic") == true)
                else {
                    arenaActive = true
                    screen = Screen.PLAYING
                    paused = false
                    changed(true)
                }
            } else if (roomSpectating) return
            else if (isHost) command(if (publicSelected) "start_public_infinity" else "start")
            else {
                val rows = room?.optJSONArray("players")
                val own = rows?.let {
                    (0 until it.length())
                        .map { i -> it.getJSONObject(i) }
                        .firstOrNull { it.optInt("id") == network.welcome?.id }
                }
                if (own != null) command("ready", "ready" to !own.optBoolean("ready"))
            }
            return
        }
        if (publicSelected) {
            online = true
            infinity = true
            arenaActive = true
            screen = Screen.CONNECTING
            changed(true)
            runCatching {
                arenaNetwork.connectPublic(
                    server,
                    callsign,
                    colorIndex,
                    localCallsign.takeIf { localSelected },
                    localColorIndex,
                    updateNames = true,
                )
            }
                .onFailure {
                    online = false
                    arenaActive = false
                    screen = Screen.READY
                    store.setActiveIntent(null)
                    error(it.message)
                }
            return
        }
        infinity = rules.infinity
        val seed = SecureRandom().nextInt()
        val secondaryPlayer =
            if (localSelected) LocalPilot(localCallsign, localColorIndex, secondLocalTeam) else null
        if (infinity) {
            practice =
                PracticeArena(
                    seed = seed,
                    name = callsign,
                    colorIndex = colorIndex,
                    botCount = botCount,
                    difficulty = difficulty,
                    secondaryPlayer = secondaryPlayer,
                )
            practice!!.configure(rules)
            practice!!.configurePilot(
                practice!!.localID,
                callsign,
                colorIndex,
                if (rules.teamMode == "teams") localTeam else 0,
            )
            practice!!.secondaryLocalID?.let {
                practice!!.configurePilot(
                    it,
                    localCallsign,
                    localColorIndex,
                    if (rules.teamMode == "teams") secondLocalTeam else 0,
                )
            }
            val firstBotID = (practice!!.secondaryLocalID ?: practice!!.localID) + 1
            localBots.forEachIndexed { index, bot ->
                practice!!.configurePilot(
                    index + firstBotID,
                    bot.name,
                    bot.colorIndex,
                    if (rules.teamMode == "teams") bot.team.coerceAtLeast(1) else 0,
                    bot.difficulty,
                )
            }
            fixed = null
            maze = practice!!.maze
            snapshot = practice!!.snapshot
        } else {
            fixed =
                FixedArena(
                    name = callsign,
                    colorIndex = colorIndex,
                    rules = rules,
                    botCount = botCount,
                    difficulty = difficulty,
                    seed = seed,
                    botNames = localBots.map { it.name },
                    botColors = localBots.map { it.colorIndex },
                    botDifficulties = localBots.map { it.difficulty },
                    botTeams = localBots.map { it.team },
                    localTeam = localTeam,
                    secondaryPlayer = secondaryPlayer,
                )
            practice = null
            maze = fixed!!.maze
            snapshot = fixed!!.snapshot
        }
        localID = practice?.localID ?: fixed!!.localID
        localID2 = practice?.secondaryLocalID ?: fixed?.secondaryLocalID
        snapshot = practice?.snapshot ?: fixed!!.snapshot
        accumulator = 0.0
        previousFrame = 0
        paused = false
        screen = Screen.PLAYING
        changed(true)
    }

    private fun localRoster(): List<PresetSeat> = buildList {
        add(PresetSeat("human", callsign, colorIndex, localTeam))
        if (localSelected) add(PresetSeat("local", localCallsign, localColorIndex, secondLocalTeam))
        localBots.forEach { bot ->
            add(PresetSeat("bot", bot.name, bot.colorIndex, bot.team, bot.difficulty))
        }
    }

    private fun onlineRoster(current: JSONObject): List<PresetSeat> {
        val host = current.optInt("host")
        return current
            .optJSONArray("players")
            ?.objects()
            .orEmpty()
            .filter { player ->
                val kind = player.optString("kind")
                player.optInt("id") == host ||
                    kind == "bot" ||
                    kind == "local" && player.optInt("owner") == host
            }
            .sortedBy { it.optInt("id") != host }
            .map { player ->
                val seat = PresetSeat.fromJson(player)
                if (player.optInt("id") == host) seat.copy(kind = "human") else seat
            }
    }

    private fun readPresets(): MutableList<RoomPreset> {
        val presets = runCatching {
            JSONArray(prefs.getString("roomPresets", "[]")!!).objects()
        }
            .getOrDefault(emptyList())
            .mapNotNull { runCatching { RoomPreset.fromJson(it) }.getOrNull() }
            .takeLast(RoomPreset.maxCount)
            .toMutableList()
        if (presets.isEmpty())
            prefs.getString("preset", null)?.let { encoded ->
                runCatching {
                    RoomPreset("Saved preset", SnapshotDecoder.rules(JSONObject(encoded)), null)
                }
                    .onSuccess { presets += it }
            }
        return presets
    }

    val canLoadPreset: Boolean
        get() {
            if (screen != Screen.READY || releasingCallsign) return false
            if (!online) return true
            val current = room ?: return false
            return isHost &&
                roomSetupOpen &&
                (current.optJSONArray("spectators")?.length() ?: 0) == 0 &&
                current.optJSONArray("players")?.objects().orEmpty().none {
                    it.optInt("id") != current.optInt("host") &&
                        it.optString("kind") !in setOf("bot", "local")
                }
        }

    fun savePreset(value: String): Boolean {
        val name = Callsigns.limit(value.trim(), RoomPreset.maxNameLength)
        if (name.isEmpty() || !isHost || releasingCallsign || screen != Screen.READY) return false
        val roster =
            if (online) room?.let(::onlineRoster)?.takeIf { it.isNotEmpty() } ?: return false
            else localRoster()
        mutablePresets.removeAll { it.name == name }
        mutablePresets.add(RoomPreset(name, rules.copy(), roster))
        if (mutablePresets.size > RoomPreset.maxCount) mutablePresets.removeAt(0)
        prefs
            .edit()
            .putString("roomPresets", JSONArray(mutablePresets.map(RoomPreset::toJson)).toString())
            .remove("preset")
            .apply()
        return true
    }

    fun loadPreset(preset: RoomPreset): Boolean {
        if (!canLoadPreset) {
            error("Presets require a host-only lobby without online guests or spectators.")
            return false
        }
        val roster = preset.roster
        if (roster == null) {
            if (rejectSurvivalRosterChange(preset.rules.mode, preset.rules.infinity, localSelected))
                return false
            changeRules(preset.rules)
            return true
        }
        if (online) {
            val current = onlineRoster(room ?: return false)
            val primary = current.firstOrNull() ?: return false
            val selectedSecondary =
                store.selected(server, 1)?.let { credential ->
                    accounts.savedCallsigns(server).firstOrNull { it.key == credential.key }?.name
                }
            val localName =
                current.firstOrNull { it.kind == "local" }?.name
                    ?: selectedSecondary
                    ?: localCallsign
            val seats = roster.map { seat ->
                when (seat.kind) {
                    "human" -> seat.copy(name = primary.name)
                    "local" -> seat.copy(name = localName)
                    else -> seat
                }
            }
            command("preset", "rules" to rulesJson(preset.rules), "roster" to seats.toRosterJson())
            return true
        }
        val primary = roster.firstOrNull()?.takeIf { it.kind == "human" } ?: return false
        val secondary = roster.firstOrNull { it.kind == "local" }
        val bots = roster.filter { it.kind == "bot" }
        if (bots.size > preset.rules.botCapacity(if (secondary == null) 1 else 2)) {
            error("The saved roster exceeds this mode's tank limit.")
            return false
        }
        rules = preset.rules.copy()
        mode = if (rules.infinity) "infinity" else rules.mode
        mutableLocalBots.clear()
        bots.forEachIndexed { index, bot ->
            mutableLocalBots.add(LocalBot(index + 2, bot.name, bot.color, bot.difficulty, bot.team))
        }
        configurationError = null
        localTeam = primary.team.coerceIn(1, 4)
        localSelected = secondary != null
        secondLocalTeam = secondary?.team?.coerceIn(1, 4) ?: 1
        localColorIndex = secondary?.color ?: 1
        publicSelected = false
        normalizeLocalTeams(resetCTF = false)
        save()
        changed(true)
        return true
    }

    fun share(forQueue: Boolean = false) {
        if (releasingCallsign || online) return
        if (!nameDrafts.pending(0) && prepareIdentityForOnline { share(forQueue) }) return
        if (!validHumanNames() || awaitDefaultNames { share(forQueue) }) return
        save()
        arenaNetwork.disconnect(false)
        arenaActive = false
        online = true
        infinity = rules.infinity
        screen = Screen.CONNECTING
        pendingQueue = forQueue
        pendingPublicSelection = publicSelected
        queuePacket = null
        spectatorAutoEnter = true
        runCatching {
            network.connectPublishedRoom(
                server,
                callsign,
                rulesJson(rules),
                localRoster().toRosterJson(),
                roomName.takeIf { it.isNotBlank() },
            )
        }
            .onFailure {
                pendingQueue = false
                pendingPublicSelection = false
                online = false
                screen = Screen.READY
                error(it.message)
            }
        changed(true)
    }

    fun join(code: String, spectator: Boolean = false) {
        val includeLocal =
            !spectator && (if (room != null) roomLocalPilot != null else localSelected)
        join(code, spectator, includeLocal)
    }

    private fun join(code: String, spectator: Boolean, includeLocal: Boolean) {
        if (releasingCallsign) return
        if (!validHumanNames(includeLocal)) return
        if (awaitDefaultNames(includeLocal) { join(code, spectator, includeLocal) }) return
        if (prepareIdentityForOnline(includeLocal) { join(code, spectator, includeLocal) }) return
        save()
        if (online) leave()
        online = true
        screen = Screen.CONNECTING
        infinity = false
        pendingQueue = false
        pendingPublicSelection = false
        pendingLocalJoin = includeLocal
        queuePacket = null
        spectatorAutoEnter = true
        runCatching { network.connectRoom(server, callsign, code.trim(), spectator) }
            .onFailure {
                pendingLocalJoin = false
                online = false
                screen = Screen.READY
                error(it.message)
            }
        changed(true)
    }

    fun findMatch() {
        if (releasingCallsign) return
        if (online) command("queue_info") else share(forQueue = true)
    }

    fun leave() {
        pendingOnlineAction = null
        pendingQueue = false
        pendingPublicSelection = false
        pendingLocalJoin = false
        queuePacket = null
        spawnNotices.clear()
        neutral()
        arenaNetwork.disconnect()
        network.disconnect()
        store.setActiveIntent(null)
        arenaActive = false
        room = null
        online = false
        paused = false
        screen = Screen.READY
        localID = 1
        localID2 = null
        followingID = 0
        latency = null
        timeline.reset()
        timelineOwner = null
        timelineConnection = -1
        renameNames.fill(null)
        renameRequests.fill(0)
        rules = savedLocalRules.copy()
        mode = savedLocalMode
        publicSelected = savedLocalPublic
        localSelected = savedLocalSelected
        configurationError = null
        preparePreview()
        status = "Local play is ready. Share to invite online friends."
        changed(true)
    }

    fun lobby(endMatch: Boolean = true) {
        neutral()
        paused = false
        if (online && room != null) {
            arenaNetwork.disconnect()
            arenaActive = false
            spectatorAutoEnter = false
            followingID = 0
            localID = network.welcome?.id ?: localID
            localID2 = network.welcome?.localId
            if (endMatch && isHost) command("lobby")
            screen = Screen.READY
            changed(true)
        } else if (online) leave()
        else {
            screen = Screen.READY
            preparePreview()
            changed(true)
        }
    }

    val canResume: Boolean
        get() =
            (!online || activeNetwork.connected) && (spectating || !Callsigns.botReserved(callsign))

    val canRestartWave: Boolean
        get() =
            if (online) room?.optBoolean("canRestartWave") == true
            else fixed?.canRestartWave == true

    fun restartMatch(wave: Boolean = false) {
        neutral()
        paused = false
        previousFrame = 0
        accumulator = 0.0
        if (!online) {
            val arena = fixed
            if (arena == null) play()
            else {
                if (wave) arena.restartWave() else arena.restart()
                maze = arena.maze
                snapshot = arena.snapshot
                screen = Screen.PLAYING
                changed(true)
            }
        } else if (wave) {
            snapshot.objectives?.survival?.let {
                command("restart_wave", "generation" to snapshot.generation, "wave" to it.wave)
            }
        } else if (room?.optJSONObject("matchmaking") != null) command("rematch")
        else if (isHost) command("start")
        else {
            command("ready", "ready" to true)
            screen = Screen.READY
            changed(true)
        }
    }

    fun pause(value: Boolean) {
        paused = value
        neutral()
        previousFrame = 0
        changed(true)
    }

    fun neutral() {
        input = GameInput()
        input2 = GameInput()
        for (id in listOfNotNull(localID, localID2)) {
            practice?.resetFire(id)
            fixed?.combat?.resetFire(id)
        }
        cancelFireFeedback()
        if (online && hasLocalPlayer) {
            val client = activeNetwork
            if (!spectating)
                client.sendInput(
                    timeline.neutralPacket(),
                    paused = true,
                    player = localID,
                    member = client.welcome?.member,
                )
            if (canControlSecondary)
                client.sendInput(
                    timeline.neutralLocalPacket() ?: GameInput(),
                    paused = true,
                    local = true,
                    player = localID2,
                    member = client.welcome?.localMember,
                )
        }
        timeline.neutralize()
    }

    fun foreground() {
        active = true
        previousFrame = 0
        val intent = if (online) null else store.activeIntent()?.takeIf { it.origin == server }
        if (online) {
            network.resume()
            if (arenaActive) arenaNetwork.resume()
        } else if (intent != null) {
            val legacyIntent =
                LegacyCallsignDefaults.shouldGenerate(
                    intent.name,
                    store.selected(intent.origin, 0) != null,
                ) ||
                    intent.localName?.let {
                        LegacyCallsignDefaults.shouldGenerate(
                            it,
                            store.selected(intent.origin, 1) != null,
                        )
                    } == true
            if (legacyIntent) {
                // A stale no-key auto-resume must not restore an old default over the bootstrap.
                // The next deliberate Play claims the new defaults with persisted independent keys.
                store.setActiveIntent(null)
                localSelected = intent.localName != null
                colorIndex = intent.colorIndex
                localColorIndex = intent.localColorIndex
                save()
                changed(true)
                main.removeCallbacks(statusTicker)
                main.post(statusTicker)
                return
            }
            online = true
            infinity = true
            arenaActive = true
            screen = Screen.CONNECTING
            callsign = intent.name
            localSelected = intent.localName != null
            localCallsign = intent.localName ?: localCallsign
            colorIndex = intent.colorIndex
            localColorIndex = intent.localColorIndex
            runCatching { arenaNetwork.restorePublicIntent() }
                .onFailure {
                    online = false
                    arenaActive = false
                    screen = Screen.READY
                    store.setActiveIntent(null)
                    error(it.message)
                }
            changed(true)
        }
        main.removeCallbacks(statusTicker)
        main.post(statusTicker)
    }

    fun background() {
        active = false
        neutral()
        network.suspend()
        arenaNetwork.suspend()
        previousFrame = 0
        statusRequest?.cancel()
        statusRequest = null
        statusInFlight = false
        statusEpoch++
        nameRequest?.cancel()
        nameRequest = null
        nameRequestEpoch++
        main.removeCallbacks(statusTicker)
    }

    fun release() {
        background()
        network.close()
        arenaNetwork.close()
        main.removeCallbacksAndMessages(null)
        accounts.close()
    }

    fun refreshStatus() {
        ensureDefaultNames()
        if (
            !active ||
                statusInFlight ||
                screen != Screen.READY ||
                (!publicSelected && (!showFPS || network.connected))
        )
            return
        statusInFlight = true
        val requestedServer = server
        val requestEpoch = ++statusEpoch
        statusRequest =
            accounts.publicStatus(server) { result ->
                if (requestEpoch == statusEpoch) {
                    statusInFlight = false
                    statusRequest = null
                    if (active && requestedServer == server && screen == Screen.READY)
                        result.onSuccess {
                            publicStatus = it
                            if (!network.connected) latency = it.latencyMilliseconds
                            changed(false)
                        }
                }
            }
    }

    fun frame(nanos: Long) {
        if (!active) return
        val dt =
            if (previousFrame == 0L) 0.0 else ((nanos - previousFrame) / 1e9).coerceIn(0.0, .08)
        previousFrame = nanos
        // Mutable controller inputs must be sampled before physics so their edge is not replayed.
        observeFire(false, input.fire, nanos)
        observeFire(true, input2.fire, nanos)
        if (screen == Screen.PLAYING && !paused) {
            if (online) {
                val client = activeNetwork
                snapshot =
                    timeline.render(
                        dt,
                        input,
                        nanos / 1e9,
                        maze,
                        input2 = input2.takeIf { localID2 != null },
                        sendLocal = { packet ->
                            if (canControlSecondary)
                                client.sendInput(
                                    packet,
                                    local = true,
                                    player = localID2,
                                    member = client.welcome?.localMember,
                                )
                        },
                    ) { packet ->
                        if (!spectating)
                            client.sendInput(
                                packet,
                                player = localID,
                                member = client.welcome?.member,
                            )
                    } ?: snapshot
            } else {
                accumulator += dt
                var steps = 0
                if (offlinePrimary != localID || offlineSecondary != localID2) {
                    offlineInputs.clear()
                    offlinePrimary = localID
                    offlineSecondary = localID2
                }
                offlineInputs[localID] = input
                localID2?.let { offlineInputs[it] = input2 }
                while (accumulator + 1e-9 >= 1.0 / 60 && steps < 5) {
                    practice?.step(offlineInputs, 1.0 / 60)
                    fixed?.step(offlineInputs, 1.0 / 60)
                    accumulator = max(0.0, accumulator - 1.0 / 60)
                    steps++
                }
                snapshot =
                    practice?.presentationSnapshot(accumulator * 60, input, input2)
                        ?: fixed?.presentationSnapshot(accumulator * 60, input, input2)
                        ?: snapshot
                fixed?.let { maze = it.maze }
            }
        }
        if (
            screen == Screen.PLAYING &&
                paused &&
                (authoritativeSnapshot.result != null ||
                    authoritativeSnapshot.phase in listOf("roundOver", "matchOver"))
        ) {
            snapshot =
                if (online) timeline.renderTerminal(dt) ?: snapshot
                else if (finishingProjectilePresentation)
                    practice?.presentationSnapshot(0.0, nowSeconds = nanos / 1e9)
                        ?: fixed?.presentationSnapshot(0.0, nowSeconds = nanos / 1e9)
                        ?: snapshot
                else snapshot
        }
        val authority = authoritativeSnapshot
        val feedbackPlaying = fireFeedbackPlaying(authority)
        previewRecoil =
            fireFeedback.pulse(
                authority.tanks.firstOrNull { it.id == localID },
                authority.generation,
                feedbackPlaying,
                nanos / 1e9,
            )
        localPreviewRecoil =
            localFireFeedback.pulse(
                localID2?.let { id -> authority.tanks.firstOrNull { it.id == id } },
                authority.generation,
                feedbackPlaying,
                nanos / 1e9,
            )
        present(snapshot, maze, localID, localID2, online)
        if (screen == Screen.PLAYING) {
            uiElapsed += dt
            val authority = authoritativeSnapshot
            val primaryEpoch =
                authority.tanks.firstOrNull { it.id == localID }?.ammoEpoch ?: Long.MIN_VALUE
            val secondaryEpoch =
                localID2?.let { id -> authority.tanks.firstOrNull { it.id == id }?.ammoEpoch }
                    ?: Long.MIN_VALUE
            val refilled = primaryEpoch != hudAmmoEpoch || secondaryEpoch != hudLocalAmmoEpoch
            hudAmmoEpoch = primaryEpoch
            hudLocalAmmoEpoch = secondaryEpoch
            if (uiElapsed >= .1 || refilled) {
                uiElapsed %= .1
                changed(false)
            }
        } else uiElapsed = 0.0
    }

    private var hudAmmoEpoch = Long.MIN_VALUE
    private var hudLocalAmmoEpoch = Long.MIN_VALUE

    fun cancelFireFeedback() {
        fireFeedback.reset(input.fire)
        localFireFeedback.reset(input2.fire)
        previewRecoil = 0.0
        localPreviewRecoil = 0.0
    }

    private fun fireFeedbackPlaying(state: ArenaSnapshot) =
        audioGameplayActive &&
            fireFeedbackAllowed() &&
            state.phase == "playing" &&
            state.result == null &&
            state.objectives?.survival?.status != "break"

    private fun observeFire(local: Boolean, fire: Boolean, nanos: Long) {
        val state = authoritativeSnapshot
        val id = if (local) localID2 else localID
        val tank = id?.let { target -> state.tanks.firstOrNull { it.id == target } }
        val edge = fire != (if (local) observedLocalFire else observedFire)
        if (local) observedLocalFire = fire else observedFire = fire
        val playing = fireFeedbackPlaying(state)
        if (edge && playing && id != null && tank != null && tank.hp > 0) {
            if (online) {
                val client = activeNetwork
                timeline.inputEdgePacket(if (local) input2 else input, local)?.let { packet ->
                    client.sendInput(
                        packet,
                        local = local,
                        player = id,
                        member = if (local) client.welcome?.localMember else client.welcome?.member,
                    )
                }
            } else {
                practice?.captureFire(id, fire)
                fixed?.combat?.captureFire(id, fire)
            }
        }
        val age = if (online) max(0.0, nanos / 1e9 - timeline.authoritativeArrivalTime) else 0.0
        val accepted =
            (if (local) localFireFeedback else fireFeedback).controls(
                fire,
                tank,
                state.generation,
                playing,
                nanos / 1e9,
                age,
            )
        if (
            accepted &&
                tank != null &&
                !muted &&
                volume > 0 &&
                PressFireFeedback.ammoUnavailable(tank, state, age)
        )
            emitAudioCue(AudioCue.DRY_FIRE)
    }

    val finishingProjectilePresentation: Boolean
        get() =
            if (online) timeline.hasPendingProjectileFlights
            else
                practice?.hasPendingProjectileFlights ?: fixed?.hasPendingProjectileFlights ?: false

    /** HUD and input readiness always read immediate authority, never a held contact body. */
    val authoritativeSnapshot: ArenaSnapshot
        get() =
            if (online) timeline.authoritativeSnapshot ?: snapshot
            else practice?.snapshot ?: fixed?.snapshot ?: snapshot

    private fun canonicalCallsign(name: String) = Callsigns.canonical(name)

    fun renameCallsign(
        name: String,
        seat: Int = 0,
        validate: Boolean = false,
        completed: (() -> Unit)? = null,
    ) {
        require(seat in 0..1)
        val cleaned =
            Callsigns.limit(name.trim()).ifBlank { if (seat == 0) "Pilot" else "Co-pilot" }
        if (Callsigns.botReserved(cleaned)) {
            error(Callsigns.botNamespaceMessage)
            return
        }
        if (switchingCallsign || releasingCallsign) return
        val previousName = committedCallsigns[seat]
        val selected = store.selected(server, seat)
        val same = canonicalCallsign(cleaned) == canonicalCallsign(previousName)
        if (seat == 0) callsign = cleaned else localCallsign = cleaned
        if (!validate && same) {
            if (seat == 0) callsign = cleaned else localCallsign = cleaned
            save()
            completed?.invoke()
            return
        }
        val origin = server
        val sourceScreen = screen
        val sourceOnline = online
        val stamp = nameDrafts.request(seat, origin, selected?.key.orEmpty())
        fun unchanged() =
            !releasingCallsign &&
                screen == sourceScreen &&
                online == sourceOnline &&
                nameDrafts.isCurrent(stamp, server, store.selected(server, seat)?.key.orEmpty())
        fun accept(checked: CheckedAccount) {
            committedCallsigns[seat] = checked.info.preferredCallsign ?: cleaned
            if (seat == 0) callsign = committedCallsigns[seat]
            else localCallsign = committedCallsigns[seat]
            save()
            if (!validate || !same || checked.key != selected?.key) leave()
            completed?.invoke()
        }
        fun reject(error: Throwable) {
            if (!unchanged()) return
            if (seat == 0) callsign = previousName else localCallsign = previousName
            save()
            error(error.message)
            changed(true)
        }
        switchingCallsign = true
        runCatching {
            accounts.switchCallsign(
                origin,
                seat,
                cleaned,
                previousName,
                localOnly = !online && screen == Screen.PLAYING,
                canCommit = ::unchanged,
            ) { result ->
                switchingCallsign = false
                result.onSuccess(::accept).onFailure { failure ->
                    if (
                        !validate &&
                            !online &&
                            unchanged() &&
                            (failure as? NetworkFailure)?.code in
                                setOf("network", "server_busy", "server_error")
                    ) {
                        accounts.switchCallsign(
                            origin,
                            seat,
                            cleaned,
                            previousName,
                            localOnly = true,
                            canCommit = ::unchanged,
                        ) {
                            it.onSuccess(::accept).onFailure(::reject)
                        }
                    } else reject(failure)
                }
            }
        }
            .onFailure {
                switchingCallsign = false
                error(it.message)
            }
    }

    private fun prepareIdentityForOnline(
        includeLocal: Boolean = localSelected,
        action: () -> Unit,
    ): Boolean {
        if (switchingCallsign) return true
        if (onlineIdentityReady) {
            onlineIdentityReady = false
            return false
        }
        val seats = if (includeLocal) listOf(0, 1) else listOf(0)
        fun prepare(index: Int) {
            if (index == seats.size) {
                onlineIdentityReady = true
                action()
                return
            }
            val seat = seats[index]
            renameCallsign(nameDrafts.name(seat), seat, validate = true) { prepare(index + 1) }
        }
        prepare(0)
        return true
    }

    fun addRoomLocalPilot() {
        if (!canAddRoomLocalPilot) return
        // An existing credential stays paired with its committed callsign. The room add
        // claims a new durable P2 credential atomically when the seat has no account yet.
        val name = if (store.selected(server, 1) == null) localCallsign else committedCallsigns[1]
        if (Callsigns.botReserved(name)) {
            error(Callsigns.botNamespaceMessage)
            return
        }
        command("add", "kind" to "local", "name" to name)
    }

    fun command(type: String, vararg fields: Pair<String, Any?>) {
        val json = JSONObject().put("type", type)
        fields.forEach { (key, value) -> json.put(key, value) }
        val target = json.optInt("target", -1)
        if (type == "rename" && json.has("name")) {
            renameCallsign(json.getString("name"), 0)
            return
        }
        if (
            type in setOf("rename_local", "configure") &&
                json.has("name") &&
                target == network.welcome?.localId
        ) {
            renameCallsign(json.getString("name"), 1)
            return
        }
        runCatching { (if (room != null) network else activeNetwork).send(json) }
            .onFailure { error(it.message) }
    }

    private fun error(message: String?) {
        status = message ?: "Unable to complete this action."
        changed(true)
        notifyError(status)
    }

    private fun attachRoomArena(public: Boolean) {
        val identity = network.welcome ?: return
        if (public && identity.spectating) {
            status = "Spectating is available for room Infinity."
            changed(true)
            return
        }
        val code = identity.room ?: return
        val token = identity.token ?: return
        infinity = true
        arenaActive = true
        screen = Screen.CONNECTING
        val roomLocal =
            room?.optJSONArray("players")?.let { rows ->
                (0 until rows.length())
                    .map { rows.getJSONObject(it) }
                    .firstOrNull {
                        it.optString("kind") == "local" && it.optInt("owner", -1) == identity.id
                    }
            }
        val hasLocal = identity.localId != null || roomLocal != null
        if (public)
            store.setActiveIntent(
                PublicIntent(
                    server,
                    callsign,
                    colorIndex,
                    if (hasLocal) roomLocal?.optString("name", localCallsign) ?: localCallsign
                    else null,
                    localColorIndex,
                ),
            )
        runCatching {
            arenaNetwork.connectRoomInfinity(
                server,
                code,
                token,
                includeLocal = hasLocal,
                spectating = identity.spectating,
            )
        }
            .onFailure {
                arenaActive = false
                screen = Screen.READY
                error(it.message)
            }
        changed(true)
    }

    private fun networkEvent(event: NetworkEvent, fromArena: Boolean) {
        val previousScreen = screen
        val client = if (fromArena) arenaNetwork else network
        val isPlayingClient = if (arenaActive) fromArena else !fromArena
        when (event) {
            is NetworkEvent.Status ->
                if (isPlayingClient || screen == Screen.CONNECTING) status = event.message
            is NetworkEvent.Welcome -> {
                val welcome = event.welcome
                if (isPlayingClient) {
                    localID = welcome.id
                    localID2 =
                        welcome.localId.takeUnless {
                            welcome.spectating && (fromArena || welcome.isPublic)
                        }
                    followingID = welcome.following
                    welcome.seed?.let { maze = InfiniteMaze(it) }
                    if (fromArena || welcome.isPublic) {
                        screen = Screen.PLAYING
                    } else screen = Screen.READY
                    val newTransport =
                        timelineOwner !== client ||
                            timelineConnection != client.connectionGeneration
                    timeline.setLocalIDs(
                        if (welcome.spectating) -1 else localID,
                        localID2,
                        client.lastLocalInputSequence,
                    )
                    if (newTransport) {
                        timeline.reset(client.lastInputSequence, client.lastLocalInputSequence)
                        timelineOwner = client
                        timelineConnection = client.connectionGeneration
                        previousFrame = 0
                    } else if (!fromArena && previousScreen == Screen.PLAYING)
                        screen = previousScreen
                }
            }
            is NetworkEvent.State ->
                if (isPlayingClient) {
                    audioStateOwner = client
                    audioStateConnection = client.connectionGeneration
                    if (client.isPublic)
                        spawnNotices.accept(event.snapshot.godlikeSpawns, System.nanoTime() / 1e9)
                    timeline.accept(event.snapshot, System.nanoTime() / 1e9)
                    if (event.snapshot.spectating) followingID = event.snapshot.following
                    event.snapshot.world?.let { world ->
                        if (maze?.world !== world) maze = InfiniteMaze(world)
                    }
                    if (event.snapshot.phase != "lobby") screen = Screen.PLAYING
                    snapshot = event.snapshot
                    for (seat in 0..1) {
                        val id = if (seat == 0) localID else localID2
                        event.snapshot.tanks
                            .firstOrNull { it.id == id }
                            ?.let { tank ->
                                if (committedCallsigns[seat] != tank.name) {
                                    committedCallsigns[seat] = tank.name
                                    store.selected(server, seat)?.let {
                                        accounts.rememberCallsign(server, seat, tank.name, it.key)
                                    }
                                }
                            }
                    }
                }
            is NetworkEvent.Latency -> if (isPlayingClient) latency = event.milliseconds
            is NetworkEvent.InfinityStarted ->
                if (!fromArena) {
                    spectatorAutoEnter = true
                    attachRoomArena(event.isPublic)
                }
            is NetworkEvent.Reconnecting ->
                if (isPlayingClient) {
                    neutral()
                    status = "Reconnecting… (${event.attempt})"
                }
            is NetworkEvent.Disconnected ->
                if (isPlayingClient && event.message != null) status = event.message
            is NetworkEvent.Error -> {
                if (
                    fromArena &&
                        event.terminal &&
                        event.code == "room_access_changed" &&
                        room != null
                ) {
                    neutral()
                    paused = false
                    arenaNetwork.disconnect(false)
                    arenaActive = false
                    followingID = 0
                    screen = Screen.READY
                    status = event.message
                } else if (
                    event.terminal &&
                        !fromArena &&
                        arenaActive &&
                        arenaNetwork.isPublic &&
                        event.code !in
                            setOf("account_key_revoked", "account_key_invalid", "session_replaced")
                ) {
                    // Public accounts survive loss of the temporary party/room route.
                    network.disconnect(false)
                    room = null
                } else {
                    neutral()
                    paused = false
                    if (event.terminal) {
                        pendingQueue = false
                        pendingPublicSelection = false
                        pendingLocalJoin = false
                        screen = Screen.READY
                        online = false
                        room = null
                        arenaActive = false
                        network.disconnect(false)
                        arenaNetwork.disconnect(false)
                        store.setActiveIntent(null)
                    }
                    error(event.message)
                }
            }
            is NetworkEvent.Packet -> packet(event.packet, fromArena)
        }
        // Display-paced frame() owns HUD updates. Network snapshots must not
        // trigger an additional hierarchy/layout pass at every server tick.
        if (event !is NetworkEvent.State) changed(event !is NetworkEvent.Latency)
        else if (screen != previousScreen) changed(true)
    }

    private fun packet(packet: JSONObject, fromArena: Boolean) {
        when (packet.optString("type")) {
            "room" -> {
                if (fromArena) return
                if (room?.optString("code")?.let { it != packet.optString("code") } == true)
                    queuePacket = null
                room = packet
                packet.optJSONArray("players")?.let { rows ->
                    for (seat in 0..1) {
                        val id = if (seat == 0) network.welcome?.id else network.welcome?.localId
                        val player =
                            (0 until rows.length())
                                .map { rows.getJSONObject(it) }
                                .firstOrNull { it.optInt("id") == id }
                        player
                            ?.optString("name")
                            ?.takeIf { it.isNotBlank() && it != committedCallsigns[seat] }
                            ?.let { name ->
                                committedCallsigns[seat] = name
                                store.selected(server, seat)?.let {
                                    accounts.rememberCallsign(server, seat, name, it.key)
                                }
                            }
                    }
                }
                packet.optJSONObject("rules")?.let {
                    rules = SnapshotDecoder.rules(it)
                    mode = if (rules.infinity) "infinity" else rules.mode
                }
                val publishedPublic = pendingPublicSelection && isHost
                pendingPublicSelection = false
                publicSelected = publishedPublic || packet.optBoolean("infinityPublic")
                if (publishedPublic && !packet.optBoolean("infinityPublic"))
                    command("select_public_infinity", "enabled" to true)
                if (pendingQueue) {
                    pendingQueue = false
                    command("queue_info")
                }
                if (packet.optString("phase") == "lobby" && !packet.optBoolean("infinityActive")) {
                    if (arenaActive) {
                        arenaNetwork.disconnect()
                        arenaActive = false
                        localID = network.welcome?.id ?: localID
                        localID2 = network.welcome?.localId
                    }
                    screen = Screen.READY
                    followingID = 0
                } else if (
                    packet.optBoolean("infinityActive") && !packet.optBoolean("infinityPublic")
                ) {
                    val changedRole =
                        arenaActive &&
                            arenaNetwork.welcome?.let { it.spectating != roomSpectating } == true
                    if (changedRole) {
                        spectatorAutoEnter = true
                        neutral()
                        arenaNetwork.disconnect(false)
                        arenaActive = false
                    }
                    if (!arenaActive && (roomSpectating && spectatorAutoEnter || changedRole))
                        attachRoomArena(false)
                }
                infinity = arenaActive || rules.infinity
                if (pendingLocalJoin) {
                    pendingLocalJoin = false
                    if (!roomSpectating) addRoomLocalPilot()
                }
            }
            "followed" -> if (fromArena && spectating) followingID = packet.optInt("following")
            "room_renamed" -> {
                packet
                    .optString("room")
                    .takeIf { it.isNotBlank() }
                    ?.let {
                        network.updateResumeRoomCode(it)
                        arenaNetwork.updateResumeRoomCode(it)
                        room?.put("code", it)
                    }
            }
            "renamed",
            "rename_error" -> {
                val seat =
                    packet.renamedSeat(
                        if (fromArena) localID else network.welcome?.id ?: localID,
                        if (fromArena) localID2 else network.welcome?.localId,
                    ) ?: return
                if (fromArena && packet.optLong("requestId") != renameRequests[seat]) return
                val expected = renameNames[seat]
                val draft = if (seat == 0) callsign else localCallsign
                if (expected != null && draft != expected) return
                if (packet.optString("type") == "rename_error") {
                    renameNames[seat] = null
                    error(packet.optString("message", "That callsign could not be used."))
                } else {
                    val value = packet.optString("name", draft)
                    if (expected == null || value == expected) {
                        if (seat == 1) localCallsign = value else callsign = value
                        renameNames[seat] = null
                        save()
                    }
                }
            }
            "error" -> {
                if (!fromArena && packet.optString("action") == "select_public_infinity")
                    publicSelected = room?.optBoolean("infinityPublic") == true
            }
            "queue_catalog",
            "queue_status",
            "queue_cancelled" -> {
                if (fromArena) return
                if (!packet.has("queues"))
                    queuePacket?.optJSONArray("queues")?.let { packet.put("queues", it) }
                queuePacket = packet
            }
            "unshared" ->
                if (!fromArena) {
                    leave()
                    error(packet.optString("message", "The room is no longer available."))
                }
            "leaderboard_reset" -> status = "Leaderboard reset. Everyone starts at 0."
        }
    }

    companion object {
        const val defaultServer = "https://leqra.com"

        val modes =
            linkedMapOf(
                "infinity" to "Infinity",
                "elimination" to "Elimination",
                "ctf" to "Capture the flag",
                "koth" to "King of the hill",
                "survival" to "Survival",
            )

        fun rulesJson(r: RoomRules) = ProtocolJson.rules(r)
    }
}
