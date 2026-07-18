import React, { useState, useEffect, useRef } from 'react';
import ReadinessBar from '../components/ReadinessBar';
import ActionSheet from '../components/ActionSheet';
import { fmtDate, fmtSet, setLogged, plateBreakdown, parsePlates, DEFAULT_BAR_KG } from '../utils/helpers';
import { lastPerformance, suggestNextWeight, recoveryCaution, logMode } from '../utils/stats';
import { intensifyWorkout } from '../api/gemini';
import { getAllHealth, getMedia, putMedia, deleteMedia } from '../db/db';
import { getAISettings, setAISettings } from '../utils/storage';

// per-set effort tap cycles through these; '' means not rated
const EFFORTS = ['', 'easy', 'good', 'grind'];

/** "90s" → 90 · "2min" → 120 · "1-2min" → 120 · fallback 90 */
function parseRestSeconds(rest) {
  const m = String(rest || '').match(/(\d+)(?:\s*-\s*(\d+))?\s*(s|sec|m|min)?/i);
  if (!m) return 90;
  const n = Number(m[2] || m[1]);
  const unit = (m[3] || 's').toLowerCase();
  const secs = unit.startsWith('m') ? n * 60 : n;
  return Math.min(Math.max(secs, 15), 600);
}

export default function Workout({ t, history = [], updateSet, swapExercise, renameExercise, applyHarder, removeExercise, adjustSets, onCancelSession, onCoach, onBack, onFinish }) {
  const p = t.plan;

  // per-exercise ⋯ menu, shown as a bottom action sheet:
  // null | { exI, mode: 'menu' | 'swap' | 'remove' }
  const [sheet, setSheet] = useState(null);
  // "discard the whole session?" confirm — 'top' (header ✕) or
  // 'bottom' (link under Finish), so it opens next to where you tapped
  const [confirmCancel, setConfirmCancel] = useState(null);

  const cancelConfirm = (
    <div className="remove-confirm" style={{ marginTop: 10 }}>
      <span>
        Discard this session entirely?
        {t.log.some((ex) => ex.some(setLogged))
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

  // index of the exercise with the plate breakdown open, or null
  const [platesFor, setPlatesFor] = useState(null);
  const gym = getAISettings();
  const barKg = Number(gym.barKg) || DEFAULT_BAR_KG;
  const plates = parsePlates(gym.plates) || undefined;

  // ── Cue notes: persistent per-exercise "note to self" cards ──
  // Keyed by lowercased exercise name; saved with the AI settings so
  // they survive re-planning, sync with backups, and reach the coach.
  const [cues, setCues] = useState(() => getAISettings().cueNotes || {});
  const [editingCue, setEditingCue] = useState(null); // exercise index or null
  const [cueDraft, setCueDraft] = useState('');
  const cueKey = (name) => String(name || '').trim().toLowerCase();
  const saveCue = (name) => {
    const next = { ...cues };
    const text = cueDraft.trim().slice(0, 200);
    if (text) next[cueKey(name)] = text;
    else delete next[cueKey(name)];
    setCues(next);
    setAISettings({ cueNotes: next });
    setEditingCue(null);
  };

  // ── Per-exercise form photo/clip (device-local, next to the cue) ──
  const [media, setMedia] = useState({}); // cueKey → { url, type }
  const [viewer, setViewer] = useState(null); // { url, type } or null
  const fileRef = useRef(null);
  const fileForRef = useRef(null); // exercise name awaiting a file pick
  useEffect(() => {
    let urls = [];
    let dead = false;
    (async () => {
      const next = {};
      for (const ex of p.exercises || []) {
        const rec = await getMedia(cueKey(ex.name)).catch(() => null);
        if (rec?.blob) {
          const url = URL.createObjectURL(rec.blob);
          urls.push(url);
          next[cueKey(ex.name)] = { url, type: rec.type || '' };
        }
      }
      if (!dead) setMedia(next);
    })();
    return () => {
      dead = true;
      urls.forEach((u) => URL.revokeObjectURL(u));
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [(p.exercises || []).map((e) => e.name).join('|')]);

  const onMediaFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    const name = fileForRef.current;
    if (!file || !name) return;
    if (file.size > 60 * 1024 * 1024) {
      alert('That file is over 60MB — record a shorter clip.');
      return;
    }
    const key = cueKey(name);
    await putMedia(key, file, file.type).catch(() => {});
    setMedia((m) => {
      if (m[key]?.url) URL.revokeObjectURL(m[key].url);
      return { ...m, [key]: { url: URL.createObjectURL(file), type: file.type } };
    });
  };

  const removeMedia = async (name) => {
    const key = cueKey(name);
    await deleteMedia(key).catch(() => {});
    setMedia((m) => {
      if (m[key]?.url) URL.revokeObjectURL(m[key].url);
      const next = { ...m };
      delete next[key];
      return next;
    });
  };

  // ── Custom swap: type what you actually did instead ──
  const [swapDraft, setSwapDraft] = useState('');
  const saveSwap = (exI) => {
    const name = swapDraft.trim();
    if (name) renameExercise?.(exI, name);
    setSheet(null);
  };

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

      {(() => {
        // Per-exercise context: how it's logged (kg×reps / min·km /
        // tick-off), history, suggestions, plate-math target.
        const exMeta = (exI) => {
          const ex = p.exercises[exI];
          const mode = logMode(ex.name, p.sessionType);
          const lastPerf = lastPerformance(history, ex.name);
          const suggest = mode !== 'strength' ? null : suggestNextWeight(lastPerf, ex.reps);
          const typed = [...t.log[exI]].reverse().find((s) => parseFloat(s.weight) > 0);
          const plateTarget =
            mode !== 'strength'
              ? null
              : parseFloat(typed?.weight) || suggest || parseFloat(ex.suggestedWeight) || null;
          return { ex, exI, mode, lastPerf, suggest, plateTarget };
        };

        const dot = (color) => (
          <span
            style={{
              width: 8,
              height: 8,
              borderRadius: 4,
              background: color,
              flexShrink: 0,
              marginRight: 8,
              display: 'inline-block',
            }}
          />
        );

        const renderHeader = (m, dotColor, paired) => {
          const { ex, exI, mode, lastPerf, suggest, plateTarget } = m;
          const plateInfo =
            platesFor === exI ? plateBreakdown(plateTarget, barKg, plates) : null;
          return (
            <div key={`h${exI}`}>
              <div className="row-between">
                <div className="ex-name" style={{ display: 'flex', alignItems: 'center' }}>
                  {dotColor ? dot(dotColor) : null}
                  {ex.name}
                </div>
                <div className="mono ex-meta">
                  RPE {ex.rpe} · rest {ex.rest}
                  <button
                    className="menu-btn"
                    aria-label={`Options for ${ex.name}`}
                    onClick={() => setSheet({ exI, mode: 'menu' })}
                  >
                    ⋯
                  </button>
                </div>
              </div>
              <div className="mono ex-prescription">
                {ex.sets} × {ex.reps}
                {suggest
                  ? ` · try ${suggest}kg`
                  : mode === 'strength' && ex.suggestedWeight
                  ? ` · try ${ex.suggestedWeight}`
                  : ''}
                {plateTarget ? (
                  <button
                    className={'plate-btn' + (platesFor === exI ? ' plate-btn--on' : '')}
                    aria-label={`Plate breakdown for ${plateTarget}kg`}
                    onClick={() => setPlatesFor(platesFor === exI ? null : exI)}
                  >
                    ⚖ plates
                  </button>
                ) : null}
              </div>
              {plateInfo && (
                <div className="mono plate-line">
                  {plateInfo.perSide.length
                    ? `${plateTarget}kg → ${plateInfo.bar}kg bar + ${plateInfo.perSide.join(' + ')} per side`
                    : `${plateTarget}kg → bar only (${plateInfo.bar}kg${
                        plateTarget < plateInfo.bar ? ' — lighter than the bar' : ''
                      })`}
                  {plateInfo.perSide.length && !plateInfo.exact
                    ? ` · closest load ${plateInfo.loaded}kg`
                    : ''}
                </div>
              )}
              {lastPerf && (
                <div className="mono" style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 2 }}>
                  last time ({fmtDate(lastPerf.date)}):{' '}
                  {lastPerf.sets.map(fmtSet).join(' · ')}
                  {suggest ? ' — all reps hit, go up' : ''}
                </div>
              )}
              {!paired && ex.superset && (
                <div className="mono superset-badge">
                  ⇋ superset {ex.superset}
                </div>
              )}
              {ex.notes && <p className="body ex-notes">{ex.notes}</p>}
              {editingCue === exI ? (
                <div>
                  <textarea
                    className="input textarea"
                    style={{ minHeight: 60, marginTop: 8 }}
                    placeholder="Note to self — sticks to this exercise forever. e.g. seat height 4 · tuck elbows, left shoulder"
                    value={cueDraft}
                    onChange={(e) => setCueDraft(e.target.value)}
                  />
                  <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                    <button className="chip chip-on" onClick={() => saveCue(ex.name)}>
                      Save note
                    </button>
                    <button
                      className="chip"
                      onClick={() => {
                        fileForRef.current = ex.name;
                        fileRef.current?.click();
                      }}
                    >
                      📷 {media[cueKey(ex.name)] ? 'Replace' : 'Add'} photo/clip
                    </button>
                    {media[cueKey(ex.name)] && (
                      <button className="chip" onClick={() => removeMedia(ex.name)}>
                        ✕ Remove media
                      </button>
                    )}
                    <button className="chip" onClick={() => setEditingCue(null)}>
                      Cancel
                    </button>
                  </div>
                  <p className="mono" style={{ fontSize: 11.5, color: 'var(--dim)', marginTop: 6 }}>
                    Photos/clips stay on this device — they don't sync.
                  </p>
                </div>
              ) : cues[cueKey(ex.name)] ? (
                <p
                  className="body cue-note"
                  onClick={() => {
                    setCueDraft(cues[cueKey(ex.name)]);
                    setEditingCue(exI);
                  }}
                >
                  ✎ {cues[cueKey(ex.name)]}
                </p>
              ) : null}
              {media[cueKey(ex.name)] && editingCue !== exI && (
                <button
                  className="media-thumb"
                  aria-label={`Form reference for ${ex.name}`}
                  onClick={() => setViewer(media[cueKey(ex.name)])}
                >
                  {media[cueKey(ex.name)].type.startsWith('video') ? (
                    <video src={media[cueKey(ex.name)].url} muted playsInline preload="metadata" />
                  ) : (
                    <img src={media[cueKey(ex.name)].url} alt="" />
                  )}
                  <span className="media-thumb__icon">
                    {media[cueKey(ex.name)].type.startsWith('video') ? '▶' : '🔍'}
                  </span>
                </button>
              )}
            </div>
          );
        };

        const renderRow = (m, setI, dotColor) => {
          const { ex, exI, mode, lastPerf, suggest } = m;
          const set = t.log[exI][setI];
          if (!set) return null;
          return (
            <div key={`${exI}-${setI}`} className="set-row">
              {dotColor ? dot(dotColor) : null}
              <button
                className={'set-chk' + (set.done ? ' set-chk-on' : '')}
                onClick={() => toggleSet(exI, setI, set)}
              >
                {set.done ? '✓' : setI + 1}
              </button>
              {mode === 'check' ? (
                <span
                  className="set-x"
                  style={{ flex: 1, fontSize: 13.5 }}
                  onClick={() => toggleSet(exI, setI, set)}
                >
                  {ex.reps}{set.done ? ' — done' : ' — tap to tick off'}
                </span>
              ) : mode === 'cardio' ? (
                <>
                  <input
                    className="set-input"
                    inputMode="decimal"
                    placeholder={lastPerf?.sets?.[setI]?.time || 'min'}
                    value={set.time || ''}
                    onChange={(e) => updateSet(exI, setI, 'time', e.target.value)}
                  />
                  <span className="set-x">min</span>
                  <input
                    className="set-input"
                    inputMode="decimal"
                    placeholder={lastPerf?.sets?.[setI]?.dist || 'km'}
                    value={set.dist || ''}
                    onChange={(e) => updateSet(exI, setI, 'dist', e.target.value)}
                  />
                  <span className="set-x">km</span>
                </>
              ) : (
                <>
                  <input
                    className="set-input"
                    inputMode="decimal"
                    placeholder={
                      suggest ? String(suggest) : lastPerf?.sets?.[setI]?.weight || 'kg'
                    }
                    value={set.weight}
                    onChange={(e) => updateSet(exI, setI, 'weight', e.target.value)}
                  />
                  <span className="set-x">×</span>
                  <input
                    className="set-input"
                    inputMode="numeric"
                    placeholder={lastPerf?.sets?.[setI]?.reps || 'reps'}
                    value={set.reps}
                    onChange={(e) => updateSet(exI, setI, 'reps', e.target.value)}
                  />
                </>
              )}
              {mode !== 'check' && (
                <button
                  className={'set-eff' + (set.effort ? ` set-eff--${set.effort}` : '')}
                  aria-label={`Effort for set ${setI + 1}: ${set.effort || 'not rated'}`}
                  onClick={() =>
                    updateSet(
                      exI,
                      setI,
                      'effort',
                      EFFORTS[(EFFORTS.indexOf(set.effort || '') + 1) % EFFORTS.length]
                    )
                  }
                >
                  {set.effort || 'rate'}
                </button>
              )}
            </div>
          );
        };

        // Superset flow: two exercises sharing a letter merge into one
        // card with rows interleaved A1 B1 A2 B2 — tick straight down,
        // no scrolling between cards.
        const renderedIdx = new Set();
        const cards = [];
        (p.exercises || []).forEach((ex, exI) => {
          if (renderedIdx.has(exI)) return;
          const partnerI = ex.superset
            ? p.exercises.findIndex((e, i2) => i2 !== exI && e?.superset === ex.superset)
            : -1;
          if (partnerI > exI) {
            renderedIdx.add(exI);
            renderedIdx.add(partnerI);
            const a = exMeta(exI);
            const b = exMeta(partnerI);
            const rounds = Math.max(t.log[exI].length, t.log[partnerI].length);
            const rows = [];
            for (let r = 0; r < rounds; r++) {
              rows.push(renderRow(a, r, 'var(--teal)'));
              rows.push(renderRow(b, r, 'var(--amber)'));
            }
            cards.push(
              <div key={`ss-${exI}`} className="ex-card card--animate">
                <div className="mono superset-badge" style={{ marginTop: 0, marginBottom: 8 }}>
                  ⇋ superset {ex.superset} — one set of each, top to bottom
                </div>
                {renderHeader(a, 'var(--teal)', true)}
                <div style={{ height: 12 }} />
                {renderHeader(b, 'var(--amber)', true)}
                <div className="sets-list">{rows}</div>
              </div>
            );
          } else {
            renderedIdx.add(exI);
            const m = exMeta(exI);
            cards.push(
              <div key={exI} className="ex-card card--animate">
                {renderHeader(m, null, false)}
                <div className="sets-list">
                  {t.log[exI].map((set, setI) => renderRow(m, setI, null))}
                </div>
              </div>
            );
          }
        });
        return cards;
      })()}

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

      {sheet && (() => {
        const ex = p.exercises[sheet.exI];
        if (!ex) return null;
        const rows = t.log[sheet.exI] || [];
        const canDrop = rows.length > 1 && !setLogged(rows[rows.length - 1]);
        return (
          <ActionSheet title={ex.name} onClose={() => setSheet(null)}>
            {sheet.mode === 'menu' && (
              <>
                {ex.alt && (
                  <button
                    className="action-sheet__item action-sheet__item--teal"
                    onClick={() => {
                      setSheet(null);
                      swapExercise(sheet.exI);
                    }}
                  >
                    ⇄ Swap to {ex.alt}
                  </button>
                )}
                <button
                  className="action-sheet__item action-sheet__item--teal"
                  onClick={() => {
                    setSwapDraft('');
                    setSheet({ ...sheet, mode: 'swap' });
                  }}
                >
                  ⇄ Did something else…
                </button>
                <a
                  className="action-sheet__item"
                  style={{ textDecoration: 'none' }}
                  href={`https://www.youtube.com/results?search_query=${encodeURIComponent(
                    `how to ${ex.name} proper form`
                  )}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={() => setSheet(null)}
                >
                  ▶ Watch how-to video
                </a>
                <button
                  className="action-sheet__item"
                  onClick={() => {
                    setSheet(null);
                    adjustSets?.(sheet.exI, +1);
                  }}
                >
                  ＋ Add set
                </button>
                <button
                  className="action-sheet__item"
                  disabled={!canDrop}
                  onClick={() => {
                    setSheet(null);
                    adjustSets?.(sheet.exI, -1);
                  }}
                >
                  − Remove set
                </button>
                <button
                  className="action-sheet__item"
                  onClick={() => {
                    setCueDraft(cues[cueKey(ex.name)] || '');
                    setEditingCue(sheet.exI);
                    setSheet(null);
                  }}
                >
                  ✎ {cues[cueKey(ex.name)] ? 'Edit note to self' : 'Note to self'}
                </button>
                <button
                  className="action-sheet__item action-sheet__item--danger"
                  onClick={() => setSheet({ ...sheet, mode: 'remove' })}
                >
                  ✕ Remove exercise
                </button>
              </>
            )}

            {sheet.mode === 'swap' && (
              <>
                <p className="action-sheet__note">
                  Log what you actually did instead — it replaces {ex.name} for
                  today, and one tap swaps it back.
                </p>
                <input
                  className="input"
                  placeholder="e.g. Running"
                  value={swapDraft}
                  autoFocus
                  onChange={(e) => setSwapDraft(e.target.value.slice(0, 60))}
                  onKeyDown={(e) => e.key === 'Enter' && saveSwap(sheet.exI)}
                />
                <button
                  className="action-sheet__go"
                  disabled={!swapDraft.trim()}
                  onClick={() => saveSwap(sheet.exI)}
                >
                  ⇄ Swap it in
                </button>
              </>
            )}

            {sheet.mode === 'remove' && (
              <>
                <p className="action-sheet__note">
                  Skip {ex.name} today?
                  {rows.some(setLogged) ? ' Logged sets will be lost.' : ''}
                </p>
                <button
                  className="action-sheet__go action-sheet__go--danger"
                  onClick={() => {
                    setSheet(null);
                    removeExercise?.(sheet.exI);
                  }}
                >
                  ✕ Remove exercise
                </button>
              </>
            )}
          </ActionSheet>
        );
      })()}

      <input
        ref={fileRef}
        type="file"
        accept="image/*,video/*"
        style={{ display: 'none' }}
        onChange={onMediaFile}
      />

      {viewer && (
        <div className="media-viewer" onClick={() => setViewer(null)}>
          {viewer.type.startsWith('video') ? (
            <video src={viewer.url} controls autoPlay playsInline onClick={(e) => e.stopPropagation()} />
          ) : (
            <img src={viewer.url} alt="Form reference" />
          )}
          <button className="media-viewer__close" onClick={() => setViewer(null)}>
            ✕
          </button>
        </div>
      )}

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
