package com.leqra.android

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.Configuration
import android.hardware.input.InputManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.*
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.*
import com.leqra.android.NativeStyle.accent
import com.leqra.android.NativeStyle.add
import com.leqra.android.NativeStyle.background
import com.leqra.android.NativeStyle.button
import com.leqra.android.NativeStyle.column
import com.leqra.android.NativeStyle.danger
import com.leqra.android.NativeStyle.dp
import com.leqra.android.NativeStyle.field
import com.leqra.android.NativeStyle.label
import com.leqra.android.NativeStyle.muted
import com.leqra.android.NativeStyle.page
import com.leqra.android.NativeStyle.paint
import com.leqra.android.NativeStyle.panelBackground
import com.leqra.android.NativeStyle.raised
import com.leqra.android.NativeStyle.row
import com.leqra.android.NativeStyle.soft
import com.leqra.android.NativeStyle.sunken
import com.leqra.android.NativeStyle.surface
import com.leqra.android.NativeStyle.text
import com.leqra.android.NativeStyle.weighted
import com.leqra.android.accounts.*
import com.leqra.android.audio.AudioCue
import com.leqra.android.audio.NativeAudio
import com.leqra.android.render.NativeArenaView
import com.leqra.core.*
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt
import org.json.JSONObject

/** Bounds shared by the native rule widgets and draft validation, matching the iOS editor. */
internal object RuleEditorLimits {
    fun scoreMaximum(rules: RoomRules) = if (rules.mode == "koth") 300 else 20

    fun snapped(value: Int, minimum: Int, maximum: Int, step: Int = 1): Int {
        val bounded = value.coerceIn(minimum, maximum)
        return (minimum + ((bounded - minimum + step / 2) / step) * step).coerceIn(minimum, maximum)
    }

    fun draft(source: RoomRules): RoomRules =
        source.copy().apply {
            if (infinity) infinityTarget = infinityTarget.coerceIn(0, 999)
            else {
                scoreTarget = scoreTarget.coerceIn(1, scoreMaximum(this))
                timeLimit = snapped(timeLimit, 30, 600, 15)
                respawnSeconds = respawnSeconds.coerceIn(1, 10)
                if (mode == "ctf" || mode == "survival") teamMode = "teams"
            }
            if (infinityBotDifficulty !in BotDifficulty.names) infinityBotDifficulty = "normal"
            if (infinityBotSpawnRate !in listOf(.5, 1.0, 2.0, 4.0)) infinityBotSpawnRate = 2.0
            infinityBotSpawnRates = roamingBotSpawnRates()
        }
}

/** Native Android UI. The arena uses Canvas, PCM audio and Kotlin physics, with no web runtime. */
class MainActivity : Activity() {
    private lateinit var session: GameSession
    private lateinit var audio: NativeAudio
    private lateinit var arena: NativeArenaView
    private lateinit var root: LinearLayout
    private lateinit var stage: FrameLayout
    private lateinit var header: NativeGameHeader
    private lateinit var statusLine: NativeStatusView
    private lateinit var objectiveLine: NativeObjectiveView
    private lateinit var roundAnnouncement: NativeRoundAnnouncement
    private lateinit var loadout: NativeHudView
    private var readyScroll: ScrollView? = null
    private var connecting: LinearLayout? = null
    private var connectingStatus: TextView? = null
    private var scores: ScrollView? = null
    private var scorePanel: View? = null
    private var dialog: AlertDialog? = null
    private var keyCaptureDialog: AlertDialog? = null
    private var quickTourDialog: QuickTour? = null
    private var showcaseDialog: Dialog? = null
    private var showcaseReturnOnResume = false
    private var pendingRoomInvite: RoomJoinRequest? = null
    private var readySignature = ""
    private var settingsOpen = false
    private var settingsVersionLabel: TextView? = null
    private var playersOpen = false
    private var showScores = false
    private var foreground = false
    private var fullscreen = false
    private var feedback = arrayOfNulls<TextView>(2)
    private var availability: CancelRequest? = null
    private var availabilityEpoch = 0L
    private val main = Handler(Looper.getMainLooper())
    private var safeLeft = 0
    private var safeRight = 0
    private var safeBottom = 0
    private val combinedHeader: Boolean
        get() = resources.configuration.smallestScreenWidthDp >= 600

    private val pressed = mutableSetOf<Int>()
    private var controlOwner: Int? = null
    private var controlLocalOwner: Int? = null
    private var updateControlsHardware: (() -> Unit)? = null

    private val gamepads = GamepadControls()
    private var gamepadIDs = emptyList<Int>()
    private val controllerDevices =
        object : InputManager.InputDeviceListener {
            override fun onInputDeviceAdded(deviceId: Int) = refreshGamepads()

            override fun onInputDeviceRemoved(deviceId: Int) = refreshGamepads(deviceId)

            override fun onInputDeviceChanged(deviceId: Int) = refreshGamepads(deviceId)
        }

    private fun refreshGamepads(changed: Int? = null) {
        val wasGamepad = changed != null && changed in gamepadIDs
        gamepadIDs =
            InputDevice.getDeviceIds()
                .filter { InputDevice.getDevice(it)?.isGamepad() == true }
                .sorted()
        gamepads.updateDevices(gamepadIDs, controlOwner != null, controlLocalOwner != null, changed)
        quickTourDialog?.updateGamepads(gamepadIDs, changed)
        if (::session.isInitialized && ::arena.isInitialized) {
            // Keyboard and mouse disconnects may never deliver a final release.
            if (changed != null && !wasGamepad && changed !in gamepadIDs) {
                pressed.clear()
                arena.clearMouseControls()
            }
            keyboardInput()
        }
        updateControlsHardware?.invoke()
    }

    private var frameCount = 0
    private var fpsStarted = 0L
    private var fps = 0
    private var queueDialog = false
    private var lastResultKey: String? = null
    private var scoreSignature = ""
    private var loadoutLayoutKey = ""
    private var refreshRateKey = ""
    private var previousPlaying = false
    private var focusSuspendedPlay = false
    private var keepAwake: Boolean? = null
    private var soundState: Boolean? = null
    private var readyPlay: Button? = null
    private val readyOnlineActions = mutableListOf<Button>()
    private val inviteButtons = arrayOfNulls<Button>(2)
    private val copiedInvites = arrayOfNulls<Pair<android.net.Uri, Long>>(2)
    private var readyStatus: TextView? = null
    private var readyStartError: TextView? = null
    private val callsignFields = arrayOfNulls<EditText>(2)
    internal var scorePanelBuilds = 0L
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.enableImmersiveEdgeToEdge(immersive = fullscreen)
        try {
            session = GameSession(applicationContext)
        } catch (_: Exception) {
            val recovery = column(this, 24)
            recovery.setBackgroundColor(page)
            recovery.add(label(this, "ACCOUNT STORAGE UNAVAILABLE", 24f, danger, true))
            recovery.add(
                label(
                    this,
                    "Saved account keys could not be read. They have been preserved. Restart the app to retry. Keep any copied keys safe; clearing app storage or uninstalling removes keys stored only on this device.",
                    14f,
                    soft,
                ),
            )
            recovery.add(button(this, "RETRY", { recreate() }))
            recovery.setOnApplyWindowInsetsListener { _, insets ->
                val safe = insets.immersiveInsets()
                recovery.setPadding(
                    dp(24) + safe.left,
                    dp(24) + safe.top,
                    dp(24) + safe.right,
                    dp(24) + safe.bottom,
                )
                insets
            }
            setContentView(recovery)
            return
        }
        if (BuildConfig.DEBUG)
            intent.getStringExtra("server")?.let { runCatching { session.setServer(it) } }
        audio = NativeAudio(applicationContext)
        audio.enabled = !session.muted
        audio.volume = session.volume
        session.changed = ::refresh
        session.notifyError = { message ->
            if (!openPendingRoomInvite()) {
                dialog?.dismiss()
                dialog = null
                queueDialog = false
                alert("leqra", message)
            }
        }
        session.emitAudioCue = { audio.play(it) }
        gamepads.enabled = session.gamepadSupport
        buildShell()
        getSystemService(InputManager::class.java)
            .registerInputDeviceListener(controllerDevices, main)
        refreshGamepads()
        if (Build.VERSION.SDK_INT >= 33)
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) {
                handleBack()
            }
        pendingRoomInvite = intent.data?.let { RoomJoinRequest.fromInvite(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingRoomInvite = intent.data?.let { RoomJoinRequest.fromInvite(it) }
    }

    private fun openPendingRoomInvite(): Boolean {
        val request = pendingRoomInvite ?: return false
        if (!foreground || session.network.hasRoomReservation(request.code)) return false
        pendingRoomInvite = null
        quickTourDialog?.dismiss()
        showcaseDialog?.dismiss()
        showJoin(RoomJoinDraft(request.code, request.spectate))
        return true
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            if (focusSuspendedPlay) {
                focusSuspendedPlay = false
                if (
                    ::session.isInitialized &&
                        session.screen == Screen.PLAYING &&
                        session.paused &&
                        dialog == null
                )
                    session.pause(false)
            }
            window.setImmersiveSystemBars(fullscreen)
        } else if (::session.isInitialized) {
            clearHeldControls()
            if (session.screen == Screen.PLAYING && !session.paused) {
                focusSuspendedPlay = true
                session.pause(true)
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        quickTourDialog?.resize()
        readySignature = ""
        scoreSignature = ""
        refreshRateKey = ""
        loadoutLayoutKey = ""
        if (::root.isInitialized) root.requestApplyInsets()
        refresh(true)
    }

    override fun onResume() {
        super.onResume()
        if (showcaseReturnOnResume) showcaseDialog?.dismiss()
        foreground = true
        if (::arena.isInitialized) {
            session.foreground()
            if (quickTourDialog == null) arena.start()
            refresh(true)
            openPendingRoomInvite()
            if (
                session.screen == Screen.READY &&
                    !session.online &&
                    dialog == null &&
                    intent.data?.let { RoomJoinRequest.fromInvite(it) } == null &&
                    !getSharedPreferences("leqra-settings", MODE_PRIVATE)
                        .getBoolean(QUICK_TOUR_SEEN, false)
            )
                showQuickTour()
            quickTourDialog?.resumePractice()
        }
    }

    override fun onPause() {
        if (showcaseDialog != null) showcaseReturnOnResume = true
        foreground = false
        quickTourDialog?.pausePractice()
        availability?.cancel()
        if (::arena.isInitialized) {
            pressed.clear()
            gamepads.clear()
            session.background()
            arena.pause()
            audio.pause()
        }
        super.onPause()
    }

    override fun onDestroy() {
        keyCaptureDialog?.dismiss()
        quickTourDialog?.dismiss()
        showcaseDialog?.dismiss()
        getSystemService(InputManager::class.java).unregisterInputDeviceListener(controllerDevices)
        main.removeCallbacksAndMessages(null)
        availability?.cancel()
        dialog?.dismiss()
        if (::arena.isInitialized) arena.release()
        if (::audio.isInitialized) audio.release()
        if (::session.isInitialized) session.release()
        super.onDestroy()
    }

    private fun buildShell() {
        root = column(this).apply { setBackgroundColor(page) }
        setContentView(root)
        header =
            NativeGameHeader(
                this,
                openVersion = {
                    startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            android.net.Uri.parse("https://github.com/nhooyr/leqra"),
                        ),
                    )
                },
                toggleSound = { toggleSound() },
                openMenu = { if (session.screen == Screen.PLAYING) showMenu() else showControls() },
                toggleFullscreen = {
                    fullscreen = !fullscreen
                    applyFullscreen()
                },
                openRoom = { if (session.screen == Screen.PLAYING) showMenu() },
                openSidebar = { showSidebar() },
            )
        root.add(header, gap = 0)
        statusLine =
            NativeStatusView(
                this,
                openScores = {
                    showScores = !showScores
                    updateScores()
                },
            )
        root.add(statusLine, gap = 0)
        objectiveLine = NativeObjectiveView(this)
        root.add(objectiveLine, gap = 0)
        stage = FrameLayout(this).apply { setBackgroundColor(sunken) }
        root.addView(stage, LinearLayout.LayoutParams(-1, 0, 1f))
        arena = NativeArenaView(this).apply { keyboardInputEnabled = false }
        arena.contentDescription = "Tank arena, joystick on the left and fire on the right"
        stage.addView(arena, FrameLayout.LayoutParams(-1, -1))
        roundAnnouncement = NativeRoundAnnouncement(this)
        stage.addView(roundAnnouncement, FrameLayout.LayoutParams(-1, -1))
        arena.onFrame = { nanos ->
            if (session.screen == Screen.PLAYING && !session.paused && arena.hasMouseInput)
                keyboardInput()
            session.frame(nanos)
            if (::loadout.isInitialized && session.screen == Screen.PLAYING) {
                arena.fireProgress = loadout.advance(nanos)
            }
            if (fpsStarted == 0L) fpsStarted = nanos
            frameCount++
            if (nanos - fpsStarted >= 1_000_000_000) {
                fps = (frameCount * 1e9 / (nanos - fpsStarted)).toInt()
                frameCount = 0
                fpsStarted = nanos
            }
        }
        arena.onInput = { keyboardInput() }
        arena.onControlsReset = { session.cancelFireFeedback() }
        session.fireFeedbackAllowed = { dialog == null && currentFocus !is EditText }
        session.present = { snapshot, maze, localID, localID2, online ->
            arena.previewRecoil = session.previewRecoil
            arena.localPreviewRecoil = session.localPreviewRecoil
            arena.encounterNotice = session.encounterNotice
            arena.followingID = session.followingID.takeIf { session.spectating }
            arena.submit(snapshot, localID, maze, localID2, online)
            roundAnnouncement.update(session, snapshot)
            if (session.audioSceneActive)
                audio.consume(
                    snapshot,
                    if (session.spectating) -1 else localID,
                    session.infinity,
                    online,
                )
            audio.updateStarman(
                snapshot,
                localID,
                localID2,
                session.audioGameplayActive,
                session.audioSceneActive,
            )
        }
        loadout = NativeHudView(this)
        root.addView(
            loadout,
            root.indexOfChild(stage),
            LinearLayout.LayoutParams(-1, -2),
        )
        root.setOnApplyWindowInsetsListener { _, insets ->
            val safe = insets.immersiveInsets()
            root.setPadding(0, safe.top, 0, safe.keyboard)
            val sidesChanged = safeLeft != safe.left || safeRight != safe.right
            if (sidesChanged || safeBottom != safe.contentBottom) {
                safeLeft = safe.left
                safeRight = safe.right
                safeBottom = safe.contentBottom
                configureStatusLayout()
                configureLoadoutLayout()
            }
            if (sidesChanged) {
                header.setPadding(dp(12) + safeLeft, dp(5), dp(8) + safeRight, dp(5))
                objectiveLine.setPadding(dp(12) + safeLeft, dp(5), dp(12) + safeRight, dp(5))
                readySignature = ""
                scoreSignature = ""
                if (foreground) main.post { refresh(true) }
            }
            insets
        }
        refresh(true)
    }

    private fun refresh(structural: Boolean) {
        if (!::root.isInitialized) return
        settingsVersionLabel?.let {
            val version = session.settingsVersionText
            if (it.text.toString() != version) it.text = version
        }
        if (
            session.network.connected &&
                pendingRoomInvite?.let { session.network.hasRoomReservation(it.code) } == true
        )
            pendingRoomInvite = null
        syncControlSeats()
        if (soundState != session.muted) {
            soundState = session.muted
            audio.enabled = !session.muted
        }
        audio.volume = session.volume
        audio.updateStarman(
            session.snapshot,
            session.localID,
            session.localID2,
            session.audioGameplayActive,
            session.audioSceneActive,
        )
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val playing = session.screen == Screen.PLAYING
        if (playing && queueDialog) {
            queueDialog = false
            dialog?.setOnDismissListener(null)
            dialog?.dismiss()
            dialog = null
        }
        val availableWidthDp =
            resources.configuration.screenWidthDp -
                (safeLeft + safeRight) / resources.displayMetrics.density
        val loading = session.screen == Screen.CONNECTING
        statusLine.visibility = if (loading) View.GONE else View.VISIBLE
        configureStatusLayout()
        header.display(
            landscape,
            availableWidthDp,
            session.muted,
            playing,
            fullscreen,
            session.roomCode,
            showSidebar = !loading,
        )
        if (loading || (!playing && previousPlaying)) showScores = false
        val awake = playing && !session.paused
        arena.controlsLayout = playing && !session.spectating
        arena.showControls = awake && dialog == null && !session.spectating
        arena.mouseInputEnabled = awake && dialog == null && session.hasLocalPlayer
        arena.mouseAimEnabled = session.mouseAim
        arena.mouseFireEnabled = session.mouseFire
        arena.keepScreenOn = awake
        if (keepAwake != awake) {
            keepAwake = awake
            if (awake) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        configureLoadoutLayout()
        loadout.visibility = if (playing && session.hasLocalPlayer) View.VISIBLE else View.GONE
        arena.visibility = if (loading) View.INVISIBLE else View.VISIBLE
        if (!loading) statusLine.update(session, fps)
        objectiveLine.update(session.snapshot.objectives.takeIf { playing }, session.rules)
        if (playing) {
            val entering = !previousPlaying
            if (entering && !session.hasLocalPlayer) showScores = true
            if (readyScroll != null || connecting != null) hideKeyboard()
            readyScroll?.let(stage::removeView)
            readyScroll = null
            readySignature = ""
            connecting?.let(stage::removeView)
            connecting = null
            connectingStatus = null
            if (entering && dialog == null) arena.requestFocus()
            val state =
                session.authoritativeSnapshot.copy(
                    phase = session.snapshot.phase,
                    result = session.snapshot.result,
                )
            loadout.update(
                state,
                session.localID,
                session.localID2,
                session.infinity,
                session.paused,
                session.online,
            )
            arena.fireLabel = loadout.fireLabel
            arena.fireAvailable = loadout.fireAvailable
            val ended = session.snapshot.phase == "matchOver" || session.snapshot.result != null
            if (!ended) lastResultKey = null
            else {
                val resultKey =
                    "${session.snapshot.generation}:${session.snapshot.round}:${session.snapshot.winner}:${session.snapshot.result}:${session.snapshot.scores}"
                if (
                    session.hasLocalPlayer &&
                        dialog == null &&
                        lastResultKey != resultKey &&
                        !session.finishingProjectilePresentation
                ) {
                    lastResultKey = resultKey
                    showResult()
                }
            }
        } else if (loading) {
            readyScroll?.let(stage::removeView)
            readyScroll = null
            readySignature = ""
            if (connecting == null) {
                connecting =
                    column(this, 24).apply {
                        gravity = Gravity.CENTER
                        add(label(this@MainActivity, "CONNECTING.", 28f, accent, true))
                        add(ProgressBar(this@MainActivity), 32, 32)
                        connectingStatus =
                            label(this@MainActivity, session.status, 12f, soft).apply {
                                gravity = Gravity.CENTER
                            }
                        add(connectingStatus!!)
                        add(button(this@MainActivity, "← BACK TO THE ROOM", { session.leave() }))
                    }
                stage.addView(
                    connecting,
                    FrameLayout.LayoutParams(
                        minOf(
                            stage.width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels,
                            dp(420),
                        ),
                        -1,
                        Gravity.CENTER,
                    ),
                )
            }
            connectingStatus?.value(session.status)
        } else {
            connecting?.let(stage::removeView)
            connecting = null
            connectingStatus = null
            if (structural || readyScroll == null) {
                val signature =
                    "${session.server}|${resources.configuration.orientation}|${session.online}|${session.room}|${session.mode}|${session.rules}|" +
                        "${session.publicSelected}|$settingsOpen|$playersOpen|${session.localSelected}|${session.localBots}|${session.localTeam}:${session.secondLocalTeam}"
                if (signature != readySignature || readyScroll == null) {
                    readySignature = signature
                    buildReadyRoom()
                }
            }
        }
        if (!playing) updateReadyActions()
        previousPlaying = playing
        if (showScores || scorePanel != null) updateScores()
        if (queueDialog) updateQueueDialog()
        applyRefreshRate()
    }

    private fun configureStatusLayout() {
        header.placeStatus(statusLine, combinedHeader)
        statusLine.setPadding(
            if (combinedHeader) dp(4) else dp(12) + safeLeft,
            dp(6),
            if (combinedHeader) dp(4) else dp(12) + safeRight,
            dp(6),
        )
        readyScroll?.apply {
            setPadding(paddingLeft, paddingTop, paddingRight, dp(16))
        }
    }

    private fun configureLoadoutLayout() {
        if (!::loadout.isInitialized) return
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val paired = session.localID2 != null
        val key = "${session.screen}:$landscape:$paired:$safeLeft:$safeRight:$safeBottom"
        if (key == loadoutLayoutKey) return
        loadoutLayoutKey = key
        val ready = session.screen == Screen.READY
        val inset = if (ready) dp(9) else 0
        stage.layoutParams =
            (stage.layoutParams as LinearLayout.LayoutParams).apply {
                setMargins(
                    inset + if (ready) safeLeft else 0,
                    inset,
                    inset + if (ready) safeRight else 0,
                    inset + if (ready) safeBottom else 0,
                )
            }
        val rounded = session.screen != Screen.CONNECTING
        stage.background =
            if (rounded) background(this, sunken, 9, NativeStyle.edge)
            else android.graphics.drawable.ColorDrawable(sunken)
        stage.foreground =
            if (rounded) background(this, android.graphics.Color.TRANSPARENT, 9, NativeStyle.edge)
            else null
        stage.clipToOutline = rounded
        loadout.compact = landscape || paired
        loadout.inline = combinedHeader
        loadout.stacked = paired && !landscape
        loadout.safeLeft = safeLeft
        loadout.safeRight = safeRight
        loadout.safeBottom = 0
        if (ready) arena.safeInsets(0, 0, 0, 0)
        else arena.safeInsets(safeLeft, 0, safeRight, safeBottom)
        roundAnnouncement.setSafeArea(safeLeft, safeRight, safeBottom)
        loadout.requestLayout()
        loadout.invalidate()
    }

    private fun clearHeldControls(resetPrediction: Boolean = true) {
        pressed.clear()
        gamepads.clear()
        if (::arena.isInitialized) arena.resetControls()
        if (resetPrediction) session.neutral()
        else {
            session.input = GameInput()
            session.input2 = GameInput()
            session.cancelFireFeedback()
        }
    }

    private fun syncControlSeats() {
        val owner =
            session.localID.takeIf { session.screen == Screen.PLAYING && !session.spectating }
        val local =
            session.localID2.takeIf {
                session.screen == Screen.PLAYING && session.canControlSecondary
            }
        if (owner != controlOwner || local != controlLocalOwner) {
            val samePrimary = owner != null && owner == controlOwner
            controlOwner = owner
            controlLocalOwner = local
            clearHeldControls(resetPrediction = !samePrimary)
        }
    }

    private fun TextView.value(value: CharSequence) {
        if (!android.text.TextUtils.equals(text, value)) text = value
    }

    private fun applyRefreshRate() {
        val attachedDisplay =
            if (Build.VERSION.SDK_INT >= 30) display
            else @Suppress("DEPRECATION") windowManager.defaultDisplay
        val key =
            "${attachedDisplay?.displayId}:${session.screen}:${session.paused}:${session.highRefresh}:${resources.configuration.orientation}"
        if (key == refreshRateKey) return
        refreshRateKey = key
        if (attachedDisplay == null) return
        window.applyArenaRefreshRate(
            arena,
            attachedDisplay,
            session.screen == Screen.PLAYING && !session.paused,
            session.highRefresh,
        )
    }

    private fun buildReadyRoom() {
        readyOnlineActions.clear()
        inviteButtons.fill(null)
        val editing = (currentFocus as? EditText)?.takeIf { it.tag is Int }
        val editingSeat = editing?.tag as? Int
        val selectionStart = editing?.selectionStart ?: 0
        val selectionEnd = editing?.selectionEnd ?: 0
        val scrollY = readyScroll?.scrollY ?: 0
        readyScroll?.let(stage::removeView)
        feedback.fill(null)
        callsignFields.fill(null)
        readyScroll =
            ScrollView(this).apply {
                isFillViewport = true
                clipToPadding = false
                setPadding(dp(12), dp(12), dp(12), dp(16))
            }
        val holder = column(this).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL }
        val panel = column(this, 16).apply { background = panelBackground(this@MainActivity) }
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val available = resources.displayMetrics.widthPixels - safeLeft - safeRight - dp(42)
        holder.addView(
            panel,
            LinearLayout.LayoutParams(minOf(available, dp(if (landscape) 650 else 420)), -2),
        )
        panel.add(
            label(
                this,
                if (session.online) "ONLINE ROOM" else "LOCAL ROOM",
                10f,
                muted,
                mono = true,
            ),
        )
        if (session.isHost) {
            val public =
                NativeStyle.toggle(this).apply {
                    contentDescription = "Public Infinity"
                    isChecked = session.publicSelected
                    setOnCheckedChangeListener { _, checked ->
                        if (checked != session.publicSelected) session.togglePublic(checked)
                    }
                }
            val publicRow = row(this)
            publicRow.add(public, 44, 44, gap = 0)
            publicRow.weighted(
                label(this, "Public Infinity", 13f, text, true).apply {
                    minHeight = dp(44)
                    gravity = Gravity.CENTER_VERTICAL
                    setPaddingRelative(dp(8), 0, 0, 0)
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                    isClickable = true
                    setOnClickListener { public.isChecked = !public.isChecked }
                },
                gap = 0,
            )
            panel.add(publicRow)
        }
        readyPlay =
            button(
                this,
                "PLAY",
                {
                    hideKeyboard()
                    session.play()
                },
                play = true,
            )
        panel.add(readyPlay!!)
        panel.add(
            label(
                    this,
                    if (session.publicSelected) "PUBLIC INFINITY, ENDLESS"
                    else if (session.rules.infinity) "ENDLESS TANK ARENA, START WHEN READY"
                    else "BOT SKIRMISH, START WHEN READY",
                    10f,
                    muted,
                    mono = true,
                )
                .apply { gravity = Gravity.CENTER },
        )
        panel.add(
            button(
                    this,
                    "FIND ONLINE BATTLE",
                    {
                        session.findMatch()
                        showQueues()
                    },
                )
                .also { readyOnlineActions += it },
        )
        if (session.room == null) {
            panel.add(
                button(this, "SHARE ROOM ONLINE ↗", { session.share() }, role = "share").also {
                    readyOnlineActions += it
                },
            )
        } else {
            panel.add(inviteButton(spectator = false).also { readyOnlineActions += it })
            if (!session.publicSelected)
                panel.add(inviteButton(spectator = true).also { readyOnlineActions += it })
        }
        panel.add(
            button(this, "Join another room ↗", { showJoin() }, role = "text").also {
                readyOnlineActions += it
            },
        )
        if (session.online) {
            panel.add(button(this, "LEAVE ROOM", { session.leave() }, danger = true))
            panel.add(
                label(this, "ROOM: ${session.roomCode ?: "…"}", 12f, accent, true, mono = true)
                    .apply { setTextIsSelectable(true) },
            )
        }
        readyStatus = label(this, session.status, 11f, soft)
        panel.add(readyStatus!!)
        val startError =
            session.room?.optString(
                if (session.publicSelected) "startPublicInfinityError" else "startError",
            ) ?: session.localStartError
        // All room modes keep the same readiness space, including a valid solo Infinity room.
        readyStartError =
            label(this, (startError ?: session.configurationError).orEmpty(), 11f, danger).apply {
                minLines = 2
                visibility =
                    if ((startError ?: session.configurationError).isNullOrBlank()) View.INVISIBLE
                    else View.VISIBLE
            }
        panel.add(readyStartError!!)
        val configurationStart = panel.childCount
        panel.add(
            label(
                this,
                session.identity + "  callsign",
                11f,
                paint(session.colorIndex),
                true,
                mono = true,
            ),
        )
        callsignRow(panel, 0)
        val localRoomPilot = session.roomLocalPilot
        if (localRoomPilot != null && session.roomSetupOpen) {
            panel.add(
                label(
                    this,
                    "${localRoomPilot.optString("name")} (P2)  callsign",
                    11f,
                    localRoomPilot
                        .optString("color")
                        .takeIf(String::isNotBlank)
                        ?.let(NativeStyle::mappedPaint) ?: paint(session.localColorIndex),
                    true,
                    mono = true,
                ),
            )
            callsignRow(panel, 1)
        }
        panel.add(
            NativeStyle.disclosure(this, "Room settings", expanded = settingsOpen) {
                settingsOpen = !settingsOpen
                refresh(true)
            },
        )
        if (settingsOpen) roomSettings(panel)
        val rosterCount =
            session.room?.optJSONArray("players")?.length()
                ?: session.localBots.size + (if (session.localSelected) 2 else 1)
        val rosterLimit =
            session.room?.optInt("maxPlayers", if (session.mode == "survival") 4 else 8)
                ?: if (session.mode == "survival") 4 else 8
        panel.add(
            NativeStyle.disclosure(
                this,
                "Players and bots",
                "$rosterCount / $rosterLimit",
                playersOpen,
            ) {
                playersOpen = !playersOpen
                refresh(true)
            },
        )
        if (playersOpen) playerSettings(panel)
        panel.add(button(this, "CONTROLS", { showControls() }))
        if (session.online) {
            panel.add(
                button(
                        this,
                        "FIND A MATCH",
                        {
                            session.findMatch()
                            showQueues()
                        },
                    )
                    .also { readyOnlineActions += it },
            )
        }
        if (landscape) {
            val children = List(panel.childCount) { panel.getChildAt(it) }
            panel.removeAllViews()
            val intro = column(this)
            val configuration = column(this)
            children.forEachIndexed { index, child ->
                (if (index < configurationStart) intro else configuration).addView(child)
            }
            val columns = row(this).apply { gravity = Gravity.TOP }
            columns.weighted(intro, gap = 20)
            columns.weighted(configuration, gap = 0)
            panel.add(columns, gap = 0)
        }
        readyScroll!!.addView(holder)
        stage.addView(readyScroll, FrameLayout.LayoutParams(-1, -1))
        readyScroll!!.post { readyScroll?.scrollTo(0, scrollY) }
        if (editingSeat != null)
            callsignFields.getOrNull(editingSeat)?.let { restored ->
                restored.requestFocus()
                restored.setSelection(
                    selectionStart.coerceIn(0, restored.length()),
                    selectionEnd.coerceIn(0, restored.length()),
                )
            }
        updateReadyActions()
        checkAvailability()
    }

    private fun inviteButton(spectator: Boolean): Button {
        val seat = if (spectator) 1 else 0
        val url =
            android.net.Uri.parse(session.server)
                .buildUpon()
                .appendQueryParameter("room", session.roomCode.orEmpty())
                .apply { if (spectator) appendQueryParameter("spectate", "1") }
                .build()
        val link = if (spectator) "SPECTATOR LINK" else "INVITE LINK"
        val normal = "COPY $link ↗"
        val copied = "$link COPIED ✓"
        val recent =
            copiedInvites[seat]?.let {
                it.first == url && it.second > android.os.SystemClock.uptimeMillis()
            } == true
        return button(
                this,
                if (recent) copied else normal,
                {
                    getSystemService(ClipboardManager::class.java)
                        .setPrimaryClip(ClipData.newRawUri(link, url))
                    val expiration = url to (android.os.SystemClock.uptimeMillis() + 2_000)
                    copiedInvites[seat] = expiration
                    inviteButtons[seat]?.value(copied)
                    main.postAtTime(
                        {
                            if (copiedInvites[seat] === expiration) {
                                copiedInvites[seat] = null
                                inviteButtons[seat]?.value(normal)
                            }
                        },
                        expiration.second,
                    )
                },
            )
            .also { inviteButtons[seat] = it }
    }

    private fun updateReadyActions() {
        val room = session.room
        val localID = session.network.welcome?.id ?: session.localID
        val players = room?.optJSONArray("players")
        val own = players?.let { rows ->
            (0 until rows.length())
                .map { rows.getJSONObject(it) }
                .firstOrNull { it.optInt("id") == localID }
        }
        val active = room?.optBoolean("infinityActive") == true
        val guestWaiting = session.online && !session.isHost
        val showArrow = active || !guestWaiting
        val label =
            if (active) if (session.roomSpectating) "WATCH INFINITY" else "REJOIN INFINITY"
            else if (guestWaiting)
                if (session.roomSpectating) "WAITING FOR HOST"
                else if (own?.optBoolean("ready") == true) "READY ✓" else "READY"
            else "PLAY"
        readyPlay?.value(label)
        val allowed =
            if (room == null) session.localStartError == null
            else if (active)
                own != null || session.roomSpectating && !room.optBoolean("infinityPublic")
            else if (session.roomSpectating) false
            else
                !session.isHost ||
                    room.optBoolean("canStart") ||
                    session.publicSelected && room.optBoolean("canStartPublicInfinity")
        readyPlay?.apply {
            if (showArrow != (compoundDrawablesRelative[2] != null)) {
                setCompoundDrawablesRelativeWithIntrinsicBounds(
                    0,
                    0,
                    if (showArrow) R.drawable.ic_play_arrow else 0,
                    0,
                )
                setPaddingRelative(dp(if (showArrow) 26 else 10), dp(8), dp(10), dp(8))
            }
            isEnabled = allowed && !session.releasingCallsign
            alpha = if (isEnabled) 1f else .45f
        }
        readyOnlineActions.forEach {
            it.isEnabled = !session.releasingCallsign
            it.alpha = if (it.isEnabled) 1f else .45f
        }
        callsignFields.forEach { it?.isEnabled = !session.releasingCallsign }
        readyStatus?.value(session.status)
        val startError =
            session.room?.optString(
                if (session.publicSelected) "startPublicInfinityError" else "startError",
            ) ?: session.localStartError
        val notice = startError ?: session.configurationError
        readyStartError?.value(notice.orEmpty())
        readyStartError?.visibility = if (notice.isNullOrBlank()) View.INVISIBLE else View.VISIBLE
    }

    private fun callsignRow(panel: LinearLayout, seat: Int) {
        val row = row(this)
        val field =
            field(this, if (seat == 0) session.callsign else session.localCallsign, "Callsign")
                .apply {
                    contentDescription = if (seat == 0) "P1 callsign" else "P2 callsign"
                    tag = seat
                    callsignFields[seat] = this
                    setTextColor(
                        paint(if (seat == 0) session.colorIndex else session.localColorIndex),
                    )
                }
        field.addTextChangedListener(
            watcher { value ->
                if (seat == 0) session.callsign = value else session.localCallsign = value
                session.save()
                checkAvailability()
            },
        )
        field.setOnFocusChangeListener { _, focused ->
            val current = if (seat == 0) session.callsign else session.localCallsign
            if (!focused && current == field.text.toString())
                session.renameCallsign(field.text.toString(), seat)
        }
        row.weighted(field)
        row.add(
            button(this, "Account", { showAccount(seat) }).apply {
                textSize = 10f
                contentDescription = "${if(seat==0) "P1" else "P2"} account key"
            },
            76,
            gap = 0,
        )
        panel.add(row, gap = 0)
        feedback[seat] =
            label(this, "", 10f, danger).apply {
                minHeight = dp(46)
                movementMethod = android.text.method.LinkMovementMethod.getInstance()
                highlightColor = android.graphics.Color.TRANSPARENT
                gravity = Gravity.TOP
                setPadding(0, dp(4), 0, 0)
            }
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val available =
            (resources.displayMetrics.widthPixels - safeLeft - safeRight) /
                resources.displayMetrics.density - 24f
        val panelWidth = minOf(available, if (landscape) 650f else 420f) - 32f
        val feedbackWidth = if (landscape) (panelWidth - 20f) / 2f else panelWidth
        val message = CALLSIGN_TAKEN_HINT
        val hintLayout =
            android.text.StaticLayout.Builder.obtain(
                    message,
                    0,
                    message.length,
                    feedback[seat]!!.paint,
                    maxOf(1, (feedbackWidth * resources.displayMetrics.density).toInt()),
                )
                .setIncludePad(false)
                .build()
        val hintHeight =
            maxOf(
                30,
                kotlin.math.ceil(hintLayout.height / resources.displayMetrics.density + 4f).toInt(),
            )
        panel.add(feedback[seat]!!, height = hintHeight, gap = 4)
    }

    private fun feedbackText(
        seat: Int,
        reserved: Boolean = false,
        taken: Boolean = false,
    ): CharSequence {
        val name = if (seat == 0) session.callsign else session.localCallsign
        val isReserved = reserved || Callsigns.botReserved(name)
        val message =
            if (isReserved) "Bot names are reserved.\n\nGenerate random?"
            else if (taken) CALLSIGN_TAKEN_HINT
            else if (session.automaticNamePending(seat))
                "Choosing available callsign…\n\nGenerate random?"
            else "\n\nGenerate random?"
        val text = android.text.SpannableString(message)
        fun link(label: String, action: () -> Unit) {
            val start = message.indexOf(label)
            if (start < 0) return
            text.setSpan(
                object : android.text.style.ClickableSpan() {
                    override fun onClick(widget: View) {
                        action()
                    }

                    override fun updateDrawState(paint: android.text.TextPaint) {
                        paint.color = accent
                        paint.isUnderlineText = true
                    }
                },
                start,
                start + label.length,
                android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }
        if (!isReserved) link("Import account key") { showAccount(seat) }
        link("Generate random?") { session.generateCallsign(seat) }
        return text
    }

    private fun feedbackMessage(seat: Int) {
        feedback[seat]?.text = feedbackText(seat)
    }

    private fun checkAvailability() {
        val epoch = ++availabilityEpoch
        availability?.cancel()
        (0..1).forEach { feedbackMessage(it) }
        val names =
            listOf(session.callsign.trim()) +
                if (session.localSelected) listOf(session.localCallsign.trim()) else emptyList()
        if (names.any(String::isBlank)) return
        main.postDelayed(
            {
                if (epoch != availabilityEpoch || !foreground) return@postDelayed
                availability =
                    session.accounts.availability(session.server, names) { result ->
                        if (epoch != availabilityEpoch) return@availability
                        result.onSuccess { rows ->
                            rows.forEach { row ->
                                feedback.getOrNull(row.seat)?.text =
                                    feedbackText(
                                        row.seat,
                                        row.reason == "reserved",
                                        !row.available && !session.automaticNamePending(row.seat),
                                    )
                            }
                        }
                    }
            },
            300,
        )
    }

    private fun roomSettings(panel: LinearLayout) {
        val code =
            field(this, session.roomCode ?: session.roomName, "Room name or code", roomNameLimit)
        code.isEnabled = session.isHost
        code.addTextChangedListener(watcher { if (!session.online) session.roomName = it })
        panel.add(code)
        if (session.online && session.isHost)
            panel.add(
                button(
                    this,
                    "RENAME ROOM",
                    { session.command("rename_room", "code" to code.text.toString()) },
                ),
            )
        if (session.publicSelected) {
            panel.add(
                label(
                    this,
                    "Turn off Public Infinity to play room modes and change their rules.",
                    11f,
                    soft,
                ),
            )
            return
        }
        panel.add(label(this, "CHOOSE YOUR BATTLE", 10f, muted, mono = true))
        val choices = row(this)
        GameSession.modes.forEach { (value, title) ->
            choices.weighted(
                button(
                        this,
                        when (value) {
                            "infinity" -> "∞\nInfinity"
                            "elimination" -> "⊕\nElimination"
                            "ctf" -> "⚑\nCapture flag"
                            "koth" -> "♛\nKing of hill"
                            else -> "◈\nSurvival"
                        },
                        { session.selectMode(value) },
                    )
                    .apply {
                        textSize = 10f
                        minWidth = 0
                        minimumWidth = 0
                        isEnabled = session.isHost
                        if (session.mode == value) {
                            setTextColor(accent)
                            background =
                                background(this@MainActivity, 0xff102e3d.toInt(), 6, accent)
                        }
                        contentDescription = title
                    },
                gap = 2,
            )
        }
        panel.add(choices)
        panel.add(label(this, modeHelp(session.mode), 11f, soft).apply { minLines = 2 })
        panel.add(
            row(this).apply {
                weighted(button(this@MainActivity, "Rules", { showRules() }), gap = 6)
                weighted(button(this@MainActivity, "Teams", { showRules() }), gap = 6)
                weighted(button(this@MainActivity, "Presets", { showPresets() }), gap = 0)
            },
        )
        val rules = session.rules
        val summary =
            if (rules.infinity) {
                if (rules.infinityTarget == 0) "ENDLESS, UP TO 8 TANKS"
                else "FIRST TO ${rules.infinityTarget}, UP TO 8 TANKS"
            } else {
                val scoreUnit =
                    when (rules.mode) {
                        "survival" -> "WAVES"
                        "ctf" -> "CAPTURES"
                        "koth" -> "POINTS"
                        else -> "WINS"
                    }
                val limit = if (rules.mode == "survival") 4 else 8
                val friendlyFire = if (rules.friendlyFire) "on" else "off"
                "FIRST TO ${rules.scoreTarget} $scoreUnit, UP TO $limit TANKS\nFriendly fire is $friendlyFire."
            }
        panel.add(label(this, summary, 10f, soft, mono = true), gap = 0)
    }

    private fun playerSettings(panel: LinearLayout) {
        session.room?.let { room ->
            val players = room.optJSONArray("players")?.objects().orEmpty()
            if (session.isHost && session.roomSetupOpen) {
                if (room.roomRosterMembers().none { it.optString("kind") == "local" }) {
                    panel.add(
                        button(this, "＋ ADD LOCAL P2", { session.addRoomLocalPilot() }).apply {
                            isEnabled = session.canAddRoomLocalPilot
                        },
                    )
                }
                panel.add(
                    button(
                            this,
                            "＋ ADD BOT",
                            {
                                session.command(
                                    "add",
                                    "kind" to "bot",
                                    "name" to
                                        BotNames.next(
                                            players.map { it.optString("name") },
                                            players.size + 1,
                                        ),
                                )
                            },
                        )
                        .apply { isEnabled = players.size < room.optInt("maxPlayers", 8) },
                )
            }
            for (member in players) panel.add(roomPilotCard(room, member))
            val spectators = room.optJSONArray("spectators")?.objects().orEmpty()
            if (spectators.isNotEmpty())
                panel.add(label(this, "SPECTATORS", 10f, muted, mono = true))
            for (member in spectators) panel.add(roomPilotCard(room, member))
            return
        }
        fun setLocalPilot(enabled: Boolean) {
            session.localSelected = enabled
            session.save()
            readySignature = ""
            refresh(true)
        }
        if (!session.localSelected)
            panel.add(
                button(this, "＋ ADD LOCAL P2", { setLocalPilot(true) }).apply {
                    isEnabled =
                        !session.releasingCallsign && session.localBots.size < session.maxLocalBots
                },
            )
        panel.add(
            button(this, "＋ ADD BOT", { session.addLocalBot() }).apply {
                isEnabled = session.localBots.size < session.maxLocalBots
                contentDescription = "Add bot"
            },
        )
        val primary =
            column(this, 10).apply { background = background(this@MainActivity, sunken, 7) }
        primary.add(label(this, session.identity, 12f, paint(session.colorIndex), true))
        paintChoices(primary, session.colorIndex) { index ->
            session.colorIndex = index
            session.save()
            readySignature = ""
            refresh(true)
        }
        if (session.rules.teamMode == "teams") localTeamChoice(primary, 0)
        panel.add(primary)
        if (session.localSelected) {
            val secondary =
                column(this, 10).apply { background = background(this@MainActivity, sunken, 7) }
            secondary.add(
                row(this).apply {
                    weighted(
                        label(
                            this@MainActivity,
                            "${session.localCallsign} (P2)",
                            12f,
                            paint(session.localColorIndex),
                            true,
                        ),
                    )
                    add(
                        button(
                            this@MainActivity,
                            "REMOVE P2",
                            { setLocalPilot(false) },
                            danger = true,
                        ),
                        width = -2,
                        gap = 0,
                    )
                },
            )
            callsignRow(secondary, 1)
            paintChoices(secondary, session.localColorIndex) { index ->
                session.localColorIndex = index
                session.save()
                readySignature = ""
                refresh(true)
            }
            if (session.rules.teamMode == "teams") localTeamChoice(secondary, 1)
            secondary.add(
                label(this, "Touch controls P1. Keyboard/mouse controls P2.", 11f, soft),
                gap = 0,
            )
            panel.add(secondary)
        }
        for (bot in session.localBots) localBotRow(panel, bot)
        panel.add(label(this, "NEW BOT DIFFICULTY", 10f, muted, mono = true))
        panel.add(
            choice(BotDifficulty.titles, BotDifficulty.index(session.difficulty)) {
                session.difficulty = BotDifficulty.names[it]
                session.save()
            },
        )
    }

    private fun localTeamChoice(panel: LinearLayout, seat: Int) {
        val count = if (session.mode == "survival") 1 else if (session.mode == "ctf") 2 else 4
        val current = if (seat == 0) session.localTeam else session.secondLocalTeam
        panel.add(
            choice(
                    (1..count).map { session.rules.teamNames.getOrNull(it - 1) ?: "Team $it" },
                    (current - 1).coerceIn(0, count - 1),
                ) {
                    if (seat == 0) session.localTeam = it + 1 else session.secondLocalTeam = it + 1
                    session.save()
                }
                .apply { isEnabled = count > 1 },
        )
    }

    private fun localBotRow(panel: LinearLayout, bot: LocalBot) {
        val card = column(this, 10).apply { background = background(this@MainActivity, sunken, 7) }
        card.add(label(this, "BOT", 10f, muted, mono = true))
        val nameRow = row(this)
        val name =
            field(this, PilotIdentity.botName(bot.name), "Bot callsign").apply {
                textSize = 12f
                setTextColor(paint(bot.colorIndex))
                contentDescription = "${bot.name} callsign"
            }
        name.setOnFocusChangeListener { _, focused ->
            if (!focused && name.text.toString() != bot.name)
                session.updateLocalBot(bot.id, name = name.text.toString())
        }
        nameRow.weighted(name)
        nameRow.add(
            button(this, "×", { session.removeLocalBot(bot.id) }, danger = true).apply {
                contentDescription = "Remove ${bot.name}"
            },
            44,
            gap = 0,
        )
        card.add(nameRow)
        val paints = row(this)
        GamePalette.names.forEachIndexed { index, colorName ->
            paints.weighted(
                button(this, "", { session.updateLocalBot(bot.id, colorIndex = index) }).apply {
                    background =
                        android.graphics.drawable.RippleDrawable(
                            android.content.res.ColorStateList.valueOf(0x3340d5ff),
                            NativeStyle.paintChip(
                                this@MainActivity,
                                paint(index),
                                bot.colorIndex == index,
                            ),
                            null,
                        )
                    minimumWidth = 0
                    minWidth = 0
                    contentDescription = "${bot.name} paint: $colorName"
                },
                gap = 2,
            )
        }
        card.add(paints)
        val difficulties = BotDifficulty.names
        card.add(label(this, "DIFFICULTY", 10f, muted, mono = true))
        card.add(
            choice(BotDifficulty.titles, BotDifficulty.index(bot.difficulty)) {
                session.updateLocalBot(bot.id, difficulty = difficulties[it])
            },
        )
        if (session.rules.teamMode == "teams") {
            val count = if (session.mode == "survival") 1 else if (session.mode == "ctf") 2 else 4
            card.add(label(this, "TEAM", 10f, muted, mono = true))
            card.add(
                choice(
                        (1..count).map { session.rules.teamNames.getOrNull(it - 1) ?: "Team $it" },
                        (bot.team - 1).coerceIn(0, count - 1),
                    ) {
                        session.updateLocalBot(bot.id, team = it + 1)
                    }
                    .apply { isEnabled = count > 1 },
            )
        }
        panel.add(card)
    }

    private fun paintChoices(panel: LinearLayout, selected: Int, onSelect: (Int) -> Unit) {
        val paints = row(this)
        GamePalette.names.forEachIndexed { index, name ->
            paints.weighted(
                button(this, "", { onSelect(index) }).apply {
                    background =
                        android.graphics.drawable.RippleDrawable(
                            android.content.res.ColorStateList.valueOf(0x3340d5ff),
                            NativeStyle.paintChip(
                                this@MainActivity,
                                paint(index),
                                selected == index,
                            ),
                            null,
                        )
                    isSelected = selected == index
                    contentDescription = name
                    minimumWidth = 0
                    minWidth = 0
                    setPadding(0, dp(8), 0, dp(8))
                },
                gap = 2,
            )
        }
        panel.add(paints, gap = 0)
    }

    private fun roomPilotCard(room: JSONObject, member: JSONObject): LinearLayout {
        val target = member.optInt("id")
        val memberID = member.optLong("member")
        val rawName = member.optString("name")
        val watching = member.optBoolean("spectating")
        val access =
            roomPilotAccess(
                member,
                session.network.welcome?.id,
                session.isHost,
                session.roomSetupOpen,
                !room.isNull("matchmaking"),
                session.rules,
            )
        val name = PilotIdentity.label(rawName, access.bot, access.localSeat)
        val colorIndex =
            member.optInt(
                "colorIndex",
                GamePalette.colors.indexOf(member.optString("color")).coerceAtLeast(0),
            )
        val color =
            member.optString("color").takeIf(String::isNotBlank)?.let(NativeStyle::mappedPaint)
                ?: paint(colorIndex)
        val card = column(this, 10).apply { background = background(this@MainActivity, sunken, 7) }
        val options = mutableListOf<Pair<String, () -> Unit>>()
        if (access.teamCount > 1)
            options +=
                "Change team" to
                    {
                        val teamNames =
                            (1..access.teamCount).map {
                                session.rules.teamNames.getOrElse(it - 1) { "Team $it" }
                            }
                        AlertDialog.Builder(this)
                            .setTitle("Team")
                            .setItems(teamNames.toTypedArray()) { _, index ->
                                session.command(
                                    "configure",
                                    "target" to target,
                                    "member" to memberID,
                                    "team" to index + 1,
                                )
                            }
                            .show()
                    }
        if (access.canRenameBot) {
            options +=
                "Rename" to
                    {
                        prompt("Bot callsign", PilotIdentity.botName(rawName), 16) {
                            if (it.isNotEmpty())
                                session.command(
                                    "configure",
                                    "target" to target,
                                    "member" to memberID,
                                    "name" to it,
                                )
                        }
                    }
            options +=
                "Bot difficulty" to
                    {
                        AlertDialog.Builder(this)
                            .setTitle("Bot difficulty")
                            .setItems(BotDifficulty.titles.toTypedArray()) { _, index ->
                                session.command(
                                    "configure",
                                    "target" to target,
                                    "member" to memberID,
                                    "difficulty" to BotDifficulty.names[index],
                                )
                            }
                            .show()
                    }
        }
        if (access.canToggleSpectating)
            options +=
                (if (watching) "Return to play" else "Spectate") to
                    {
                        session.command(
                            "spectate",
                            "target" to target,
                            "member" to memberID,
                            "spectating" to !watching,
                        )
                    }
        if (access.canRemove)
            options +=
                "Remove" to { session.command("kick", "target" to target, "member" to memberID) }
        card.add(
            row(this).apply {
                val marker =
                    View(this@MainActivity).apply {
                        background =
                            android.graphics.drawable.GradientDrawable().apply {
                                shape = android.graphics.drawable.GradientDrawable.OVAL
                                setColor(color)
                            }
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                    }
                add(marker, width = 10, height = 10, gap = 6)
                weighted(label(this@MainActivity, name, 12f, color, access.localSeat > 0), gap = 5)
                val status =
                    if (watching) "WATCHING"
                    else if (member.optBoolean("ready")) "READY" else "WAITING"
                val identity =
                    if (access.bot) "BOT"
                    else
                        "HUMAN PILOT\n" +
                            (if (room.optInt("host") == target) "HOST, " else "") +
                            status
                add(
                    label(this@MainActivity, identity, 10f, muted, mono = true).apply {
                        gravity = Gravity.END
                    },
                    width = -2,
                    gap = 4,
                )
                if (options.isNotEmpty())
                    add(
                        button(
                                this@MainActivity,
                                "…",
                                {
                                    AlertDialog.Builder(this@MainActivity)
                                        .setTitle(name)
                                        .setItems(options.map { it.first }.toTypedArray()) {
                                            _,
                                            index ->
                                            options[index].second()
                                        }
                                        .show()
                                },
                            )
                            .apply {
                                contentDescription = "Player options for $name"
                                minimumWidth = 0
                                minWidth = 0
                                setPadding(0, 0, 0, 0)
                            },
                        width = 36,
                        gap = 0,
                    )
            },
            gap = 8,
        )
        if (access.canPaint)
            paintChoices(card, colorIndex) { index ->
                session.command(
                    "paint",
                    "target" to target,
                    "member" to memberID,
                    "colorIndex" to index,
                )
            }
        return card
    }

    private fun showMenu() {
        if (session.screen != Screen.PLAYING) {
            showControls()
            return
        }
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val panel = column(this, 16)
        val intro = column(this)
        val actions = column(this)
        val card =
            if (landscape)
                row(this).apply {
                    gravity = Gravity.TOP
                    weighted(intro, gap = 24)
                    weighted(actions, gap = 0)
                }
            else
                column(this).apply {
                    add(intro, gap = 12)
                    add(actions, gap = 0)
                }
        intro.add(
            label(
                this,
                if (session.online) "ONLINE MATCH" else "TAKE A BREATHER",
                10f,
                soft,
                mono = true,
            ),
        )
        val lead = if (session.online) "STAY" else if (session.infinity) "HOLD YOUR" else "TAKE A"
        val tail =
            if (session.online) "CONNECTED." else if (session.infinity) "FIRE." else "BREATHER."
        val heading =
            android.text.SpannableString("$lead\n$tail").apply {
                setSpan(
                    android.text.style.ForegroundColorSpan(accent),
                    lead.length + 1,
                    length,
                    android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
            }
        intro.add(
            label(this, "", if (landscape) 26f else 34f, text, true).apply { this.text = heading },
        )
        val description =
            when {
                session.spectating -> "The arena keeps running while you browse the menu."
                !session.online -> "The battle is paused. Tanks are safe."
                session.infinity ->
                    "The match keeps running. Tanks remain vulnerable. Respawning waits until the menu closes."
                else -> "The match keeps running. Tanks remain vulnerable."
            }
        intro.add(label(this, description, 12f, soft))
        if (session.showFPS) {
            intro.add(
                label(
                    this,
                    performanceReadout(false, session.online, fps, session.latency),
                    10f,
                    muted,
                    mono = true,
                ),
            )
        }
        val notice = label(this, "", 12f, danger).apply { visibility = View.GONE }
        fun showNotice(message: String) {
            notice.text = message
            notice.visibility = View.VISIBLE
        }
        if (!session.canResume) showNotice(session.status)
        intro.add(notice)

        val originalName = session.callsign.trim()
        val callsign =
            if (session.spectating) null
            else
                field(this, originalName, "Callsign").apply {
                    contentDescription = "P1 callsign"
                    setTextColor(paint(session.colorIndex))
                    imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_DONE
                }
        fun resumeBattle() {
            val newName = callsign?.text?.toString()?.trim().orEmpty()
            if (Callsigns.botReserved(newName)) {
                showNotice(Callsigns.botNamespaceMessage)
                return
            }
            if (!session.canResume) {
                showNotice(session.status)
                return
            }
            dismissDialog()
            session.pause(false)
            if (newName.isNotBlank() && newName != originalName) session.renameCallsign(newName)
        }
        if (callsign != null) {
            actions.add(label(this, "CALLSIGN", 10f, muted, mono = true))
            actions.add(
                row(this).apply {
                    weighted(callsign)
                    add(
                        button(
                                this@MainActivity,
                                "Account",
                                { showAccount(0, returnToPause = true) },
                            )
                            .apply {
                                textSize = 10f
                                contentDescription = "P1 account key"
                            },
                        width = 76,
                        gap = 0,
                    )
                },
            )
            callsign.setOnEditorActionListener { _, action, _ ->
                if (action != android.view.inputmethod.EditorInfo.IME_ACTION_DONE) false
                else {
                    resumeBattle()
                    true
                }
            }
        }
        actions.add(
            button(
                this,
                if (session.online) "← BACK TO THE ARENA" else "← BACK TO THE BATTLE",
                ::resumeBattle,
                role = "primary",
            ),
        )
        if (!session.spectating || session.canControlSecondary)
            actions.add(button(this, "Controls", { showControls(returnToPause = true) }))
        if (session.room != null && session.isHost)
            actions.add(
                button(
                    this,
                    "End match",
                    {
                        dismissDialog()
                        session.lobby()
                    },
                ),
            )
        if (session.canRestartWave && (!session.online || session.isHost))
            actions.add(
                button(
                    this,
                    "Restart wave",
                    {
                        dismissDialog()
                        session.restartMatch(true)
                    },
                ),
            )
        actions.add(
            button(
                this,
                if (session.infinity) "Exit Infinity" else "Return to room",
                {
                    dismissDialog()
                    if (session.infinity) session.lobby(endMatch = false) else session.leave()
                },
            ),
            gap = 0,
        )
        panel.add(card, gap = 12)
        if (session.infinity) {
            panel.add(label(this, "LEADERBOARD", 10f, accent, mono = true))
            currentLeaders().take(10).forEachIndexed { index, entry ->
                panel.add(standingsRow(entry, index + 1, localSeat(entry)))
            }
            panel.add(label(this, "+1 per kill, −1 per death", 11f, soft), gap = 16)
            appendFieldManual(panel)
        }
        showPanel(panel, "Paused")
        dialog?.setOnKeyListener { _, key, event ->
            if (key != KeyEvent.KEYCODE_BUTTON_START || !event.isGamepad())
                return@setOnKeyListener false
            if (
                event.action == KeyEvent.ACTION_DOWN &&
                    event.repeatCount == 0 &&
                    gamepads.inputForDevice(
                        event.deviceId,
                        controlOwner != null,
                        controlLocalOwner != null,
                    ) != null
            )
                resumeBattle()
            true
        }
    }

    private fun showControls() = showControls(false)

    private fun showControls(returnToPause: Boolean) {
        val panel = column(this, 16)
        val paired = if (session.online) session.localID2 != null else session.localSelected
        val hasLocalCoPilot =
            when {
                session.room != null -> session.roomLocalPilot != null
                session.online || session.screen == Screen.PLAYING -> session.localID2 != null
                else -> session.localSelected
            }
        panel.add(label(this, session.identity, 13f, paint(session.colorIndex), true))
        panel.add(
            label(
                this,
                "Drag the left stick to drive and aim. Touch near your tank to rotate toward that point without moving. Tap Fire to shoot, or hold it to fire continuously. Press off-center or drag Fire to aim while firing, even while driving with the joystick. Pickups equip automatically.",
                13f,
            ),
        )
        panel.add(label(this, "Swipe from an edge for Android system controls.", 12f, soft))
        val showcaseHelp = label(this, "", 11f, soft)
        hardwareControls(panel, paired, showcaseHelp)
        panel.add(button(this, "QUICK TOUR", { showQuickTour() }))
        panel.add(button(this, "SHOWCASE", { showShowcase() }))
        panel.add(showcaseHelp)
        val reopenControls = { showControls(returnToPause) }
        panel.add(
            button(
                this,
                if (hasLocalCoPilot) "P1 ACCOUNT KEY" else "ACCOUNT KEY",
                {
                    showAccount(0, returnToPause = false, onClose = reopenControls)
                },
            ),
        )
        if (hasLocalCoPilot)
            panel.add(
                button(
                    this,
                    "P2 ACCOUNT KEY",
                    {
                        showAccount(1, returnToPause = false, onClose = reopenControls)
                    },
                ),
            )
        panel.add(View(this).apply { setBackgroundColor(NativeStyle.edge) }, height = 1)
        panel.add(
            settingsToggle("Game controller support", session.gamepadSupport) {
                session.gamepadSupport = it
                gamepads.enabled = it
                keyboardInput()
                session.save()
            },
        )
        panel.add(
            settingsToggle("Request high refresh rate", session.highRefresh) {
                session.highRefresh = it
                session.save()
                applyRefreshRate()
            },
        )
        panel.add(
            settingsToggle("Show FPS and ping", session.showFPS) {
                session.showFPS = it
                session.save()
                refresh(false)
            },
        )
        panel.add(
            settingsToggle("Sound and haptics", !session.muted) {
                if (it == session.muted) toggleSound()
            },
        )
        val volume = (session.volume * 100).roundToInt()
        val volumeValue = label(this, "$volume%", 13f, mono = true)
        panel.add(
            row(this).apply {
                weighted(label(this@MainActivity, "Sound volume", 13f), gap = 8)
                add(volumeValue, width = -2, gap = 0)
            },
        )
        panel.add(
            SeekBar(this).apply {
                contentDescription = "Sound volume"
                max = 100
                keyProgressIncrement = 5
                progress = volume
                setOnSeekBarChangeListener(
                    object : SeekBar.OnSeekBarChangeListener {
                        private var dragging = false

                        override fun onProgressChanged(
                            bar: SeekBar?,
                            value: Int,
                            fromUser: Boolean,
                        ) {
                            if (!fromUser) return
                            val effective = if (value in 46..54) 50 else value
                            if (!dragging && value != effective) bar?.progress = effective
                            val normalized = effective / 100f
                            if (session.volume == normalized) return
                            session.volume = normalized
                            volumeValue.text = "$effective%"
                            session.save()
                            refresh(false)
                        }

                        override fun onStartTrackingTouch(bar: SeekBar?) {
                            dragging = true
                        }

                        override fun onStopTrackingTouch(bar: SeekBar?) {
                            dragging = false
                            bar?.progress = (session.volume * 100).roundToInt()
                            if (!session.muted) previewAudio(AudioCue.VOLUME_PREVIEW)
                        }
                    },
                )
            },
        )
        onlineServerSetting(panel)
        panel.add(button(this, "RESET ALL SETTINGS", { confirmResetSettings() }, role = "danger"))
        panel.add(button(this, "BACK", ::dismissDialog, role = "primary"), gap = 0)
        val versionLabel =
            label(this, session.settingsVersionText, 11f, muted, mono = true).apply {
                tag = "settingsVersion"
            }
        panel.add(versionLabel)
        panel.isFocusableInTouchMode = true
        panel.requestFocus()
        showPanel(
            panel,
            "Controls",
            afterClose = if (returnToPause) ::showMenu else null,
            header = panelHeader("Controls"),
        )
        settingsVersionLabel = versionLabel
    }

    private fun onlineServerSetting(panel: LinearLayout) {
        val address =
            field(this, session.server, GameSession.defaultServer, 512).apply {
                contentDescription = "Online server"
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
                imeOptions = EditorInfo.IME_ACTION_DONE
            }
        val feedback =
            label(this, "", 11f, soft).apply {
                visibility = View.GONE
                accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            }
        if (session.online)
            panel.add(label(this, "Changing servers returns you to the room.", 11f, soft))
        fun applyServer() {
            val previous = session.server
            val connected = session.online
            runCatching { session.setServer(address.text.toString()) }
                .onSuccess {
                    getSystemService(InputMethodManager::class.java)
                        .hideSoftInputFromWindow(address.windowToken, 0)
                    if (connected && previous != session.server) dismissDialog()
                    else {
                        address.setText(session.server)
                        address.clearFocus()
                        feedback.text = "Server saved."
                        feedback.visibility = View.VISIBLE
                    }
                }
                .onFailure { address.error = it.message ?: "Invalid server address." }
        }
        address.addTextChangedListener(
            watcher {
                address.error = null
                feedback.visibility = View.GONE
            },
        )
        address.setOnEditorActionListener { _, action, _ ->
            if (action != EditorInfo.IME_ACTION_DONE) false
            else {
                applyServer()
                true
            }
        }
        panel.add(label(this, "ONLINE SERVER", 10f, muted, mono = true), gap = 6)
        panel.add(address)
        panel.add(button(this, "SAVE SERVER", ::applyServer))
        panel.add(feedback)
    }

    private fun settingsToggle(title: String, value: Boolean, change: (Boolean) -> Unit): Switch =
        NativeStyle.toggle(this).apply {
            text = title
            textSize = 13f
            setTextColor(NativeStyle.text)
            isChecked = value
            setOnCheckedChangeListener { _, enabled -> change(enabled) }
        }

    private fun hardwareControls(panel: LinearLayout, paired: Boolean, showcaseHelp: TextView) {
        val pilot = if (paired) "${session.localCallsign} (P2)" else session.identity
        val color = paint(if (paired) session.localColorIndex else session.colorIndex)
        val section = column(this).apply { visibility = View.GONE }
        val contents = column(this)
        val heading = label(this, "", 11f, color, true, mono = true)
        val seatHelp = label(this, "", 12f, soft)
        val keyboardDefaults =
            label(
                this,
                "Keyboard defaults are WASD/arrow keys to drive and Q/C/Space/Enter to fire.",
                12f,
                soft,
            )
        val bindingRows = column(this)
        val mouseOptions =
            column(this).apply {
                add(
                    settingsToggle("Mouse aim", session.mouseAim) {
                        session.mouseAim = it
                        session.save()
                        arena.mouseAimEnabled = it
                    },
                )
                add(
                    settingsToggle("Mouse fire", session.mouseFire) {
                        session.mouseFire = it
                        session.save()
                        arena.mouseFireEnabled = it
                    },
                    gap = 0,
                )
            }
        contents.add(heading)
        contents.add(seatHelp)
        contents.add(keyboardDefaults)
        contents.add(bindingRows)
        contents.add(mouseOptions, gap = 0)
        section.add(
            NativeStyle.disclosure(this, "Binds", expanded = false, controlledContent = contents),
        )
        section.add(contents, gap = 0)
        val update = {
            val hardware =
                InputDevice.getDeviceIds()
                    .asList()
                    .mapNotNull { InputDevice.getDevice(it) }
                    .filterNot { it.isVirtual }
            val keyboard = hardware.any { it.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC }
            val mouse = hardware.any { it.supportsSource(InputDevice.SOURCE_MOUSE) }
            val methods =
                when {
                    keyboard && mouse -> "Keyboard/mouse"
                    keyboard -> "Keyboard"
                    else -> "Mouse"
                }
            section.visibility = if (keyboard || mouse) View.VISIBLE else View.GONE
            heading.text = "${methods.uppercase()}, $pilot"
            seatHelp.text =
                if (paired) "Touch controls P1. $methods controls P2."
                else
                    "$methods and touch control P1. Add local P2 in Players and bots to assign ${methods.lowercase()} to P2."
            keyboardDefaults.visibility = if (keyboard) View.VISIBLE else View.GONE
            bindingRows.visibility = keyboardDefaults.visibility
            mouseOptions.visibility = if (mouse) View.VISIBLE else View.GONE
            if (keyboard && bindingRows.childCount == 0) buildKeyBindings(bindingRows)
            if (!keyboard) keyCaptureDialog?.dismiss()
            showcaseHelp.text =
                if (keyboard) "Exit Showcase with Escape, or switch away from the app and return."
                else "Switch away from the app and return to exit Showcase."
        }
        section.addOnAttachStateChangeListener(
            object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(view: View) {
                    updateControlsHardware = update
                    update()
                }

                override fun onViewDetachedFromWindow(view: View) {
                    if (updateControlsHardware === update) updateControlsHardware = null
                }
            },
        )
        panel.add(section)
    }

    private fun buildKeyBindings(panel: LinearLayout) {
        panel.removeAllViews()
        repeat(NativeControlBindings.layoutCount) { layout ->
            panel.add(label(this, "KEYBOARD LAYOUT ${layout + 1}", 11f, soft, mono = true))
            for (action in NativeControlAction.entries) {
                val keyLabel = NativeControlBindings.label(session.keyboardBindings[layout, action])
                val assign =
                    button(
                            this,
                            keyLabel,
                            { captureKey(layout, action) { buildKeyBindings(panel) } },
                        )
                        .apply {
                            contentDescription = "Layout ${layout + 1}, ${action.label}, $keyLabel"
                        }
                panel.add(
                    row(this).apply {
                        weighted(label(this@MainActivity, action.label, 13f), gap = 12)
                        add(assign, width = 115, gap = 0)
                    },
                )
            }
        }
        panel.add(
            button(
                this,
                "RESET DEFAULT KEYS",
                {
                    session.keyboardBindings = NativeControlBindings.defaults
                    session.save()
                    buildKeyBindings(panel)
                },
            ),
        )
    }

    private fun captureKey(layout: Int, action: NativeControlAction, applied: () -> Unit) {
        val panel = column(this, 16)
        panel.add(label(this, "Layout ${layout + 1}, ${action.label}", 14f, bold = true))
        panel.add(label(this, "Press a keyboard key. Escape cancels.", 13f, soft))
        val error = label(this, "", 12f, danger)
        panel.add(error)
        val shown =
            AlertDialog.Builder(this)
                .setTitle("Press a key")
                .setView(panel)
                .setNegativeButton("CANCEL", null)
                .create()
        keyCaptureDialog = shown
        shown.setOnDismissListener { keyCaptureDialog = null }
        shown.setOnKeyListener { _, key, event ->
            if (event.isSystem) return@setOnKeyListener false
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                when {
                    key == KeyEvent.KEYCODE_ESCAPE -> shown.dismiss()
                    event.isCtrlPressed || event.isAltPressed || event.isMetaPressed ->
                        error.text = "System shortcuts cannot be assigned."
                    else ->
                        runCatching { session.keyboardBindings.assign(layout, action, key) }
                            .onSuccess {
                                session.keyboardBindings = it
                                session.save()
                                shown.dismiss()
                                applied()
                            }
                            .onFailure { error.text = it.message }
                }
            }
            true
        }
        shown.show()
    }

    private fun confirmResetSettings() {
        AlertDialog.Builder(this)
            .setTitle("Reset all settings?")
            .setMessage(
                "Restore defaults and return to the room. Room, server, display, audio, and control settings will reset. Saved account keys and callsigns stay on this device.",
            )
            .setNegativeButton("CANCEL", null)
            .setPositiveButton("RESET ALL SETTINGS") { _, _ -> resetSettings() }
            .show()
    }

    private fun resetSettings() {
        val settings = getSharedPreferences("leqra-settings", MODE_PRIVATE)
        val preserve =
            setOf(
                "callsign",
                "localCallsign",
                "autoPending0",
                "autoPending1",
                "autoRequest0",
                "autoRequest1",
                QUICK_TOUR_SEEN,
            )
        dialog?.apply {
            setOnDismissListener(null)
            dismiss()
        }
        dialog = null
        session.leave()
        settings.edit().apply { (settings.all.keys - preserve).forEach(::remove) }.apply()
        setIntent(Intent(intent).setData(null).apply { removeExtra("server") })
        fullscreen = false
        applyFullscreen()
        recreate()
    }

    @android.annotation.SuppressLint(
        "GestureBackNavigation",
    ) // Legacy Back is consumed; API33+ registers a no-op preview callback below.
    private fun showShowcase() {
        if (showcaseDialog != null) return
        hideKeyboard()
        val preview = runCatching {
            ShowcaseView(this, session.muted, session.showFPS)
        }
            .getOrElse {
                alert("Showcase", "The showcase could not be loaded.")
                return
            }
        val shown = Dialog(this, R.style.AppTheme)
        shown.window?.apply {
            addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            setBackgroundDrawable(android.graphics.drawable.ColorDrawable(0xff10181e.toInt()))
            enableImmersiveEdgeToEdge()
        }
        showcaseDialog = shown
        showcaseReturnOnResume = false
        shown.setCancelable(false)
        shown.setCanceledOnTouchOutside(false)
        shown.setContentView(preview, ViewGroup.LayoutParams(-1, -1))
        shown.setOnKeyListener { _, key, event ->
            when (key) {
                KeyEvent.KEYCODE_ESCAPE -> {
                    if (event.action == KeyEvent.ACTION_UP) shown.dismiss()
                    true
                }
                KeyEvent.KEYCODE_BACK -> true
                else -> false
            }
        }
        shown.setOnDismissListener {
            if (showcaseDialog === shown) showcaseDialog = null
            showcaseReturnOnResume = false
            preview.release()
            window.setImmersiveSystemBars(fullscreen)
        }
        shown.show()
        preview.requestFocus()
        shown.window?.setLayout(-1, -1)
        if (Build.VERSION.SDK_INT >= 33)
            shown.onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY,
            ) {}
    }

    private fun showJoin(draft: RoomJoinDraft = RoomJoinDraft()) {
        val panel =
            roomJoinPanel(
                this,
                session.callsign,
                draft,
                canJoin = { !session.releasingCallsign },
                openAccount = { current ->
                    showAccount(0, returnToPause = false, onClose = { showJoin(current) })
                },
            ) { callsign, request ->
                hideKeyboard()
                dismissDialog()
                if (callsign != session.callsign) session.callsign = callsign
                session.join(request.code, request.spectate)
            }
        showPanel(panel, "Find a room")
    }

    private fun showRules() = showRules(session.rules)

    private fun showRules(source: RoomRules) {
        val panel = column(this, 16)
        panel.add(label(this, "ROOM RULES.", 24f, accent, true))
        panel.add(
            label(
                this,
                GameSession.modes.getValue(session.mode).uppercase(),
                12f,
                accent,
                mono = true,
            ),
        )
        val draft = RuleEditorLimits.draft(source)
        var teamSection: LinearLayout? = null
        var powerSummary: TextView? = null
        val powerDescriptions = mutableMapOf<String, TextView>()
        fun refreshPowerHelp() {
            powerSummary?.text = PowerupHelp.summary(draft)
            powerDescriptions.forEach { (kind, view) ->
                view.text = PowerupHelp.description(kind, draft)
            }
        }
        fun select(
            title: String,
            values: List<String>,
            current: String,
            enabled: Boolean = true,
            set: (String) -> Unit,
        ): View {
            panel.add(label(this, title, 10f, muted, mono = true))
            val options =
                choice(values, values.indexOf(current).coerceAtLeast(0)) { set(values[it]) }
                    .apply {
                        isEnabled = enabled
                        contentDescription = title
                    }
            panel.add(options)
            return options
        }
        select(
            "MAP SIZE",
            listOf("compact", "standard", "large", "huge", "giant", "ultrawide"),
            draft.mapSize,
            enabled = !draft.infinity,
        ) {
            draft.mapSize = it
            refreshPowerHelp()
        }
        select(
            "FORMAT",
            listOf("ffa", "teams"),
            draft.teamMode,
            enabled = draft.infinity || draft.mode !in listOf("ctf", "survival"),
        ) {
            draft.teamMode = it
            teamSection?.visibility = if (it == "teams") View.VISIBLE else View.GONE
        }
        if (!draft.infinity) {
            select(
                "POWER-UP FREQUENCY",
                listOf("off", "slow", "normal", "fast", "superfast"),
                draft.pickupRate,
            ) {
                draft.pickupRate = it
                refreshPowerHelp()
            }
            ruleStepper(
                panel,
                if (draft.mode == "survival") "Wave target" else "Score target",
                draft.scoreTarget,
                1,
                RuleEditorLimits.scoreMaximum(draft),
            ) {
                draft.scoreTarget = it
            }
            ruleStepper(panel, "Time limit", draft.timeLimit, 30, 600, 15, format = { "${it}s" }) {
                draft.timeLimit = it
            }
            ruleStepper(panel, "Respawn", draft.respawnSeconds, 1, 10, format = { "${it}s" }) {
                draft.respawnSeconds = it
            }
        }
        panel.add(
            NativeStyle.toggle(this).apply {
                text = "Friendly fire"
                textSize = 13f
                setTextColor(NativeStyle.text)
                isChecked = draft.friendlyFire
                setOnCheckedChangeListener { _, v -> draft.friendlyFire = v }
            },
        )
        panel.add(
            NativeStyle.toggle(this).apply {
                text = "Portrait maze"
                textSize = 13f
                setTextColor(NativeStyle.text)
                isChecked = draft.portraitMaze
                isEnabled = !draft.infinity
                setOnCheckedChangeListener { _, v -> draft.portraitMaze = v }
            },
        )
        teamSection =
            column(this).apply {
                visibility = if (draft.teamMode == "teams") View.VISIBLE else View.GONE
            }
        val teams = teamSection!!
        teams.add(label(this, "TEAM NAMES & PAINT", 10f, muted, mono = true))
        repeat(4) { team ->
            val teamRow = row(this)
            val name =
                field(this, draft.teamNames.getOrElse(team) { "Team ${team+1}" }, "Team ${team+1}")
            name.addTextChangedListener(
                watcher { value ->
                    draft.teamNames = draft.teamNames.toMutableList().apply { this[team] = value }
                },
            )
            teamRow.weighted(name)
            var teamPaint = draft.teamColors.getOrElse(team) { team }
            val paintButton =
                button(this, "●", {}).apply {
                    contentDescription = "Team ${team+1} paint"
                    setTextColor(paint(teamPaint))
                }
            paintButton.setOnClickListener {
                teamPaint = (teamPaint + 1) % 8
                draft.teamColors = draft.teamColors.toMutableList().apply { this[team] = teamPaint }
                paintButton.setTextColor(paint(teamPaint))
            }
            teamRow.add(paintButton, 52, gap = 0)
            teams.add(teamRow)
        }
        panel.add(teams)
        if (draft.infinity) {
            ruleStepper(
                panel,
                "Score target",
                draft.infinityTarget,
                0,
                999,
                format = { if (it == 0) "Endless" else it.toString() },
            ) {
                draft.infinityTarget = it
            }
            val roamingControls = ArrayList<View>()
            fun enableRoaming(view: View, enabled: Boolean) {
                view.isEnabled = enabled
                if (view is ViewGroup)
                    for (i in 0 until view.childCount) enableRoaming(view.getChildAt(i), enabled)
            }
            fun syncRoaming() {
                roamingControls.forEach {
                    enableRoaming(it, draft.infinityRandomBots)
                    it.alpha = if (draft.infinityRandomBots) 1f else .45f
                }
            }
            panel.add(
                NativeStyle.toggle(this).apply {
                    text = "Random roaming bots"
                    textSize = 13f
                    setTextColor(NativeStyle.text)
                    isChecked = draft.infinityRandomBots
                    setOnCheckedChangeListener { _, v ->
                        draft.infinityRandomBots = v
                        syncRoaming()
                    }
                },
            )
            val difficultyTitles = BotDifficulty.titles
            val configuredRates = draft.roamingBotSpawnRates().toMutableMap()
            for ((index, level) in BotDifficulty.names.withIndex()) {
                val current = configuredRates.getValue(level)
                val rates = (listOf(0.0, .5, 1.0, 2.0, 4.0) + current).distinct().sorted()
                val rateLabels = rates.map {
                    if (it == 0.0) "Off"
                    else
                        java.math.BigDecimal.valueOf(it)
                            .round(java.math.MathContext(3))
                            .stripTrailingZeros()
                            .toString()
                            .replace("E", "e") + "×"
                }
                panel.add(
                    label(
                        this,
                        "${difficultyTitles[index].uppercase(java.util.Locale.ROOT)} BOT SPAWN RATE",
                        10f,
                        muted,
                        mono = true,
                    ),
                )
                val picker =
                    choice(rateLabels, rates.indexOf(current)) { selection ->
                            configuredRates[level] = rates[selection]
                            draft.infinityBotSpawnRates = configuredRates.toMap()
                        }
                        .apply {
                            tag = "roamingRate:$level"
                            contentDescription = "${difficultyTitles[index]} bot spawn rate"
                        }
                panel.add(picker)
                roamingControls += picker
            }
            panel.add(
                label(
                    this,
                    "1× averages one bot every 1.5 seconds per living human while the room has capacity. Shared limit: 16 roaming bots per human, 128 per room. Roster bots always play.",
                    11f,
                    muted,
                ),
            )
            syncRoaming()
        }
        panel.add(
            label(
                this,
                if (draft.infinity) "INFINITY POWER-UPS" else "AVAILABLE POWER-UPS",
                10f,
                muted,
                mono = true,
            ),
        )
        powerSummary = label(this, PowerupHelp.summary(draft), 11f, soft).also { panel.add(it) }
        PowerupHelp.kinds.forEach { power ->
            if (draft.infinity) {
                panel.add(label(this, PowerupHelp.title(power), 13f, accent, true), gap = 0)
            } else
                panel.add(
                    NativeStyle.checkBox(this).apply {
                        text = PowerupHelp.title(power)
                        textSize = 13f
                        setTextColor(NativeStyle.text)
                        isChecked = power in draft.weapons
                        setOnCheckedChangeListener { _, v ->
                            draft.weapons =
                                if (v) (draft.weapons + power).distinct() else draft.weapons - power
                            refreshPowerHelp()
                        }
                    },
                    gap = 0,
                )
            powerDescriptions[power] =
                label(this, PowerupHelp.description(power, draft), 11f, soft).also {
                    panel.add(it, gap = 3)
                }
        }
        panel.add(
            button(
                    this,
                    "APPLY RULES",
                    {
                        session.changeRules(RuleEditorLimits.draft(draft))
                        dismissDialog()
                    },
                    role = "primary",
                )
                .apply { isEnabled = session.isHost && session.screen != Screen.PLAYING },
        )
        panel.add(
            button(this, "Restore defaults", { showRules(session.rules.restoringModeDefaults()) }),
            gap = 0,
        )
        showPanel(panel, "Rules")
    }

    private fun ruleStepper(
        panel: LinearLayout,
        title: String,
        initial: Int,
        minimum: Int,
        maximum: Int,
        step: Int = 1,
        format: (Int) -> String = { it.toString() },
        changed: (Int) -> Unit,
    ) {
        var value = RuleEditorLimits.snapped(initial, minimum, maximum, step)
        val controls = row(this)
        controls.weighted(label(this, title, 13f, text), gap = 8)
        lateinit var minus: Button
        lateinit var number: Button
        lateinit var plus: Button
        fun update() {
            number.value(format(value))
            number.contentDescription = "$title: ${format(value)}"
            minus.isEnabled = value > minimum
            plus.isEnabled = value < maximum
            changed(value)
        }
        fun set(next: Int) {
            value = RuleEditorLimits.snapped(next, minimum, maximum, step)
            update()
        }
        minus =
            button(this, "−", { set(value - step) }).apply {
                contentDescription = "Decrease $title"
                minimumWidth = 0
                minWidth = 0
            }
        plus =
            button(this, "+", { set(value + step) }).apply {
                contentDescription = "Increase $title"
                minimumWidth = 0
                minWidth = 0
            }
        number =
            button(
                    this,
                    format(value),
                    {
                        val choices = (minimum..maximum step step).toList()
                        val picker =
                            NumberPicker(this).apply {
                                minValue = 0
                                maxValue = choices.lastIndex
                                displayedValues = choices.map(format).toTypedArray()
                                this.value = choices.indexOf(value).coerceAtLeast(0)
                                wrapSelectorWheel = false
                            }
                        AlertDialog.Builder(this)
                            .setTitle(title)
                            .setView(column(this, 12).apply { add(picker) })
                            .setNegativeButton("Cancel", null)
                            .setPositiveButton("Set") { _, _ ->
                                picker.clearFocus()
                                set(choices[picker.value])
                            }
                            .show()
                    },
                )
                .apply {
                    textSize = 12f
                    minimumWidth = 0
                    minWidth = 0
                }
        controls.add(minus, 44, gap = 0)
        controls.add(number, 76, gap = 0)
        controls.add(plus, 44, gap = 0)
        panel.add(controls)
        update()
    }

    private fun showPresets() {
        showPanel(roomPresetPanel(this, session, ::dismissDialog), "Room presets")
    }

    private fun showResult() {
        val outcome =
            matchOutcome(
                session.snapshot,
                session.rules,
                session.localID,
                session.localID2,
                session.network.welcome?.member,
                session.online,
            )
        val winnerColor = outcome.winnerColor?.let(NativeStyle::mappedPaint) ?: accent
        val panel = column(this, 16)
        panel.add(label(this, "MATCH COMPLETE", 10f, soft, mono = true))
        panel.add(
            label(
                this,
                outcome.title,
                28f,
                if (outcome.title == "DEFEAT") danger else winnerColor,
                outcome.boldTitle,
            ),
        )
        if (outcome.detail.isNotEmpty()) panel.add(label(this, outcome.detail, 12f, winnerColor))
        currentLeaders().take(8).forEachIndexed { index, player ->
            panel.add(standingsRow(player, index + 1, localSeat(player)))
        }

        val room = session.room
        if (session.infinity) {
            panel.add(
                button(
                    this,
                    "← BACK TO ROOM",
                    {
                        dismissDialog()
                        session.lobby(endMatch = false)
                    },
                    role = "primary",
                ),
            )
        } else {
            val canRunBack =
                !session.online || session.isHost || room?.optJSONObject("matchmaking") != null
            panel.add(
                button(
                    this,
                    if (canRunBack) "RUN IT BACK ↻" else "READY FOR REMATCH",
                    {
                        dismissDialog()
                        session.restartMatch()
                    },
                    play = true,
                ),
            )
            if (session.canRestartWave)
                panel.add(
                    button(
                        this,
                        "RESTART CURRENT WAVE",
                        {
                            dismissDialog()
                            session.restartMatch(true)
                        },
                    ),
                )
        }
        if (!session.infinity || session.online) {
            if (!session.online || session.isHost && !session.infinity) {
                panel.add(
                    button(
                        this,
                        "Change mode or difficulty",
                        {
                            dismissDialog()
                            session.lobby()
                        },
                    ),
                )
            } else if (ownRoomMemberHasParty()) {
                panel.add(
                    button(
                        this,
                        "Return to party",
                        {
                            dismissDialog()
                            session.command("return_party")
                        },
                    ),
                )
            } else if (!session.isHost) {
                panel.add(
                    button(
                        this,
                        "Leave room",
                        {
                            dismissDialog()
                            session.leave()
                        },
                        danger = true,
                    ),
                )
            }
        }
        if (room != null)
            panel.add(button(this, "MATCH REPORT", { showSidebar(returnToResults = true) }))
        showPanel(panel, "Match complete")
    }

    private fun ownRoomMemberHasParty(): Boolean {
        val room = session.room ?: return false
        val id = session.network.welcome?.id ?: return false
        return listOfNotNull(room.optJSONArray("players"), room.optJSONArray("spectators")).any {
            members ->
            (0 until members.length()).any {
                members.optJSONObject(it)?.let { member ->
                    member.optInt("id", -1) == id && member.optBoolean("hasParty")
                } == true
            }
        }
    }

    private fun confirmReleaseCallsign(name: String, key: String) {
        if (!session.canImportAccount) {
            alert("Release callsign", "Return to the local room first.")
            return
        }
        AlertDialog.Builder(this)
            .setTitle("Release $name?")
            .setMessage(
                "This permanently deletes this account's score, makes its callsign available to others, and signs out its devices. Other saved accounts are kept.",
            )
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Release callsign") { _, _ ->
                val accountDialog = dialog
                session.releaseCallsign(key) { result ->
                    result
                        .onSuccess {
                            if (dialog === accountDialog) dismissDialog()
                            readySignature = ""
                            refresh(true)
                        }
                        .onFailure {
                            alert(
                                "Release callsign",
                                it.message ?: "Could not release the callsign.",
                            )
                        }
                }
            }
            .show()
    }

    private fun showAccount(seat: Int) = showAccount(seat, false)

    private fun showAccount(seat: Int, returnToPause: Boolean, onClose: (() -> Unit)? = null) {
        val origin = session.server
        val panel = column(this, 16)
        val selected = session.store.selected(origin, seat)
        val resetPending = session.accounts.pendingRotation(origin, seat) != null
        var accountDialog: AlertDialog? = null
        fun stillOpen() =
            accountDialog?.isShowing == true &&
                dialog === accountDialog &&
                session.server == origin &&
                session.store.selected(origin, seat)?.key == selected?.key
        val pilot = if (seat == 0) session.identity else "${session.localCallsign} (P2)"
        val pilotColor = paint(if (seat == 0) session.colorIndex else session.localColorIndex)
        panel.add(label(this, pilot, 12f, pilotColor, true, mono = true))
        panel.add(
            label(
                this,
                "Each local player has a separate account key. Copying, importing, or resetting this key affects only this player's account.",
                12f,
                soft,
            ),
        )
        val details =
            if (selected == null)
                "Play online to create an account. Offline callsigns are always available."
            else if (selected.registrationPending)
                "This key and callsign are saved on this device for offline play. Going online checks availability and registers them before joining."
            else
                "This key controls your callsign and public Infinity score. Copy it to another trusted device to use the same account. Keep it private."
        panel.add(label(this, details, 12f, soft))
        panel.add(
            label(
                this,
                "Each callsign has its own account and score. New callsigns start at zero. Saved callsigns let you switch back without pasting a key. Accounts expire after one month without signing in.",
                12f,
                soft,
            ),
        )
        panel.add(
            label(
                this,
                if (selected == null) "No account key saved on this device."
                else "••••••••••••••••",
                12f,
                mono = true,
            ),
        )
        panel.add(
            button(
                    this,
                    "COPY ACCOUNT KEY",
                    {
                        selected?.let { copy("leqra account key", it.key, sensitive = true) }
                    },
                )
                .apply { isEnabled = selected?.registrationPending == false && !resetPending },
        )
        val savedCallsigns = session.accounts.savedCallsigns(origin).toMutableList()
        if (selected != null && savedCallsigns.none { it.key == selected.key }) {
            savedCallsigns.add(
                0,
                AccountService.SavedCallsign(
                    if (seat == 0) session.callsign else session.localCallsign,
                    selected.key,
                ),
            )
        }
        val scoreRows = mutableListOf<Triple<String, String, TextView>>()
        savedCallsigns
            .filter { it.key != session.store.selected(origin, 1 - seat)?.key }
            .forEach { saved ->
                val score = label(this, "${saved.name}: Loading score…", 12f, soft)
                panel.add(score)
                scoreRows.add(Triple(saved.key, saved.name, score))
                panel.add(
                    button(
                            this,
                            "USE " + saved.name,
                            {
                                session.renameCallsign(saved.name, seat, validate = true)
                                dismissDialog()
                            },
                        )
                        .apply {
                            isEnabled =
                                session.canImportAccount &&
                                    !resetPending &&
                                    saved.key != selected?.key
                            if (!isEnabled) {
                                setTextColor(android.graphics.Color.parseColor("#9b9b9b"))
                                background =
                                    background(
                                        this@MainActivity,
                                        android.graphics.Color.parseColor("#292929"),
                                        6,
                                        android.graphics.Color.parseColor("#505050"),
                                    )
                                alpha = .45f
                            }
                        },
                )
                panel.add(
                    button(
                            this,
                            "RELEASE " + saved.name,
                            { confirmReleaseCallsign(saved.name, saved.key) },
                            danger = true,
                        )
                        .apply {
                            isEnabled = session.canImportAccount && !resetPending
                        },
                )
            }
        if (selected != null) {
            panel.add(
                button(
                        this,
                        "RELEASE CURRENT CALLSIGN",
                        {
                            confirmReleaseCallsign(
                                if (seat == 0) session.callsign else session.localCallsign,
                                selected.key,
                            )
                        },
                        danger = true,
                    )
                    .apply {
                        isEnabled = session.canImportAccount && !resetPending
                    },
            )
            panel.add(
                button(
                        this,
                        if (resetPending) "RETRY KEY RESET" else "RESET ACCOUNT KEY",
                        {
                            if (!session.canImportAccount) {
                                alert(
                                    "Account key",
                                    "Leave the online room before resetting the key.",
                                )
                                return@button
                            }
                            AlertDialog.Builder(this)
                                .setTitle("Reset P${seat+1} key?")
                                .setMessage(
                                    "The old key will stop working on every device. Your callsign and score stay with the new key. Copy the new key to your other devices afterwards.",
                                )
                                .setNegativeButton("Cancel", null)
                                .setPositiveButton("Reset key") { _, _ ->
                                    if (!session.canImportAccount) return@setPositiveButton
                                    runCatching {
                                        session.accounts.rotate(origin, seat) { result ->
                                            if (
                                                accountDialog?.isShowing != true ||
                                                    dialog !== accountDialog ||
                                                    session.server != origin
                                            )
                                                return@rotate
                                            result
                                                .onSuccess { recovered ->
                                                    if (recovered.promoted) {
                                                        dismissDialog()
                                                        session.leave()
                                                        showAccount(seat, returnToPause, onClose)
                                                    } else
                                                        alert(
                                                            "Replacement saved",
                                                            "A different account is selected. Review saved keys to recover the replacement.",
                                                        )
                                                }
                                                .onFailure {
                                                    showAccount(seat, returnToPause, onClose)
                                                    alert(
                                                        "Key reset",
                                                        it.message
                                                            ?: "The replacement key is saved. Retry to finish.",
                                                    )
                                                }
                                        }
                                    }
                                        .onFailure {
                                            alert("Key reset", it.message ?: "Try again.")
                                        }
                                }
                                .show()
                        },
                        danger = true,
                    )
                    .apply {
                        isEnabled = session.canImportAccount && !selected.registrationPending
                    },
            )
        }
        val activations = session.accounts.savedActivations(origin, seat)
        if (activations.isNotEmpty())
            panel.add(
                label(
                    this,
                    "A previous activation may have finished after its connection closed. You can review its saved key before choosing which account to use.",
                    11f,
                    soft,
                ),
            )
        val activationButtons = mutableListOf<Button>()
        panel.add(label(this, "IMPORT FROM ANOTHER DEVICE", 10f, muted, mono = true))
        val key =
            field(this, "", "Paste account key", 45).apply {
                inputType =
                    android.text.InputType.TYPE_CLASS_TEXT or
                        android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
                contentDescription = "Account key to import"
            }
        val canReview = session.canImportAccount && !resetPending
        key.isEnabled = canReview
        if (!canReview) {
            val reason =
                if (resetPending) "A key reset is pending. Retry reset to finish it safely."
                else "Return to the local room to import or reset a key."
            panel.add(label(this, reason, 11f, muted))
        }
        var checked: CheckedAccount? = null
        var checking = false
        var committing = false
        var previewRequest: CancelRequest? = null
        var previewRevision = 0
        val preview = label(this, "", 12f, soft)
        val checkButton = button(this, "CHECK KEY", {})
        val use = button(this, "USE THIS ACCOUNT", {}, play = true)
        fun refreshActions() {
            key.isEnabled = canReview && !committing
            checkButton.isEnabled = canReview && !checking && !committing && key.text.isNotBlank()
            use.visibility = if (checked != null) View.VISIBLE else View.GONE
            use.isEnabled = canReview && !committing
            activationButtons.forEach { it.isEnabled = canReview && !checking && !committing }
        }
        fun checkCandidate(candidate: String, saved: Boolean) {
            if (!stillOpen() || !canReview || !session.canImportAccount || checking || committing)
                return
            val revision = ++previewRevision
            checked = null
            checking = true
            preview.text = "Checking key…"
            refreshActions()
            previewRequest =
                session.accounts.inspectForSeat(origin, candidate, seat) { result ->
                    if (!stillOpen() || revision != previewRevision) return@inspectForSeat
                    checking = false
                    previewRequest = null
                    result
                        .onSuccess { verified ->
                            checked = verified
                            val name = verified.info.preferredCallsign.orEmpty()
                            val points =
                                verified.info.publicProfile?.let {
                                    "Public Infinity score: ${it.score}"
                                } ?: "No public score yet"
                            preview.text =
                                "$name\n$points\nYour current callsign and key stay saved when you select this account."
                        }
                        .onFailure {
                            preview.text =
                                if (saved)
                                    "That activation is not confirmed yet. Its key remains saved."
                                else it.message ?: "That key is unavailable."
                        }
                    refreshActions()
                }
        }
        activations.forEachIndexed { index, activation ->
            val review =
                button(
                    this,
                    "REVIEW SAVED ACTIVATION ${index + 1}",
                    { checkCandidate(activation.key, saved = true) },
                )
            activationButtons.add(review)
            panel.add(review)
        }
        panel.add(key)
        key.addTextChangedListener(
            watcher {
                previewRevision++
                previewRequest?.cancel()
                previewRequest = null
                checking = false
                checked = null
                preview.text = ""
                refreshActions()
            },
        )
        panel.add(preview)
        checkButton.setOnClickListener { checkCandidate(key.text.toString().trim(), saved = false) }
        panel.add(checkButton)
        use.setOnClickListener {
            val verified = checked ?: return@setOnClickListener
            if (!stillOpen() || !canReview || !session.canImportAccount || committing)
                return@setOnClickListener
            committing = true
            refreshActions()
            fun currentImport() = stillOpen() && checked === verified && session.canImportAccount
            session.accounts.signInChecked(
                verified,
                seat,
                if (seat == 0) session.callsign else session.localCallsign,
                canCommit = ::currentImport,
            ) { result ->
                committing = false
                // A successful import changes the selected key, so stillOpen() no longer matches.
                if (
                    accountDialog?.isShowing != true ||
                        dialog !== accountDialog ||
                        session.server != origin
                )
                    return@signInChecked
                result
                    .onSuccess { signedIn ->
                        signedIn.info.preferredCallsign?.let { name ->
                            if (seat == 0) session.callsign = name else session.localCallsign = name
                        }
                        session.accountImported(seat)
                        session.save()
                        session.leave()
                        showAccount(seat, returnToPause, onClose)
                        readySignature = ""
                        refresh(true)
                    }
                    .onFailure {
                        preview.text = it.message ?: "Unable to import the account."
                        refreshActions()
                    }
            }
        }
        panel.add(use)
        refreshActions()
        panel.add(
            label(
                this,
                "If a callsign is already yours on another device, copy its key now. Without the key, automatic recovery is impossible.",
                11f,
                muted,
            ),
        )
        panel.add(
            button(
                this,
                "GET MANUAL HELP ON GITHUB ↗",
                {
                    startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            android.net.Uri.parse("https://github.com/nhooyr/leqra/issues/new"),
                        ),
                    )
                },
            ),
        )
        showPanel(
            panel,
            "P${seat+1} account key",
            secure = true,
            afterClose = if (returnToPause) ::showMenu else onClose,
            header = panelHeader("Account key"),
        )
        val shown = dialog ?: return
        accountDialog = shown
        val pendingScores = mutableSetOf<CancelRequest>()
        val remainingScores = scoreRows.distinctBy { it.first }.iterator()
        fun accountStillOpen() =
            dialog === shown &&
                shown.isShowing &&
                session.server == origin &&
                session.store.selected(origin, seat)?.key == selected?.key
        fun loadNextScore() {
            if (!accountStillOpen() || !remainingScores.hasNext()) return
            val (accountKey, name, score) = remainingScores.next()
            var request: CancelRequest? = null
            request =
                session.accounts.inspect(origin, accountKey) { result ->
                    request?.let { pendingScores.remove(it) }
                    if (!accountStillOpen()) return@inspect
                    score.text =
                        result.fold(
                            { checked ->
                                checked.info.scoreForCallsign(name)?.let { "$name: $it points" }
                                    ?: "$name: Score unavailable"
                            },
                            { "$name: Score unavailable" },
                        )
                    loadNextScore()
                }
            request?.let { pendingScores.add(it) }
        }
        panel.addOnAttachStateChangeListener(
            object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(view: View) {}

                override fun onViewDetachedFromWindow(view: View) {
                    previewRevision++
                    previewRequest?.cancel()
                    previewRequest = null
                    pendingScores.toList().forEach { it.cancel() }
                    pendingScores.clear()
                    view.removeOnAttachStateChangeListener(this)
                }
            },
        )
        repeat(minOf(3, scoreRows.size)) { loadNextScore() }
    }

    private fun currentLeaders(): List<LeaderboardEntry> {
        val snapshot = session.snapshot
        if (snapshot.leaderboard.isNotEmpty()) return snapshot.leaderboard
        return snapshot.tanks
            .filterNot { it.survivalEnemy }
            .sortedByDescending { it.score }
            .map {
                LeaderboardEntry(
                    it.id,
                    it.name,
                    it.score,
                    it.colorIndex,
                    it.bot,
                    it.team,
                    it.difficulty,
                )
            }
    }

    private fun localSeat(entry: LeaderboardEntry): Int =
        when {
            entry.bot -> 0
            entry.id == session.localID2 && session.canControlSecondary -> 2
            entry.id == session.localID && !session.spectating -> 1
            else -> 0
        }

    private fun showSidebar(returnToResults: Boolean = false) {
        val panel = column(this, 16)
        panel.add(label(this, "Sidebar", 24f, accent, true))
        session.snapshot.matchStats?.let { report ->
            panel.add(label(this, "MATCH REPORT", 10f, accent, mono = true))
            panel.add(
                label(
                    this,
                    "${report.rounds} rounds, ${report.duration.toInt()} seconds",
                    10f,
                    muted,
                    mono = true,
                ),
            )
            report.players.forEach { player ->
                val seat = player.localSeat(session.network.welcome?.member)
                val color = NativeStyle.mappedPaint(player.color)
                val playerPanel = column(this)
                playerPanel.add(
                    row(this).apply {
                        weighted(
                            label(
                                this@MainActivity,
                                PilotIdentity.label(player.name, player.bot, seat),
                                12f,
                                color,
                                seat > 0,
                            ),
                            gap = 6,
                        )
                        add(
                            label(
                                this@MainActivity,
                                if (player.bot) "BOT" else "HUMAN PILOT",
                                10f,
                                muted,
                                mono = true,
                            ),
                            width = -2,
                            gap = 6,
                        )
                        add(
                            label(this@MainActivity, player.score.toString(), 12f, color, true),
                            width = -2,
                            gap = 0,
                        )
                    },
                    gap = 4,
                )
                playerPanel.add(
                    label(
                        this,
                        "${player.eliminations} eliminations, ${player.deaths} deaths, ${player.selfDestructs} self-destructs",
                        11f,
                        soft,
                    ),
                    gap = 3,
                )
                when (report.mode) {
                    "ctf" ->
                        playerPanel.add(
                            label(
                                this,
                                "${player.captures} captures, ${player.flagReturns} returns",
                                11f,
                                muted,
                            ),
                            gap = 0,
                        )
                    "koth" ->
                        playerPanel.add(
                            label(this, "${player.hillSeconds.toInt()}s on hill", 11f, muted),
                            gap = 0,
                        )
                }
                panel.add(playerPanel)
            }
        }
        panel.add(label(this, "LEADERBOARD", 10f, accent, mono = true))
        currentLeaders().forEachIndexed { index, player ->
            panel.add(standingsRow(player, index + 1, localSeat(player)))
        }
        appendFieldManual(panel, sidebar = true)
        panel.add(button(this, "CONTROLS", { showControls() }))
        showPanel(
            panel,
            "Sidebar",
            afterClose =
                if (returnToResults)
                    ({
                        main.post {
                            if (
                                isFinishing ||
                                    isDestroyed ||
                                    dialog != null ||
                                    session.screen != Screen.PLAYING
                            )
                                return@post
                            if (
                                session.snapshot.phase == "matchOver" ||
                                    session.snapshot.result != null
                            )
                                showResult()
                            else {
                                session.pause(false)
                                window.setImmersiveSystemBars(fullscreen)
                                arena.requestFocus()
                                refresh(false)
                            }
                        }
                    })
                else null,
        )
    }

    private fun appendFieldManual(panel: LinearLayout, sidebar: Boolean = false) {
        val infinity =
            if (session.screen == Screen.PLAYING) session.infinity
            else session.rules.infinity || session.publicSelected
        val rules = session.rules.copy(infinity = infinity)
        val world = session.snapshot.world.takeIf { session.screen == Screen.PLAYING }
        panel.add(label(this, "FIELD MANUAL", 10f, accent, mono = true))
        panel.add(label(this, "Touch", 13f, text, true))
        panel.add(
            label(
                this,
                "Drag the joystick to drive and aim. Touch near the tank to aim in place. Tap Fire to shoot, or hold it to fire continuously. Press off-center or drag Fire to aim while firing, even while driving with the joystick.",
                12f,
                soft,
            ),
        )
        if (sidebar) panel.add(label(this, "Connect a game controller to play.", 12f, soft))
        panel.add(
            label(
                this,
                if (infinity) "INFINITY" else session.modeTitle.uppercase(java.util.Locale.ROOT),
                10f,
                accent,
                mono = true,
            ),
        )
        panel.add(
            label(
                this,
                if (infinity)
                    "Gain a point for each kill and lose a point each time the tank is destroyed. Respawn after one second. Keep growing the score without a time limit."
                else modeHelp(session.mode),
                12f,
                soft,
            ),
        )
        panel.add(label(this, "POWER-UPS", 10f, accent, mono = true))
        panel.add(label(this, PowerupHelp.summary(rules, world), 12f, soft))
        for (kind in PowerupHelp.kinds) {
            val entry = column(this)
            entry.add(label(this, PowerupHelp.title(kind), 12f, text, true), gap = 3)
            entry.add(
                label(
                    this,
                    PowerupHelp.description(kind, rules, world, includeGrenadeControls = sidebar),
                    12f,
                    soft,
                ),
                gap = 0,
            )
            panel.add(entry)
        }
    }

    private fun updateScores() {
        if (!showScores) {
            scorePanel?.let(stage::removeView)
            scorePanel = null
            scores = null
            scoreSignature = ""
            return
        }
        val preview = session.screen != Screen.PLAYING
        val selecting = !preview && session.spectating && session.infinity
        val leaders =
            if (!preview) currentLeaders()
            else
                session.publicStatus?.leaders.orEmpty().map {
                    LeaderboardEntry(
                        it.id,
                        it.name,
                        it.score,
                        it.colorIndex,
                        it.bot,
                        difficulty = it.difficulty,
                    )
                }
        val signature =
            "${stage.width}:${stage.height}:$safeLeft:$safeRight:$preview:$selecting:${session.localID}:${session.localID2}:${session.followingID}:$leaders"
        if (scores != null && signature == scoreSignature) return
        scoreSignature = signature
        val previousScroll = scores?.scrollY ?: 0
        scorePanel?.let(stage::removeView)
        scorePanelBuilds++
        val panel =
            object : LinearLayout(this) {
                    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                        val maxHeight = minOf(MeasureSpec.getSize(heightMeasureSpec), dp(330))
                        super.onMeasure(
                            widthMeasureSpec,
                            MeasureSpec.makeMeasureSpec(maxHeight, MeasureSpec.AT_MOST),
                        )
                    }
                }
                .apply {
                    orientation = LinearLayout.VERTICAL
                    background = background(this@MainActivity, surface, 8)
                }
        panel.add(
            button(
                    this,
                    "LEADERBOARD  ⌃",
                    {
                        showScores = false
                        updateScores()
                    },
                    role = "text",
                )
                .apply {
                    contentDescription = "Close leaderboard"
                    setTextColor(accent)
                    gravity = Gravity.CENTER_VERTICAL or Gravity.START
                },
            gap = 0,
        )
        val list = column(this, 6)
        if (leaders.isEmpty()) list.add(label(this, "No tanks yet", 12f, soft), gap = 0)
        (if (selecting) leaders else leaders.take(10)).forEachIndexed { index, player ->
            val following = selecting && player.id == session.followingID
            list.add(
                standingsRow(player, index + 1, if (preview) 0 else localSeat(player), following)
                    .apply {
                        if (selecting) {
                            minimumHeight = dp(44)
                            setPadding(dp(6), dp(6), dp(6), dp(6))
                            contentDescription = "Follow ${player.name}"
                            isClickable = true
                            setOnClickListener {
                                session.followTank(player.id)
                                if (
                                    resources.configuration.orientation !=
                                        Configuration.ORIENTATION_LANDSCAPE
                                ) {
                                    showScores = false
                                    updateScores()
                                }
                            }
                            if (following) setBackgroundColor(raised)
                        }
                    },
                gap = 3,
            )
        }
        val scroll =
            ScrollView(this).apply {
                contentDescription = "Leaderboard list"
                addView(list)
                post { scrollTo(0, previousScroll) }
            }
        panel.addView(scroll, LinearLayout.LayoutParams(-1, -2, 1f))
        if (selecting)
            panel.add(
                label(this, "Tap a tank to follow", 11f, soft).apply {
                    setPadding(dp(10), dp(4), dp(10), dp(4))
                },
                gap = 0,
            )
        panel.add(
            label(this, "+1 per kill, -1 per death", 11f, soft).apply {
                setPadding(dp(10), dp(4), dp(10), dp(8))
            },
            gap = 0,
        )
        scores = scroll
        scorePanel = panel
        val margin = dp(10)
        val width =
            (stage.width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels) -
                safeLeft -
                safeRight -
                2 * margin
        stage.addView(
            panel,
            FrameLayout.LayoutParams(
                    minOf(dp(if (selecting) 245 else 205), width.coerceAtLeast(0)),
                    -2,
                    Gravity.TOP or Gravity.END,
                )
                .apply { setMargins(margin + safeLeft, margin, margin + safeRight, margin) },
        )
    }

    private fun standingsRow(
        entry: LeaderboardEntry,
        rank: Int,
        seat: Int = 0,
        following: Boolean = false,
    ): LinearLayout {
        val name = PilotIdentity.leaderboardLabel(entry.name, entry.bot, seat)
        val difficulty =
            PilotIdentity.leaderboardDifficulty(entry.name, entry.bot, entry.difficulty)
        val difficultyTitle = difficulty?.let(BotDifficulty::title)
        val identity = column(this, 0)
        identity.add(label(this, "$rank. $name", 12f, paint(entry.colorIndex), seat > 0), gap = 0)
        if (difficultyTitle != null)
            identity.add(
                label(
                    this,
                    difficultyTitle.uppercase(java.util.Locale.ROOT),
                    10f,
                    muted,
                    mono = true,
                ),
                gap = 0,
            )
        if (following) identity.add(label(this, "FOLLOWING", 10f, accent, mono = true), gap = 0)
        return row(this).apply {
            weighted(identity, gap = 8)
            addView(
                label(
                    this@MainActivity,
                    entry.score.toString(),
                    12f,
                    paint(entry.colorIndex),
                    bold = true,
                ),
            )
            contentDescription =
                "$rank. $name" + (difficultyTitle?.let { ", $it" } ?: "") + ", score ${entry.score}"
        }
    }

    private fun showQueues() {
        shownQueuePacket = null
        queueDialog = true
        val panel = column(this, 16)
        panel.add(label(this, "FIND A MATCH.", 24f, accent, true))
        panel.add(label(this, "Loading queues…", 12f, soft))
        showPanel(panel, "Matchmaking")
        queueDialog = true
    }

    private var shownQueuePacket: String? = null

    private fun updateQueueDialog() {
        val packet = session.queuePacket
        val room = session.room
        val queue =
            room?.optJSONObject("queue").takeUnless {
                packet?.optString("type") == "queue_cancelled"
            }
        if (packet == null && queue == null) return
        val signature =
            "$packet:$queue:${session.isHost}:${room?.optString("phase")}:${room?.optBoolean("infinityActive")}"
        if (signature == shownQueuePacket) return
        shownQueuePacket = signature
        val panel = column(this, 16)
        panel.add(label(this, "FIND A MATCH.", 24f, accent, true))
        if (queue != null) {
            panel.add(label(this, queue.optString("name"), 18f, accent, true))
            panel.add(
                label(
                    this,
                    "${queue.optInt("players")} / ${queue.optInt("required")} players, ${queue.optString("stage")}",
                    12f,
                    soft,
                ),
            )
            val member = session.network.welcome?.member
            val members = queue.optJSONArray("members")?.objects().orEmpty()
            var participating = false
            var waiting = false
            members.forEach { entry ->
                val local = entry.optLong("controller") == member
                val accepted = entry.optBoolean("accepted")
                val seat = if (!local) 0 else if (entry.optString("kind") == "local") 2 else 1
                val name =
                    PilotIdentity.label(
                        entry.optString("name"),
                        entry.optString("kind") == "bot",
                        seat,
                    )
                panel.add(
                    row(this).apply {
                        weighted(label(this@MainActivity, name, 12f, bold = local))
                        addView(
                            label(
                                this@MainActivity,
                                if (accepted) "READY" else "WAITING",
                                12f,
                                soft,
                            ),
                        )
                    },
                )
                participating = participating || local
                waiting = waiting || local && !accepted
            }
            val id = queue.optLong("id")
            if (queue.optString("stage") == "confirming" && waiting)
                panel.add(
                    button(
                        this,
                        "READY",
                        { session.command("queue_accept", "queueId" to id, "ready" to true) },
                        play = true,
                    ),
                )
            if (session.isHost || participating)
                panel.add(
                    button(
                        this,
                        "CANCEL SEARCH",
                        { session.command("queue_cancel", "queueId" to id) },
                    ),
                )
        } else {
            val canQueue =
                room != null &&
                    session.isHost &&
                    room.optString("phase") in setOf("lobby", "matchOver") &&
                    !room.optBoolean("infinityActive") &&
                    room.isNull("matchmaking") &&
                    room.optString("awayMatch").isEmpty()
            packet?.optJSONArray("queues")?.objects().orEmpty().forEach { listing ->
                val definition = listing.optJSONObject("definition") ?: return@forEach
                val details =
                    "${listing.optInt("waitingPlayers")} waiting, ${definition.optInt("cols")} × ${definition.optInt("rows")} maze"
                panel.add(
                    button(
                            this,
                            "${definition.optString("name")}\n$details",
                            {
                                session.command(
                                    "queue_join",
                                    "queue" to definition.optString("key"),
                                )
                            },
                        )
                        .apply {
                            isEnabled = canQueue
                            alpha = if (isEnabled) 1f else .45f
                        },
                )
            }
        }
        packet?.optString("message")?.takeIf(String::isNotBlank)?.let {
            panel.add(label(this, it, 12f, soft))
        }
        dialog?.setOnDismissListener(null)
        dialog?.dismiss()
        dialog = null
        showPanel(panel, "Matchmaking")
        queueDialog = true
    }

    private fun toggleSound() {
        session.muted = !session.muted
        session.save()
        refresh(false)
        if (!session.muted) previewAudio(AudioCue.UNMUTE)
    }

    private fun previewAudio(cue: AudioCue) {
        if (session.screen == Screen.PLAYING && !session.paused) audio.play(cue)
        else audio.preview(cue)
    }

    private fun showQuickTour() {
        if (quickTourDialog != null) return
        val shown = QuickTour(this, session.highRefresh, session.gamepadSupport, ::previewAudio)
        quickTourDialog = shown
        shown.updateGamepads(gamepadIDs)
        // Keep a static backdrop while the dialog owns the interactive arena.
        if (arena.renderedFrames == 0L)
            arena.submit(
                session.snapshot,
                session.localID,
                session.maze,
                session.localID2,
                session.online,
            )
        arena.pause()
        fpsStarted = 0L
        frameCount = 0
        shown.setOnCancelListener {
            getSharedPreferences("leqra-settings", MODE_PRIVATE)
                .edit()
                .putBoolean(QUICK_TOUR_SEEN, true)
                .apply()
        }
        shown.setOnDismissListener {
            if (quickTourDialog === shown) {
                quickTourDialog = null
                if (foreground && !isFinishing && !isDestroyed) arena.start()
            }
        }
        shown.show()
        shown.resize()
    }

    private fun panelHeader(title: String) =
        row(this).apply {
            setPadding(dp(16), dp(10), dp(10), dp(4))
            weighted(
                label(this@MainActivity, title, 23f, bold = true).apply {
                    if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
                },
            )
            add(
                button(this@MainActivity, "×", ::dismissDialog, role = "text").apply {
                    textSize = 22f
                    contentDescription = "Close $title"
                },
                width = 44,
                height = 44,
                gap = 0,
            )
        }

    private fun showPanel(
        panel: LinearLayout,
        title: String,
        secure: Boolean = false,
        afterClose: (() -> Unit)? = null,
        header: View? = null,
    ) {
        val openingScreen = session.screen
        focusSuspendedPlay = false
        settingsVersionLabel = null
        dialog?.dismiss()
        clearHeldControls()
        if (session.screen == Screen.PLAYING) session.pause(true) else session.neutral()
        val scroll =
            ScrollView(this).apply {
                addView(panel)
                setBackgroundColor(surface)
            }
        val content =
            if (header == null) scroll
            else
                column(this).apply {
                    add(header, gap = 0)
                    add(
                        View(this@MainActivity).apply { setBackgroundColor(NativeStyle.edge) },
                        height = 1,
                        gap = 0,
                    )
                    addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
                }
        dialog =
            AlertDialog.Builder(this)
                .setView(content)
                .apply { if (header == null) setNegativeButton("CLOSE", null) }
                .create()
                .also { shown ->
                    shown.setOnDismissListener {
                        if (dialog !== shown) return@setOnDismissListener
                        dialog = null
                        settingsVersionLabel = null
                        queueDialog = false
                        if (isFinishing || isDestroyed) return@setOnDismissListener
                        if (afterClose != null && session.screen == openingScreen) {
                            afterClose()
                            return@setOnDismissListener
                        }
                        if (session.screen == Screen.PLAYING && session.paused) session.pause(false)
                        window.setImmersiveSystemBars(fullscreen)
                        if (session.screen == Screen.PLAYING) arena.requestFocus()
                        refresh(false)
                    }
                    shown.show()
                    shown.window?.setTitle(title)
                    shown.window?.setBackgroundDrawable(background(this, surface, 13))
                    shown.window?.setLayout(
                        minOf(resources.displayMetrics.widthPixels - dp(24), dp(540)),
                        minOf(resources.displayMetrics.heightPixels - dp(48), dp(760)),
                    )
                    if (secure) shown.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
        arena.showControls = false
    }

    private fun dismissDialog() {
        dialog?.dismiss()
        queueDialog = false
        session.neutral()
        refresh(false)
    }

    private fun applyFullscreen() {
        window.setImmersiveSystemBars(fullscreen)
        root.requestApplyInsets()
        refresh(false)
    }

    private fun alert(title: String, message: String) {
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton("OK", null)
            .show()
    }

    private fun prompt(title: String, value: String, limit: Int, onValue: (String) -> Unit) {
        val field = field(this, value, title, limit)
        AlertDialog.Builder(this)
            .setTitle(title)
            .setView(column(this, 16).apply { add(field) })
            .setNegativeButton("Cancel", null)
            .setPositiveButton("OK") { _, _ -> onValue(field.text.toString().trim()) }
            .show()
    }

    private fun copy(label: String, value: String, sensitive: Boolean = false) {
        val clipboard = getSystemService(ClipboardManager::class.java)
        val clip = ClipData.newPlainText(label, value)
        if (sensitive && Build.VERSION.SDK_INT >= 33)
            clip.description.extras =
                android.os.PersistableBundle().apply {
                    putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
        clipboard.setPrimaryClip(clip)
        Toast.makeText(
                this,
                if (sensitive) "Account key copied. Keep it private." else "Copied",
                Toast.LENGTH_SHORT,
            )
            .show()
        if (sensitive)
            main.postDelayed(
                {
                    if (clipboard.primaryClip?.getItemAt(0)?.text?.toString() == value) {
                        if (Build.VERSION.SDK_INT >= 28) clipboard.clearPrimaryClip()
                        else clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                    }
                },
                600_000,
            )
    }

    private fun choice(values: List<String>, selected: Int, onSelect: (Int) -> Unit) =
        Spinner(this).apply {
            adapter =
                object :
                        ArrayAdapter<String>(
                            this@MainActivity,
                            android.R.layout.simple_spinner_item,
                            values,
                        ) {
                        override fun getView(
                            position: Int,
                            convertView: View?,
                            parent: ViewGroup,
                        ): View =
                            (super.getView(position, convertView, parent) as TextView).apply {
                                setTextColor(NativeStyle.text)
                                textSize = 13f
                                minHeight = dp(44)
                                gravity = Gravity.CENTER_VERTICAL
                            }

                        override fun getDropDownView(
                            position: Int,
                            convertView: View?,
                            parent: ViewGroup,
                        ): View =
                            (super.getDropDownView(position, convertView, parent) as TextView)
                                .apply {
                                    setTextColor(NativeStyle.text)
                                    setBackgroundColor(raised)
                                    textSize = 13f
                                    minHeight = dp(44)
                                }
                    }
                    .apply {
                        setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
                    }
            setSelection(selected, false)
            var previousSelection = selected
            onItemSelectedListener =
                object : AdapterView.OnItemSelectedListener {
                    override fun onNothingSelected(parent: AdapterView<*>?) {}

                    override fun onItemSelected(
                        parent: AdapterView<*>?,
                        view: View?,
                        position: Int,
                        id: Long,
                    ) {
                        if (position != previousSelection) {
                            previousSelection = position
                            onSelect(position)
                        }
                    }
                }
        }

    private fun watcher(change: (String) -> Unit) =
        object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}

            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                change(s?.toString() ?: "")
            }

            override fun afterTextChanged(s: Editable?) {}
        }

    private fun hideKeyboard() {
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(
            currentFocus?.windowToken,
            0,
        )
        currentFocus?.clearFocus()
    }

    private fun modeHelp(value: String) =
        when (value) {
            "infinity" -> "An endless tank arena. +1 per kill, −1 per death."
            "ctf" -> "Carry the enemy flag home while your home flag is safe."
            "koth" -> "Hold the hill for points. Contested hills score nothing."
            "survival" -> "One squad against waves of enemy tanks. Survive together."
            else -> "Last side standing wins a round. A fresh maze every round."
        }

    @Suppress("DEPRECATION")
    @android.annotation.SuppressLint(
        "GestureBackNavigation",
    ) // API33+ uses the dispatcher registered in onCreate; this is only the API26–32 fallback.
    @Deprecated("Handled with OnBackInvokedDispatcher on Android 13+")
    override fun onBackPressed() {
        handleBack()
    }

    private fun handleBack() {
        if (showcaseDialog != null) return
        if (dialog != null) dismissDialog()
        else if (session.screen == Screen.PLAYING) showMenu()
        else if (session.screen == Screen.CONNECTING || session.online) session.leave()
        else super.onBackPressed()
    }

    @android.annotation.SuppressLint(
        "GestureBackNavigation",
    ) // Preview's API33+ dispatcher consumes Back; this covers older keyboards.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        showcaseDialog?.let { shown ->
            if (event.keyCode == KeyEvent.KEYCODE_BACK) return true
            if (event.keyCode == KeyEvent.KEYCODE_ESCAPE) {
                if (event.action == KeyEvent.ACTION_UP) shown.dismiss()
                return true
            }
            if (isGameKey(event.keyCode) || event.keyCode == KeyEvent.KEYCODE_BUTTON_START)
                return true
        }
        // Route paired controls before the focused arena's single-seat fallback.
        if (
            ::session.isInitialized &&
                session.screen == Screen.PLAYING &&
                dialog == null &&
                (isGameKey(event.keyCode) ||
                    event.keyCode == KeyEvent.KEYCODE_ESCAPE ||
                    event.keyCode == KeyEvent.KEYCODE_BUTTON_START)
        )
            return if (event.action == KeyEvent.ACTION_DOWN) onKeyDown(event.keyCode, event)
            else onKeyUp(event.keyCode, event)
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (
            ::session.isInitialized &&
                session.screen == Screen.PLAYING &&
                dialog == null &&
                event.isGamepadMotion()
        ) {
            syncControlSeats()
            val gamepad =
                gamepads.inputForDevice(
                    event.deviceId,
                    controlOwner != null,
                    controlLocalOwner != null,
                )
            if (gamepad != null) {
                gamepad.motion(event)
                keyboardInput()
            }
            return true
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (session.screen != Screen.PLAYING || dialog != null)
            return super.onKeyDown(keyCode, event)
        syncControlSeats()
        if (keyCode == KeyEvent.KEYCODE_ESCAPE) {
            if (event.repeatCount == 0) showMenu()
            return true
        }
        if (event.isGamepad() && keyCode == KeyEvent.KEYCODE_BUTTON_START) {
            if (
                event.repeatCount == 0 &&
                    gamepads.inputForDevice(
                        event.deviceId,
                        controlOwner != null,
                        controlLocalOwner != null,
                    ) != null
            )
                showMenu()
            return true
        }
        if (keyCode in GamepadInput.keys && event.isGamepad()) {
            gamepadKey(event, down = true)
            return true
        }
        if (keyCode in session.keyboardBindings) {
            if (event.repeatCount > 0 && keyCode !in pressed) return true
            if (event.isCtrlPressed || event.isAltPressed || event.isMetaPressed)
                return super.onKeyDown(keyCode, event)
            pressed.add(keyCode)
            keyboardInput()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (::session.isInitialized) syncControlSeats()
        if (keyCode in GamepadInput.keys && event.isGamepad()) {
            gamepadKey(event, down = false)
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_BUTTON_START && event.isGamepad()) return true
        if (pressed.remove(keyCode)) {
            keyboardInput()
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun gamepadKey(event: KeyEvent, down: Boolean) {
        val gamepad =
            gamepads.inputForDevice(event.deviceId, controlOwner != null, controlLocalOwner != null)
                ?: return
        gamepad.key(event.keyCode, down, event.repeatCount > 0)
        keyboardInput()
    }

    private fun isGameKey(code: Int) = code in GamepadInput.keys || code in session.keyboardBindings

    private fun keyboardInput() {
        session.input = combinedInput(false)
        if (session.localID2 != null) session.input2 = combinedInput(true)
    }

    private fun combinedInput(local: Boolean): GameInput {
        val paired = session.localID2 != null
        val keyboardSeat = local == paired
        val controls =
            if (keyboardSeat) session.keyboardBindings.input(pressed)
            else GameInput(touchAim = false)
        val gamepad =
            gamepads.inputForSeat(
                if (local) 1 else 0,
                controlOwner != null,
                controlLocalOwner != null,
            )
        gamepad?.merge(controls)
        val analog = hypot(controls.stickX, controls.stickY) > .1
        if (
            !local &&
                (controls.forward || controls.reverse || controls.left || controls.right || analog)
        )
            arena.clearDirectAim()
        val touch = if (local) null else arena.input
        val touchActive = touch != null && hypot(touch.stickX, touch.stickY) > .1
        val mouse = if (keyboardSeat) arena.mouseInput() else null
        if (touch != null) {
            controls.fire = controls.fire || touch.fire
            controls.aimX = touch.aimX
            controls.aimY = touch.aimY
        }
        if (mouse != null) {
            controls.fire = controls.fire || mouse.fire
            if (
                !touchActive &&
                    !analog &&
                    gamepad?.left != true &&
                    gamepad?.right != true &&
                    hypot(controls.aimX, controls.aimY) <= .1
            ) {
                controls.aimX = mouse.aimX
                controls.aimY = mouse.aimY
            }
        }
        if (touchActive && touch != null) {
            controls.stickX = touch.stickX
            controls.stickY = touch.stickY
            controls.touchAim = true
            controls.aimOnly = touch.aimOnly
            controls.snapAim = touch.snapAim
        }
        return controls
    }

    companion object {
        private const val CALLSIGN_TAKEN_HINT =
            "Used online; offline is OK.\nYours? Import account key\nGenerate random?"
    }
}
