package com.leqra.android

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.*
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
import kotlin.math.max
import org.json.JSONArray
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
            if (infinityBotDifficulty !in BotDifficulty.names)
                infinityBotDifficulty = "normal"
        }
}

/** Native Android UI. The arena uses Canvas, PCM audio and Kotlin physics, with no web runtime. */
class MainActivity : Activity() {
    private lateinit var session: GameSession
    private lateinit var audio: NativeAudio
    private lateinit var arena: NativeArenaView
    private lateinit var root: LinearLayout
    private lateinit var stage: FrameLayout
    private lateinit var header: LinearLayout
    private lateinit var statusLine: NativeStatusView
    private lateinit var objectiveLine: TextView
    private lateinit var loadout: NativeHudView
    private lateinit var soundButton: Button
    private lateinit var menuButton: Button
    private lateinit var chatButton: Button
    private lateinit var brandSubtitle: TextView
    private lateinit var brandMark: View
    private var readyScroll: ScrollView? = null
    private var connecting: LinearLayout? = null
    private var scores: View? = null
    private var dialog: AlertDialog? = null
    private var readySignature = ""
    private var settingsOpen = false
    private var playersOpen = false
    private var showScores = false
    private var foreground = false
    private var feedback = arrayOfNulls<TextView>(2)
    private var availability: CancelRequest? = null
    private var availabilityEpoch = 0L
    private val main = Handler(Looper.getMainLooper())
    private var safeLeft = 0
    private var safeRight = 0
    private var safeTop = 0
    private var safeBottom = 0
    private val pressed = mutableSetOf<Int>()

    private data class ControllerState(
        var x: Double = 0.0,
        var y: Double = 0.0,
        var trigger: Boolean = false,
        val buttons: MutableSet<Int> = mutableSetOf(),
    )

    private val controllers = mutableMapOf<Int, ControllerState>()
    private var frameCount = 0
    private var fpsStarted = 0L
    private var fps = 0
    private var queueDialog = false
    private var lastResultKey: String? = null
    private var chatHistory: TextView? = null
    private var scoreSignature = ""
    private var chatSignature = ""
    private var loadoutLayoutKey = ""
    private var refreshRateKey = ""
    private var previousPlaying = false
    private var focusSuspendedPlay = false
    private var keepAwake: Boolean? = null
    private var soundState: Boolean? = null
    private var readyPlay: Button? = null
    private var readyStatus: TextView? = null
    private val callsignFields = arrayOfNulls<EditText>(2)
    internal var scorePanelBuilds = 0L
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        immersive()
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
            dialog?.dismiss()
            dialog = null
            queueDialog = false
            alert("leqra", message)
        }
        session.notifyChat = { audio.notifyChat() }
        buildShell()
        if (Build.VERSION.SDK_INT >= 33)
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) {
                handleBack()
            }
        intent.data?.getQueryParameter("room")?.takeIf { it.length <= 32 }?.let {
            session.join(it, intent.data?.getQueryParameter("spectate") == "1")
        }
    }

    private fun immersive() {
        val decor =
            window
                .decorView // Create DecorView before asking PhoneWindow for its insets controller.
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            decor.windowInsetsController?.apply {
                hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
        if (Build.VERSION.SDK_INT >= 28)
            window.attributes =
                window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
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
            immersive()
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
        readySignature = ""
        scoreSignature = ""
        refreshRateKey = ""
        loadoutLayoutKey = ""
        if (::root.isInitialized) root.requestApplyInsets()
        refresh(true)
    }

    override fun onResume() {
        super.onResume()
        foreground = true
        if (::arena.isInitialized) {
            session.foreground()
            arena.start()
            refresh(true)
        }
    }

    override fun onPause() {
        foreground = false
        availability?.cancel()
        if (::arena.isInitialized) {
            pressed.clear()
            controllers.clear()
            session.background()
            arena.pause()
            audio.pause()
        }
        super.onPause()
    }

    override fun onDestroy() {
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
        header = row(this).apply { setPadding(dp(12), dp(5), dp(8), dp(5)) }
        val brand = row(this).apply { setPadding(0, 0, dp(8), 0) }
        brandMark = NativeStyle.tankMark(this)
        brand.add(brandMark, 32, 32, gap = 0)
        val names = column(this).apply { setPadding(dp(7), 0, 0, 0) }
        names.add(
            label(this, "leqra", 17f, text, true).apply { contentDescription = "leqra" },
            gap = 3,
        )
        brandSubtitle = label(this, "TANK ARENA", 10f, muted, mono = true)
        names.add(brandSubtitle, gap = 0)
        brand.add(names, width = -2, gap = 0)
        header.add(brand, width = -2, gap = 0)
        header.add(
            label(this, "v${BuildConfig.VERSION_NAME}", 10f, muted, mono = true).apply {
                contentDescription = "View leqra on GitHub"
                setPadding(dp(6), dp(7), dp(6), dp(7))
                background = background(this@MainActivity, surface, 8, 0xff34434a.toInt())
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            android.net.Uri.parse("https://github.com/nhooyr/leqra"),
                        ),
                    )
                }
            },
            width = -2,
            gap = 0,
        )
        header.addView(View(this), LinearLayout.LayoutParams(0, 0, 1f))
        chatButton =
            compactButton("") { showChat() }
                .apply {
                    contentDescription = "Chat"
                    visibility = View.GONE
                    setCompoundDrawablesWithIntrinsicBounds(
                        NativeStyle.icon(this@MainActivity, "chat"),
                        null,
                        null,
                        null,
                    )
                }
        header.add(chatButton, 40, gap = 0)
        soundButton = compactButton("SFX") { toggleSound() }
        header.add(soundButton, 44, gap = 0)
        menuButton = compactButton("☰") { showMenu() }.apply { contentDescription = "Open menu" }
        header.add(menuButton, 44, gap = 0)
        root.add(header, gap = 0)
        statusLine =
            NativeStatusView(this) {
                showScores = !showScores
                updateScores()
            }
        root.add(statusLine, gap = 0)
        objectiveLine =
            label(this, "", 10f, soft, mono = true).apply {
                setPadding(dp(12), dp(5), dp(12), dp(5))
                setBackgroundColor(surface)
                visibility = View.GONE
            }
        root.add(objectiveLine, gap = 0)
        stage = FrameLayout(this).apply { setBackgroundColor(sunken) }
        root.addView(stage, LinearLayout.LayoutParams(-1, 0, 1f))
        arena = NativeArenaView(this)
        arena.contentDescription = "Tank arena, joystick on the left and fire on the right"
        stage.addView(arena, FrameLayout.LayoutParams(-1, -1))
        arena.onFrame = { nanos ->
            session.frame(nanos)
            if (::loadout.isInitialized && session.screen == Screen.PLAYING)
                arena.fireProgress = loadout.advance(nanos)
            if (fpsStarted == 0L) fpsStarted = nanos
            frameCount++
            if (nanos - fpsStarted >= 1_000_000_000) {
                fps = (frameCount * 1e9 / (nanos - fpsStarted)).toInt()
                frameCount = 0
                fpsStarted = nanos
            }
        }
        arena.onInput = { session.input = it }
        session.present = { snapshot, maze, localID, localID2, online ->
            arena.encounterNotice = session.encounterNotice
            arena.followingID = session.followingID.takeIf { session.spectating }
            arena.submit(snapshot, localID, maze, localID2, online)
            if (session.audioSceneActive)
                audio.consume(snapshot, if (session.spectating) -1 else localID, session.infinity, online)
            audio.updateStarman(snapshot, localID, localID2, session.audioGameplayActive, session.audioSceneActive)
        }
        loadout = NativeHudView(this)
        loadout.onHeightChanged = { height ->
            if (loadout.parent === stage) arena.overlayHudHeightDp = height
        }
        root.add(loadout, gap = 0)
        root.setOnApplyWindowInsetsListener { _, insets ->
            val oldLeft = safeLeft
            val oldRight = safeRight
            val oldTop = safeTop
            val oldBottom = safeBottom
            if (Build.VERSION.SDK_INT >= 30) {
                val cuts = insets.getInsets(WindowInsets.Type.displayCutout())
                val gestures = insets.getInsets(WindowInsets.Type.systemGestures())
                safeLeft = cuts.left
                safeRight = cuts.right
                safeTop = cuts.top
                safeBottom = max(cuts.bottom, gestures.bottom)
            } else if (Build.VERSION.SDK_INT >= 28) {
                safeLeft = insets.displayCutout?.safeInsetLeft ?: 0
                safeRight = insets.displayCutout?.safeInsetRight ?: 0
                safeTop = insets.displayCutout?.safeInsetTop ?: 0
                safeBottom = insets.displayCutout?.safeInsetBottom ?: 0
            }
            root.setPadding(0, safeTop, 0, 0)
            header.setPadding(dp(12) + safeLeft, dp(5), dp(8) + safeRight, dp(5))
            loadoutLayoutKey = ""
            configureLoadoutLayout()
            if (oldLeft != safeLeft || oldRight != safeRight || oldTop != safeTop || oldBottom != safeBottom) {
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
        if (soundState != session.muted) {
            soundState = session.muted
            soundButton.text = ""
            soundButton.setCompoundDrawablesWithIntrinsicBounds(
                NativeStyle.icon(this, if (session.muted) "muted" else "sound"),
                null,
                null,
                null,
            )
            soundButton.contentDescription = if (session.muted) "Unmute sound" else "Mute sound"
            audio.enabled = !session.muted
        }
        audio.volume = session.volume
        audio.updateStarman(session.snapshot, session.localID, session.localID2, session.audioGameplayActive, session.audioSceneActive)
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        brandSubtitle.visibility = if (landscape) View.GONE else View.VISIBLE
        brandMark.visibility =
            if (resources.configuration.screenWidthDp < 375) View.GONE else View.VISIBLE
        chatButton.visibility = if (session.room != null) View.VISIBLE else View.GONE
        val playing = session.screen == Screen.PLAYING
        if (!playing && previousPlaying) showScores = false
        menuButton.value(if (playing) "Ⅱ" else "☰")
        val awake = playing && !session.paused
        arena.controlsLayout = playing && !session.spectating
        arena.showControls = awake && dialog == null && !session.spectating
        arena.keepScreenOn = awake
        if (keepAwake != awake) {
            keepAwake = awake
            if (awake) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        configureLoadoutLayout()
        loadout.visibility = if (playing && !session.spectating) View.VISIBLE else View.GONE
        statusLine.update(session, fps)
        val objective = if (playing) objectiveText().removePrefix("\n") else ""
        objectiveLine.value(objective)
        objectiveLine.visibility = if (objective.isEmpty()) View.GONE else View.VISIBLE
        if (playing) {
            val entering = !previousPlaying
            if (entering && session.spectating) showScores = true
            if (readyScroll != null || connecting != null) hideKeyboard()
            readyScroll?.let(stage::removeView)
            readyScroll = null
            readySignature = ""
            connecting?.let(stage::removeView)
            connecting = null
            if (entering && dialog == null) arena.requestFocus()
            loadout.update(
                session.snapshot,
                session.localID,
                session.localID2,
                session.infinity,
                session.paused,
                session.online,
            )
            arena.fireLabel = loadout.fireLabel
            arena.fireHint = loadout.fireHint
            arena.fireAvailable = loadout.fireAvailable
            val ended = session.snapshot.phase == "matchOver" || session.snapshot.result != null
            if (!ended) lastResultKey = null
            else {
                val resultKey =
                    "${session.snapshot.generation}:${session.snapshot.round}:${session.snapshot.winner}:${session.snapshot.result}:${session.snapshot.scores}"
                if (dialog == null && lastResultKey != resultKey) {
                    lastResultKey = resultKey
                    showResult()
                }
            }
        } else if (session.screen == Screen.CONNECTING) {
            readyScroll?.let(stage::removeView)
            readyScroll = null
            readySignature = ""
            if (connecting == null) {
                connecting =
                    column(this, 24).apply {
                        gravity = Gravity.CENTER
                        add(label(this@MainActivity, "CONNECTING.", 28f, accent, true))
                        add(ProgressBar(this@MainActivity), 56, 56)
                        add(button(this@MainActivity, "← BACK TO THE ROOM", { session.leave() }))
                    }
                stage.addView(connecting, FrameLayout.LayoutParams(-1, -1))
            }
        } else {
            connecting?.let(stage::removeView)
            connecting = null
            if (structural || readyScroll == null) {
                val signature =
                    "${session.server}|${resources.configuration.orientation}|${session.online}|${session.room?.toString()}|${session.mode}|${session.publicSelected}|$settingsOpen|$playersOpen|${session.localSelected}|${session.localBots}|${session.localTeam}:${session.secondLocalTeam}"
                if (signature != readySignature || readyScroll == null) {
                    readySignature = signature
                    buildReadyRoom()
                }
            }
        }
        if (!playing) updateReadyActions()
        previousPlaying = playing
        if (showScores) updateScores()
        chatHistory?.let { history ->
            val key = "${session.chat.size}:${session.chat.lastOrNull()}"
            if (key != chatSignature) {
                chatSignature = key
                history.value(session.chat.joinToString("\n"))
            }
        }
        if (queueDialog) updateQueueDialog()
        applyRefreshRate()
    }

    private fun configureLoadoutLayout() {
        if (!::loadout.isInitialized) return
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val embedded = session.screen == Screen.PLAYING && !session.infinity && !landscape
        val key = "$embedded:$landscape:$safeLeft:$safeRight:$safeBottom"
        if (key == loadoutLayoutKey) return
        loadoutLayoutKey = key
        loadout.compact = landscape
        loadout.safeLeft = safeLeft
        loadout.safeRight = safeRight
        loadout.safeBottom = if (embedded) 0 else safeBottom
        val parent = if (embedded) stage else root
        if (loadout.parent !== parent) {
            (loadout.parent as? ViewGroup)?.removeView(loadout)
            if (embedded)
                stage.addView(
                    loadout,
                    FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply {
                        bottomMargin = dp(119) + safeBottom
                    },
                )
            else root.add(loadout, gap = 0)
        } else if (embedded) {
            (loadout.layoutParams as FrameLayout.LayoutParams).apply {
                bottomMargin = dp(119) + safeBottom
                loadout.layoutParams = this
            }
        }
        arena.overlayHudHeightDp =
            if (embedded)
                (loadout.measuredHeight.takeIf { it > 0 }?.div(resources.displayMetrics.density)
                    ?: 97f)
            else 0f
        arena.safeInsets(safeLeft, 0, safeRight, if (embedded) safeBottom else 0)
        loadout.requestLayout()
        loadout.invalidate()
    }

    private fun clearHeldControls() {
        pressed.clear()
        controllers.clear()
        session.neutral()
    }

    private fun TextView.value(value: CharSequence) {
        if (!android.text.TextUtils.equals(text, value)) text = value
    }

    private fun objectiveText(): String {
        val o = session.snapshot.objectives ?: return ""
        return when (o.mode) {
            "survival" ->
                o.survival?.let { "\nWAVE ${it.wave} · ${it.enemiesRemaining} ENEMIES" } ?: ""
            "ctf" ->
                "\n" +
                    o.flags.joinToString(" · ") {
                        "TEAM ${it.team}: ${if(it.home) "FLAG HOME" else if(it.carrier>=0) "CARRIED" else "DROPPED"}"
                    }
            "koth" ->
                "\n" +
                    if (o.contested) "HILL CONTESTED"
                    else if (o.owner > 0) "TEAM ${o.owner} HOLDS THE HILL"
                    else if (o.owner < 0)
                        "${session.snapshot.tanks.firstOrNull { it.id == -o.owner - 1 }?.name ?: "Tank"} HOLDS THE HILL"
                    else "CAPTURE THE HILL"
            else -> ""
        }
    }

    private fun applyRefreshRate() {
        val attachedDisplay =
            if (Build.VERSION.SDK_INT >= 30) display
            else @Suppress("DEPRECATION") windowManager.defaultDisplay
        val key =
            "${attachedDisplay?.displayId}:${session.screen}:${session.paused}:${session.highRefresh}:${resources.configuration.orientation}"
        if (key == refreshRateKey) return
        refreshRateKey = key
        val current = attachedDisplay?.mode ?: return
        val compatible =
            attachedDisplay.supportedModes.filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
        val best =
            if (session.highRefresh) compatible.maxByOrNull { it.refreshRate }
            else compatible.minByOrNull { kotlin.math.abs(it.refreshRate - 60f) }
        val playing = session.screen == Screen.PLAYING && !session.paused
        val target = if (playing) best?.modeId ?: 0 else 0
        val rate = if (playing) if (session.highRefresh) best?.refreshRate ?: 60f else 60f else 30f
        // Android 15+ needs an explicit view vote as well as the compatible display mode.
        if (Build.VERSION.SDK_INT >= 35 && arena.requestedFrameRate != rate)
            arena.requestedFrameRate = rate
        if (
            window.attributes.preferredDisplayModeId != target ||
                window.attributes.preferredRefreshRate != rate
        )
            window.attributes =
                window.attributes.apply {
                    preferredDisplayModeId = target
                    preferredRefreshRate = rate
                }
    }

    private fun buildReadyRoom() {
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
                setPadding(dp(12) + safeLeft, dp(12), dp(12) + safeRight, dp(16) + safeBottom)
            }
        val holder = column(this).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL }
        val panel = column(this, 16).apply { background = panelBackground(this@MainActivity) }
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val available = resources.displayMetrics.widthPixels - safeLeft - safeRight - dp(24)
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
        panel.add(
            label(this, "READY ROOM.", if (landscape) 25f else 28f, accent, true).apply {
                typeface =
                    android.graphics.Typeface.create(
                        "sans-serif-black",
                        android.graphics.Typeface.NORMAL,
                    )
                text =
                    android.text.SpannableString("READY ROOM.").apply {
                        setSpan(
                            android.text.style.ForegroundColorSpan(NativeStyle.text),
                            0,
                            6,
                            android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                    }
            },
        )
        if (session.isHost) {
            val public =
                Switch(this).apply {
                    contentDescription = "Public Infinity"
                    isChecked = session.publicSelected
                    showText = false
                    scaleX = .75f
                    scaleY = .75f
                    thumbTintList =
                        android.content.res.ColorStateList(
                            arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                            intArrayOf(0xff002536.toInt(), muted),
                        )
                    trackTintList =
                        android.content.res.ColorStateList(
                            arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                            intArrayOf(0xff00c8ff.toInt(), 0xff324249.toInt()),
                        )
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
                "PLAY  →",
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
            ),
        )
        panel.add(
            button(
                this,
                if (session.online) "COPY INVITE LINK ↗" else "SHARE ROOM ONLINE ↗",
                {
                    if (session.online)
                        copy(
                            "Room invite",
                            "${session.server}/?room=${android.net.Uri.encode(session.roomCode ?: "")}",
                        )
                    else session.share()
                },
                role = if (session.online) null else "share",
            ),
        )
        if (session.online)
            panel.add(button(this, "COPY SPECTATOR LINK ↗", {
                copy("Room spectator link", "${session.server}/?room=${android.net.Uri.encode(session.roomCode ?: "")}&spectate=1")
            }))
        panel.add(button(this, "Join another room ↗", { showJoin() }, role = "text"))
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
            )
        // All room modes keep the same readiness space, including a valid solo Infinity room.
        panel.add(
            label(this, startError.orEmpty(), 11f, danger).apply {
                minLines = 2
                visibility = if (startError.isNullOrBlank()) View.INVISIBLE else View.VISIBLE
            },
        )
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
        if (session.localSelected) {
            panel.add(
                label(
                    this,
                    "${session.localCallsign} (P2)  callsign",
                    11f,
                    paint(session.localColorIndex),
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
        val label =
            if (active) if (session.roomSpectating) "WATCH INFINITY  →" else "REJOIN INFINITY  →"
            else if (session.online && !session.isHost)
                if (session.roomSpectating) "WAITING FOR HOST" else if (own?.optBoolean("ready") == true) "READY ✓" else "READY"
            else "PLAY  →"
        readyPlay?.value(label)
        val allowed =
            if (room == null) true
            else if (active) own != null || session.roomSpectating && !room.optBoolean("infinityPublic")
            else if (session.roomSpectating) false
            else
                !session.isHost ||
                    room.optBoolean("canStart") ||
                    session.publicSelected && room.optBoolean("canStartPublicInfinity")
        readyPlay?.apply {
            isEnabled = allowed
            alpha = if (allowed) 1f else .45f
        }
        readyStatus?.value(session.status)
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
                                    feedbackText(row.seat, row.reason == "reserved", !row.available && !session.automaticNamePending(row.seat))
                            }
                        }
                    }
            },
            300,
        )
    }

    private fun roomSettings(panel: LinearLayout) {
        val code = field(this, session.roomCode ?: session.roomName, "Room name or code", 32)
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
        panel.add(label(this, modeHelp(session.mode), 11f, soft))
        panel.add(button(this, "RULES, TEAMS & POWER-UPS", { showRules() }))
        panel.add(button(this, "PRESETS", { showPresets() }))
    }

    private fun playerSettings(panel: LinearLayout) {
        if (session.room != null) {
            val players = session.room!!.optJSONArray("players") ?: JSONArray()
            repeat(players.length()) { index ->
                val player = players.getJSONObject(index)
                val own =
                    player.optInt("id") == session.network.welcome?.id ||
                        player.optInt("id") == session.network.welcome?.localId
                val bot = player.optString("kind") == "bot" || player.optBoolean("bot")
                val seat = if (own) if (player.optInt("id") == session.network.welcome?.id) 1 else 2 else 0
                panel.add(
                    label(
                        this,
                        PilotIdentity.label(player.optString("name"), bot, seat),
                        12f,
                        paint(player.optInt("colorIndex")),
                        own,
                    ),
                )
                if (!bot) panel.add(label(this, "HUMAN PILOT", 10f, muted, mono = true))
                if (session.isHost || own)
                    panel.add(button(this, "PLAYER OPTIONS", { playerOptions(player) }))
            }
            val spectators = session.room!!.optJSONArray("spectators") ?: JSONArray()
            if (spectators.length() > 0)
                panel.add(label(this, "SPECTATORS", 10f, muted, mono = true))
            repeat(spectators.length()) { index ->
                val member = spectators.getJSONObject(index)
                val own =
                    member.optInt("id") == session.network.welcome?.id ||
                        member.optInt("id") == session.network.welcome?.localId
                panel.add(
                    label(
                        this,
                        member.optString("name") +
                            if (own)
                                if (member.optInt("id") == session.network.welcome?.id) " (P1)"
                                else " (P2)"
                            else "",
                        12f,
                        paint(member.optInt("colorIndex")),
                        own,
                    ),
                )
                if (session.isHost || own)
                    panel.add(
                        button(
                            this,
                            "PLAYER OPTIONS",
                            { playerOptions(member, true) },
                        ),
                    )
            }
            if (session.isHost)
                panel.add(
                    button(
                        this,
                        "＋ ADD BOT",
                        {
                            session.command(
                                "add",
                                "kind" to "bot",
                                "name" to BotNames.next((0 until players.length()).map { players.getJSONObject(it).optString("name") }, players.length() + 1),
                                "difficulty" to session.difficulty,
                            )
                        },
                    ),
                )
            if (session.network.welcome?.localId == null)
                panel.add(
                    button(
                        this,
                        "＋ ADD P2",
                        {
                            session.localSelected = true
                            session.command(
                                "add",
                                "kind" to "local",
                                "name" to session.localCallsign,
                                "colorIndex" to session.localColorIndex,
                            )
                            session.save()
                            refresh(true)
                        },
                    ),
                )
        } else {
            val local =
                CheckBox(this).apply {
                    text = "Add a local tank (P2 keyboard/gamepad)"
                    textSize = 12f
                    setTextColor(NativeStyle.text)
                    isChecked = session.localSelected
                    setOnCheckedChangeListener { _, checked ->
                        session.localSelected = checked
                        session.save()
                        readySignature = ""
                        refresh(true)
                    }
                }
            panel.add(local)
            panel.add(
                button(this, "＋ ADD BOT", { session.addLocalBot() }).apply {
                    isEnabled = session.localBots.size < session.maxLocalBots
                    contentDescription = "Add bot"
                },
            )
            for (bot in session.localBots) localBotRow(panel, bot)
            panel.add(label(this, "NEW BOT DIFFICULTY", 10f, muted, mono = true))
            val difficulties = BotDifficulty.names
            panel.add(
                choice(difficulties, BotDifficulty.index(session.difficulty)) {
                    session.difficulty = difficulties[it]
                    session.save()
                },
            )
        }
        panel.add(label(this, "P1 TANK PAINT", 10f, muted, mono = true))
        paintChoices(panel, 0)
        if (session.room == null && session.rules.teamMode == "teams") localTeamChoice(panel, 0)
        if (session.localSelected) {
            panel.add(label(this, "P2 TANK PAINT", 10f, muted, mono = true))
            paintChoices(panel, 1)
            if (session.room == null && session.rules.teamMode == "teams") localTeamChoice(panel, 1)
        }
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
            choice(difficulties, BotDifficulty.index(bot.difficulty)) {
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

    private fun paintChoices(panel: LinearLayout, seat: Int) {
        val row = row(this)
        GamePalette.names.forEachIndexed { index, name ->
            row.weighted(
                button(
                        this,
                        "",
                        {
                            if (seat == 0) session.colorIndex = index
                            else session.localColorIndex = index
                            session.save()
                            if (session.online)
                                session.command(
                                    "paint",
                                    "colorIndex" to index,
                                    "target" to
                                        if (seat == 0) session.network.welcome?.id
                                        else session.network.welcome?.localId,
                                    "member" to
                                        if (seat == 0) session.network.welcome?.member
                                        else session.network.welcome?.localMember,
                                )
                            readySignature = ""
                            refresh(true)
                        },
                    )
                    .apply {
                        val selected =
                            index == if (seat == 0) session.colorIndex else session.localColorIndex
                        background =
                            android.graphics.drawable.RippleDrawable(
                                android.content.res.ColorStateList.valueOf(0x3340d5ff),
                                NativeStyle.paintChip(this@MainActivity, paint(index), selected),
                                null,
                            )
                        isSelected = selected
                        isEnabled =
                            !session.online ||
                                if (seat == 0) session.network.welcome?.member != null
                                else
                                    session.network.welcome?.localId != null &&
                                        session.network.welcome?.localMember != null
                        contentDescription = name
                        minimumWidth = 0
                        minWidth = 0
                        setPadding(0, dp(8), 0, dp(8))
                    },
                gap = 2,
            )
        }
        panel.add(row)
    }

    private fun playerOptions(
        player: JSONObject,
        spectating: Boolean = player.optBoolean("spectating"),
    ) {
        val target = player.optInt("id")
        val member = player.optLong("member")
        val options = mutableListOf("Change team", "Rename")
        if (session.isHost && player.optString("kind") == "bot") options.add("Bot difficulty")
        if (session.isHost && target != session.localID) options.add("Remove tank")
        options.add(if (spectating) "Join battle" else "Spectate")
        AlertDialog.Builder(this)
            .setTitle(player.optString("name"))
            .setItems(options.toTypedArray()) { _, index ->
                when (options[index]) {
                    "Change team" ->
                        AlertDialog.Builder(this)
                            .setTitle("Team")
                            .setItems(arrayOf("No team", "Team 1", "Team 2", "Team 3", "Team 4")) {
                                _,
                                team ->
                                session.command(
                                    "configure",
                                    "target" to target,
                                    "member" to member,
                                    "team" to team,
                                )
                            }
                            .show()
                    "Rename" ->
                        prompt("Callsign", player.optString("name"), 16) {
                            session.command(
                                "configure",
                                "target" to target,
                                "member" to member,
                                "name" to it,
                            )
                        }
                    "Remove tank" -> session.command("kick", "target" to target, "member" to member)
                    "Bot difficulty" ->
                        AlertDialog.Builder(this)
                            .setTitle("Bot difficulty")
                            .setItems(BotDifficulty.names.toTypedArray()) { _, difficulty
                                ->
                                session.command(
                                    "configure",
                                    "target" to target,
                                    "member" to member,
                                    "difficulty" to
                                        BotDifficulty.names[difficulty],
                                )
                            }
                            .show()
                    "Join battle",
                    "Spectate" ->
                        session.command(
                            "spectate",
                            "target" to target,
                            "member" to member,
                            "spectating" to !spectating,
                        )
                }
            }
            .show()
    }

    private fun showMenu() {
        focusSuspendedPlay = false
        if (session.screen == Screen.PLAYING) session.pause(true)
        val panel = column(this, 16)
        panel.add(
            label(
                this,
                if (session.screen == Screen.PLAYING) "PAUSED." else "leqra",
                28f,
                accent,
                true,
            ),
        )
        if (session.screen == Screen.PLAYING)
            panel.add(
                button(
                    this,
                    "RESUME →",
                    {
                        dismissDialog()
                        session.pause(false)
                    },
                    play = true,
                ),
            )
        panel.add(
            button(
                this,
                "SETTINGS",
                {
                    dismissDialog()
                    showSettings()
                },
            ),
        )
        panel.add(
            button(
                this,
                "CONTROLS",
                {
                    dismissDialog()
                    showControls()
                },
            ),
        )
        panel.add(
            button(
                this,
                "RULES",
                {
                    dismissDialog()
                    showRules()
                },
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
        if (session.online)
            panel.add(
                button(
                    this,
                    "CHAT",
                    {
                        dismissDialog()
                        showChat()
                    },
                ),
            )
        panel.add(
            button(
                this,
                "P1 ACCOUNT KEY",
                {
                    dismissDialog()
                    showAccount(0)
                },
            ),
        )
        panel.add(
            button(
                this,
                "P2 ACCOUNT KEY",
                {
                    dismissDialog()
                    showAccount(1)
                },
            ),
        )
        if (session.screen == Screen.PLAYING)
            panel.add(
                button(
                    this,
                    "BACK TO THE ROOM",
                    {
                        dismissDialog()
                        session.lobby()
                    },
                ),
            )
        if (session.online || session.screen == Screen.PLAYING)
            panel.add(
                button(
                    this,
                    "LEAVE ARENA",
                    {
                        dismissDialog()
                        session.leave()
                    },
                    danger = true,
                ),
            )
        showPanel(panel, "Menu")
    }

    private fun showSettings() {
        val panel = column(this, 16)
        panel.add(label(this, "SETTINGS.", 24f, accent, true))
        val sound =
            Switch(this).apply {
                text = "Sound effects"
                textSize = 13f
                setTextColor(NativeStyle.text)
                isChecked = !session.muted
                setOnCheckedChangeListener { _, enabled ->
                    session.muted = !enabled
                    session.save()
                    refresh(false)
                }
            }
        panel.add(sound)
        panel.add(label(this, "VOLUME", 10f, muted, mono = true))
        panel.add(
            SeekBar(this).apply {
                max = 100
                progress = (session.volume * 100).toInt()
                setOnSeekBarChangeListener(
                    object : SeekBar.OnSeekBarChangeListener {
                        override fun onProgressChanged(
                            bar: SeekBar?,
                            value: Int,
                            fromUser: Boolean,
                        ) {
                            if (fromUser) {
                                session.volume = value / 100f
                                session.save()
                                refresh(false)
                            }
                        }

                        override fun onStartTrackingTouch(bar: SeekBar?) {}

                        override fun onStopTrackingTouch(bar: SeekBar?) {
                            if (!session.muted) previewAudio(AudioCue.VOLUME_PREVIEW)
                        }
                    },
                )
            },
        )
        panel.add(
            Switch(this).apply {
                text = "High refresh rate"
                textSize = 13f
                setTextColor(NativeStyle.text)
                isChecked = session.highRefresh
                setOnCheckedChangeListener { _, enabled ->
                    session.highRefresh = enabled
                    session.save()
                    applyRefreshRate()
                }
            },
        )
        panel.add(
            Switch(this).apply {
                text = "Show frame rate"
                textSize = 13f
                setTextColor(NativeStyle.text)
                isChecked = session.showFPS
                setOnCheckedChangeListener { _, enabled ->
                    session.showFPS = enabled
                    session.save()
                }
            },
        )
        panel.add(label(this, "SERVER ADDRESS", 10f, muted, mono = true))
        val server =
            field(this, session.server, "https://leqra.com", 256).apply {
                inputType =
                    android.text.InputType.TYPE_CLASS_TEXT or
                        android.text.InputType.TYPE_TEXT_VARIATION_URI
            }
        panel.add(server)
        panel.add(
            button(
                this,
                "SAVE SERVER",
                {
                    runCatching {
                        session.setServer(server.text.toString())
                        dismissDialog()
                    }
                        .onFailure { alert("Server", it.message ?: "Invalid address") }
                },
            ),
        )
        panel.add(
            label(
                this,
                "Native Android · v${BuildConfig.VERSION_NAME}\nBackground music keeps playing with sound on or off.",
                11f,
                soft,
            ),
        )
        showPanel(panel, "Settings")
    }

    private fun showControls() {
        val panel = column(this, 16)
        panel.add(label(this, "CONTROLS.", 24f, accent, true))
        panel.add(
            label(
                this,
                "Drag the left joystick to steer and drive. Hold FIRE on the right to shoot. Lift your thumb to stop.\n\nKeyboard: P1 W/S or ↑/↓ to drive, A/D or ←/→ to turn, Space/Q/C to fire. With P2 enabled, use W/A/S/D and Q for P1, arrow keys and Enter for P2.\n\nGamepad: left stick to drive, A/R1/R2 to fire. A second connected gamepad controls P2.\n\nBack/Escape pauses. Swipe from an edge for Android system controls.\n\nShots ricochet off walls. Cannon pierces them. Power-ups can stack, and Starman gives rapid fire.",
                13f,
                soft,
            ),
        )
        showPanel(panel, "Controls")
    }

    private fun showJoin() {
        prompt("JOIN ROOM", "", 160) { value ->
            val uri = runCatching { android.net.Uri.parse(value) }.getOrNull()
            val code =
                runCatching { uri?.getQueryParameter("room") }.getOrNull()
                    ?: value
            session.join(code, runCatching { uri?.getQueryParameter("spectate") == "1" }.getOrDefault(false))
        }
    }

    private fun showRules() {
        val panel = column(this, 16)
        panel.add(label(this, "ROOM RULES.", 24f, accent, true))
        val draft = RuleEditorLimits.draft(session.rules)
        var teamSection: LinearLayout? = null
        fun select(
            title: String,
            values: List<String>,
            current: String,
            enabled: Boolean = true,
            set: (String) -> Unit,
        ) {
            panel.add(label(this, title, 10f, muted, mono = true))
            panel.add(
                choice(values, values.indexOf(current).coerceAtLeast(0)) { set(values[it]) }
                    .apply { isEnabled = enabled },
            )
        }
        select(
            "MAP SIZE",
            listOf("compact", "standard", "large", "huge", "giant", "ultrawide"),
            draft.mapSize,
        ) {
            draft.mapSize = it
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
        select(
            "PICKUP RATE",
            listOf("off", "slow", "normal", "fast", "superfast"),
            draft.pickupRate,
        ) {
            draft.pickupRate = it
        }
        if (!draft.infinity) {
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
            CheckBox(this).apply {
                text = "Friendly fire"
                textSize = 13f
                setTextColor(NativeStyle.text)
                isChecked = draft.friendlyFire
                setOnCheckedChangeListener { _, v -> draft.friendlyFire = v }
            },
        )
        panel.add(
            CheckBox(this).apply {
                text = "Portrait maze"
                textSize = 13f
                setTextColor(NativeStyle.text)
                isChecked = draft.portraitMaze
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
            panel.add(
                CheckBox(this).apply {
                    text = "Fill Infinity with random bots"
                    textSize = 13f
                    setTextColor(NativeStyle.text)
                    isChecked = draft.infinityRandomBots
                    setOnCheckedChangeListener { _, v -> draft.infinityRandomBots = v }
                },
            )
            val difficultyValues = BotDifficulty.names
            val difficultyTitles = listOf("Dumb", "Chill", "Normal", "Fierce", "Godlike")
            select(
                "ROAMING BOT DIFFICULTY",
                difficultyTitles,
                difficultyTitles[
                    BotDifficulty.index(draft.infinityBotDifficulty)],
            ) {
                draft.infinityBotDifficulty = difficultyValues[difficultyTitles.indexOf(it)]
            }
            panel.add(
                CheckBox(this).apply {
                    text = "Random bot difficulty"
                    textSize = 13f
                    setTextColor(NativeStyle.text)
                    isChecked = draft.infinityRandomDifficulty
                    setOnCheckedChangeListener { _, v -> draft.infinityRandomDifficulty = v }
                },
            )
        }
        panel.add(label(this, "POWER-UPS", 10f, muted, mono = true))
        listOf(
                "rapid",
                "scatter",
                "shield",
                "homing",
                "grenade",
                "speed",
                "laser",
                "cannon",
                "ghost",
                "starman",
            )
            .forEach { power ->
                panel.add(
                    CheckBox(this).apply {
                        text = power.replaceFirstChar(Char::uppercase)
                        textSize = 13f
                        setTextColor(NativeStyle.text)
                        isChecked = power in draft.weapons
                        setOnCheckedChangeListener { _, v ->
                            draft.weapons =
                                if (v) (draft.weapons + power).distinct() else draft.weapons - power
                        }
                    },
                    gap = 0,
                )
            }
        panel.add(
            button(
                    this,
                    "APPLY RULES",
                    {
                        session.changeRules(RuleEditorLimits.draft(draft))
                        dismissDialog()
                    },
                    play = true,
                )
                .apply { isEnabled = session.isHost && session.screen != Screen.PLAYING },
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
        val options =
            (GameSession.modes.values + "Save current preset" + "Load saved preset").toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("PRESETS")
            .setItems(options) { _, index ->
                when (index) {
                    in 0..4 -> session.selectMode(GameSession.modes.keys.elementAt(index))
                    5 ->
                        getSharedPreferences("leqra-settings", MODE_PRIVATE)
                            .edit()
                            .putString("preset", GameSession.rulesJson(session.rules).toString())
                            .apply()
                    6 ->
                        getSharedPreferences("leqra-settings", MODE_PRIVATE)
                            .getString("preset", null)
                            ?.let {
                                runCatching {
                                    session.changeRules(
                                        com.leqra.android.network.ProtocolJson.roomRules(
                                            JSONObject(it),
                                        ),
                                    )
                                }
                            }
                }
            }
            .show()
    }

    private fun showResult() {
        val result = session.snapshot.result
        val winner = session.snapshot.tanks.firstOrNull { it.id == session.snapshot.winner }
        val winnerName =
            result?.name?.takeIf(String::isNotBlank)
                ?: if (session.rules.teamMode == "teams" && winner != null) "Team ${winner.team}"
                else winner?.name ?: "Match complete"
        val winnerScore = result?.score ?: winner?.score ?: session.snapshot.scores.maxOrNull() ?: 0
        val panel = column(this, 16)
        panel.add(label(this, "MATCH COMPLETE.", 24f, accent, true))
        panel.add(label(this, "${winnerName} · ${winnerScore} points", 16f, text, true))
        panel.add(
            button(
                this,
                "PLAY AGAIN",
                {
                    dismissDialog()
                    session.restartMatch()
                },
                play = true,
            ),
        )
        panel.add(
            button(
                this,
                "BACK TO THE ROOM",
                {
                    dismissDialog()
                    session.lobby()
                },
            ),
        )
        showPanel(panel, "Match complete")
    }

    private fun showAccount(seat: Int) {
        val origin = session.server
        val panel = column(this, 16)
        panel.add(
            label(
                this,
                "${if(seat==0) session.callsign else session.localCallsign} (P${seat+1}) ACCOUNT KEY",
                20f,
                accent,
                true,
            ),
        )
        val details = label(this, "", 12f, soft)
        val selected = session.store.selected(origin, seat)
        details.text =
            if (selected == null)
                "Play online to create an account. Offline callsigns are always available."
            else
                "This key owns your online callsigns and scores. Copy it to sign in on another device. Keep it private."
        panel.add(details)
        if (selected != null) {
            panel.add(
                button(
                    this,
                    "COPY ACCOUNT KEY",
                    { copy("leqra account key", selected.key, sensitive = true) },
                ),
            )
            session.accounts.inspect(origin, selected.key) { result ->
                if (
                    dialog?.isShowing == true &&
                        session.server == origin &&
                        session.store.selected(origin, seat)?.key == selected.key
                ) {
                    result.onSuccess { checked ->
                        details.text =
                            "${checked.info.names.joinToString(", ")}\n${checked.info.publicProfile?.let { "${it.name}: ${it.score} points\n" } ?: ""}Keep your key private. The newest device takes over your tank."
                    }
                }
            }
            panel.add(
                button(
                    this,
                    "RESET ACCOUNT KEY",
                    {
                        if (!session.canImportAccount) {
                            alert("Account key", "Leave the online room before resetting the key.")
                            return@button
                        }
                        AlertDialog.Builder(this)
                            .setTitle("Reset P${seat+1} key?")
                            .setMessage(
                                "The old key will stop working on every device. Your callsigns and scores stay with the new key. Copy the new key to your other devices afterwards.",
                            )
                            .setNegativeButton("Cancel", null)
                            .setPositiveButton("Reset key") { _, _ ->
                                runCatching {
                                    session.accounts.rotate(origin, seat) { result ->
                                        result
                                            .onSuccess { recovered ->
                                                if (recovered.promoted) {
                                                    dismissDialog()
                                                    session.leave()
                                                    showAccount(seat)
                                                } else
                                                    alert(
                                                        "Replacement saved",
                                                        "A different account is selected. Review saved keys to recover the replacement.",
                                                    )
                                            }
                                            .onFailure {
                                                alert(
                                                    "Key reset",
                                                    it.message
                                                        ?: "The replacement key is saved. Retry to finish.",
                                                )
                                            }
                                    }
                                }
                                    .onFailure { alert("Key reset", it.message ?: "Try again.") }
                            }
                            .show()
                    },
                    danger = true,
                ),
            )
        }
        panel.add(label(this, "IMPORT FROM ANOTHER DEVICE", 10f, muted, mono = true))
        val key =
            field(this, "", "Paste account key", 45).apply {
                inputType =
                    android.text.InputType.TYPE_CLASS_TEXT or
                        android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
                contentDescription = "Account key to import"
            }
        key.isEnabled = session.canImportAccount
        panel.add(key)
        if (!session.canImportAccount)
            panel.add(
                label(
                    this,
                    "Leave the online room before importing or resetting an account key.",
                    11f,
                    muted,
                ),
            )
        val preview = label(this, "", 12f, soft)
        panel.add(preview)
        var checked: CheckedAccount? = null
        val use =
            button(
                    this,
                    "USE THIS KEY",
                    {
                        checked?.let { verified ->
                            runCatching {
                                session.accounts.useChecked(verified, seat)
                                session.accountImported(seat)
                                val name = verified.info.preferredCallsign
                                if (name != null) {
                                    if (seat == 0) session.callsign = name
                                    else session.localCallsign = name
                                }
                                session.save()
                                session.leave()
                                dismissDialog()
                                readySignature = ""
                                refresh(true)
                            }
                                .onFailure {
                                    alert("Account key", it.message ?: "Unable to import key")
                                }
                        }
                    },
                )
                .apply { isEnabled = false }
        key.addTextChangedListener(
            watcher {
                checked = null
                use.isEnabled = false
                preview.text = ""
            },
        )
        panel.add(
            button(
                this,
                "PREVIEW ACCOUNT",
                {
                    val candidate = key.text.toString().trim()
                    use.isEnabled = false
                    checked = null
                    session.accounts.inspect(origin, candidate) { result ->
                        if (
                            origin != session.server ||
                                key.text.toString().trim() != candidate ||
                                dialog?.isShowing != true
                        )
                            return@inspect
                        result
                            .onSuccess { verified ->
                                checked = verified
                                preview.text =
                                    "${verified.info.names.joinToString(", ")}\n${verified.info.publicProfile?.let { "${it.name}: ${it.score} points" } ?: "${verified.info.totalNames} callsigns"}"
                                use.isEnabled = session.canImportAccount
                            }
                            .onFailure { preview.text = it.message ?: "That key is unavailable." }
                    }
                },
            ),
        )
        use.isEnabled = false
        panel.add(use)
        session.store.pending(origin, seat).forEachIndexed { index, pending ->
            panel.add(
                button(
                    this,
                    "REVIEW SAVED KEY ${index+1}",
                    {
                        session.accounts.recover(origin, pending) { result ->
                            result
                                .onSuccess { recovered ->
                                    if (recovered.promoted) {
                                        dismissDialog()
                                        showAccount(seat)
                                    } else {
                                        checked = recovered.checked
                                        preview.text =
                                            "Recovered account: ${recovered.checked.info.names.joinToString(", ")}. Review it, then use this key to switch accounts."
                                        use.isEnabled = session.canImportAccount
                                    }
                                }
                                .onFailure {
                                    preview.text =
                                        it.message ?: "Not yet confirmed. The key remains saved."
                                }
                        }
                    },
                ),
            )
        }
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
        showPanel(panel, "P${seat+1} account key", secure = true)
    }

    private fun updateScores() {
        if (!showScores) {
            scores?.let(stage::removeView)
            scores = null
            scoreSignature = ""
            return
        }
        val signature =
            if (session.screen == Screen.PLAYING)
                "${stage.width}:${stage.height}:${resources.configuration.orientation}:${session.localID}:${session.localID2}:${session.spectating}:${session.followingID}:${session.snapshot.leaderboard}:" + if (session.snapshot.leaderboard.isEmpty()) session.snapshot.tanks.map { listOf(it.id,it.name,it.score,it.colorIndex) }.toString() else ""
            else session.publicStatus?.leaders.toString()
        if (scores != null && signature == scoreSignature) return
        scoreSignature = signature
        val previousScroll = (scores as? ScrollView)?.scrollY ?: 0
        scores?.let(stage::removeView)
        scores = null
        scorePanelBuilds++
        val panel =
            column(this, 12).apply { background = background(this@MainActivity, surface, 9) }
        panel.add(label(this, "LEADERBOARD", 10f, accent, true, mono = true))
        if (session.spectating) panel.add(label(this, "Tap a tank to follow. Dead tanks stay selectable through respawn.", 10f, soft))
        val leaders =
            if (session.screen == Screen.PLAYING)
                session.snapshot.leaderboard.takeIf { it.isNotEmpty() }
                    ?: session.snapshot.tanks
                        .sortedByDescending { it.score }
                        .map {
                            LeaderboardEntry(
                                it.id,
                                it.name,
                                it.score,
                                it.colorIndex,
                                it.bot,
                                it.team,
                            )
                        }
            else null
        if (leaders != null)
            (if (session.spectating) leaders else leaders.take(10)).forEachIndexed { index, p ->
                panel.add(
                    label(
                        this,
                        "${index+1}. ${PilotIdentity.leaderboardLabel(p.name, p.bot, if(p.id==session.localID) 1 else if(p.id==session.localID2) 2 else 0)}    ${p.score}" + if (session.spectating && p.id == session.followingID) "\nFOLLOWING" else "",
                        12f,
                        paint(p.colorIndex),
                        p.id == session.localID || p.id == session.localID2,
                    ).apply {
                        if (session.spectating) {
                            minHeight = dp(44)
                            setPadding(dp(6), dp(6), dp(6), dp(6))
                            contentDescription = "Follow ${p.name}"
                            isClickable = true
                            setOnClickListener {
                                session.followTank(p.id)
                                if (resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE) {
                                    showScores = false
                                    updateScores()
                                }
                            }
                            if (p.id == session.followingID) setBackgroundColor(raised)
                        }
                    },
                )
            }
        else
            session.publicStatus?.leaders?.take(10)?.forEachIndexed { index, p ->
                panel.add(
                    label(this, "${index+1}. ${PilotIdentity.leaderboardLabel(p.name, p.bot)}    ${p.score}", 12f, paint(p.colorIndex)),
                )
            }
        panel.add(
            button(
                this,
                "CLOSE",
                {
                    showScores = false
                    updateScores()
                },
            ),
        )
        val scroll = ScrollView(this).apply {
            contentDescription = "Leaderboard list"
            addView(panel)
            post { scrollTo(0, previousScroll) }
        }
        scores = scroll
        stage.addView(
            scroll,
            FrameLayout.LayoutParams(
                    minOf(dp(if (session.spectating) 280 else 205), resources.displayMetrics.widthPixels - dp(24)),
                    if (session.spectating) (stage.height - dp(24)).coerceAtLeast(dp(120)) else -2,
                    Gravity.TOP or Gravity.END,
                )
                .apply { setMargins(dp(12) + safeLeft, dp(12), dp(12) + safeRight, dp(12)) },
        )
    }

    private fun showChat() {
        val panel = column(this, 16)
        panel.add(label(this, "ROOM CHAT", 22f, accent, true))
        val history = label(this, session.chat.joinToString("\n"), 12f, soft)
        chatHistory = history
        chatSignature = ""
        panel.add(history)
        val text = field(this, "", "Message", 180)
        panel.add(text)
        panel.add(
            button(
                this,
                "SEND",
                {
                    val value = text.text.toString().trim()
                    if (value.isNotBlank()) {
                        session.command("chat", "channel" to "room", "text" to value)
                        text.setText("")
                        history.text = session.chat.joinToString("\n")
                    }
                },
            ),
        )
        showPanel(panel, "Chat")
    }

    private fun showQueues() {
        shownQueuePacket = null
        queueDialog = true
        val panel = column(this, 16)
        panel.add(label(this, "FIND A MATCH.", 24f, accent, true))
        panel.add(label(this, "Loading queues…", 12f, soft))
        showPanel(panel, "Matchmaking")
        queueDialog = true
        session.command("queue_info")
    }

    private var shownQueuePacket: String? = null

    private fun updateQueueDialog() {
        val packet = session.queuePacket ?: return
        val signature = packet.toString()
        if (signature == shownQueuePacket) return
        shownQueuePacket = signature
        val panel = column(this, 16)
        panel.add(label(this, "FIND A MATCH.", 24f, accent, true))
        packet.optJSONObject("queue")?.let { queue ->
            panel.add(
                label(
                    this,
                    "${queue.optString("name")} · ${queue.optInt("players")} / ${queue.optInt("required")}\n${queue.optString("stage")}",
                    13f,
                    soft,
                ),
            )
            panel.add(
                button(
                    this,
                    "ACCEPT MATCH",
                    {
                        session.command(
                            "queue_accept",
                            "queueId" to queue.optLong("id"),
                            "ready" to true,
                        )
                    },
                    play = true,
                ),
            )
            panel.add(
                button(
                    this,
                    "CANCEL QUEUE",
                    { session.command("queue_cancel", "queueId" to queue.optLong("id")) },
                ),
            )
        }
        val rows = packet.optJSONArray("queues") ?: JSONArray()
        repeat(rows.length()) {
            val row = rows.getJSONObject(it)
            val definition = row.optJSONObject("definition") ?: return@repeat
            panel.add(
                button(
                    this,
                    "${definition.optString("name")} · ${row.optInt("waitingPlayers")} waiting",
                    { session.command("queue_join", "queue" to definition.optString("key")) },
                ),
            )
        }
        packet.optString("message").takeIf(String::isNotBlank)?.let {
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

    private fun compactButton(value: String, action: () -> Unit) =
        button(this, value, action).apply {
            textSize = 12f
            minWidth = 0
            minimumWidth = 0
            setPadding(0, dp(8), 0, dp(8))
        }

    private fun showPanel(panel: LinearLayout, title: String, secure: Boolean = false) {
        focusSuspendedPlay = false
        dialog?.dismiss()
        clearHeldControls()
        if (session.screen == Screen.PLAYING) session.pause(true) else session.neutral()
        val scroll =
            ScrollView(this).apply {
                addView(panel)
                setBackgroundColor(surface)
            }
        dialog =
            AlertDialog.Builder(this)
                .setView(scroll)
                .setNegativeButton("CLOSE", null)
                .create()
                .also { shown ->
                    shown.setOnDismissListener {
                        chatHistory = null
                        dialog = null
                        queueDialog = false
                        if (session.screen == Screen.PLAYING && session.paused) session.pause(false)
                        immersive()
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
        dialog = null
        queueDialog = false
        session.neutral()
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
            var initialized = false
            onItemSelectedListener =
                object : AdapterView.OnItemSelectedListener {
                    override fun onNothingSelected(parent: AdapterView<*>?) {}

                    override fun onItemSelected(
                        parent: AdapterView<*>?,
                        view: View?,
                        position: Int,
                        id: Long,
                    ) {
                        if (initialized && position != selected) onSelect(position)
                        initialized = true
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
        if (dialog != null) dismissDialog()
        else if (session.screen == Screen.PLAYING) showMenu()
        else if (session.screen == Screen.CONNECTING || session.online) session.leave()
        else super.onBackPressed()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Route paired controls before the focused arena's single-seat fallback.
        if (
            ::session.isInitialized &&
                session.screen == Screen.PLAYING &&
                dialog == null &&
                (event.keyCode in gameKeys ||
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
                event.source and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
        )
            return onGenericMotionEvent(event)
        return super.dispatchGenericMotionEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (session.screen != Screen.PLAYING || dialog != null)
            return super.onKeyDown(keyCode, event)
        if (keyCode == KeyEvent.KEYCODE_ESCAPE || keyCode == KeyEvent.KEYCODE_BUTTON_START) {
            showMenu()
            return true
        }
        if (
            keyCode in gamepadFireKeys &&
                event.device?.sources?.and(InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
        ) {
            controllers.getOrPut(event.deviceId) { ControllerState() }.buttons.add(keyCode)
            controllerInput(event.deviceId)
            return true
        }
        if (keyCode in gameKeys) {
            pressed.add(keyCode)
            keyboardInput()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (controllers[event.deviceId]?.buttons?.remove(keyCode) == true) {
            controllerInput(event.deviceId)
            return true
        }
        if (pressed.remove(keyCode)) {
            keyboardInput()
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun keyboardInput() {
        fun key(code: Int) = code in pressed
        val paired = session.localID2 != null
        session.input =
            GameInput(
                forward = key(KeyEvent.KEYCODE_W) || (!paired && key(KeyEvent.KEYCODE_DPAD_UP)),
                reverse = key(KeyEvent.KEYCODE_S) || (!paired && key(KeyEvent.KEYCODE_DPAD_DOWN)),
                left = key(KeyEvent.KEYCODE_A) || (!paired && key(KeyEvent.KEYCODE_DPAD_LEFT)),
                right = key(KeyEvent.KEYCODE_D) || (!paired && key(KeyEvent.KEYCODE_DPAD_RIGHT)),
                fire =
                    key(KeyEvent.KEYCODE_SPACE) ||
                        key(KeyEvent.KEYCODE_Q) ||
                        key(KeyEvent.KEYCODE_C) ||
                        key(KeyEvent.KEYCODE_BUTTON_A) ||
                        key(KeyEvent.KEYCODE_BUTTON_R1) ||
                        key(KeyEvent.KEYCODE_BUTTON_R2),
                touchAim = false,
            )
        if (paired)
            session.input2 =
                GameInput(
                    forward = key(KeyEvent.KEYCODE_DPAD_UP),
                    reverse = key(KeyEvent.KEYCODE_DPAD_DOWN),
                    left = key(KeyEvent.KEYCODE_DPAD_LEFT),
                    right = key(KeyEvent.KEYCODE_DPAD_RIGHT),
                    fire = key(KeyEvent.KEYCODE_ENTER),
                    touchAim = false,
                )
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (
            event.source and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK &&
                session.screen == Screen.PLAYING &&
                dialog == null
        ) {
            val state = controllers.getOrPut(event.deviceId) { ControllerState() }
            state.x = event.getAxisValue(MotionEvent.AXIS_X).toDouble()
            state.y = event.getAxisValue(MotionEvent.AXIS_Y).toDouble()
            state.trigger = event.getAxisValue(MotionEvent.AXIS_RTRIGGER) > .3
            controllerInput(event.deviceId)
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    private fun controllerInput(deviceId: Int) {
        val devices =
            InputDevice.getDeviceIds().filter {
                InputDevice.getDevice(it)?.sources?.and(InputDevice.SOURCE_GAMEPAD) ==
                    InputDevice.SOURCE_GAMEPAD
            }
        val state = controllers[deviceId] ?: return
        val input =
            GameInput(
                stickX = state.x,
                stickY = state.y,
                fire = state.trigger || state.buttons.isNotEmpty(),
                touchAim = true,
            )
        if (session.localID2 != null && devices.indexOf(deviceId) > 0) session.input2 = input
        else session.input = input
    }

    companion object {
        private const val CALLSIGN_TAKEN_HINT =
            "Used online; offline is OK.\nYours? Import account key\nGenerate random?"
        private val gamepadFireKeys =
            setOf(KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_BUTTON_R1, KeyEvent.KEYCODE_BUTTON_R2)
        private val gameKeys =
            setOf(
                KeyEvent.KEYCODE_W,
                KeyEvent.KEYCODE_A,
                KeyEvent.KEYCODE_S,
                KeyEvent.KEYCODE_D,
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_SPACE,
                KeyEvent.KEYCODE_Q,
                KeyEvent.KEYCODE_C,
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_BUTTON_A,
                KeyEvent.KEYCODE_BUTTON_R1,
                KeyEvent.KEYCODE_BUTTON_R2,
            )
    }
}
