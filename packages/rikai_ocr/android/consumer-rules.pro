# ONNX Runtime uses reflection for its Java API.
-keep class ai.onnxruntime.** { *; }
-keep interface ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Keep the Flutter plugin entry point.
-keep class com.rikai.ocr.** { *; }
