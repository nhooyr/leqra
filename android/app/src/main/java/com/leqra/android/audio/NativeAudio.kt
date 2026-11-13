package com.leqra.android.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.VibrationEffect
import android.os.Vibrator
import com.leqra.core.ArenaSnapshot
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReferenceArray

/** Lazy low-latency native output. Never requests audio focus, so music keeps playing. */
class NativeAudio(context: Context) {
    private val vibrator = context.getSystemService(Vibrator::class.java)
    private val mixer = AudioVoiceMixer()
    private val router = AudioEventRouter()
    private val cached = AtomicReferenceArray<FloatArray>(AudioCue.entries.size * 2)
    private val pending = AudioCueQueue()
    private val preparedVoice: (Int) -> FloatArray? = cached::get
    private val enqueueVoice: (FloatArray) -> Boolean = mixer::enqueue
    private val outputGuard = Any()
    private val main = Handler(Looper.getMainLooper())
    private var previewStop: Runnable? = null
    internal val pendingCueCount: Int
        get() = pending.size

    internal val preparedVoiceCount: Int
        get() = (0 until cached.length()).count { cached.get(it) != null }

    internal val lastCueLatencyNanos: Long
        get() = pending.lastLatencyNanos

    @Volatile
    internal var outputStarts = 0
        private set

    @Volatile
    internal var framesWritten = 0L
        private set

    private val preparation = Executors.newSingleThreadExecutor { task ->
        Thread(
                {
                    runCatching { Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND) }
                    task.run()
                },
                "leqra-voices",
            )
            .apply { isDaemon = true }
    }
    @Volatile private var running = false
    @Volatile private var released = false
    private var thread: Thread? = null
    @Volatile private var track: AudioTrack? = null
    var enabled: Boolean = true
        set(value) {
            if (field == value) return
            field = value
            if (!value) pause()
        }

    var volume: Float = .5f
        set(value) {
            val next = if (value.isNaN()) 0f else value.coerceIn(0f, 1f)
            if (field == next) return
            field = next
            mixer.setVolume(next)
            if (next <= 0) pause()
        }

    private var previousHP: Int? = null
    private var generation: Int? = null
    private var lastHaptic = Double.NEGATIVE_INFINITY
    private var lastChat = Double.NEGATIVE_INFINITY
    @Volatile private var playbackEpoch = 0
    private var lastSnapshotTick: Long? = null
    private var lastLocalID: Int? = null
    private var lastInfinity: Boolean? = null
    private var lastOnline: Boolean? = null

    init {
        // Harmonic synthesis never blocks the Activity or the real-time audio
        // callback. The menu gives this immutable bank time to warm naturally.
        preparation.execute {
            for (cue in AudioCue.entries) {
                if (released) break
                val local = AudioSynthesis.samples(cue)
                cached.set(cue.ordinal * 2, local)
                cached.set(
                    cue.ordinal * 2 + 1,
                    if (AudioSynthesis.recipe(cue) == AudioSynthesis.recipe(cue, false)) local
                    else AudioSynthesis.samples(cue, false),
                )
            }
        }
    }

    fun resume() {
        synchronized(outputGuard) {
            if (released || !enabled || volume <= 0 || running) return
            running = true
            mixer.setVolume(volume, true)
            val epoch = playbackEpoch
            thread = Thread({ renderLoop(epoch) }, "leqra-audio").apply { start() }
        }
    }

    fun pause() {
        previewStop?.let(main::removeCallbacks)
        previewStop = null
        val previous =
            synchronized(outputGuard) {
                playbackEpoch++
                running = false
                thread = null
                track.also { track = null }
            }
        // Unblock a hardware write, then let the output thread release its own
        // track. Never join it on Android's UI/render thread.
        runCatching {
            previous?.pause()
            previous?.flush()
        }
        reset()
    }

    fun release() {
        released = true
        pause()
        preparation.shutdownNow()
    }

    fun reset() {
        pending.clear()
        mixer.clear()
        router.reset()
        previousHP = null
        generation = null
        lastSnapshotTick = null
        lastLocalID = null
        lastInfinity = null
        lastOnline = null
    }

    fun play(cue: AudioCue, local: Boolean = true) {
        if (!enabled || volume <= 0 || released) return
        pending.offer(cue.ordinal * 2 + if (local) 0 else 1, System.nanoTime())
        resume()
    }

    fun preview(cue: AudioCue) {
        if (!enabled || volume <= 0 || released) return
        previewStop?.let(main::removeCallbacks)
        play(cue)
        previewStop =
            Runnable {
                    previewStop = null
                    pause()
                }
                .also { main.postDelayed(it, 400) }
    }

    fun notifyChat(now: Double = System.nanoTime() / 1e9) {
        if (now - lastChat >= .18) {
            lastChat = now
            play(AudioCue.CHAT)
        }
    }

    fun consume(
        snapshot: ArenaSnapshot,
        localID: Int,
        infinity: Boolean,
        online: Boolean,
        nowSeconds: Double = System.nanoTime() / 1e9,
    ) {
        previewStop?.let(main::removeCallbacks)
        previewStop = null
        val tank = snapshot.tanks.firstOrNull { it.id == localID }
        if (
            generation != snapshot.generation ||
                lastLocalID != localID ||
                lastInfinity != infinity ||
                lastOnline != online ||
                lastSnapshotTick?.let { snapshot.tick < it } == true
        ) {
            reset()
            generation = snapshot.generation
            previousHP = tank?.hp
            lastLocalID = localID
            lastInfinity = infinity
            lastOnline = online
        }
        lastSnapshotTick = snapshot.tick
        val died = (previousHP ?: 0) > 0 && tank?.hp == 0
        previousHP = tank?.hp
        val requests = router.consume(snapshot, localID, infinity, online, nowSeconds)
        if (!enabled || volume <= 0) return
        if (died) haptic(nowSeconds, 35, 100)
        for (request in requests) {
            play(request.cue, request.local)
            if (request.cue == AudioCue.PICKUP && request.local) haptic(nowSeconds, 18, 55)
        }
    }

    private fun haptic(now: Double, duration: Long, amplitude: Int) {
        if (now - lastHaptic < .1 || vibrator?.hasVibrator() != true) return
        lastHaptic = now
        runCatching { vibrator.vibrate(VibrationEffect.createOneShot(duration, amplitude)) }
    }

    private fun renderLoop(epoch: Int) {
        runCatching { Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO) }
        var output: AudioTrack? = null
        try {
            val minimum =
                AudioTrack.getMinBufferSize(
                    48_000,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_FLOAT,
                )
            output =
                AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                            .setSampleRate(48_000)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build(),
                    )
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .setBufferSizeInBytes(maxOf(minimum, 768 * 4))
                    .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                    .build()
            synchronized(outputGuard) {
                if (!running || released || epoch != playbackEpoch) return
                track = output
                outputStarts++
            }
            output.play()
            val block = FloatArray(192)
            while (running && !released && epoch == playbackEpoch) {
                pending.drain(System.nanoTime(), preparedVoice, enqueueVoice)
                mixer.render(block)
                var offset = 0
                while (offset < block.size && running && epoch == playbackEpoch) {
                    val written =
                        output.write(block, offset, block.size - offset, AudioTrack.WRITE_BLOCKING)
                    if (written <= 0) return
                    offset += written
                    framesWritten += written
                }
            }
        } catch (_: Exception) {
            // Losing a route must never stop the game; the next cue retries.
        } finally {
            runCatching {
                output?.pause()
                output?.flush()
                output?.release()
            }
            synchronized(outputGuard) {
                if (track === output) track = null
                if (epoch == playbackEpoch) running = false
            }
        }
    }
}
