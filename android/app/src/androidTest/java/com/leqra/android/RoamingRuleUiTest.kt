package com.leqra.android

import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Rect
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
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

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
                    session.changeRules(
                        RoomRules.localDefaults("infinity")
                            .copy(infinityRandomBots = false, infinityBotSpawnRate = if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) 4.0 else .5)
                    )
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
                    val rate = all.filterIsInstance<Spinner>().single { it.adapter.count == 4 && it.adapter.getItem(0).toString() == "0.5×" }
                    val fill =
                        all.filterIsInstance<CheckBox>().single {
                            it.text.toString() == "Fill Infinity with random bots"
                        }
                    assertFalse(rate.isEnabled)
                    val before = bounds(root)
                    assertTrue("The rules dialog must be laid out", before.width() > 0 && before.height() > 0)
                    fill.performClick()
                    assertTrue(rate.isEnabled)
                    assertEquals(
                        "Enabling options must not resize the rules dialog",
                        before,
                        bounds(root),
                    )
                    rate.setSelection(if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) 0 else 3)
                    rate.requestRectangleOnScreen(Rect(0, 0, rate.width, rate.height), true)
                }
                SystemClock.sleep(100)
                if (orientation == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE) {
                    main {
                        val dialog = field(activity, "dialog") as AlertDialog
                        descendants(dialog.window!!.decorView).filterIsInstance<Spinner>().single { it.adapter.count == 4 && it.adapter.getItem(0).toString() == "0.5×" }.setSelection(0)
                    }
                    SystemClock.sleep(100)
                }
                main {
                    val session = field(activity, "session") as GameSession
                    val dialog = field(activity, "dialog") as AlertDialog
                    val apply = descendants(dialog.window!!.decorView).filterIsInstance<TextView>().single { it.text.toString() == "APPLY RULES" }
                    apply.performClick()
                    assertEquals(.5, session.rules.infinityBotSpawnRate, 0.0)
                    assertTrue(session.rules.infinityRandomBots)
                    val saved =
                        instrumentation.targetContext
                            .getSharedPreferences("leqra-settings", 0)
                            .getString("rules", null)
                    assertNotNull(saved)
                    assertEquals(
                        .5,
                        com.leqra.android.network.ProtocolJson.roomRules(
                                org.json.JSONObject(saved!!)
                            )
                            .infinityBotSpawnRate,
                        0.0,
                    )
                }
            }
        } finally {
            main { activity.finish() }
        }
    }
}
