package com.leqra.android.audio

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicLong

/** Bounded handoff to the audio thread. Cold synthesis never turns old shots into a late burst. */
internal class AudioCueQueue(capacity: Int = 32, private val maxAgeNanos: Long = 125_000_000L) {
    private class Request(val voice: Int, val at: Long, val epoch: Long)

    private val queue = ArrayBlockingQueue<Request>(capacity)
    private val epoch = AtomicLong()
    val size: Int
        get() = queue.size

    @Volatile
    var lastLatencyNanos = 0L
        private set

    fun offer(voice: Int, now: Long): Boolean = queue.offer(Request(voice, now, epoch.get()))

    fun clear() {
        epoch.incrementAndGet()
        queue.clear()
    }

    fun drain(now: Long, prepared: (Int) -> FloatArray?, play: (FloatArray) -> Boolean): Int {
        var played = 0
        // Only inspect the commands present at the start of this block. An
        // unprepared voice can wait briefly without spinning or blocking output.
        repeat(queue.size) {
            val request = queue.poll() ?: return played
            val age = now - request.at
            if (request.epoch != epoch.get() || age < 0 || age > maxAgeNanos) return@repeat
            val pcm = prepared(request.voice)
            if (pcm == null) queue.offer(request)
            else if (play(pcm)) {
                lastLatencyNanos = age
                played++
            }
        }
        return played
    }
}
