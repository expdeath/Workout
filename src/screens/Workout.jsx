import React from 'react';
import ReadinessBar from '../components/ReadinessBar';
import { fmtDate } from '../utils/helpers';

export default function Workout({ t, updateSet, onBack, onFinish }) {
  const p = t.plan;
  const totalSets = t.log.reduce((a, ex) => a + ex.length, 0);
  const doneSets = t.log.reduce(
    (a, ex) => a + ex.filter((s) => s.done).length,
    0
  );

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Home</button>
        <span className="mono sets-counter">
          {doneSets}/{totalSets} sets
        </span>
      </header>

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

      {(p.exercises || []).map((ex, exI) => (
        <div key={exI} className="ex-card card--animate">
          <div className="row-between">
            <div className="ex-name">{ex.name}</div>
            <div className="mono ex-meta">
              RPE {ex.rpe} · rest {ex.rest}
            </div>
          </div>
          <div className="mono ex-prescription">
            {ex.sets} × {ex.reps}
            {ex.suggestedWeight ? ` · try ${ex.suggestedWeight}` : ''}
          </div>
          {ex.notes && <p className="body ex-notes">{ex.notes}</p>}
          <div className="sets-list">
            {t.log[exI].map((set, setI) => (
              <div key={setI} className="set-row">
                <button
                  className={'set-chk' + (set.done ? ' set-chk-on' : '')}
                  onClick={() => updateSet(exI, setI, 'done', !set.done)}
                >
                  {set.done ? '✓' : setI + 1}
                </button>
                <input
                  className="set-input"
                  inputMode="decimal"
                  placeholder="kg"
                  value={set.weight}
                  onChange={(e) =>
                    updateSet(exI, setI, 'weight', e.target.value)
                  }
                />
                <span className="set-x">×</span>
                <input
                  className="set-input"
                  inputMode="numeric"
                  placeholder="reps"
                  value={set.reps}
                  onChange={(e) =>
                    updateSet(exI, setI, 'reps', e.target.value)
                  }
                />
              </div>
            ))}
          </div>
          {ex.alt && (
            <div className="mono ex-alt">Machine busy? → {ex.alt}</div>
          )}
        </div>
      ))}

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

      <button className="big-btn" onClick={onFinish}>
        Finish session
      </button>
      <div style={{ height: 24 }} />
    </div>
  );
}
