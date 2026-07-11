import React, { useState, useEffect, useRef } from 'react';
import { loadKey, saveKey } from './utils/storage';
import { todayStr, quickReadiness, cleanWeight, cleanReps } from './utils/helpers';
import { generateWorkoutPlan, generateDebrief, generateWeeklyReview } from './api/gemini';
import { lastWeekSummary, mondayOf } from './utils/stats';
import {
  ingestHealthFromUrl,
  todaysHealth,
  pruneOldHealth,
  storeTodaysHealth,
  looksLikeHealthData,
} from './utils/healthIngest';
import { getApiKey } from './utils/storage';
import {
  getAllSessions,
  putSession,
  clearSessions,
  logEvent,
  migrateFromLocalStorage,
} from './db/db';
import { syncNow } from './db/sync';

import Home from './screens/Home';
import Progress from './screens/Progress';
import Coach from './screens/Coach';
import CheckIn from './screens/CheckIn';
import Generating from './screens/Generating';
import Workout from './screens/Workout';
import Finish from './screens/Finish';
import History from './screens/History';
import Settings from './screens/Settings';

// ------------------------------------------------------------------
// COACH — zero-friction daily training app
// Flow: Home → 60-second check-in → AI plans the session → guided
// workout with set logging → session saved → history feeds tomorrow.
// ------------------------------------------------------------------

export default function App() {
  const [screen, setScreen] = useState('loading');
  const [history, setHistory] = useState([]);
  const [todayPlan, setTodayPlan] = useState(null);
  const [error, setError] = useState('');
  const [statusMsg, setStatusMsg] = useState('');
  const [syncInfo, setSyncInfo] = useState(null);
  const lastSyncAt = useRef(0);
  const [weeklyReview, setWeeklyReview] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem('coach:weekly-review'));
    } catch {
      return null;
    }
  });

  // Check-in state — pre-filled with a "normal day"
  const [ci, setCi] = useState({
    energy: 7,
    sleep: 'OK',
    soreness: 'None',
    soreAreas: '',
    backTight: false,
    timeAvail: '60',
    health: '',
    notes: '',
  });

  // Finish state
  const [fin, setFin] = useState({ rpe: 7, pain: '', feedback: '' });

  // ── Load persisted data ──
  useEffect(() => {
    (async () => {
      checkHealthHash();
      try {
        pruneOldHealth();
      } catch { /* non-critical */ }

      await migrateFromLocalStorage();
      const h = await loadActive();
      const t = await loadKey('today', null);
      setHistory(h);
      if (t && t.date === todayStr()) setTodayPlan(t);
      logEvent('app_open', { sessions: h.length });
      runSync(); // background — pulls sessions logged on other devices
      maybeWeeklyReview(h); // background — Sunday review generation

      // If no API key, go to settings first
      if (!getApiKey()) {
        setScreen('settings');
      } else {
        setScreen('home');
      }
    })();
  }, []);

  const persistToday = async (t) => {
    setTodayPlan(t);
    await saveKey('today', t);
  };

  // deleted sessions stay in the DB as tombstones (so the deletion
  // syncs to other devices instead of being merged back) but never
  // reach the UI, stats, or the AI
  const loadActive = async () => (await getAllSessions()).filter((s) => !s.deleted);

  // ── Cloud sync (no-op until configured in Settings) ──
  const syncRetry = useRef(null);
  async function runSync(opts) {
    lastSyncAt.current = Date.now();
    setSyncInfo((s) => ({ ...(s || {}), state: 'syncing' }));
    try {
      const r = await syncNow(opts);
      clearTimeout(syncRetry.current);
      if (r.status === 'unconfigured') {
        setSyncInfo(null);
        return;
      }
      if (r.changedLocal) setHistory(await loadActive());
      setSyncInfo({ state: 'ok', at: Date.now(), sessions: r.sessions });
    } catch (e) {
      console.warn('[COACH] sync failed', e);
      logEvent('sync_failed', { message: e.message });
      setSyncInfo({ state: 'error', message: e.message });
      // iOS often aborts the fetch when the app is backgrounded right
      // after opening ("Load failed") — retry once things settle
      clearTimeout(syncRetry.current);
      syncRetry.current = setTimeout(() => {
        if (document.visibilityState === 'visible') runSync();
      }, 20000);
    }
  }

  // Watch data via the Shortcut deep link (#health=…). Must run not
  // only at boot: when the tab is already open, iOS performs a
  // fragment-only navigation (hashchange) or restores the page from
  // the back-forward cache (pageshow) with no reload at all.
  function checkHealthHash() {
    try {
      // Debug trail: record what the URL actually contained on arrival,
      // shown in Settings → Apple Watch card to diagnose the Shortcut
      if (window.location.search || window.location.hash) {
        localStorage.setItem('coach:url-debug', JSON.stringify({
          at: new Date().toISOString(),
          search: window.location.search.slice(0, 120),
          hash: window.location.hash.slice(0, 120),
        }));
      }
      const ingested = ingestHealthFromUrl();
      if (!ingested) return;
      window.history.replaceState(null, '', window.location.pathname);
      logEvent('health_autoreceived', { chars: ingested.length });
      // If a check-in is on screen right now, fill it in live too
      setCi((c) => ({ ...c, health: ingested }));
    } catch (e) {
      console.warn('[COACH] health ingest failed', e);
    }
  }

  useEffect(() => {
    window.addEventListener('hashchange', checkHealthHash);
    window.addEventListener('pageshow', checkHealthHash);
    return () => {
      window.removeEventListener('hashchange', checkHealthHash);
      window.removeEventListener('pageshow', checkHealthHash);
    };
  }, []);

  // Re-sync when the app regains focus (phones rarely reload the tab),
  // and every 5 minutes while it stays open. Throttled to 20s.
  useEffect(() => {
    const maybeSync = () => {
      if (document.visibilityState !== 'visible') return;
      checkHealthHash();
      if (Date.now() - lastSyncAt.current < 20000) return;
      runSync();
    };
    document.addEventListener('visibilitychange', maybeSync);
    window.addEventListener('focus', maybeSync);
    const interval = setInterval(maybeSync, 5 * 60 * 1000);
    return () => {
      document.removeEventListener('visibilitychange', maybeSync);
      window.removeEventListener('focus', maybeSync);
      clearInterval(interval);
    };
  }, []);

  // Default "normal day" check-in; grabs Watch data (stored or via the
  // clipboard — the button tap that got us here is the user gesture)
  async function buildDefaultCheckin() {
    let health = todaysHealth();
    if (!health && navigator.clipboard?.readText) {
      try {
        const clip = await navigator.clipboard.readText();
        if (looksLikeHealthData(clip)) {
          health = storeTodaysHealth(clip);
          logEvent('health_pasted_auto', { chars: health.length });
        }
      } catch { /* paste declined — fine */ }
    }
    return {
      energy: 7,
      sleep: 'OK',
      soreness: 'None',
      soreAreas: '',
      backTight: false,
      timeAvail: '60',
      health,
      notes: '',
    };
  }

  // ── AI call ──
  async function generateWorkout(checkin) {
    setScreen('generating');
    setError('');
    setStatusMsg('');

    logEvent('checkin_submitted', { checkin });

    try {
      const plan = await generateWorkoutPlan(checkin, history, setStatusMsg);
      logEvent('plan_generated', {
        sessionType: plan.sessionType,
        title: plan.title,
        recoveryScore: plan.recoveryScore,
        estTimeMin: plan.estTimeMin,
      });
      const log = (plan.exercises || []).map((ex) =>
        Array.from({ length: Number(ex.sets) || 3 }, () => ({
          weight: '',
          reps: '',
          done: false,
        }))
      );
      // unique id: same-day sessions are distinct and never overwrite
      const t = {
        id: `${todayStr()}#${Date.now()}`,
        date: todayStr(),
        startedAt: Date.now(),
        checkin,
        plan,
        log,
        finished: false,
      };
      await persistToday(t);
      setScreen('workout');
    } catch (e) {
      console.error(e);
      logEvent('generation_failed', { message: e.message });
      setError(e.message || "Couldn't build today's session. Check Settings for your API key, then try again.");
      setScreen('checkin');
    }
  }

  // ── Weekly review: generated on Sundays, shown for the week after ──
  async function maybeWeeklyReview(hist) {
    try {
      if (new Date().getDay() !== 0) return; // Sundays only
      const cur = JSON.parse(localStorage.getItem('coach:weekly-review') || 'null');
      if (cur?.week === mondayOf(todayStr())) return; // already done this week
      const summary = lastWeekSummary(hist);
      if (!summary || !getApiKey()) return;
      const text = await generateWeeklyReview(summary);
      const review = {
        week: mondayOf(todayStr()),
        at: Date.now(),
        text,
        count: summary.count,
        progressions: summary.progressions,
      };
      localStorage.setItem('coach:weekly-review', JSON.stringify(review));
      setWeeklyReview(review);
    } catch (e) {
      console.warn('[COACH] weekly review failed', e);
    }
  }

  // ── Mid-workout exercise swap (machine busy → use the alternative) ──
  function swapExercise(exI) {
    const ex = todayPlan?.plan?.exercises?.[exI];
    if (!ex?.alt) return;
    const t = {
      ...todayPlan,
      plan: {
        ...todayPlan.plan,
        exercises: todayPlan.plan.exercises.map((e, i) =>
          i === exI ? { ...e, name: e.alt, alt: e.name } : e
        ),
      },
    };
    logEvent('exercise_swapped', { from: ex.name, to: ex.alt });
    persistToday(t);
  }

  // ── Set logging ──
  const updateSet = (exI, setI, field, val) => {
    if (field === 'weight') val = cleanWeight(val);
    if (field === 'reps') val = cleanReps(val);
    const t = {
      ...todayPlan,
      log: todayPlan.log.map((a) => a.map((s) => ({ ...s }))),
    };
    t.log[exI][setI][field] = val;
    persistToday(t);
  };

  const sid = (s) => s.id || s.date;

  // ── Finish session ──
  async function finishSession() {
    // real session length, capped at 4h in case the tab sat open
    const durationMin = todayPlan.startedAt
      ? Math.min(Math.round((Date.now() - todayPlan.startedAt) / 60000), 240)
      : undefined;
    // typed-but-unticked sets clearly happened — complete them on save
    const t = {
      ...todayPlan,
      finished: true,
      fin,
      ...(durationMin && durationMin >= 10 ? { durationMin } : {}),
      log: (todayPlan.log || []).map((ex) =>
        ex.map((s) => (s.weight || s.reps ? { ...s, done: true } : s))
      ),
    };
    const newHist = [...history.filter((h) => sid(h) !== sid(t)), t];
    setHistory(newHist);
    await putSession(t);
    await persistToday(t);
    logEvent('session_finished', {
      date: t.date,
      sessionType: t.plan?.sessionType,
      rpe: fin.rpe,
      pain: fin.pain,
      feedback: fin.feedback,
      setsDone: (t.log || []).flat().filter((s) => s.done).length, // post auto-complete
    });
    setScreen('home');
    runSync(); // background — push today's session to the cloud

    // Background: coach debrief on the finished session
    generateDebrief(t, history)
      .then(async (text) => {
        const t2 = { ...t, debrief: text };
        await putSession(t2);
        await persistToday(t2);
        setHistory((hs) => hs.map((s) => (sid(s) === sid(t2) ? t2 : s)));
        runSync();
      })
      .catch((e) => console.warn('[COACH] debrief failed', e));
  }

  // ── Clear all history ──
  async function clearHistory() {
    setHistory([]);
    setTodayPlan(null);
    await clearSessions();
    await saveKey('today', null);
    logEvent('history_cleared');
    // overwrite the cloud too — a merge would resurrect the deleted data
    runSync({ replaceRemote: true });
  }

  // ── Reload after backup import or manual sync ──
  async function reloadFromDb() {
    setHistory(await loadActive());
  }

  // ── Delete / edit a logged session ──
  async function deleteSession(s) {
    await putSession({ ...s, deleted: true });
    setHistory((h) => h.filter((x) => sid(x) !== sid(s)));
    if (todayPlan && sid(todayPlan) === sid(s)) {
      setTodayPlan(null);
      await saveKey('today', null);
    }
    logEvent('session_deleted', { id: sid(s), date: s.date, sessionType: s.plan?.sessionType });
    runSync();
  }

  async function updateSession(s) {
    await putSession(s);
    setHistory((h) => h.map((x) => (sid(x) === sid(s) ? s : x)));
    if (todayPlan && sid(todayPlan) === sid(s)) await persistToday(s);
    logEvent('session_edited', { id: sid(s), date: s.date });
    runSync();
  }

  // ================= RENDER =================
  if (screen === 'loading') {
    return (
      <div className="app">
        <div className="center-fill">
          <div className="brand pulse">COACH</div>
        </div>
      </div>
    );
  }

  return (
    <div className="app">
      <div className="frame">
        {screen === 'home' && (
          <Home
            todayPlan={todayPlan}
            history={history}
            syncInfo={syncInfo}
            weeklyReview={weeklyReview}
            onProgress={() => setScreen('progress')}
            onStart={async () => {
              setCi(await buildDefaultCheckin());
              setError('');
              setScreen('checkin');
            }}
            onQuickStart={async () => {
              const checkin = await buildDefaultCheckin();
              setCi(checkin);
              logEvent('quick_start');
              generateWorkout({ ...checkin, notes: 'Quick start — assumed a normal day.' });
            }}
            onResume={() => setScreen('workout')}
            onHistory={() => setScreen('history')}
            onSettings={() => setScreen('settings')}
            onCoach={() => setScreen('coach')}
          />
        )}

        {screen === 'checkin' && (
          <CheckIn
            ci={ci}
            setCi={setCi}
            error={error}
            onCancel={() => setScreen('home')}
            onSubmit={() => generateWorkout(ci)}
          />
        )}

        {screen === 'generating' && (
          <Generating readiness={quickReadiness(ci)} statusMsg={statusMsg} />
        )}

        {screen === 'progress' && (
          <Progress history={history} onBack={() => setScreen('home')} />
        )}

        {screen === 'coach' && (
          <Coach
            history={history}
            todayPlan={todayPlan}
            onBack={() => setScreen(todayPlan && !todayPlan.finished ? 'workout' : 'home')}
          />
        )}

        {screen === 'workout' && todayPlan && (
          <Workout
            t={todayPlan}
            history={history}
            updateSet={updateSet}
            swapExercise={swapExercise}
            onCoach={() => setScreen('coach')}
            onBack={() => setScreen('home')}
            onFinish={() => {
              setFin({ rpe: 7, pain: '', feedback: '' });
              setScreen('finish');
            }}
          />
        )}

        {screen === 'finish' && (
          <Finish
            fin={fin}
            setFin={setFin}
            onSave={finishSession}
            onBack={() => setScreen('workout')}
          />
        )}

        {screen === 'history' && (
          <History
            history={history}
            onBack={() => setScreen('home')}
            onDelete={deleteSession}
            onUpdate={updateSession}
          />
        )}

        {screen === 'settings' && (
          <Settings
            onBack={() => setScreen('home')}
            onClearHistory={clearHistory}
            onDataImported={async () => {
              await reloadFromDb();
              runSync({ replaceRemote: true }); // restored backup becomes truth
            }}
            onSynced={reloadFromDb}
            sessionCount={history.length}
          />
        )}
      </div>
    </div>
  );
}
