import React, { useEffect, useMemo, useRef, useState } from 'react';
import Header from '../components/Header';
import Icon from '../components/Icon';
import { TabHeader, PageHero, StatusPill, IconWell, useDesktop } from '../components/Shell';
import { onCloudChange } from '../db/cloud';
import { logEvent } from '../db/db';
import { buildWorkouts } from '../api/gemini';
import { listWorkouts, saveWorkout, deleteWorkout, blankExercise, getWorkout, daysLabel, WEEKDAYS, WEEK_ORDER } from '../utils/workouts';

/** Downscale a photo (≤1600px JPEG) for the coach — it's only sent to
 *  Gemini to read, never stored. */
async function photoForCoach(file) {
  const bmp = await createImageBitmap(file);
  const scale = Math.min(1, 1600 / Math.max(bmp.width, bmp.height));
  const c = document.createElement('canvas');
  c.width = Math.round(bmp.width * scale);
  c.height = Math.round(bmp.height * scale);
  c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
  const url = c.toDataURL('image/jpeg', 0.85);
  return { mimeType: 'image/jpeg', data: url.split(',')[1], preview: url };
}

const newDraft = (kind = 'session') => ({ name: '', kind, source: 'me', trainer: '', notes: '', adapt: false, days: [], exercises: [blankExercise()] });

/**
 * My workouts: the saved-workout library (yours and your trainer's),
 * the weekday schedule, daily add-ons, and the coach that builds them
 * from a program, a photo of one, or a description. Everything is
 * account state in Firestore (src/utils/workouts.js).
 */
export default function Workouts({ history, onBack, onStart, openId }) {
  const desktop = useDesktop();
  const [, bump] = useState(0);
  useEffect(() => onCloudChange((what) => what === 'state' && bump((n) => n + 1)), []);
  const all = listWorkouts();

  // view: list | edit | build | review
  const [view, setView] = useState(() => (openId && getWorkout(openId) ? 'edit' : 'list'));
  const [draft, setDraft] = useState(() => (openId ? getWorkout(openId) : null));
  const [drafts, setDrafts] = useState([]); // coach-built, awaiting review
  const [coachMsg, setCoachMsg] = useState('');
  const [confirmDel, setConfirmDel] = useState(null);
  const known = useMemo(
    () => [...new Set(history.flatMap((s) => (s.plan?.exercises || []).map((e) => e?.name?.trim()).filter(Boolean)))].sort(),
    [history]
  );

  const edit = (w) => {
    setDraft(JSON.parse(JSON.stringify(w)));
    setView('edit');
  };
  const save = () => {
    const saved = saveWorkout(draft);
    logEvent('workout_saved', { id: saved.id, kind: saved.kind, source: saved.source, exercises: saved.exercises.length, days: saved.days.length });
    setDraft(null);
    setView('list');
  };

  const sessions = all.filter((w) => w.kind === 'session');
  const addOns = all.filter((w) => w.kind === 'addon');

  // ── header (phone: back chevron; desktop: the site nav + page head) ──
  const titles = { list: 'My workouts', edit: draft?.id ? 'Edit workout' : 'New workout', build: 'Build with coach', review: 'Review' };
  const back = view === 'list' ? onBack : () => setView(view === 'review' ? 'build' : 'list');
  const head = desktop ? (
    <>
      <TabHeader title="Workouts" />
      <PageHero
        kicker={view === 'list' ? 'Your library' : <button className="link-btn" onClick={back}>← Back</button>}
        title={titles[view]}
        sub={view === 'list' ? 'Your own workouts and your trainer’s — scheduled by weekday, with add-ons that ride along on any session.' : undefined}
      >
        {view === 'list' && (
          <>
            <button className="small-btn" style={{ padding: '12px 18px' }} onClick={() => edit(newDraft())}>
              <Icon name="add" size={18} /> New workout
            </button>
            <button className="big-btn" onClick={() => setView('build')}>
              <Icon name="psychology" size={20} /> Build with coach
            </button>
          </>
        )}
      </PageHero>
    </>
  ) : (
    <Header title={titles[view]} onBack={back} />
  );

  if (view === 'edit' && draft) {
    return (
      <div className="screen screen--slide-in">
        {head}
        <Editor draft={draft} setDraft={setDraft} known={known} desktop={desktop} />
        <div className="wk-actions">
          <button className="big-btn" disabled={!draft.name.trim() || !draft.exercises.some((e) => e.name.trim())} onClick={save}>
            Save workout
          </button>
          <button className="ghost-btn" onClick={() => setView('list')}>Cancel</button>
        </div>
        <datalist id="known-exercises">{known.map((n) => <option key={n} value={n} />)}</datalist>
      </div>
    );
  }

  if (view === 'build') {
    return (
      <div className="screen screen--slide-in">
        {head}
        <Builder
          history={history}
          onBuilt={(res) => {
            setDrafts(res.workouts.map((w, i) => ({ ...w, _k: i, source: res.source, trainer: res.trainer })));
            setCoachMsg(res.message);
            setView('review');
          }}
        />
      </div>
    );
  }

  if (view === 'review') {
    const upd = (k, patch) => setDrafts(drafts.map((d) => (d._k === k ? { ...d, ...patch } : d)));
    return (
      <div className="screen screen--slide-in">
        {head}
        {coachMsg && (
          <div className="notice" style={{ marginTop: 0 }}>
            <IconWell icon="psychology" size={32} />
            <p className="body" style={{ flex: 1 }}>{coachMsg}</p>
          </div>
        )}
        <div className={desktop ? 'wk-grid' : undefined}>
          {drafts.map((d) => (
            <div key={d._k} className="card">
              <div className="row-between" style={{ gap: 8 }}>
                <input className="input wk-name" style={{ marginTop: 0 }} value={d.name} onChange={(e) => upd(d._k, { name: e.target.value })} />
                <button className="icon-btn" aria-label="Remove" onClick={() => setDrafts(drafts.filter((x) => x._k !== d._k))}>
                  <Icon name="x" size={20} />
                </button>
              </div>
              <KindAndDays w={d} onChange={(patch) => upd(d._k, patch)} />
              <ExerciseSummary exercises={d.exercises} />
            </div>
          ))}
        </div>
        <div className="wk-actions">
          <button
            className="big-btn"
            disabled={!drafts.length}
            onClick={() => {
              drafts.forEach(({ _k, ...d }) => saveWorkout(d));
              logEvent('workouts_imported', { count: drafts.length, source: drafts[0]?.source });
              setDrafts([]);
              setView('list');
            }}
          >
            Save {drafts.length > 1 ? `all ${drafts.length}` : 'workout'}
          </button>
          <button className="ghost-btn" onClick={() => setView('build')}>Start over</button>
        </div>
        <p className="foot-note">You can change anything later — open a workout and edit it.</p>
      </div>
    );
  }

  // ── list ──
  const card = (w) => (
    <div key={w.id} className="card wk-card">
      <div className="row-between" style={{ alignItems: 'flex-start', gap: 10 }}>
        <div style={{ minWidth: 0 }}>
          <div className="hero-title" style={{ fontSize: 22 }}>{w.name}</div>
          <div className="wk-badges">
            {w.source === 'trainer' && <StatusPill text={w.trainer ? `Trainer · ${w.trainer}` : 'Trainer'} color="var(--green)" dot={false} />}
            {w.kind === 'session' && <StatusPill text={w.adapt ? 'Coach adapts' : 'Kept exact'} color="var(--amber-text)" dot={false} />}
            <span className="caps" style={{ fontSize: 11.5, color: daysLabel(w) ? 'var(--text-body)' : 'var(--dim)' }}>
              {daysLabel(w) || 'Not scheduled'}
            </span>
          </div>
        </div>
        {w.kind === 'session' && (
          <button className="small-btn" style={{ flexShrink: 0 }} onClick={() => onStart(w.id)}>
            Start <Icon name="arrow_forward" size={16} />
          </button>
        )}
      </div>
      <ExerciseSummary exercises={w.exercises} max={desktop ? 6 : 4} />
      <div className="wk-card__foot">
        <button className="link-btn" onClick={() => edit(w)}><Icon name="edit" size={15} /> Edit</button>
        {confirmDel === w.id ? (
          <button className="link-btn link-btn--danger" onClick={() => { deleteWorkout(w.id); setConfirmDel(null); }}>Tap again to delete</button>
        ) : (
          <button className="link-btn" onClick={() => setConfirmDel(w.id)}><Icon name="trash" size={15} /> Delete</button>
        )}
      </div>
    </div>
  );

  return (
    <div className="screen screen--slide-in">
      {head}
      {!desktop && (
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="big-btn" style={{ marginTop: 0, flex: 1.4, fontSize: 15 }} onClick={() => setView('build')}>
            <Icon name="psychology" size={20} /> Build with coach
          </button>
          <button className="outline-btn" style={{ flex: 1, justifyContent: 'center' }} onClick={() => edit(newDraft())}>
            <Icon name="add" size={18} /> New
          </button>
        </div>
      )}

      <WeekPlan all={all} />

      {!all.length && (
        <div className="card" style={{ textAlign: 'center', padding: '28px 18px' }}>
          <div className="hero-title" style={{ fontSize: 22 }}>No saved workouts yet</div>
          <p className="body" style={{ color: 'var(--muted)', marginTop: 6 }}>
            Snap a photo of your trainer's program, paste it, or tell the coach what you want — it turns it into workouts you can schedule and start in one tap.
          </p>
        </div>
      )}

      {sessions.length > 0 && <div className="section-head"><span className="caps">Workouts</span></div>}
      <div className={desktop ? 'wk-grid' : undefined}>{sessions.map(card)}</div>
      {addOns.length > 0 && (
        <div className="section-head"><span className="caps">Add-ons</span><span className="caps section-head__note" style={{ color: 'var(--muted)' }}>Added to sessions on their days</span></div>
      )}
      <div className={desktop ? 'wk-grid' : undefined}>{addOns.map(card)}</div>
    </div>
  );
}

/** Mon–Sun: what's scheduled each day. */
function WeekPlan({ all }) {
  if (!all.some((w) => w.days.length || w.kind === 'addon')) return null;
  const todayIdx = new Date().getDay();
  return (
    <div className="card wk-week">
      {WEEK_ORDER.map((d) => {
        const s = all.filter((w) => w.kind === 'session' && w.days.includes(d));
        const a = all.filter((w) => w.kind === 'addon' && (!w.days.length || w.days.includes(d)));
        return (
          <div key={d} className={'wk-week__day' + (d === todayIdx ? ' wk-week__day--today' : '')}>
            <span className="caps">{WEEKDAYS[d]}</span>
            {s.map((w) => <span key={w.id} className="wk-week__item">{w.name}</span>)}
            {a.map((w) => <span key={w.id} className="wk-week__item wk-week__item--addon">+ {w.name}</span>)}
            {!s.length && !a.length && <span className="wk-week__rest">—</span>}
          </div>
        );
      })}
    </div>
  );
}

function ExerciseSummary({ exercises, max = 99 }) {
  return (
    <div className="wk-ex">
      {exercises.slice(0, max).map((e, i) => (
        <div key={i} className="wk-ex__row">
          <span className="wk-ex__name">{e.name}</span>
          <span className="caps wk-ex__dose">
            {e.sets} × {e.reps}{e.weight ? ` · ${e.weight}` : ''}
          </span>
        </div>
      ))}
      {exercises.length > max && <div className="wk-ex__more">+{exercises.length - max} more</div>}
    </div>
  );
}

/** Session / add-on, and the weekdays it's on. */
function KindAndDays({ w, onChange }) {
  const toggleDay = (d) => onChange({ days: w.days.includes(d) ? w.days.filter((x) => x !== d) : [...w.days, d] });
  return (
    <>
      <div className="seg-group" style={{ marginTop: 10 }}>
        {[['session', 'Workout'], ['addon', 'Daily add-on']].map(([v, l]) => (
          <button key={v} className={'seg-btn' + (w.kind === v ? ' seg-on' : '')} onClick={() => onChange({ kind: v })}>{l}</button>
        ))}
      </div>
      <div className="wk-days">
        {WEEK_ORDER.map((d) => (
          <button key={d} className={'chip' + (w.days.includes(d) ? ' chip-on' : '')} onClick={() => toggleDay(d)}>{WEEKDAYS[d]}</button>
        ))}
      </div>
      <p style={{ fontSize: 12.5, color: 'var(--muted)', margin: '6px 0 0' }}>
        {w.kind === 'addon'
          ? w.days.length ? 'Added to your session on these days.' : 'No days picked = added to every session.'
          : w.days.length ? 'Ready to start on these days — Today shows it.' : 'Not scheduled — start it from here or the check-in whenever you like.'}
      </p>
    </>
  );
}

function Editor({ draft, setDraft, desktop }) {
  const set = (patch) => setDraft({ ...draft, ...patch });
  const setEx = (i, patch) => set({ exercises: draft.exercises.map((e, j) => (j === i ? { ...e, ...patch } : e)) });
  const move = (i, dir) => {
    const ex = [...draft.exercises];
    const j = i + dir;
    if (j < 0 || j >= ex.length) return;
    [ex[i], ex[j]] = [ex[j], ex[i]];
    set({ exercises: ex });
  };
  return (
    <div className={desktop ? 'wk-editor' : undefined}>
      <div className="card" style={{ marginTop: desktop ? 0 : 14 }}>
        <div className="q-label" style={{ marginTop: 0 }}>Name</div>
        <input className="input" style={{ marginTop: 0 }} placeholder="e.g. Upper A, Leg day, Daily core" value={draft.name} onChange={(e) => set({ name: e.target.value.slice(0, 60) })} />
        <KindAndDays w={draft} onChange={set} />

        <div className="q-label">Who wrote it?</div>
        <div className="seg-group">
          {[['me', 'Me'], ['trainer', 'My trainer']].map(([v, l]) => (
            <button key={v} className={'seg-btn' + (draft.source === v ? ' seg-on' : '')} onClick={() => set({ source: v })}>{l}</button>
          ))}
        </div>
        {draft.source === 'trainer' && (
          <input className="input" placeholder="Trainer's name (optional)" value={draft.trainer} onChange={(e) => set({ trainer: e.target.value.slice(0, 40) })} />
        )}

        {draft.kind === 'session' && (
          <label className="toggle-row" style={{ marginTop: 14 }}>
            <span>
              <span className="toggle-row__title">Let the coach adapt it</span>
              <span className="toggle-row__sub">
                {draft.adapt
                  ? 'On a tired or sore day the coach may ease or trim it, and tells you what changed.'
                  : 'Off: kept exactly as written — the coach only fills in weights and flags recovery.'}
              </span>
            </span>
            <input type="checkbox" role="switch" className="switch" checked={!!draft.adapt} onChange={(e) => set({ adapt: e.target.checked })} />
          </label>
        )}

        <div className="q-label">Notes</div>
        <textarea className="input textarea" style={{ marginTop: 0, minHeight: 60 }} placeholder="Anything to remember — tempo, warm-up, the trainer's instructions…" value={draft.notes} onChange={(e) => set({ notes: e.target.value.slice(0, 600) })} />
      </div>

      <div className="card" style={{ marginTop: desktop ? 0 : 14 }}>
        <div className="row-between" style={{ alignItems: 'center' }}>
          <span className="caps">Exercises</span>
          <span className="caps" style={{ color: 'var(--muted)', fontSize: 11 }}>Weight empty = from your history</span>
        </div>
        {draft.exercises.map((e, i) => (
          <div key={i} className="wk-row">
            <div className="wk-row__top">
              <span className="caps wk-row__n">{i + 1}</span>
              <input className="input" list="known-exercises" placeholder="Exercise" value={e.name} onChange={(ev) => setEx(i, { name: ev.target.value.slice(0, 60) })} />
              <button className="icon-btn" aria-label="Move up" disabled={i === 0} onClick={() => move(i, -1)}><Icon name="expand_less" size={20} /></button>
              <button className="icon-btn" aria-label="Move down" disabled={i === draft.exercises.length - 1} onClick={() => move(i, 1)}><Icon name="down" size={20} /></button>
              <button className="icon-btn" aria-label="Remove exercise" onClick={() => set({ exercises: draft.exercises.filter((_, j) => j !== i) })}><Icon name="x" size={18} /></button>
            </div>
            <div className="wk-row__dose">
              <label><span className="caps">Sets</span><input className="input" inputMode="numeric" value={e.sets} onChange={(ev) => setEx(i, { sets: ev.target.value.replace(/\D/g, '').slice(0, 2) })} /></label>
              <label><span className="caps">Reps</span><input className="input" placeholder="8-10" value={e.reps} onChange={(ev) => setEx(i, { reps: ev.target.value.slice(0, 12) })} /></label>
              <label><span className="caps">Weight</span><input className="input" placeholder="auto" value={e.weight} onChange={(ev) => setEx(i, { weight: ev.target.value.slice(0, 16) })} /></label>
              <label><span className="caps">Rest</span><input className="input" placeholder="90s" value={e.rest} onChange={(ev) => setEx(i, { rest: ev.target.value.slice(0, 10) })} /></label>
            </div>
            <input className="input wk-row__notes" placeholder="Cue or note (optional)" value={e.notes} onChange={(ev) => setEx(i, { notes: ev.target.value.slice(0, 120) })} />
          </div>
        ))}
        <button className="outline-btn" style={{ width: '100%', justifyContent: 'center', marginTop: 12 }} onClick={() => set({ exercises: [...draft.exercises, blankExercise()] })}>
          <Icon name="add" size={18} /> Add exercise
        </button>
      </div>
    </div>
  );
}

/** Paste a program, add a photo of it, or describe what you want. */
function Builder({ history, onBuilt }) {
  const [source, setSource] = useState('trainer'); // trainer | me
  const [trainer, setTrainer] = useState('');
  const [text, setText] = useState('');
  const [photo, setPhoto] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const fileRef = useRef(null);

  const pick = async (file) => {
    if (!file) return;
    setError('');
    try {
      setPhoto(await photoForCoach(file));
    } catch {
      setError("Couldn't read that image — try a JPEG or PNG.");
    }
  };

  const go = async () => {
    setBusy(true);
    setError('');
    try {
      const res = await buildWorkouts({ text, image: photo && { mimeType: photo.mimeType, data: photo.data }, source, history });
      onBuilt({ ...res, source, trainer: source === 'trainer' ? trainer : '' });
    } catch (e) {
      setError(e.message || 'The coach couldn’t build that — try again.');
    }
    setBusy(false);
  };

  return (
    <div className="card" style={{ marginTop: 0 }}>
      <div className="seg-group">
        {[['trainer', 'From my trainer'], ['me', 'Describe what I want']].map(([v, l]) => (
          <button key={v} className={'seg-btn' + (source === v ? ' seg-on' : '')} onClick={() => setSource(v)}>{l}</button>
        ))}
      </div>
      <p className="body" style={{ color: 'var(--muted)', fontSize: 13.5, marginTop: 10 }}>
        {source === 'trainer'
          ? 'Paste the program your trainer sent, or add a photo of it. The coach copies it exactly — every exercise, set and rep — and splits a multi-day plan into separate workouts.'
          : 'Tell the coach what you want, e.g. “15 minutes of core every day” or “upper body with dumbbells, 45 min, Mon and Thu”. It builds it around your goals, equipment and history.'}
      </p>
      {source === 'trainer' && (
        <input className="input" placeholder="Trainer's name (optional)" value={trainer} onChange={(e) => setTrainer(e.target.value.slice(0, 40))} />
      )}
      <textarea
        className="input textarea"
        style={{ minHeight: 140 }}
        placeholder={source === 'trainer' ? 'Day A — Mon\nBench press 4x6 @ 70kg, rest 2 min\nDB row 3x10 each side\n…' : 'What do you want to do, and when?'}
        value={text}
        onChange={(e) => setText(e.target.value.slice(0, 6000))}
      />
      <input ref={fileRef} type="file" accept="image/*" style={{ display: 'none' }} onChange={(e) => pick(e.target.files?.[0])} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 10 }}>
        <button className="outline-btn" onClick={() => fileRef.current?.click()}>
          <Icon name="upload" size={18} /> {photo ? 'Change photo' : 'Add a photo'}
        </button>
        {photo && (
          <>
            <img src={photo.preview} alt="Program photo" className="wk-photo" />
            <button className="link-btn" onClick={() => setPhoto(null)}>Remove</button>
          </>
        )}
      </div>
      <p style={{ fontSize: 12, color: 'var(--dim)', marginTop: 6 }}>The photo is only sent to the coach to read — it isn't stored.</p>
      {error && <div className="err-box">{error}</div>}
      <button className="big-btn" disabled={busy || (!text.trim() && !photo)} onClick={go}>
        {busy ? 'The coach is reading it…' : 'Build my workouts'}
      </button>
    </div>
  );
}
