package nl.mennovanhout.nspanel_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Automatically starts the production application after boot or app update.
 *
 * The .dev variant must never start itself automatically: otherwise both
 * variants race for the foreground after a reboot.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val packageName = context.packageName

        if (packageName != "nl.mennovanhout.nspanel") {
            Log.i(
                "NSPanelBoot",
                "Ignoring ${intent.action} for non-production package: $packageName"
            )
            return
        }

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.i(
                    "NSPanelBoot",
                    "Starting production app after ${intent.action}"
                )

                val launch = Intent(context, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP
                    )
                }

                context.startActivity(launch)
            }
        }
    }
}
