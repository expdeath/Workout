import React, { useState, useEffect } from 'react';
import { loadKey, saveKey } from './utils/storage';
import { todayStr, quickReadiness } from './utils/helpers';
import { generateWorkoutPlan } from './api/gemini';
import { getApiKey } from './utils/storage';

import Home from './screens/Home';
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
      const h = await loadKey('history', []);
      const t = await loadKey('today', null);
      setHistory(h);
      if (t && t.date === todayStr()) setTodayPlan(t);

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

  // ── AI call ──
  async function generateWorkout(checkin) {
    setScreen('generating');
    setError('');
    setStatusMsg('');

    try {
      const plan = await generateWorkoutPlan(checkin, history, setStatusMsg);
      const log = (plan.exercises || []).map((ex) =>
        Array.from({ length: Number(ex.sets) || 3 }, () => ({
          weight: '',
          reps: '',
          done: false,
        }))
      );
      const t = { date: todayStr(), checkin, plan, log, finished: false };
      await persistToday(t);
      setScreen('workout');
    } catch (e) {
      console.error(e);
      setError(e.message || "Couldn't build today's session. Check Settings for your API key, then try again.");
      setScreen('checkin');
    }
  }

  // ── Set logging ──
  const updateSet = (exI, setI, field, val) => {
    const t = {
      ...todayPlan,
      log: todayPlan.log.map((a) => a.map((s) => ({ ...s }))),
    };
    t.log[exI][setI][field] = val;
    persistToday(t);
  };

  // ── Finish session ──
  async function finishSession() {
    const t = { ...todayPlan, finished: true, fin };
    const newHist = [...history.filter((h) => h.date !== t.date), t].slice(-30);
    setHistory(newHist);
    await saveKey('history', newHist);
    await persistToday(t);
    setScreen('home');
  }

  // ── Clear all history ──
  async function clearHistory() {
    setHistory([]);
    setTodayPlan(null);
    await saveKey('history', []);
    await saveKey('today', null);
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
            onStart={() => {
              setCi({
                energy: 7,
                sleep: 'OK',
                soreness: 'None',
                soreAreas: '',
                backTight: false,
                timeAvail: '60',
                health: '',
                notes: '',
              });
              setError('');
              setScreen('checkin');
            }}
            onResume={() => setScreen('workout')}
            onHistory={() => setScreen('history')}
            onSettings={() => setScreen('settings')}
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

        {screen === 'workout' && todayPlan && (
          <Workout
            t={todayPlan}
            updateSet={updateSet}
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
          <History history={history} onBack={() => setScreen('home')} />
        )}

        {screen === 'settings' && (
          <Settings
            onBack={() => setScreen('home')}
            onClearHistory={clearHistory}
          />
        )}
      </div>
    </div>
  );
}
