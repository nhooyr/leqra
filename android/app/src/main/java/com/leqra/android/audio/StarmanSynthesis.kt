package com.leqra.android.audio

import kotlin.math.*

/** Original shared 32-step tune. This immutable bank is prepared off the audio/render threads. */
object StarmanSynthesis {
    const val duration = 4.0
    const val step = .125
    const val fadeSeconds = .012
    private val lead =
        intArrayOf(
            74,
            78,
            81,
            86,
            83,
            81,
            78,
            81,
            76,
            79,
            83,
            88,
            86,
            83,
            79,
            83,
            74,
            81,
            86,
            90,
            88,
            86,
            81,
            78,
            73,
            76,
            81,
            85,
            83,
            81,
            76,
            73,
        )
    private val bass = intArrayOf(50, 55, 50, 57, 50, 55, 52, 57)

    fun samples(rate: Double = 48000.0): FloatArray {
        if (!rate.isFinite() || rate !in 8000.0..192000.0) return FloatArray(0)
        val result = FloatArray((duration * rate).roundToInt())
        for ((index, note) in lead.withIndex()) {
            val start = index * step
            val frequency = 440 * 2.0.pow((note - 69) / 12.0)
            for (frame in
                ceil(start * rate).toInt() until
                    min(result.size, ceil((start + .105) * rate).toInt())) {
                val t = frame / rate - start
                val envelope =
                    max(
                        0.0,
                        min(1.0, t / .006) * min(1.0, (.105 - t) / .035) * (.7 + .3 * exp(-10 * t)),
                    )
                val p = 2 * PI * frequency * t
                val wave = (sin(p) - sin(3 * p) / 9 + sin(5 * p) / 25) * 8 / (PI * PI)
                result[frame] += (wave * envelope * .0035).toFloat()
            }
        }
        for ((index, note) in bass.withIndex()) {
            val start = index * .5
            val frequency = 440 * 2.0.pow((note - 69) / 12.0)
            for (frame in
                ceil(start * rate).toInt() until
                    min(result.size, ceil((start + .42) * rate).toInt())) {
                val t = frame / rate - start
                val envelope = max(0.0, min(1.0, t / .008) * min(1.0, (.42 - t) / .06))
                val p = 2 * PI * frequency * t
                result[frame] += ((sin(p) + .18 * sin(2 * p)) * envelope * .0018).toFloat()
            }
        }
        return result
    }
}
