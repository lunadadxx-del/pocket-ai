package com.pocketai.pocket_ai

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.ContactsContract
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Native Android actions for Pocket AI.
///
/// Every method returns a real result map: {ok: Boolean, message/error: String}.
/// Nothing is ever claimed as done unless Android itself confirmed it.
class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.pocketai/actions"
        const val REQ_CONTACTS = 101
        const val REQ_CALL = 102
    }

    private var pendingContacts: MethodChannel.Result? = null
    private var pendingContactsQuery: String? = null
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingCallNumber: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openApp" -> openApp(call.argument<String>("package"), result)
                "openSettings" -> openSettings(result)
                "getContacts" -> getContacts(
                    call.argument<String>("query") ?: "", result
                )
                "placeCall" -> placeCall(call.argument<String>("number"), result)
                "setAlarm" -> setAlarm(
                    call.argument<Int>("hour") ?: -1,
                    call.argument<Int>("minute") ?: -1,
                    result,
                )
                "startKeepAlive" -> startKeepAlive(result)
                "stopKeepAlive" -> stopKeepAlive(result)
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------------ apps

    private fun openApp(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrBlank()) {
            result.error("ARG", "No package name given.", null)
            return
        }
        val pm = packageManager
        // Direct package launch when we know the package id.
        pm.getLaunchIntentForPackage(packageName)?.let { intent ->
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(mapOf("ok" to true, "via" to "package"))
            return
        }
        // Fallback: match by human-readable launcher label, e.g. "YouTube".
        val launchables = pm.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
            PackageManager.MATCH_ALL,
        )
        val match = launchables.firstOrNull {
            it.loadLabel(pm).toString().equals(packageName, ignoreCase = true)
        }
        if (match != null) {
            val intent = pm.getLaunchIntentForPackage(match.activityInfo.packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                result.success(mapOf("ok" to true, "via" to "label"))
                return
            }
        }
        result.success(
            mapOf("ok" to false, "error" to "App '$packageName' is not installed.")
        )
    }

    private fun openSettings(result: MethodChannel.Result) {
        return try {
            val intent = Intent(Settings.ACTION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(mapOf("ok" to true))
        } catch (e: Exception) {
            result.success(mapOf("ok" to false, "error" to e.message))
        }
    }

    // -------------------------------------------------------------- contacts

    private fun getContacts(query: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this, Manifest.permission.READ_CONTACTS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            // Retain the query so the lookup can run for real once the
            // permission is granted — never answer with a fake empty list.
            pendingContacts = result
            pendingContactsQuery = query
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.READ_CONTACTS), REQ_CONTACTS
            )
            return
        }
        result.success(queryContacts(query))
    }

    private fun queryContacts(query: String): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        val sel = "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?"
        val args = arrayOf("%$query%")
        contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
            ),
            sel, args,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC",
        )?.use { c ->
            val nameIdx = c.getColumnIndex(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
            )
            val numIdx = c.getColumnIndex(
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            var count = 0
            while (c.moveToNext() && count < 10) {
                val name = c.getString(nameIdx) ?: continue
                val number = c.getString(numIdx) ?: continue
                out.add(mapOf("name" to name, "number" to number))
                count++
            }
        }
        return out
    }

    // ----------------------------------------------------------------- calls

    private fun placeCall(number: String?, result: MethodChannel.Result) {
        if (number.isNullOrBlank()) {
            result.error("ARG", "No phone number given.", null)
            return
        }
        if (ContextCompat.checkSelfPermission(
                this, Manifest.permission.CALL_PHONE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingCallNumber = number
            pendingCallResult = result
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.CALL_PHONE), REQ_CALL
            )
            return
        }
        startCall(number)
        result.success(mapOf("ok" to true))
    }

    private fun startCall(number: String) {
        val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    // ---------------------------------------------------------------- alarms

    private fun setAlarm(hour: Int, minute: Int, result: MethodChannel.Result) {
        if (hour !in 0..23 || minute !in 0..59) {
            result.error("ARG", "Hour/minute out of range.", null)
            return
        }
        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minute)
            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                result.success(mapOf("ok" to true))
            } else {
                result.success(
                    mapOf("ok" to false, "error" to "No alarm app found.")
                )
            }
        } catch (e: Exception) {
            result.success(mapOf("ok" to false, "error" to e.message))
        }
    }

    // ------------------------------------------------------------ keep-alive

    private fun startKeepAlive(result: MethodChannel.Result) {
        val intent = Intent(this, WakeKeepAliveService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(mapOf("ok" to true))
    }

    private fun stopKeepAlive(result: MethodChannel.Result) {
        stopService(Intent(this, WakeKeepAliveService::class.java))
        result.success(mapOf("ok" to true))
    }

    // ------------------------------------------------------------ permissions

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            REQ_CONTACTS -> {
                val r = pendingContacts
                val q = pendingContactsQuery
                pendingContacts = null
                pendingContactsQuery = null
                if (r == null) return
                if (granted) {
                    // Permission just granted: run the ORIGINAL query now and
                    // return its real results.
                    r.success(queryContacts(q ?: ""))
                } else {
                    r.error(
                        "DENIED",
                        "Contacts permission denied — cannot look up contacts.",
                        null,
                    )
                }
            }
            REQ_CALL -> {
                val r = pendingCallResult
                val number = pendingCallNumber
                pendingCallResult = null
                pendingCallNumber = null
                if (r == null) return
                if (granted && !number.isNullOrBlank()) {
                    startCall(number)
                    r.success(mapOf("ok" to true))
                } else {
                    r.error(
                        "DENIED",
                        "Phone permission denied — cannot place the call.",
                        null,
                    )
                }
            }
        }
    }
}
