package com.leqra.android

import android.annotation.TargetApi
import android.graphics.Insets
import android.view.WindowInsets
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 30)
@TargetApi(30)
class ImmersiveWindowTest {
    @Test
    fun reservesCutoutsAndSystemBarsWithoutCountingKeyboardSpaceTwice() {
        val insets = WindowInsets.Builder()
            .setInsets(WindowInsets.Type.displayCutout(), Insets.of(36, 12, 0, 0))
            .setInsets(WindowInsets.Type.statusBars(), Insets.of(0, 24, 0, 0))
            .setInsets(WindowInsets.Type.captionBar(), Insets.of(0, 42, 0, 0))
            .setInsets(WindowInsets.Type.navigationBars(), Insets.of(0, 0, 42, 36))
            .setInsets(WindowInsets.Type.systemGestures(), Insets.of(18, 0, 18, 28))
            .setInsets(WindowInsets.Type.ime(), Insets.of(0, 0, 0, 300))
            .build()

        val safe = insets.immersiveInsets()
        assertEquals(ImmersiveInsets(36, 42, 42, 36, 300), safe)
        assertEquals(300, safe.keyboard + safe.contentBottom)
    }

    @Test
    fun hiddenBarsKeepOnlyCutoutAndBottomGestureSpace() {
        val insets = WindowInsets.Builder()
            .setInsets(WindowInsets.Type.displayCutout(), Insets.of(0, 48, 0, 0))
            .setInsets(WindowInsets.Type.systemGestures(), Insets.of(18, 0, 18, 24))
            .build()

        assertEquals(ImmersiveInsets(0, 48, 0, 24), insets.immersiveInsets())
    }
}
