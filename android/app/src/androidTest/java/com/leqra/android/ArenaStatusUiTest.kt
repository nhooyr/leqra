package com.leqra.android

import android.content.ContextWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.accounts.isolatedAccountContext
import java.util.UUID
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ArenaStatusUiTest {
    @Test
    fun performanceSettingShowsOneCombinedReadoutAndFiniteOpensSidebar() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val accountContext = isolatedAccountContext()
            val prefix = "arena-status-${UUID.randomUUID()}-"
            val context = object : ContextWrapper(accountContext) {
                override fun getSharedPreferences(name: String, mode: Int) = super.getSharedPreferences(prefix + name, mode)
            }
            val prefs = context.getSharedPreferences("leqra-settings", 0)
            prefs.edit().putBoolean("showFPS", false).commit()
            val session = GameSession(context)
            try {
                assertTrue(session.showFPS)
                var sidebarOpened = false
                val status = NativeStatusView(context, openScores = {}, openSidebar = { sidebarOpened = true })
                session.publicSelected = true
                status.update(session, fps = 120)
                assertTrue("fps: —, ping: —" in visibleTexts(status))
                assertFalse(children(status).any { it.visibility == View.VISIBLE && it.contentDescription == "Open sidebar" })

                session.publicSelected = false
                session.selectMode("elimination")
                status.update(session, fps = 120)
                assertTrue("fps: —, ping: —" in visibleTexts(status))
                children(status).single { it.visibility == View.VISIBLE && it.contentDescription == "Open sidebar" }.performClick()
                assertTrue(sidebarOpened)

                session.showFPS = false
                session.save()
                status.update(session, fps = 120)
                assertFalse(visibleTexts(status).any { "fps:" in it || "ping:" in it })
                assertFalse(prefs.getBoolean("showPerformanceReadout", true))
            } finally {
                session.release()
                context.noBackupFilesDir.deleteRecursively()
            }
        }
    }

    private fun children(view: View) = if (view is ViewGroup) (0 until view.childCount).map(view::getChildAt) else emptyList()

    private fun visibleTexts(view: View): List<String> = when {
        view.visibility != View.VISIBLE -> emptyList()
        view is TextView -> listOf(view.text.toString())
        else -> children(view).flatMap(::visibleTexts)
    }
}
