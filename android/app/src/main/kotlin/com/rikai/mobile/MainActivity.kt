package com.rikai.mobile

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter plus the native storage-permission bridge.
 *
 * Rikai-Mobile reads a user-supplied UniDic directory and MDict files in place.
 * On Android 11+ that requires MANAGE_EXTERNAL_STORAGE ("All files access");
 * on Android 10 and below it uses READ_EXTERNAL_STORAGE. permission_handler was
 * removed because its Kotlin DSL does not compile with this toolchain.
 */
class MainActivity : FlutterActivity() {
    private val legacyStorageRequestCode = 4301
    private var pendingLegacyResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rikai/storage_permission")
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
        if (requestCode != legacyStorageRequestCode) return
        val granted =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingLegacyResult?.success(granted)
        pendingLegacyResult = null
    }
}
