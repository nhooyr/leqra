package com.leqra.android.audio

import kotlin.math.*

enum class AudioCue {
    REGULAR,
    RAPID,
    SCATTER,
    LASER,
    HOMING,
    GRENADE,
    CANNON,
    EXPLOSION,
    GRENADE_EXPLOSION,
    RICOCHET,
    IMPACT,
    SHIELD,
    PICKUP,
    CHAT,
    VOLUME_PREVIEW,
    UNMUTE,
    COUNTDOWN,
    GO,
    ROUND_WIN,
    ROUND_LOSS,
    ROUND_DRAW,
    ONLINE_ROUND_END,
    HOMING_WARNING,
}

enum class AudioWaveform {
    SINE,
    TRIANGLE,
    SQUARE,
    SAWTOOTH,
}

data class AudioTone(
    val frequency: Double,
    val endFrequency: Double,
    val duration: Double,
    val gain: Double,
    val waveform: AudioWaveform = AudioWaveform.SINE,
    val delay: Double = 0.0,
)

data class AudioNoise(
    val duration: Double = .3,
    val gain: Double,
    val cutoff: Double,
    val resonanceDB: Double = .5,
    val attack: Double = .02,
)

data class AudioRecipe(val tones: List<AudioTone> = emptyList(), val noise: AudioNoise? = null) {
    val duration: Double
        get() =
            max(tones.maxOfOrNull { it.delay + it.duration + .012 } ?: 0.0, noise?.duration ?: 0.0)
}

/** Browser voices before the shared effects bus. These recipes also match iOS. */
object AudioSynthesis {
    const val effectGain = 32.0
    const val compressorThresholdDB = -3.0
    const val compressorRatio = 4.0
    const val limiterCeiling = .98
    const val repeatedShotInterval = .065
    const val ricochetInterval = .07
    const val explosionInterval = .07
    const val homingWarningInterval = 1.5
    val trimGain = 10.0.pow(compressorThresholdDB * (1 - 1 / compressorRatio) * .6 / 20)

    fun recipe(cue: AudioCue, local: Boolean = true): AudioRecipe {
        fun tone(
            a: Double,
            b: Double,
            d: Double,
            near: Double,
            far: Double = near,
            wave: AudioWaveform = AudioWaveform.SINE,
            delay: Double = 0.0,
        ) = AudioTone(a, b, d, if (local) near else far, wave, delay)
        val triangle = AudioWaveform.TRIANGLE
        val tones =
            when (cue) {
                AudioCue.REGULAR -> listOf(tone(200.0, 90.0, .09, .048, .029, triangle))
                AudioCue.RAPID -> listOf(tone(210.0, 120.0, .06, .023, .014, triangle))
                AudioCue.SCATTER ->
                    listOf(
                        tone(165.0, 85.0, .10, .045, .027, triangle),
                        tone(330.0, 150.0, .055, .012, .007),
                    )
                AudioCue.LASER ->
                    listOf(
                        tone(720.0, 270.0, .18, .021, .013),
                        tone(1080.0, 540.0, .10, .006, .004),
                    )
                AudioCue.HOMING ->
                    listOf(
                        tone(150.0, 300.0, .21, .027, .016),
                        tone(260.0, 390.0, .13, .009, .005, triangle),
                    )
                AudioCue.GRENADE -> listOf(tone(180.0, 85.0, .14, .032, .019, triangle))
                AudioCue.CANNON ->
                    listOf(
                        tone(105.0, 55.0, .24, .055, .033),
                        tone(240.0, 110.0, .13, .022, .013, triangle),
                    )
                AudioCue.EXPLOSION ->
                    return AudioRecipe(
                        listOf(tone(90.0, 45.0, .26, .055)),
                        AudioNoise(gain = .10, cutoff = 320.0),
                    )
                AudioCue.GRENADE_EXPLOSION ->
                    return AudioRecipe(
                        listOf(
                            tone(160.0, 75.0, .26, .065),
                            tone(360.0, 140.0, .17, .040, wave = triangle, delay = .02),
                        ),
                        AudioNoise(gain = .12, cutoff = 750.0),
                    )
                AudioCue.RICOCHET -> listOf(tone(650.0, 420.0, .045, .016))
                AudioCue.IMPACT -> listOf(tone(170.0, 95.0, .095, .025))
                AudioCue.SHIELD -> listOf(tone(500.0, 260.0, .16, .020))
                AudioCue.PICKUP ->
                    listOf(
                        tone(480.0, 520.0, .095, .013),
                        tone(640.0, 700.0, .10, .011, delay = .07),
                        tone(880.0, 980.0, .12, .010, delay = .14),
                    )
                AudioCue.CHAT ->
                    listOf(
                        tone(660.0, 720.0, .07, .014),
                        tone(880.0, 760.0, .09, .010, delay = .065),
                    )
                AudioCue.VOLUME_PREVIEW -> listOf(tone(620.0, 760.0, .10, .008))
                AudioCue.UNMUTE -> listOf(tone(500.0, 700.0, .10, .008))
                AudioCue.COUNTDOWN -> listOf(tone(390.0, 360.0, .07, .012))
                AudioCue.GO -> listOf(tone(740.0, 880.0, .15, .012))
                AudioCue.ROUND_WIN ->
                    listOf(
                        tone(430.0, 550.0, .12, .012),
                        tone(650.0, 800.0, .19, .011, delay = .13),
                    )
                AudioCue.ROUND_LOSS -> listOf(tone(300.0, 450.0, .16, .012))
                AudioCue.ROUND_DRAW -> listOf(tone(260.0, 180.0, .20, .012))
                AudioCue.ONLINE_ROUND_END ->
                    listOf(tone(if (local) 600.0 else 300.0, 450.0, .16, .012))
                AudioCue.HOMING_WARNING ->
                    listOf(
                        tone(620.0, 740.0, .08, .015),
                        tone(740.0, 860.0, .09, .013, delay = .105),
                    )
            }
        return AudioRecipe(tones)
    }

    fun samples(
        cue: AudioCue,
        local: Boolean = true,
        sampleRate: Double = 48_000.0,
        noiseSeed: Int = 0x51e9a7c3,
    ) = samples(recipe(cue, local), sampleRate, noiseSeed)

    fun samples(
        recipe: AudioRecipe,
        sampleRate: Double = 48_000.0,
        noiseSeed: Int = 0x51e9a7c3,
    ): FloatArray {
        if (
            !sampleRate.isFinite() ||
                sampleRate !in 8_000.0..192_000.0 ||
                !recipe.duration.isFinite() ||
                recipe.duration <= 0 ||
                recipe.duration > 10
        )
            return FloatArray(0)
        val result = FloatArray(ceil(recipe.duration * sampleRate).toInt())
        for (tone in recipe.tones) {
            if (
                !tone.frequency.isFinite() ||
                    tone.frequency <= 0 ||
                    !tone.endFrequency.isFinite() ||
                    !tone.duration.isFinite() ||
                    tone.duration <= 0 ||
                    !tone.gain.isFinite() ||
                    tone.gain <= 0 ||
                    !tone.delay.isFinite() ||
                    tone.delay < 0
            )
                continue
            val start = ceil(tone.delay * sampleRate).toInt()
            val stop =
                min(result.size, ceil((tone.delay + tone.duration + .012) * sampleRate).toInt())
            val harmonics =
                (sampleRate / (2 * max(max(tone.frequency, tone.endFrequency), 20.0)))
                    .toInt()
                    .coerceIn(1, 256)
            for (index in start until stop) {
                val time = index / sampleRate - tone.delay
                result[index] +=
                    (wave(tone.waveform, phase(tone, time), harmonics) * envelope(tone, time))
                        .toFloat()
            }
        }
        recipe.noise?.let { addNoise(it, sampleRate, noiseSeed, result) }
        return result
    }

    fun envelope(tone: AudioTone, time: Double): Double {
        if (time < 0 || time >= tone.duration + .008 || tone.gain <= 0) return 0.0
        val attack = min(.012, tone.duration * .16)
        return when {
            time < attack -> tone.gain * time / attack
            time <= tone.duration ->
                tone.gain * (.0001 / tone.gain).pow((time - attack) / (tone.duration - attack))
            else -> .0001 * (1 - (time - tone.duration) / .008)
        }
    }

    fun phase(tone: AudioTone, time: Double): Double {
        val span = time.coerceIn(0.0, tone.duration)
        val rate = ln(max(20.0, tone.endFrequency) / tone.frequency) / tone.duration
        val cycles =
            if (abs(rate) < 1e-12) tone.frequency * span
            else tone.frequency * expm1(rate * span) / rate
        return 2 * PI * (cycles + max(0.0, time - tone.duration) * max(20.0, tone.endFrequency))
    }

    private fun wave(wave: AudioWaveform, phase: Double, harmonics: Int): Double {
        if (wave == AudioWaveform.SINE) return sin(phase)
        var result = 0.0
        when (wave) {
            AudioWaveform.TRIANGLE -> {
                for (h in 1..harmonics step 2) result +=
                    (if (h % 4 == 1) 1 else -1) * sin(h * phase) / (h * h)
                result *= 8 / (PI * PI)
            }
            AudioWaveform.SQUARE -> {
                for (h in 1..harmonics step 2) result += sin(h * phase) / h
                result *= 4 / PI
            }
            AudioWaveform.SAWTOOTH -> {
                for (h in 1..harmonics) result += (if (h % 2 == 1) 1 else -1) * sin(h * phase) / h
                result *= 2 / PI
            }
        }
        return result
    }

    private fun addNoise(noise: AudioNoise, rate: Double, seed: Int, samples: FloatArray) {
        if (
            !noise.duration.isFinite() ||
                noise.duration <= 0 ||
                noise.attack <= 0 ||
                noise.attack >= noise.duration ||
                !noise.gain.isFinite() ||
                noise.gain <= 0 ||
                !noise.cutoff.isFinite() ||
                noise.cutoff <= 0 ||
                !noise.resonanceDB.isFinite()
        )
            return
        val count = min(samples.size, floor(noise.duration * rate).toInt())
        val omega = 2 * PI * min(noise.cutoff, rate / 2) / rate
        val cosine = cos(omega)
        val alpha = sin(omega) / (2 * 10.0.pow(noise.resonanceDB / 20))
        val a0 = 1 + alpha
        val b0 = (1 - cosine) / 2 / a0
        val b1 = (1 - cosine) / a0
        val a1 = -2 * cosine / a0
        val a2 = (1 - alpha) / a0
        var random = if (seed == 0) 1 else seed
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        for (index in 0 until count) {
            random = random xor (random shl 13)
            random = random xor (random ushr 17)
            random = random xor (random shl 5)
            val input =
                ((random.toLong() and 0xffffffffL).toDouble() / 4294967295.0 * 2 - 1) *
                    (1 - index.toDouble() / count)
            val output = b0 * input + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = input
            y2 = y1
            y1 = output
            val time = index / rate
            val gain =
                noise.gain *
                    if (time < noise.attack) time / noise.attack
                    else (noise.duration - time) / (noise.duration - noise.attack)
            samples[index] += (output * gain).toFloat()
        }
    }
}
