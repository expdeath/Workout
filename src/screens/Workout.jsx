import React, { useState, useEffect, useRef } from 'react';
import ReadinessBar from '../components/ReadinessBar';
import { fmtDate } from '../utils/helpers';
import { lastPerformance, suggestNextWeight, recoveryCaution } from '../utils/stats';
import { intensifyWorkout } from '../api/gemini';
import { getAllHealth } from '../db/db';

/** "90s" → 90 · "2min" → 120 · "1-2min" → 120 · fallback 90 */
function parseRestSeconds(rest) {
  const m = String(rest || '').match(/(\d+)(?:\s*-\s*(\d+))?\s*(s|sec|m|min)?/i);
  if (!m) return 90;
  const n = Number(m[2] || m[1]);
  const unit = (m[3] || 's').toLowerCase();
  const secs = unit.startsWith('m') ? n * 60 : n;
  return Math.min(Math.max(secs, 15), 600);
}

export default function Workout({ t, history = [], updateSet, swapExercise, applyHarder, removeExercise, adjustSets, onCancelSession, onCoach, onBack, onFinish }) {
  const p = t.plan;

  // index of the exercise with the "remove?" confirm open, or null
  const [confirmRemove, setConfirmRemove] = useState(null);
  // "discard the whole session?" confirm — 'top' (header ✕) or
  // 'bottom' (link under Finish), so it opens next to where you tapped
  const [confirmCancel, setConfirmCancel] = useState(null);

  const cancelConfirm = (
    <div className="remove-confirm" style={{ marginTop: 10 }}>
      <span>
        Discard this session entirely?
        {t.log.some((ex) => ex.some((s) => s.done || s.weight || s.reps))
          ? ' Your logged sets will be lost.'
          : ''}
      </span>
      <button className="remove-confirm__yes" onClick={onCancelSession}>
        Discard
      </button>
      <button className="remove-confirm__no" onClick={() => setConfirmCancel(null)}>
        Keep
      </button>
    </div>
  );

  // ── "Make it harder" panel ──
  // null = closed · {loading, caution} = fetching · {caution, options, applied, error}
  const [harder, setHarder] = useState(null);

  async function openHarder() {
    const healthLog = await getAllHealth().catch(() => []);
    // gentle data-driven reminder, shown instantly while the AI thinks
    const caution = recoveryCaution(t.checkin, history, healthLog);
    setHarder({ loading: true, caution });
    try {
      const res = await intensifyWorkout(t, history, healthLog);
      setHarder({
        caution: caution || res.note || null,
        options: res.options || [],
        applied: [],
      });
    } catch (e) {
      console.warn('[COACH] intensify failed', e);
      setHarder({
        caution,
        options: [],
        applied: [],
        error: 'Couldn’t reach the coach — try again in a moment.',
      });
    }
  }

  const harderLabel = (o) => {
    const ex = o.exercise;
    if (o.kind === 'add') return `Add ${ex.name} — ${ex.sets}×${ex.reps}${ex.suggestedWeight ? ` @ ${ex.suggestedWeight}` : ''}`;
    if (o.kind === 'extraSet') return `One more set of ${o.target}`;
    return `Swap ${o.target} → ${ex.name} — ${ex.sets}×${ex.reps}${ex.suggestedWeight ? ` @ ${ex.suggestedWeight}` : ''}`;
  };
  const totalSets = t.log.reduce((a, ex) => a + ex.length, 0);
  const doneSets = t.log.reduce(
    (a, ex) => a + ex.filter((s) => s.done).length,
    0
  );

  // ── Rest timer ──
  const [timer, setTimer] = useState(null); // { endsAt, total, exName }
  const [now, setNow] = useState(Date.now());
  const audioRef = useRef(null);
  const firedRef = useRef(false);
  const wakeRef = useRef(null);

  // Screen wake lock: a locked iPhone suspends web JS entirely, so we
  // keep the screen awake while a rest timer runs — the countdown and
  // buzz then always fire. Released as soon as the timer ends.
  const acquireWake = async () => {
    try {
      wakeRef.current = await navigator.wakeLock?.request('screen');
    } catch { /* low battery / unsupported — timer still works on-screen */ }
  };
  const releaseWake = () => {
    try {
      wakeRef.current?.release();
    } catch { /* already released */ }
    wakeRef.current = null;
  };

  // wake locks drop when the app is hidden — re-grab on return if resting
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible' && timer) acquireWake();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      document.removeEventListener('visibilitychange', onVisible);
      releaseWake();
    };
  }, [timer]);

  useEffect(() => {
    if (!timer) return;
    const iv = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(iv);
  }, [timer]);

  const remaining = timer ? Math.ceil((timer.endsAt - now) / 1000) : 0;

  useEffect(() => {
    if (!timer || remaining > 0 || firedRef.current) return;
    firedRef.current = true;
    try {
      navigator.vibrate?.([200, 100, 200]);
      const ctx = audioRef.current;
      if (ctx) {
        [0, 0.25].forEach((delay) => {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.frequency.value = 880;
          gain.gain.setValueAtTime(0.15, ctx.currentTime + delay);
          gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + delay + 0.18);
          osc.connect(gain).connect(ctx.destination);
          osc.start(ctx.currentTime + delay);
          osc.stop(ctx.currentTime + delay + 0.2);
        });
      }
    } catch { /* audio is best-effort */ }
    // switched to another app? send a real notification
    if (document.hidden && typeof Notification !== 'undefined' && Notification.permission === 'granted') {
      navigator.serviceWorker?.ready
        .then((reg) => reg.showNotification('⏱ Rest over — GO', {
          body: `Next set: ${timer.exName}`,
          tag: 'rest-timer',
        }))
        .catch(() => {});
    }
    const clear = setTimeout(() => {
      setTimer(null);
      releaseWake();
    }, 4000);
    return () => clearTimeout(clear);
  }, [timer, remaining]);

  const toggleSet = (exI, setI, set) => {
    const turningOn = !set.done;
    updateSet(exI, setI, 'done', !set.done);
    if (!turningOn) return;
    // The tap is our user gesture — set up audio now so the buzz can play later
    try {
      if (!audioRef.current) {
        const Ctor = window.AudioContext || window.webkitAudioContext;
        if (Ctor) audioRef.current = new Ctor();
      }
      audioRef.current?.resume?.();
    } catch { /* no audio */ }
    const ex = p.exercises[exI];
    const secs = parseRestSeconds(ex?.rest);
    firedRef.current = false;
    setTimer({ endsAt: Date.now() + secs * 1000, total: secs, exName: ex?.name });
    acquireWake();
    // one-time ask, from this tap's user gesture (installed app only)
    if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
      Notification.requestPermission().catch(() => {});
    }
  };

  const fmtClock = (s) => `${Math.floor(Math.max(s, 0) / 60)}:${String(Math.max(s, 0) % 60).padStart(2, '0')}`;

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Home</button>
        <div className="header__actions">
          <button className="ghost-btn" onClick={onCoach}>🗨 Coach</button>
          <span className="mono sets-counter">
            {doneSets}/{totalSets} sets
          </span>
          <button
            className="ghost-btn ghost-btn--danger"
            aria-label="Cancel this session"
            onClick={() => setConfirmCancel(confirmCancel === 'top' ? null : 'top')}
          >
            ✕
          </button>
        </div>
      </header>

      {confirmCancel === 'top' && cancelConfirm}

      <div className="hero">
        <div className="eyebrow">
          {fmtDate(t.date)} · est. {p.estTimeMin} min door-to-door
        </div>
        <h1 className="h1 h1--accent">{p.sessionType.toUpperCase()}</h1>
        {p.title && <p className="subtitle">{p.title}</p>}
      </div>

      <ReadinessBar value={p.recoveryScore} label="Coach recovery score" />

      <div className="card" style={{ marginTop: 16 }}>
        <div className="card__label">Why this session</div>
        <p className="body">{p.reasoning}</p>
        {p.concerns ? (
          <p className="body body--warn" style={{ marginTop: 8 }}>
            ⚠ {p.concerns}
          </p>
        ) : null}
      </div>

      {p.warmup?.length > 0 && (
        <div className="card card--animate">
          <div className="card__label">Warm-up</div>
          {p.warmup.map((w, i) => (
            <p key={i} className="body">
              · {w}
            </p>
          ))}
        </div>
      )}

      {(p.exercises || []).map((ex, exI) => {
        const lastPerf = lastPerformance(history, ex.name);
        const suggest = suggestNextWeight(lastPerf, ex.reps);
        return (
        <div key={exI} className="ex-card card--animate">
          <div className="row-between">
            <div className="ex-name">{ex.name}</div>
            <div className="mono ex-meta">
              RPE {ex.rpe} · rest {ex.rest}
              <button
                className="ex-remove"
                aria-label={`Remove ${ex.name}`}
                onClick={() => setConfirmRemove(confirmRemove === exI ? null : exI)}
              >
                ✕
              </button>
            </div>
          </div>
          {confirmRemove === exI && (
            <div className="remove-confirm">
              <span>
                Skip {ex.name} today?
                {t.log[exI].some((s) => s.done || s.weight || s.reps)
                  ? ' Logged sets will be lost.'
                  : ''}
              </span>
              <button
                className="remove-confirm__yes"
                onClick={() => {
                  setConfirmRemove(null);
                  removeExercise?.(exI);
                }}
              >
                Remove
              </button>
              <button
                className="remove-confirm__no"
                onClick={() => setConfirmRemove(null)}
              >
                Keep
              </button>
            </div>
          )}
          <div className="mono ex-prescription">
            {ex.sets} × {ex.reps}
            {suggest
              ? ` · try ${suggest}kg`
              : ex.suggestedWeight
              ? ` · try ${ex.suggestedWeight}`
              : ''}
          </div>
          {lastPerf && (
            <div className="mono" style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 2 }}>
              last time ({fmtDate(lastPerf.date)}):{' '}
              {lastPerf.sets.map((s) => `${s.weight || '?'}×${s.reps || '?'}`).join(' · ')}
              {suggest ? ' — all reps hit, go up' : ''}
            </div>
          )}
          {ex.notes && <p className="body ex-notes">{ex.notes}</p>}
          <div className="sets-list">
            {t.log[exI].map((set, setI) => (
              <div key={setI} className="set-row">
                <button
                  className={'set-chk' + (set.done ? ' set-chk-on' : '')}
                  onClick={() => toggleSet(exI, setI, set)}
                >
                  {set.done ? '✓' : setI + 1}
                </button>
                <input
                  className="set-input"
                  inputMode="decimal"
                  placeholder={
                    suggest
                      ? String(suggest)
                      : lastPerf?.sets?.[setI]?.weight || 'kg'
                  }
                  value={set.weight}
                  onChange={(e) =>
                    updateSet(exI, setI, 'weight', e.target.value)
                  }
                />
                <span className="set-x">×</span>
                <input
                  className="set-input"
                  inputMode="numeric"
                  placeholder={lastPerf?.sets?.[setI]?.reps || 'reps'}
                  value={set.reps}
                  onChange={(e) =>
                    updateSet(exI, setI, 'reps', e.target.value)
                  }
                />
              </div>
            ))}
          </div>
          {(() => {
            const last = t.log[exI][t.log[exI].length - 1];
            const canDrop =
              t.log[exI].length > 1 && !(last?.done || last?.weight || last?.reps);
            return (
              <div className="set-adjust">
                <button
                  className="set-adjust__btn"
                  disabled={!canDrop}
                  onClick={() => adjustSets?.(exI, -1)}
                >
                  − set
                </button>
                <button
                  className="set-adjust__btn"
                  onClick={() => adjustSets?.(exI, +1)}
                >
                  + set
                </button>
              </div>
            );
          })()}
          {ex.alt && (
            <button className="swap-btn" onClick={() => swapExercise(exI)}>
              ⇄ Machine busy? Swap to {ex.alt}
            </button>
          )}
        </div>
        );
      })}

      {p.cardio && (
        <div className="card card--animate">
          <div className="card__label">Cardio</div>
          <p className="body">
            {p.cardio.desc} — {p.cardio.duration}
          </p>
        </div>
      )}

      {p.cooldown?.length > 0 && (
        <div className="card card--animate">
          <div className="card__label">Cool-down</div>
          {p.cooldown.map((c, i) => (
            <p key={i} className="body">
              · {c}
            </p>
          ))}
        </div>
      )}

      {!harder && (
        <button className="harder-btn" onClick={openHarder}>
          ⚡ Feeling strong? Make it harder
        </button>
      )}

      {harder && (
        <div className="card card--animate">
          <div className="row-between">
            <div className="card__label">Push harder</div>
            <button
              className="ghost-btn"
              style={{ padding: 0 }}
              onClick={() => setHarder(null)}
            >
              close
            </button>
          </div>

          {harder.caution && <p className="harder-note">{harder.caution}</p>}

          {harder.loading && (
            <p className="body" style={{ color: 'var(--muted)' }}>
              Coach is picking your upgrades…
            </p>
          )}

          {harder.error && <p className="body body--warn">{harder.error}</p>}

          {(harder.options || []).map((o, i) => {
            const done = harder.applied?.includes(i);
            return (
              <div key={i} className="harder-opt">
                <div>
                  <div className="body">{harderLabel(o)}</div>
                  {o.why && <div className="harder-why">{o.why}</div>}
                </div>
                <button
                  className={'harder-apply' + (done ? ' harder-apply--done' : '')}
                  disabled={done}
                  onClick={() => {
                    if (applyHarder?.(o)) {
                      setHarder((h) => ({ ...h, applied: [...(h.applied || []), i] }));
                    }
                  }}
                >
                  {done ? '✓ In' : 'Apply'}
                </button>
              </div>
            );
          })}

          {!harder.loading && !harder.error && !(harder.options || []).length && (
            <p className="body" style={{ color: 'var(--muted)' }}>
              No sensible upgrades today — finish strong instead.
            </p>
          )}
        </div>
      )}

      <button className="big-btn" onClick={onFinish}>
        Finish session
      </button>

      {confirmCancel === 'bottom' ? (
        cancelConfirm
      ) : (
        <button className="cancel-session-btn" onClick={() => setConfirmCancel('bottom')}>
          Cancel this session
        </button>
      )}
      <div style={{ height: timer ? 84 : 24 }} />

      {timer && (
        <div className={'rest-bar' + (remaining <= 0 ? ' rest-bar--go' : '')}>
          <div className="rest-bar__fill" style={{
            width: `${Math.max(0, Math.min(100, (remaining / timer.total) * 100))}%`,
          }} />
          <div className="rest-bar__content">
            <span className="mono rest-bar__time">
              {remaining <= 0 ? 'GO' : fmtClock(remaining)}
            </span>
            <span className="rest-bar__label">
              {remaining <= 0 ? `next set — ${timer.exName}` : `rest · ${timer.exName}`}
            </span>
            <button className="ghost-btn" onClick={() => { setTimer(null); releaseWake(); }}>
              Skip
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
