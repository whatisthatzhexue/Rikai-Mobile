package com.rikai.ocr

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter entry point for the Rikai OCR plugin.
 *
 * The native OCR pipeline is being ported from overlay-translator in Phase 3/4.
 * This skeleton keeps the channel contract stable so the Dart side and app UI
 * can be developed independently.
 */
class RikaiOcrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler(this)
        channel = methodChannel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                // Model paths are validated by the Dart ModelManager. The native
                // sessions are opened lazily by the OCR pipeline (Phase 3).
                result.success(null)
            }
            "recognize" -> result.error(
                "NOT_IMPLEMENTED",
                "OCR pipeline is not implemented yet (Phase 3/4).",
                null,
            )
            "dispose" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL = "rikai/ocr"
    }
}
