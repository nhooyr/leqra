package com.leqra.android

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.leqra.android.accounts.*
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
                !online &&
                !network.connected &&
                !arenaNetwork.connected &&
                store.activeIntent() == null

    var changed: (Boolean) -> Unit = {}
    var present: (ArenaSnapshot, InfiniteMaze?, Int, Int?, Boolean) -> Unit = { _, _, _, _, _ -> }
    var notifyError: (String) -> Unit = {}
    var notifyChat: () -> Unit = {}
    var server = prefs.getString("server", "https://leqra.com")!!
        private set

    var callsign = prefs.getString("callsign", "Pilot ${100 + SecureRandom().nextInt(900)}")!!
    var localCallsign = prefs.getString("localCallsign", "Co-pilot")!!
    var colorIndex = prefs.getInt("color", 0)
    var localColorIndex = prefs.getInt("localColor", 1)
    var localSelected = prefs.getBoolean("localSelected", false)
    var publicSelected = prefs.getBoolean("publicSelected", true)
    var mode = prefs.getString("mode", "infinity")!!.takeIf { it in modes } ?: "infinity"
    var rules =
        runCatching {
            prefs.getString("rules", null)?.let { SnapshotDecoder.rules(JSONObject(it)) }
        }
            .getOrNull() ?: RoomRules.localDefaults(mode)
    private var savedLocalRules = rules.copy()
    private var savedLocalMode = mode
    private var savedLocalPublic = publicSelected
    private val modeProfiles = mutableMapOf<String, RoomRules>()
    private val mutableLocalBots = mutableListOf<LocalBot>()
    val localBots: List<LocalBot>
        get() = mutableLocalBots

    var botCount: Int
        get() = mutableLocalBots.size
        set(value) {
            resizeBots(value.coerceIn(0, maxLocalBots))
        }

    var localTeam = prefs.getInt("localTeam", 1).coerceIn(1, 4)
    var secondLocalTeam = prefs.getInt("secondLocalTeam", 1).coerceIn(1, 4)
    var difficulty = prefs.getString("difficulty", "normal")?.takeIf { it in BotDifficulty.names } ?: "normal"
    var roomName = ""
    var muted = prefs.getBoolean("muted", false)
    var volume = prefs.getFloat("volume", .5f)
    var highRefresh = prefs.getBoolean("highRefresh", true)
    var showFPS = prefs.getBoolean("showFPS", false)
    var screen = Screen.READY
        private set

    var paused = false
        private set

    var online = false
        private set

    var infinity = true
        private set

    var room: JSONObject? = null
        private set

    var status = "Local play is ready. Share to invite online friends."
        private set

    var latency = 0.0
        private set

    var publicStatus: PublicStatus? = null
        private set

    var snapshot = ArenaSnapshot()
        private set

    var localID = 1
        private set

    var localID2: Int? = null
        private set

    var maze: InfiniteMaze? = null
        private set

    var queuePacket: JSONObject? = null
        private set

    val chat = mutableListOf<String>()
    var input = GameInput()
    var input2 = GameInput()
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
    private var previewSeed = 137
    private var timeline = OnlinePresentation()
    private var timelineOwner: NativeNetworkClient? = null
    private var timelineConnection = -1L
    private var pendingAutoStart = false
    private val main = Handler(Looper.getMainLooper())
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
            } ?: resizeBots(prefs.getInt("bots", 3).coerceIn(0, maxLocalBots))
        }
            .onFailure {
                mutableLocalBots.clear()
                resizeBots(3.coerceAtMost(maxLocalBots))
            }
        normalizeLocalTeams(resetCTF = false)
        preparePreview()
        save()
    }

    private val profileContext: String
        get() = roomCode?.takeIf { online } ?: if (online) "online" else "local"

    fun save() {
        if (!online) {
            botCount = botCount.coerceIn(0, maxLocalBots)
            savedLocalRules = rules.copy()
            savedLocalMode = mode
            savedLocalPublic = publicSelected
            modeProfiles["local:${if(rules.infinity) "infinity" else rules.mode}"] = rules.copy()
        }
        val profiles = JSONObject()
        modes.keys.forEach { key ->
            modeProfiles["local:$key"]?.let { profiles.put(key, rulesJson(it)) }
        }
        prefs
            .edit()
            .putString("callsign", Callsigns.limit(callsign.trim()))
            .putString("localCallsign", Callsigns.limit(localCallsign.trim()))
            .putInt("color", colorIndex)
            .putInt("localColor", localColorIndex)
            .putString("mode", savedLocalMode)
            .putString("rules", rulesJson(savedLocalRules).toString())
            .putString("modeProfiles", profiles.toString())
            .putBoolean("publicSelected", savedLocalPublic)
            .putBoolean("localSelected", localSelected)
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
            .putBoolean("showFPS", showFPS)
            .apply()
    }

    fun setServer(address: String) {
        val normalized = ServerAddress.origin(address)
        require(BuildConfig.DEBUG || normalized.startsWith("https://")) {
            "A secure HTTPS server is required."
        }
        if (normalized == server) return
        leave()
        server = normalized
        prefs.edit().putString("server", server).apply()
        statusRequest?.cancel()
        statusRequest = null
        statusInFlight = false
        statusEpoch++
        publicStatus = null
        refreshStatus()
        changed(true)
    }

    fun selectMode(value: String) {
        if (value !in modes) return
        modeProfiles["$profileContext:${if(rules.infinity) "infinity" else rules.mode}"] =
            rules.copy()
        rules = rules.selectingMode(value, modeProfiles["$profileContext:$value"])
        mode = value
        if (!online) normalizeLocalTeams()
        if (value != "infinity") publicSelected = false
        if (online) command("rules", "rules" to rulesJson(rules))
        save()
        changed(true)
    }

    fun changeRules(value: RoomRules) {
        rules =
            value.copy(
                teamMode =
                    if (!value.infinity && value.mode in listOf("ctf", "survival")) "teams"
                    else value.teamMode,
            )
        mode = if (rules.infinity) "infinity" else rules.mode
        if (!online) normalizeLocalTeams()
        modeProfiles["$profileContext:$mode"] = rules.copy()
        if (online) command("rules", "rules" to rulesJson(rules))
        save()
        changed(true)
    }

    fun togglePublic(enabled: Boolean) {
        publicSelected = enabled
        if (enabled) {
            modeProfiles["$profileContext:${if(rules.infinity) "infinity" else rules.mode}"] =
                rules.copy()
            rules = rules.selectingMode("infinity", modeProfiles["$profileContext:infinity"])
            mode = "infinity"
        }
        if (online) command("select_public_infinity", "enabled" to enabled)
        save()
        changed(true)
    }

    private fun resizeBots(count: Int) {
        while (mutableLocalBots.size > count) mutableLocalBots.removeAt(mutableLocalBots.lastIndex)
        while (mutableLocalBots.size < count) {
            val id = (mutableLocalBots.maxOfOrNull { it.id } ?: 1) + 1
            val used =
                (mutableLocalBots.map { it.name } + callsign + localCallsign)
                    .map { it.uppercase(java.util.Locale.ROOT) }
                    .toSet()
            val name =
                listOf("RUST", "VAPOR", "EMBER", "NOVA", "COMET", "ONYX", "BLITZ").firstOrNull {
                    it !in used
                } ?: "BOT $id"
            mutableLocalBots.add(
                LocalBot(
                    id,
                    name,
                    GamePalette.index(id - 1),
                    difficulty,
                    if (rules.teamMode == "teams") localTeam else 0,
                ),
            )
        }
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
                difficulty =
                    difficulty?.takeIf { it in BotDifficulty.names }
                        ?: old.difficulty,
                team = side,
            )
        save()
        changed(true)
    }

    private fun preparePreview() {
        fixed = null
        localID = 1
        localID2 = null
        accumulator = 0.0
        previousFrame = 0
        practice =
            PracticeArena(
                seed = previewSeed,
                name = callsign,
                colorIndex = colorIndex,
                botCount = 2,
            )
        maze = practice!!.maze
        snapshot = practice!!.snapshot
    }

    fun play() {
        save()
        neutral()
        if (online) {
            if (room?.optBoolean("infinityActive") == true) {
                if (!arenaNetwork.connected)
                    attachRoomArena(room?.optBoolean("infinityPublic") == true)
                else {
                    arenaActive = true
                    screen = Screen.PLAYING
                    paused = false
                    changed(true)
                }
            } else if (isHost) command(if (publicSelected) "start_public_infinity" else "start")
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
        if (infinity) {
            practice =
                PracticeArena(
                    seed = seed,
                    name = callsign,
                    colorIndex = colorIndex,
                    botCount = botCount,
                    difficulty = difficulty,
                )
            practice!!.configure(rules)
            practice!!.configurePilot(
                practice!!.localID,
                callsign,
                colorIndex,
                if (rules.teamMode == "teams") localTeam else 0,
            )
            localBots.forEachIndexed { index, bot ->
                practice!!.configurePilot(
                    index + 2,
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
                )
            practice = null
            maze = fixed!!.maze
            snapshot = fixed!!.snapshot
        }
        localID = practice?.localID ?: fixed!!.localID
        localID2 =
            if (localSelected)
                practice?.configureLocal(
                    localCallsign,
                    localColorIndex,
                    if (rules.teamMode == "teams") secondLocalTeam else 0,
                )
                    ?: fixed?.configureLocal(
                        localCallsign,
                        localColorIndex,
                        if (rules.teamMode == "teams") secondLocalTeam else 0,
                    )
            else null
        snapshot = practice?.snapshot ?: fixed!!.snapshot
        accumulator = 0.0
        previousFrame = 0
        paused = false
        screen = Screen.PLAYING
        changed(true)
    }

    fun share() {
        save()
        arenaNetwork.disconnect(false)
        arenaActive = false
        online = true
        infinity = rules.infinity
        screen = Screen.CONNECTING
        pendingAutoStart = false
        val roster =
            JSONArray()
                .put(
                    JSONObject()
                        .put("kind", "human")
                        .put("name", callsign)
                        .put("colorIndex", colorIndex)
                        .put("team", if (rules.teamMode == "teams") localTeam else 0),
                )
        if (localSelected)
            roster.put(
                JSONObject()
                    .put("kind", "local")
                    .put("name", localCallsign)
                    .put("colorIndex", localColorIndex)
                    .put("team", if (rules.teamMode == "teams") secondLocalTeam else 0),
            )
        localBots.forEach { bot ->
            roster.put(
                JSONObject()
                    .put("kind", "bot")
                    .put("name", bot.name)
                    .put("colorIndex", bot.colorIndex)
                    .put("difficulty", bot.difficulty)
                    .put("team", if (rules.teamMode == "teams") bot.team.coerceAtLeast(1) else 0),
            )
        }
        runCatching {
            network.connectPublishedRoom(
                server,
                callsign,
                rulesJson(rules),
                roster,
                roomName.takeIf { it.isNotBlank() },
            )
        }
            .onFailure {
                online = false
                screen = Screen.READY
                error(it.message)
            }
        changed(true)
    }

    fun join(code: String, spectator: Boolean = false) {
        save()
        arenaNetwork.disconnect(false)
        arenaActive = false
        online = true
        screen = Screen.CONNECTING
        infinity = false
        pendingAutoStart = false
        runCatching { network.connectRoom(server, callsign, code.trim(), spectator) }
            .onFailure {
                online = false
                screen = Screen.READY
                error(it.message)
            }
        changed(true)
    }

    fun findMatch() {
        if (online) command("queue_info")
        else {
            pendingAutoStart = true
            online = true
            screen = Screen.CONNECTING
            network.connectRoom(server, callsign)
        }
        changed(true)
    }

    fun leave() {
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
        timeline.reset()
        timelineOwner = null
        timelineConnection = -1
        renameNames.fill(null)
        renameRequests.fill(0)
        rules = savedLocalRules.copy()
        mode = savedLocalMode
        publicSelected = savedLocalPublic
        preparePreview()
        status = "Local play is ready. Share to invite online friends."
        changed(true)
    }

    fun lobby() {
        neutral()
        paused = false
        if (online && room != null) {
            arenaNetwork.disconnect()
            arenaActive = false
            localID = network.welcome?.id ?: localID
            localID2 = network.welcome?.localId
            command("lobby")
            screen = Screen.READY
            changed(true)
        } else if (online) leave()
        else {
            screen = Screen.READY
            preparePreview()
            changed(true)
        }
    }

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
        if (online) {
            val client = activeNetwork
            client.sendInput(
                timeline.neutralPacket(),
                paused = true,
                player = localID,
                member = client.welcome?.member,
            )
            if (localID2 != null)
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
        if (online) {
            network.resume()
            if (arenaActive) arenaNetwork.resume()
        } else if (store.activeIntent() != null) {
            val intent = store.activeIntent()!!
            online = true
            infinity = true
            arenaActive = true
            screen = Screen.CONNECTING
            server = intent.origin
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
        if (!active || statusInFlight) return
        statusInFlight = true
        val requestedServer = server
        val requestEpoch = ++statusEpoch
        statusRequest =
            accounts.publicStatus(server) { result ->
                if (requestEpoch == statusEpoch) {
                    statusInFlight = false
                    statusRequest = null
                    if (active && requestedServer == server)
                        result.onSuccess {
                            publicStatus = it
                            if (!online) latency = it.latencyMilliseconds
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
                            client.sendInput(
                                packet,
                                local = true,
                                player = localID2,
                                member = client.welcome?.localMember,
                            )
                        },
                    ) { packet ->
                        client.sendInput(packet, player = localID, member = client.welcome?.member)
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
        present(snapshot, maze, localID, localID2, online)
        if (screen == Screen.PLAYING) {
            uiElapsed += dt
            if (uiElapsed >= .1) {
                uiElapsed %= .1
                changed(false)
            }
        } else uiElapsed = 0.0
    }

    fun renameCallsign(name: String, seat: Int = 0) {
        require(seat in 0..1)
        val cleaned =
            Callsigns.limit(name.trim()).ifBlank { if (seat == 0) "Pilot" else "Co-pilot" }
        if (seat == 0) callsign = cleaned else localCallsign = cleaned
        save()
        val confirmed =
            if (!online || arenaActive)
                snapshot.tanks.firstOrNull { it.id == if (seat == 0) localID else localID2 }?.name
            else
                room?.optJSONArray("players")?.let { rows ->
                    (0 until rows.length())
                        .map { rows.getJSONObject(it) }
                        .firstOrNull {
                            it.optInt("id") ==
                                if (seat == 0) network.welcome?.id else network.welcome?.localId
                        }
                        ?.optString("name")
                }
        if (cleaned == confirmed || renameNames[seat] == cleaned) return
        if (!online) {
            val id = if (seat == 0) localID else localID2
            if (id != null) {
                val pilot = snapshot.tanks.firstOrNull { it.id == id }
                practice?.configurePilot(
                    id,
                    cleaned,
                    if (seat == 0) colorIndex else localColorIndex,
                    pilot?.team ?: 0,
                    pilot?.difficulty ?: "normal",
                )
                fixed?.configurePilot(
                    id,
                    cleaned,
                    if (seat == 0) colorIndex else localColorIndex,
                    pilot?.team ?: 0,
                    pilot?.difficulty ?: "normal",
                )
            }
        } else if (arenaActive && infinity) {
            if (seat == 1 && arenaNetwork.welcome?.localId == null) return
            renameNames[seat] = cleaned
            renameRequests[seat] = arenaNetwork.renameInfinity(cleaned, seat)
        } else if (seat == 0) {
            renameNames[seat] = cleaned
            command("rename", "name" to cleaned)
        } else {
            val identity = network.welcome ?: return
            val target = identity.localId ?: return
            val member = identity.localMember ?: return
            renameNames[seat] = cleaned
            command("rename_local", "target" to target, "member" to member, "name" to cleaned)
        }
        changed(true)
    }

    fun command(type: String, vararg fields: Pair<String, Any?>) {
        val json = JSONObject().put("type", type)
        fields.forEach { (key, value) -> json.put(key, value) }
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
            arenaNetwork.connectRoomInfinity(server, code, token, includeLocal = hasLocal)
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
                    localID2 = welcome.localId
                    welcome.seed?.let { maze = InfiniteMaze(it) }
                    if (fromArena || welcome.isPublic) {
                        screen = Screen.PLAYING
                    } else screen = Screen.READY
                    val newTransport =
                        timelineOwner !== client ||
                            timelineConnection != client.connectionGeneration
                    timeline.setLocalIDs(localID, localID2, client.lastLocalInputSequence)
                    if (newTransport) {
                        timeline.reset(client.lastInputSequence, client.lastLocalInputSequence)
                        timelineOwner = client
                        timelineConnection = client.connectionGeneration
                        previousFrame = 0
                    } else if (!fromArena && previousScreen == Screen.PLAYING)
                        screen = previousScreen
                }
                if (!fromArena && pendingAutoStart) {
                    pendingAutoStart = false
                    command("queue_info")
                }
            }
            is NetworkEvent.State ->
                if (isPlayingClient) {
                    timeline.accept(event.snapshot, System.nanoTime() / 1e9)
                    event.snapshot.world?.let { world ->
                        if (maze?.world !== world) maze = InfiniteMaze(world)
                    }
                    if (event.snapshot.phase != "lobby") screen = Screen.PLAYING
                    snapshot = event.snapshot
                }
            is NetworkEvent.Latency -> if (isPlayingClient) latency = event.milliseconds
            is NetworkEvent.InfinityStarted -> if (!fromArena) attachRoomArena(event.isPublic)
            is NetworkEvent.Reconnecting ->
                if (isPlayingClient) {
                    neutral()
                    status = "Reconnecting… (${event.attempt})"
                }
            is NetworkEvent.Disconnected ->
                if (isPlayingClient && event.message != null) status = event.message
            is NetworkEvent.Error -> {
                if (
                    event.terminal &&
                        !fromArena &&
                        arenaActive &&
                        arenaNetwork.isPublic &&
                        event.code !in setOf("account_key_revoked", "session_replaced")
                ) {
                    // Public accounts survive loss of the temporary party/room route.
                    network.disconnect(false)
                    room = null
                } else {
                    neutral()
                    paused = false
                    if (event.terminal) {
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
                room = packet
                packet.optJSONObject("rules")?.let {
                    rules = SnapshotDecoder.rules(it)
                    mode = if (rules.infinity) "infinity" else rules.mode
                }
                publicSelected = packet.optBoolean("infinityPublic")
                infinity = rules.infinity
                if (packet.optString("phase") == "lobby" && !packet.optBoolean("infinityActive")) {
                    if (arenaActive) {
                        arenaNetwork.disconnect()
                        arenaActive = false
                        localID = network.welcome?.id ?: localID
                        localID2 = network.welcome?.localId
                    }
                    screen = Screen.READY
                }
            }
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
            "chat",
            "chat_history" -> {
                if (packet.optString("type") == "chat_history") chat.clear()
                val rows =
                    packet.optJSONArray("messages")
                        ?: JSONArray().apply { packet.optJSONObject("message")?.let(::put) }
                repeat(rows.length()) {
                    val m = rows.getJSONObject(it)
                    chat.add("${m.optString("name")}: ${m.optString("text")}")
                }
                while (chat.size > 80) chat.removeAt(0)
                if (packet.optString("type") == "chat") notifyChat()
            }
            "queue_catalog",
            "queue_status",
            "queue_cancelled" -> queuePacket = packet
            "kicked",
            "room_offline" ->
                if (!arenaActive || !arenaNetwork.isPublic) {
                    leave()
                    error(packet.optString("message", "The room is no longer available."))
                }
            "leaderboard_reset" -> status = "Leaderboard reset. Everyone starts at 0."
        }
    }

    companion object {
        val modes =
            linkedMapOf(
                "infinity" to "Infinity",
                "elimination" to "Elimination",
                "ctf" to "Capture the flag",
                "koth" to "King of the hill",
                "survival" to "Survival",
            )

        fun rulesJson(r: RoomRules) =
            JSONObject()
                .put("mode", r.mode)
                .put("infinity", r.infinity)
                .put("infinityTarget", r.infinityTarget)
                .put("infinityRandomBots", r.infinityRandomBots)
                .put("infinityBotDifficulty", r.infinityBotDifficulty)
                .put("infinityRandomDifficulty", r.infinityRandomDifficulty)
                .put("teamMode", r.teamMode)
                .put("mapSize", r.mapSize)
                .put("portraitMaze", r.portraitMaze)
                .put("scoreTarget", r.scoreTarget)
                .put("timeLimit", r.timeLimit)
                .put("respawnSeconds", r.respawnSeconds)
                .put("pickupRate", r.pickupRate)
                .put("weapons", JSONArray(r.weapons))
                .put("friendlyFire", r.friendlyFire)
                .put("teamNames", JSONArray(r.teamNames))
                .put("teamColors", JSONArray(r.teamColors))
    }
}
