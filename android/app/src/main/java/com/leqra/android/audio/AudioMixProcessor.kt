package com.leqra.android.audio

import kotlin.math.*

/** One shared compressor/trim/limiter/master bus, identical to the browser/iOS order. */
class AudioMixProcessor(rate: Double = 48_000.0, volume: Float = .5f) {
    val sampleRate = if (rate.isFinite() && rate in 8_000.0..192_000.0) rate else 48_000.0
    val latencyFrames = max(1, (sampleRate * .006).toInt())
    private val delay = FloatArray(latencyFrames)
    private var index = 0
    private var compressorGain = 1.0
    private var detectorAverage = 0.0
    private var desiredGain = 0.0
    private var envelopeRate = 0.0
    private var divisionRemaining = 0
    private var greatestAttackDifference = -1.0
    private val threshold = 10.0.pow(AudioSynthesis.compressorThresholdDB / 20)
    private val compressionExponent = 1 - 1 / AudioSynthesis.compressorRatio
    private val attackFrames = sampleRate * .003
    private val releaseFrames = sampleRate * .08
    private val detectorFrames = sampleRate * .0025
    private val unityDetectorRate = 10.0.pow(2.0 / detectorFrames / 20) - 1
    private val postGain =
        (1 / threshold.pow(compressionExponent)).pow(.6) * AudioSynthesis.trimGain
    private val rampFrames = max(1, (sampleRate * .012).roundToInt())
    private var master = unit(volume)
    private var targetMaster = master
    private var increment = 0.0
    private var rampRemaining = 0

    fun setVolume(value: Float, immediate: Boolean = false) {
        val target = unit(value)
        if (immediate) {
            master = target
            targetMaster = target
            increment = 0.0
            rampRemaining = 0
        } else if (target != targetMaster) {
            targetMaster = target
            rampRemaining = rampFrames
            increment = (target - master) / rampFrames
        }
    }

    fun reset() {
        delay.fill(0f)
        index = 0
        compressorGain = 1.0
        detectorAverage = 0.0
        desiredGain = 0.0
        envelopeRate = 0.0
        divisionRemaining = 0
        greatestAttackDifference = -1.0
        master = targetMaster
        increment = 0.0
        rampRemaining = 0
    }

    fun process(sample: Float): Float {
        val input =
            if (sample.isFinite())
                (sample.toDouble() * AudioSynthesis.effectGain).coerceIn(-1024.0, 1024.0)
            else 0.0
        if (divisionRemaining == 0) {
            updateEnvelope()
            divisionRemaining = 32
        }
        val magnitude = abs(input)
        val target =
            if (magnitude > threshold) (threshold / magnitude).pow(compressionExponent) else 1.0
        val detectorRate =
            if (target <= detectorAverage) 1.0
            else if (target == 1.0) unityDetectorRate
            else {
                val detectorDB = max(2.0, -20 * log10(max(.0000001, target)))
                10.0.pow(detectorDB / detectorFrames / 20) - 1
            }
        detectorAverage = min(1.0, detectorAverage + (target - detectorAverage) * detectorRate)
        compressorGain =
            if (envelopeRate < 1) compressorGain + (desiredGain - compressorGain) * envelopeRate
            else min(1.0, compressorGain * envelopeRate)
        divisionRemaining--
        val delayed = delay[index].toDouble()
        delay[index] = input.toFloat()
        index = (index + 1) % delay.size
        val compressed =
            if (delayed == 0.0) 0.0 else delayed * sin(PI / 2 * compressorGain) * postGain
        val output =
            (compressed.coerceIn(-1.0, 1.0) * AudioSynthesis.limiterCeiling * master).toFloat()
        if (rampRemaining > 0) {
            master += increment
            rampRemaining--
            if (rampRemaining == 0) {
                master = targetMaster
                increment = 0.0
            }
        }
        return output
    }

    private fun updateEnvelope() {
        desiredGain = asin(detectorAverage.coerceIn(0.0, 1.0)) / (PI / 2)
        val releasing = desiredGain > compressorGain
        val difference =
            if (desiredGain > 0) 20 * log10(max(.0000000001, compressorGain / desiredGain))
            else if (releasing) -1.0 else 1.0
        if (releasing) {
            greatestAttackDifference = -1.0
            val x = (difference.coerceIn(-12.0, 0.0) + 12) * .25
            val duration =
                .09 +
                    x *
                        (.005988750244256685 +
                            x *
                                (.050409513441085324 +
                                    x * (.012655416910923124 + x * .0009463194037350395)))
            envelopeRate = 10.0.pow(5 / max(1.0, duration * releaseFrames) / 20)
        } else {
            greatestAttackDifference = max(greatestAttackDifference, difference)
            envelopeRate = 1 - (.25 / max(.5, greatestAttackDifference)).pow(1 / attackFrames)
        }
    }

    private fun unit(value: Float) = if (value.isNaN()) 0.0 else value.toDouble().coerceIn(0.0, 1.0)
}

/** Fixed voice pool; saturation drops a new cue rather than cutting an existing tail. */
class AudioVoiceMixer(sampleRate: Double = 48_000.0, val capacity: Int = 32) {
    private val buffers = arrayOfNulls<FloatArray>(capacity)
    private val positions = IntArray(capacity)
    private val processor = AudioMixProcessor(sampleRate)
    private val loopFadeFrames = max(1, (processor.sampleRate * StarmanSynthesis.fadeSeconds).roundToInt())
    private var loopSamples: FloatArray? = null
    private var loopPosition = 0
    private var loopGain = 0f
    private var loopTarget = 0f
    private var loopIncrement = 0f
    private var loopRampRemaining = 0
    val activeVoices: Int
        get() = buffers.count { it != null }

    val activeLoops: Int
        @Synchronized get() = if (loopSamples != null && (loopGain > 0 || loopTarget > 0)) 1 else 0

    /** One independent bounded slot; repeated snapshots never restart or duplicate it. */
    @Synchronized
    fun setLoop(samples: FloatArray?, active: Boolean) {
        if (samples != null && samples.isNotEmpty() && loopSamples !== samples) {
            loopSamples = samples
            loopPosition = 0
            loopGain = 0f
            loopTarget = 0f
        }
        val target = if (active && loopSamples != null) 1f else 0f
        if (target == loopTarget) return
        if (target > 0 && loopGain == 0f) loopPosition = 0
        loopTarget = target
        loopRampRemaining = loopFadeFrames
        loopIncrement = (target - loopGain) / loopFadeFrames
    }

    @Synchronized
    fun enqueue(samples: FloatArray): Boolean {
        if (samples.isEmpty()) return false
        for (slot in buffers.indices) if (buffers[slot] == null) {
            buffers[slot] = samples
            positions[slot] = 0
            return true
        }
        return false
    }

    @Synchronized
    fun setVolume(value: Float, immediate: Boolean = false) = processor.setVolume(value, immediate)

    @Synchronized
    fun clear() {
        buffers.fill(null)
        positions.fill(0)
        loopSamples = null
        loopPosition = 0
        loopGain = 0f
        loopTarget = 0f
        loopIncrement = 0f
        loopRampRemaining = 0
        processor.reset()
    }

    @Synchronized
    fun render(destination: FloatArray) {
        for (frame in destination.indices) {
            var mixed = 0f
            val loop = loopSamples
            if (loop != null && (loopGain > 0 || loopTarget > 0)) {
                mixed += loop[loopPosition] * loopGain
                loopPosition++
                if (loopPosition == loop.size) loopPosition = 0
            }
            if (loopRampRemaining > 0) {
                loopGain += loopIncrement
                loopRampRemaining--
                if (loopRampRemaining == 0) loopGain = loopTarget
            }
            for (slot in buffers.indices) {
                val samples = buffers[slot] ?: continue
                mixed += samples[positions[slot]++]
                if (positions[slot] == samples.size) buffers[slot] = null
            }
            destination[frame] = processor.process(mixed)
        }
    }
}
