package com.lexicandy.mobile

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter plus the native storage-permission bridge.
 *
 * LexiCandy reads a user-supplied UniDic directory and MDict files in place.
 * On Android 11+ that requires MANAGE_EXTERNAL_STORAGE ("All files access");
 * on Android 10 and below it uses READ_EXTERNAL_STORAGE. permission_handler was
 * removed because its Kotlin DSL does not compile with this toolchain.
 */
class MainActivity : FlutterActivity() {
    private val legacyStorageRequestCode = 4301
    private val notificationPermissionRequestCode = 4302
    private var pendingLegacyResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexicandy/storage_permission")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageAccessStatus" -> result.success(storageAccessStatus())
                    "requestAllFilesAccess" -> requestAllFilesAccess(result)
                    "requestLegacyReadPermission" -> requestLegacyReadPermission(result)
                    "openAppSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexicandy/storage_space")
            .setMethodCallHandler { call, result ->
                if (call.method != "getAvailableBytes") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_PATH", "缺少目录路径", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(StatFs(path).availableBytes)
                } catch (error: Exception) {
                    result.error("STAT_FAILED", error.message ?: "无法读取存储空间", null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexicandy/agent_background")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            // Android 13+ hides a foreground-service notice
                            // when notifications are denied. Ask once when the
                            // first Agent run starts; the service still runs
                            // if the user declines.
                            if (
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                    PackageManager.PERMISSION_GRANTED
                            ) {
                                val preferences =
                                    getSharedPreferences("lexicandy_prefs", MODE_PRIVATE)
                                if (!preferences.getBoolean(
                                        "agent_notification_permission_requested",
                                        false,
                                    )
                                ) {
                                    preferences
                                        .edit()
                                        .putBoolean(
                                            "agent_notification_permission_requested",
                                            true,
                                        )
                                        .apply()
                                    requestPermissions(
                                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                        notificationPermissionRequestCode,
                                    )
                                }
                            }
                            startForegroundService(
                                Intent(this, AgentRunService::class.java)
                                    .setAction(AgentRunService.ACTION_START),
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.error(
                                "START_FAILED",
                                error.message ?: "无法启动后台运行服务",
                                null,
                            )
                        }
                    }
                    "stop" -> {
                        stopService(Intent(this, AgentRunService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun storageAccessStatus(): Map<String, Any> {
        val sdkInt = Build.VERSION.SDK_INT
        val allFilesAccess =
            sdkInt >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()
        val legacyRead =
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        return mapOf(
            "sdkInt" to sdkInt,
            "allFilesAccess" to allFilesAccess,
            "legacyRead" to legacyRead,
        )
    }

    private fun requestAllFilesAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            requestLegacyReadPermission(result)
            return
        }
        if (Environment.isExternalStorageManager()) {
            result.success(true)
            return
        }

        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            } catch (_: Exception) {
                result.error("UNAVAILABLE", "无法打开所有文件访问设置页", null)
                return
            }
        }
        result.success(Environment.isExternalStorageManager())
    }

    private fun requestLegacyReadPermission(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingLegacyResult != null) {
            result.error("PENDING", "已有存储权限请求正在进行", null)
            return
        }
        pendingLegacyResult = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
            legacyStorageRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode) {
            // Optional: a denied notification permission only hides the
            // foreground-service notice; the run continues.
            return
        }
        if (requestCode != legacyStorageRequestCode) return
        val granted =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingLegacyResult?.success(granted)
        pendingLegacyResult = null
    }
}
