package com.expdeath.coach.ui.screens

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.expdeath.coach.account.AppleSignIn
import com.expdeath.coach.account.Subscriptions
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.CoachApplication
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.IconWell
import com.expdeath.coach.ui.ReadinessBar
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TextButtonC
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.Title
import com.expdeath.coach.ui.VGap
import com.expdeath.coach.ui.openUrl
import com.expdeath.coach.ui.panel
import com.expdeath.coach.ui.sf
import kotlinx.coroutines.delay

/** The COACH wordmark, tracked wide. */
@Composable
fun Wordmark(modifier: Modifier = Modifier) {
    Text(
        "COACH", style = Theme.head(40f, FontWeight.Bold).copy(letterSpacing = 14.sp), color = Theme.amber,
        modifier = modifier.padding(start = 14.dp), // balances the trailing tracking so it reads centered
    )
}

/** Sign-in gate — ports Login.jsx. Any Google account gets in: the first
 *  sign-in creates its account, later ones reopen it. */
@Composable
fun LoginScreen(app: AppState) {
    val ctx = LocalContext.current
    var busy by remember { mutableStateOf(false) }
    CoachScreen {
        Column(
            Modifier.fillMaxSize().padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically),
        ) {
            Wordmark()
            T("Your AI training coach.", Theme.body(15f), Theme.muted, align = TextAlign.Center)
            if (app.loginError.isNotEmpty()) T(app.loginError, Theme.body(13.5f), Theme.amber, align = TextAlign.Center)
            BigButton(if (busy) "Signing in…" else "Sign in with Google", enabled = !busy) {
                val act = CoachApplication.activity ?: return@BigButton
                busy = true
                app.signIn(act).invokeOnCompletion { busy = false }
            }
            if (AppleSignIn.enabled) {
                Box(
                    Modifier.fillMaxWidth().height(54.dp).clip(RoundedCornerShape(Theme.radius)).background(Color.White)
                        .clickable(enabled = !busy) {
                            val act = CoachApplication.activity ?: return@clickable
                            busy = true
                            app.signInWithApple(act).invokeOnCompletion { busy = false }
                        },
                    contentAlignment = Alignment.Center,
                ) { T(" Sign in with Apple", Theme.body(17f, FontWeight.Medium), Color.Black) }
            }
            T("Any Google account works — new here? Your account is created on first sign-in.", Theme.body(13f), Theme.dim, align = TextAlign.Center)
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                TextButtonC("Privacy", style = Theme.body(13f)) { openUrl(ctx, Subscriptions.privacyURL) }
                TextButtonC("Terms", style = Theme.body(13f)) { openUrl(ctx, Subscriptions.termsURL) }
            }
        }
    }
}

/** What goes to Gemini — also listed under Settings → AI Coach. */
val aiShared = listOf(
    Triple("dumbbell", "Your workouts", "Logged sessions, sets and weights, goals, equipment, profile notes"),
    Triple("square.and.pencil", "Your check-ins and chats", "Energy, sleep, soreness, body weight, notes, questions you ask the coach"),
    Triple("heart.text.square", "Health Connect / watch data", "HRV, resting heart rate, sleep, steps, active energy"),
    Triple("photo", "Photos you choose", "Only a program photo you add in “Build with coach” — read, never stored by COACH"),
)

/** Asked once per account, before anything is sent to Google Gemini.
 *  Ports AIConsent.jsx; the answer is account state `aiConsent`, shared
 *  with the other apps, and Settings → AI Coach changes it. */
@Composable
fun AIConsentScreen(app: AppState) {
    val ctx = LocalContext.current
    CoachScreen {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            VGap(28.dp)
            IconWell("brain.head.profile", size = 56.dp)
            Title("Your AI coach", 34f)
            Text(buildAnnotatedString {
                append("COACH plans your sessions with ")
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("Google Gemini") }
                append(", an AI service run by Google. To do that it sends Gemini:")
            }, style = Theme.body(15f), color = Theme.textBody)
            for ((icon, title, sub) in aiShared) {
                Row(Modifier.fillMaxWidth().panel(radius = Theme.radiusSm).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(sf(icon), null, tint = Theme.amberText, modifier = Modifier.size(22.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        T(title, Theme.body(15f, FontWeight.SemiBold))
                        T(sub, Theme.meta(13f), Theme.muted)
                    }
                }
            }
            T("With your own Gemini key it goes straight from your phone to Google, under Google's Gemini API terms — on free keys Google may use it to improve its products. With COACH Pro it goes through COACH's server, which passes it on without keeping it, to COACH's paid Gemini account — which Google doesn't use to improve its products. Nothing is sent until you allow it, and you can turn it off any time in Settings → AI Coach.",
                Theme.meta(12.5f), Theme.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                TextButtonC("Gemini API terms", style = Theme.meta(12.5f)) { openUrl(ctx, "https://ai.google.dev/gemini-api/terms") }
                TextButtonC("Privacy policy", style = Theme.meta(12.5f)) { openUrl(ctx, Subscriptions.privacyURL) }
            }
            BigButton("Allow the AI coach") { app.aiConsentAnswered(true) }
            TextButtonC("Not now", Theme.muted, Theme.body(15f, FontWeight.Medium), modifier = Modifier.align(Alignment.CenterHorizontally)) { app.aiConsentAnswered(false) }
            T("Without it you can still log workouts and run your saved workouts as written.", Theme.meta(12.5f), Theme.dim, Modifier.fillMaxWidth(), align = TextAlign.Center)
        }
    }
}

private val generatingMessages = listOf(
    "Reading your training log…",
    "Checking recovery signals…",
    "Weighing volume vs. your evening…",
    "Building the session…",
)

/** Ports Generating.jsx — shown while Gemini builds the plan. Cycles
 *  reassurance lines unless the fallback ladder has a live status. */
@Composable
fun GeneratingScreen(app: AppState) {
    var msg by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) { delay(1800); msg = (msg + 1) % generatingMessages.size }
    }
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(1f, 0.45f, infiniteRepeatable(tween(1200), RepeatMode.Reverse), label = "a")
    CoachScreen {
        Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Wordmark(Modifier.alpha(pulse))
            VGap(28.dp)
            ReadinessBar(Helpers.quickReadiness(app.ci), "Readiness", Modifier.widthIn(max = 320.dp))
            VGap(18.dp)
            T(app.statusMsg.ifEmpty { generatingMessages[msg] }, Theme.body(14f), Theme.muted, align = TextAlign.Center)
        }
    }
}
