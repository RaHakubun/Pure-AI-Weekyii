package com.weekyii.android.ui.screens.today

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayStartFlowCoordinatorTest {
    @Test
    fun startFlowRequiresWarningThenRitualBeforeConfirmation() {
        val coordinator = TodayStartFlowCoordinator()

        coordinator.present()
        assertTrue(coordinator.state.value.isVisible)
        assertEquals(TodayStartFlowStep.WARNING, coordinator.state.value.step)

        coordinator.continueToRitual()
        assertEquals(TodayStartFlowStep.RITUAL, coordinator.state.value.step)

        coordinator.finish()
        assertFalse(coordinator.state.value.isVisible)
        assertEquals(TodayStartFlowStep.WARNING, coordinator.state.value.step)
    }

    @Test
    fun dismissingStartFlowResetsItToWarning() {
        val coordinator = TodayStartFlowCoordinator()

        coordinator.present()
        coordinator.continueToRitual()
        coordinator.dismiss()

        assertFalse(coordinator.state.value.isVisible)
        assertEquals(TodayStartFlowStep.WARNING, coordinator.state.value.step)
    }
}
