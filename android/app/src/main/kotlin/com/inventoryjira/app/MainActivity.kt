package com.inventoryjira.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity: регистрирует BroadcastReceiver для лазерного сканера
 * ТСД (Urovo DT50 и аналоги) и передаёт считанные коды в Flutter
 * через MethodChannel `inventory_jira/scanner` (метод `onScan`).
 *
 * Поддерживаемые нотации сканеров (Broadcast Intents):
 *  - Urovo:   android.intent.action.SCANRESULT (extra: "data")
 *  - Urovo:   urowo.intent.action.SCAN
 *  - Chainway:android.intent.action.SCANRESULT / com.chainway.scan.*
 *  - Zebra / Symbol DataWedge: com.symbol.datawedge.data_string
 *  - Honeywell: com.honeywell.action.BARCODE_SCAN
 *
 * Обычная «keyboard wedge»-работа (сканер эмулирует клавиатуру + Enter)
 * обрабатывается на стороне Flutter полем поиска (onSubmitted),
 * поэтому отдельный код здесь не требуется.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "inventory_jira/scanner"
    private var channel: MethodChannel? = null

    private val scanActions = listOf(
        "android.intent.action.SCANRESULT",
        "com.urovo.scan.action",
        "com.urovo.scan.action.DECODE",
        "urowo.intent.action.SCAN",
        "com.chainway.scan.ACTION_BARCODE_SEND",
        "com.symbol.datawedge.data_string",
        "com.zebra.datawedge.data_string",
        "com.honeywell.action.BARCODE_SCAN",
    )

    private val extraKeys = listOf(
        "data",
        "barcode",
        "barcode_string",
        "decode_data",
        "decode_data_string",
        "scannerdata",
        "data_string",
        "result",
        "com.symbol.datawedge.data_string",
    )

    private val scanReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val code = intent?.let { extractCode(it) } ?: return
            runOnUiThread {
                channel?.invokeMethod("onScan", code)
            }
        }
    }

    private fun extractCode(intent: Intent): String? {
        // 1) Строковые extras (стандарт большинства ТСД)
        for (key in extraKeys) {
            intent.getStringExtra(key)?.trim()?.takeIf { it.isNotEmpty() }
                ?.let { return it }
        }
        // 2) Бинарные extras (некоторые прошивки Urovo/Chainway)
        for (key in extraKeys) {
            intent.getByteArrayExtra(key)?.let { bytes ->
                return String(bytes, Charsets.UTF_8).trim()
                    .takeIf { it.isNotEmpty() }
            }
        }
        // 3) Всё, что лежит в extras как CharSequence/Serializable
        val extras = intent.extras
        if (extras != null) {
            for (key in extraKeys) {
                extras.getCharSequence(key)?.toString()?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { return it }
            }
        }
        return null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        val filter = IntentFilter()
        for (action in scanActions) {
            filter.addAction(action)
        }
        // Ретрансляция от системного сканера приходит извне нашего приложения,
        // поэтому на Android 13+ требуется RECEIVER_EXPORTED.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                scanReceiver,
                filter,
                RECEIVER_EXPORTED,
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(scanReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(scanReceiver)
        } catch (_: IllegalArgumentException) {
            // Ресивер уже отписан — игнорируем.
        }
        channel = null
        super.onDestroy()
    }
}
