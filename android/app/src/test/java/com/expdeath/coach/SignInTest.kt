package com.expdeath.coach

import com.expdeath.coach.sync.Cloud
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A Google rejection must reach the login screen; a real "closed the sheet" must not. */
class SignInTest {
    @Test fun unregisteredAppIsReportedNotSwallowed() {
        assertTrue(Cloud.isConfigRejection("[16] Account reauth failed."))
        assertTrue(Cloud.isConfigRejection("[28444] Developer console is not set up correctly."))
        assertTrue(Cloud.isConfigRejection("10: DEVELOPER_ERROR"))
    }

    @Test fun userClosingTheSheetStaysSilent() {
        assertFalse(Cloud.isConfigRejection("activity is cancelled by the user."))
        assertFalse(Cloud.isConfigRejection("During begin sign in, failure response from one tap: 16: Cancelled by user."))
        assertFalse(Cloud.isConfigRejection(null))
    }
}
