package com.example.giant_agent

import android.Manifest
import android.media.AudioManager
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import kotlin.math.sqrt

/**
 * App-owned 16 kHz mono PCM capture for the local Whisper pipeline.
 *
 * Uses VOICE_COMMUNICATION input so Android can attach hardware/platform AEC
 * and noise suppression when available. A bounded energy VAD emits speech
 * boundary events; it never uploads audio or performs transcription itself.
 */
class VoiceCaptureBridge(
    private val activity: Activity,
    messenger: io.flutter.plugin.common.BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val SAMPLE_RATE = 16000
        private const val FRAME_SAMPLES = 320 // 20 ms
        private const val CHANNEL = "giant_agent/voice_capture"
        private const val EVENTS = "giant_agent/voice_activity"

        fun register(activity: Activity, messenger: io.flutter.plugin.common.BinaryMessenger) {
            val bridge = VoiceCaptureBridge(activity, messenger)
            MethodChannel(messenger, CHANNEL).setMethodCallHandler(bridge)
            EventChannel(messenger, EVENTS).setStreamHandler(bridge)
        }
    }

    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var previousAudioMode: Int? = null
    @Volatile private var running = false
    private var recorder: AudioRecord? = null
    private var captureThread: Thread? = null
    private var output: File? = null
    private var outputStream: FileOutputStream? = null
    private var pcmBytes = 0L
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var gainControl: AutomaticGainControl? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> try {
                result.success(startCapture())
            } catch (error: Throwable) {
                result.error("VOICE_CAPTURE_START_FAILED", error.message, null)
            }
            "stop" -> try {
                result.success(stopCapture(discard = false))
            } catch (error: Throwable) {
                result.error("VOICE_CAPTURE_STOP_FAILED", error.message, null)
            }
            "cancel" -> try {
                stopCapture(discard = true)
                result.success(true)
            } catch (error: Throwable) {
                result.error("VOICE_CAPTURE_CANCEL_FAILED", error.message, null)
            }
            "capabilities" -> result.success(mapOf(
                "sample_rate" to SAMPLE_RATE,
                "vad" to true,
                "aec_available" to AcousticEchoCanceler.isAvailable(),
                "noise_suppression_available" to NoiseSuppressor.isAvailable(),
                "automatic_gain_control_available" to AutomaticGainControl.isAvailable()
            ))
            else -> result.notImplemented()
        }
    }

    private fun startCapture(): String = synchronized(lock) {
        if (running) return@synchronized output?.absolutePath
            ?: throw IllegalStateException("Capture is already active.")
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("Microphone permission has not been granted.")
        }
        val minimum = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        if (minimum <= 0) throw IllegalStateException("AudioRecord buffer configuration is unsupported.")
        val bufferBytes = maxOf(minimum, FRAME_SAMPLES * 2 * 4)
        val audio = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferBytes
        )
        if (audio.state != AudioRecord.STATE_INITIALIZED) {
            audio.release()
            throw IllegalStateException("Android could not initialize the microphone.")
        }

        val file = File(activity.cacheDir, "giant-voice-${System.currentTimeMillis()}.wav")
        val stream = FileOutputStream(file, false)
        stream.write(ByteArray(44))
        pcmBytes = 0
        output = file
        outputStream = stream
        recorder = audio

        if (AcousticEchoCanceler.isAvailable()) {
            echoCanceler = runCatching { AcousticEchoCanceler.create(audio.audioSessionId) }
                .getOrNull()?.also { it.enabled = true }
        }
        if (NoiseSuppressor.isAvailable()) {
            noiseSuppressor = runCatching { NoiseSuppressor.create(audio.audioSessionId) }
                .getOrNull()?.also { it.enabled = true }
        }
        if (AutomaticGainControl.isAvailable()) {
            gainControl = runCatching { AutomaticGainControl.create(audio.audioSessionId) }
                .getOrNull()?.also { it.enabled = true }
        }

        previousAudioMode = audioManager.mode
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audio.startRecording()
        running = true
        captureThread = Thread({ captureLoop(audio, stream) }, "GiantAgentVoiceCapture").apply {
            isDaemon = true
            start()
        }
        file.absolutePath
    }

    private fun captureLoop(audio: AudioRecord, stream: FileOutputStream) {
        val frame = ShortArray(FRAME_SAMPLES)
        var noiseFloor = 250.0
        var speechFrames = 0
        var silenceFrames = 0
        var speechActive = false
        var frameCounter = 0

        while (running) {
            val count = audio.read(frame, 0, frame.size, AudioRecord.READ_BLOCKING)
            if (count <= 0) {
                if (count < 0) break
                continue
            }
            val bytes = ByteArray(count * 2)
            var energy = 0.0
            for (index in 0 until count) {
                val sample = frame[index].toInt()
                energy += sample.toDouble() * sample.toDouble()
                bytes[index * 2] = (sample and 0xff).toByte()
                bytes[index * 2 + 1] = ((sample shr 8) and 0xff).toByte()
            }
            synchronized(lock) {
                if (!running) break
                stream.write(bytes)
                pcmBytes += bytes.size
            }

            val rms = sqrt(energy / count)
            val threshold = maxOf(650.0, noiseFloor * 2.4)
            if (!speechActive && rms < threshold * 1.4) {
                noiseFloor = (noiseFloor * 0.94) + (rms * 0.06)
            }
            if (rms >= threshold) {
                speechFrames++
                silenceFrames = 0
                if (!speechActive && speechFrames >= 2) {
                    speechActive = true
                    emitActivity("speech_started", rms)
                }
            } else {
                speechFrames = 0
                if (speechActive) {
                    silenceFrames++
                    if (silenceFrames >= 20) { // 400 ms hangover
                        speechActive = false
                        silenceFrames = 0
                        emitActivity("speech_ended", rms)
                    }
                }
            }
            frameCounter++
            if (frameCounter % 5 == 0) emitActivity("audio_level", rms)
        }
        if (speechActive) emitActivity("speech_ended", 0.0)
    }

    private fun emitActivity(type: String, rms: Double) {
        val event = mapOf(
            "type" to type,
            "rms" to rms,
            "timestamp_ms" to System.currentTimeMillis()
        )
        mainHandler.post { eventSink?.success(event) }
    }

    private fun stopCapture(discard: Boolean): String? {
        val thread: Thread?
        val file: File?
        synchronized(lock) {
            if (!running && recorder == null) return null
            running = false
            thread = captureThread
            file = output
        }
        runCatching { recorder?.stop() }
        if (thread != null && thread !== Thread.currentThread()) thread.join(1500)

        synchronized(lock) {
            runCatching { outputStream?.flush() }
            runCatching { outputStream?.close() }
            outputStream = null
            releaseEffects()
            runCatching { recorder?.release() }
            previousAudioMode?.let { mode -> runCatching { audioManager.mode = mode } }
            previousAudioMode = null
            recorder = null
            captureThread = null
            output = null
            if (file == null) return null
            if (discard || pcmBytes == 0L) {
                file.delete()
                pcmBytes = 0
                return null
            }
            RandomAccessFile(file, "rw").use { wav ->
                writeWavHeader(wav, pcmBytes)
            }
            pcmBytes = 0
            return file.absolutePath
        }
    }

    private fun releaseEffects() {
        runCatching { echoCanceler?.release() }
        runCatching { noiseSuppressor?.release() }
        runCatching { gainControl?.release() }
        echoCanceler = null
        noiseSuppressor = null
        gainControl = null
    }

    private fun writeWavHeader(file: RandomAccessFile, dataLength: Long) {
        val total = dataLength + 36
        file.seek(0)
        file.writeBytes("RIFF")
        writeIntLE(file, total)
        file.writeBytes("WAVE")
        file.writeBytes("fmt ")
        writeIntLE(file, 16)
        writeShortLE(file, 1)
        writeShortLE(file, 1)
        writeIntLE(file, SAMPLE_RATE.toLong())
        writeIntLE(file, SAMPLE_RATE * 2L)
        writeShortLE(file, 2)
        writeShortLE(file, 16)
        file.writeBytes("data")
        writeIntLE(file, dataLength)
    }

    private fun writeIntLE(file: RandomAccessFile, value: Long) {
        repeat(4) { shift -> file.write((value shr (shift * 8)).toInt() and 0xff) }
    }

    private fun writeShortLE(file: RandomAccessFile, value: Int) {
        file.write(value and 0xff)
        file.write((value shr 8) and 0xff)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}