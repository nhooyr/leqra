package com.leqra.android

import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Rect
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.Spinner
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.leqra.core.RoomRules
import com.leqra.core.roamingBotSpawnRates
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class RoamingRuleUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }

    private fun field(owner: Any, name: String): Any? =
        owner.javaClass.getDeclaredField(name).run {
            isAccessible = true
            get(owner)
        }

    private fun descendants(view: View): List<View> =
        listOf(view) +
            if (view is ViewGroup)
                (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
            else emptyList()

    private fun bounds(view: View) = Rect().also { view.getGlobalVisibleRect(it) }

    @Test
    fun roamingRateIsDisabledWhenBotsAreOffAndPersistsInBothOrientations() {
        instrumentation.targetContext
            .getSharedPreferences("leqra-settings", 0)
            .edit()
            .putBoolean("muted", true)
            .putBoolean("publicSelected", false)
            .putString("callsign", "Rule Pilot")
            .putBoolean("autoPending0", false)
            .putBoolean("autoPending1", false)
            .putString("server", "http://127.0.0.1:1")
            .commit()
        main {
            instrumentation.targetContext.startActivity(
                Intent(instrumentation.targetContext, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            )
        }
        val deadline = SystemClock.elapsedRealtime() + 10000
        var launched: MainActivity? = null
        while (launched == null && SystemClock.elapsedRealtime() < deadline) {
            launched = main {
                ActivityLifecycleMonitorRegistry.getInstance()
                    .getActivitiesInStage(Stage.RESUMED)
                    .filterIsInstance<MainActivity>()
                    .firstOrNull()
            }
            if (launched == null) SystemClock.sleep(20)
        }
        val activity =
            checkNotNull(launched) {
                "The continuously animated menu must resume without waiting for UI idleness"
            }
        try {
            for (orientation in
                listOf(
                    ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
                    ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
                )) {
                main { activity.requestedOrientation = orientation }
                SystemClock.sleep(150)
                main {
                    val session = field(activity, "session") as GameSession
                    val legacy = orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    session.changeRules(RoomRules.localDefaults("infinity").copy(
                        infinityRandomBots = false, infinityBotDifficulty = "normal", infinityRandomDifficulty = true,
                        infinityBotSpawnRates = if (legacy) null else mapOf("dumb" to 4.0, "normal" to 1.0, "godlike" to .5),
                    ))
                    activity.javaClass
                        .getDeclaredMethod("showRules")
                        .apply { isAccessible = true }
                        .invoke(activity)
                }
                val layoutDeadline = SystemClock.elapsedRealtime() + 5000
                while (main { (field(activity, "dialog") as AlertDialog).window!!.decorView.width == 0 } && SystemClock.elapsedRealtime() < layoutDeadline) SystemClock.sleep(20)
                main {
                    val dialog = field(activity, "dialog") as AlertDialog
                    val root = dialog.window!!.decorView
                    val all = descendants(root)
                    val rates = all.filterIsInstance<Spinner>().filter { it.tag?.toString()?.startsWith("roamingRate:") == true }.associateBy { it.tag.toString().substringAfter(":") }
                    val fill = all.filterIsInstance<CheckBox>().single { it.text.toString() == "Fill Infinity with random bots" }
                    assertEquals(5, rates.size)
                    assertTrue(rates.values.all { !it.isEnabled })
                    assertFalse(all.filterIsInstance<TextView>().any { it.text.toString() == "Random bot difficulty" })
                    if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) {
                        assertEquals("0.667×", rates.getValue("easy").selectedItem)
                    }
                    val before = bounds(root)
                    assertTrue("The rules dialog must be laid out", before.width() > 0 && before.height() > 0)
                    fill.performClick()
                    assertTrue(rates.values.all { it.isEnabled })
                    assertEquals("Enabling options must not resize the rules dialog", before, bounds(root))
                    fun pick(level: String, value: String) {
                        val spinner = rates.getValue(level)
                        spinner.setSelection((0 until spinner.adapter.count).first { spinner.adapter.getItem(it).toString() == value })
                    }
                    if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) {
                        pick("dumb", "Off"); pick("normal", "4×"); pick("godlike", "1×")
                    } else {
                        pick("dumb", "0.5×"); pick("normal", "Off"); pick("godlike", "4×")
                    }
                    rates.getValue("normal").requestRectangleOnScreen(Rect(0, 0, rates.getValue("normal").width, rates.getValue("normal").height), true)
                }
                SystemClock.sleep(150)
                main {
                    val session = field(activity, "session") as GameSession
                    val dialog = field(activity, "dialog") as AlertDialog
                    val shown = dialog.window!!.decorView
                    val bitmap = Bitmap.createBitmap(shown.width, shown.height, Bitmap.Config.ARGB_8888)
                    shown.draw(android.graphics.Canvas(bitmap))
                    File(instrumentation.targetContext.cacheDir, "roaming-rates-${if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) "portrait" else "landscape"}.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    bitmap.recycle()
                    val apply = descendants(dialog.window!!.decorView).filterIsInstance<TextView>().single { it.text.toString() == "APPLY RULES" }
                    apply.performClick()
                    val actual = session.rules.roamingBotSpawnRates()
                    assertEquals(if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) 0.0 else .5, actual.getValue("dumb"), 0.0)
                    assertEquals(if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) 4.0 else 0.0, actual.getValue("normal"), 0.0)
                    assertEquals(if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) 1.0 else 4.0, actual.getValue("godlike"), 0.0)
                    if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) assertEquals(2.0 / 3, actual.getValue("easy"), 0.0)
                    assertTrue(session.rules.infinityRandomBots)
                    val saved =
                        instrumentation.targetContext
                            .getSharedPreferences("leqra-settings", 0)
                            .getString("rules", null)
                    assertNotNull(saved)
                    assertEquals(actual, com.leqra.android.network.ProtocolJson.roomRules(org.json.JSONObject(saved!!)).roamingBotSpawnRates())
                }
            }
        } finally {
            main { activity.finish() }
        }
    }
}
