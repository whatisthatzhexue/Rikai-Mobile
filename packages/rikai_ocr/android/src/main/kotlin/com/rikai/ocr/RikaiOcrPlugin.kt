package com.rikai.ocr

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Flutter entry point for the Rikai OCR plugin.
 *
 * The plugin only accepts local model paths and image paths. Downloads,
 * mirror selection and license prompts belong to the Dart ModelManager.
 */
class RikaiOcrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val engine = PaddleOcrEngine()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val handler = Handler(Looper.getMainLooper())
    private val operationMutex = Mutex()
    private val cancelRequested = AtomicBoolean(false)
    private var recognizeJob: Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        cancelRequested.set(true)
        recognizeJob?.cancel()
        recognizeJob = null
        scope.cancel()
        // Close off the platform thread; an in-flight recognition may hold the
        // engine monitor until it observes cancellation.
        Thread { engine.close() }.start()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "prepare" -> prepare(call, result)
            "recognize" -> recognize(call, result)
            "cancel" -> {
                cancelRequested.set(true)
                recognizeJob?.cancel()
                result.success(true)
            }
            "dispose" -> {
                cancelRequested.set(true)
                recognizeJob?.cancel()
                recognizeJob = null
                // Wait for an in-flight recognize to leave the engine before
                // closing its sessions.
                scope.launch {
                    operationMutex.withLock { engine.close() }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val detPath = args?.get("detModelPath") as? String
        val recPath = args?.get("recModelPath") as? String
        val keysPath = args?.get("keysPath") as? String
        val mangaEncoderPath = args?.get("mangaEncoderPath") as? String
        val mangaDecoderPath = args?.get("mangaDecoderPath") as? String
        val mangaVocabPath = args?.get("mangaVocabPath") as? String
        val docOrientationPath = args?.get("docOrientationPath") as? String
        val textLineOrientationPath = args?.get("textLineOrientationPath") as? String
        if (detPath.isNullOrBlank() || recPath.isNullOrBlank() || keysPath.isNullOrBlank()) {
            result.error("MODEL_MISSING", "缺少 PaddleOCR 模型路径", null)
            return
        }
        val replied = AtomicBoolean(false)
        scope.launch {
            try {
                val readiness = operationMutex.withLock {
                    engine.initialize(
                        detPath = detPath,
                        recPath = recPath,
                        keysPath = keysPath,
                        mangaEncoderPath = mangaEncoderPath,
                        mangaDecoderPath = mangaDecoderPath,
                        mangaVocabPath = mangaVocabPath,
                        docOrientationPath = docOrientationPath,
                        textLineOrientationPath = textLineOrientationPath,
                    )
                }
                replySuccess(result, readiness, replied)
            } catch (error: OcrFailure) {
                replyError(result, error.code, error.message, replied)
            } catch (error: Throwable) {
                replyError(
                    result,
                    "MODEL_INVALID",
                    error.message ?: "OCR 初始化失败",
                    replied,
                )
            } finally {
                if (!replied.get()) {
                    replyError(result, "ENGINE_ERROR", "OCR 初始化未返回结果", replied)
                }
            }
        }
    }

    private fun prepare(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val mode = args?.get("mode") as? String ?: "auto"
        val replied = AtomicBoolean(false)
        scope.launch {
            try {
                val readiness = operationMutex.withLock {
                    engine.prepare(mode)
                }
                replySuccess(result, readiness, replied)
            } catch (error: OcrFailure) {
                replyError(result, error.code, error.message, replied)
            } catch (error: Throwable) {
                replyError(
                    result,
                    "ENGINE_ERROR",
                    error.message ?: "OCR 预热失败",
                    replied,
                )
            } finally {
                if (!replied.get()) {
                    replyError(result, "ENGINE_ERROR", "OCR 预热未返回结果", replied)
                }
            }
        }
    }

    private fun recognize(call: MethodCall, result: MethodChannel.Result) {
        if (recognizeJob?.isActive == true) {
            result.error("BUSY", "已有识别任务正在进行", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        val imagePath = args?.get("imagePath") as? String
        if (imagePath.isNullOrBlank()) {
            result.error("IMAGE_DECODE_FAILED", "缺少图片路径", null)
            return
        }
        val mode = args?.get("mode") as? String ?: "auto"
        cancelRequested.set(false)
        val replied = AtomicBoolean(false)
        val job = scope.launch(start = CoroutineStart.ATOMIC) {
            try {
                operationMutex.withLock {
                    val nativeResult = engine.recognize(
                        imagePath = imagePath,
                        mode = mode,
                        onProgress = { stage, current, total ->
                            emitProgress(stage, current, total)
                        },
                        isCancelled = { cancelRequested.get() || !isActive },
                    )
                    replySuccess(result, nativeResult.toMap(), replied)
                }
            } catch (error: OcrFailure) {
                if (error.code == "CANCELLED") {
                    emitProgress("cancelled", 0, 0)
                }
                replyError(result, error.code, error.message, replied)
            } catch (error: CancellationException) {
                emitProgress("cancelled", 0, 0)
                replyError(result, "CANCELLED", "已取消识别", replied)
            } catch (error: OutOfMemoryError) {
                replyError(result, "OOM", "识别时内存不足", replied)
            } catch (error: Throwable) {
                replyError(
                    result,
                    "ENGINE_ERROR",
                    error.message ?: "OCR 识别失败",
                    replied,
                )
            } finally {
                if (!replied.get()) {
                    val cancelled = cancelRequested.get()
                    replyError(
                        result,
                        if (cancelled) "CANCELLED" else "ENGINE_ERROR",
                        if (cancelled) "已取消识别" else "OCR 识别未返回结果",
                        replied,
                    )
                }
                if (recognizeJob === coroutineContext[Job]) {
                    recognizeJob = null
                }
            }
        }
        recognizeJob = job
    }

    private fun emitProgress(stage: String, current: Int, total: Int) {
        val progress = if (total <= 0) 0.0 else {
            (current.toDouble() / total.toDouble()).coerceIn(0.0, 1.0)
        }
        handler.post {
            eventSink?.success(
                mapOf(
                    "stage" to stage,
                    "current" to current,
                    "total" to total,
                    "progress" to progress,
                ),
            )
        }
    }

    private fun replySuccess(
        result: MethodChannel.Result,
        value: Any?,
        replied: AtomicBoolean,
    ) {
        if (!replied.compareAndSet(false, true)) return
        handler.post { result.success(value) }
    }

    private fun replyError(
        result: MethodChannel.Result,
        code: String,
        message: String,
        replied: AtomicBoolean,
    ) {
        if (!replied.compareAndSet(false, true)) return
        handler.post { result.error(code, message, null) }
    }

    private fun NativeOcrResult.toMap(): Map<String, Any> = mapOf(
        "engine" to engine,
        "elapsedMs" to elapsedMs,
        "width" to width,
        "height" to height,
        "blocks" to blocks.map { block ->
            mapOf(
                "text" to block.text,
                "left" to block.left,
                "top" to block.top,
                "right" to block.right,
                "bottom" to block.bottom,
                "confidence" to block.confidence,
                "orientation" to block.orientation,
                "points" to block.points,
            )
        },
    )

    companion object {
        private const val METHOD_CHANNEL = "rikai/ocr"
        private const val EVENT_CHANNEL = "rikai/ocr_progress"
    }
}
