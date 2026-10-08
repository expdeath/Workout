import React, { useState, useEffect } from 'react';
import Header from '../components/Header';
import { fmtDate, fmtSet, setLogged } from '../utils/helpers';
import { askCoach } from '../api/gemini';
import { getAllHealth } from '../db/db';
import { estimateSessionCalories, latestBodyWeightKg } from '../utils/calories';

// Full view of one logged session, with a chat scoped to just it.
// The chat is ephemeral — questions about an old session rarely
// matter next time you open it.
export default function HistoryDetail({ session, history, onBack }) {
  const s = session;
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [healthLog, setHealthLog] = useState([]);

  useEffect(() => {
    getAllHealth().then(setHealthLog).catch(() => {});
  }, []);

  const send = async () => {
    const text = input.trim();
    if (!text || busy) return;
    const next = [...messages, { role: 'user', text }];
    setMessages(next);
    setInput('');
    setError('');
    setBusy(true);
    try {
      const reply = await askCoach(next, { history, healthLog, focusSession: s });
      setMessages([...next, { role: 'coach', text: reply }]);
    } catch (e) {
      setError(
        /status|empty/i.test(e.message || '')
          ? 'The coach didn’t answer — check your API key in Settings, then try again.'
          : e.message || 'The coach is unreachable — try again.'
      );
    }
    setBusy(false);
  };

  const kcal = estimateSessionCalories(s, latestBodyWeightKg(healthLog));

  const exercises = (s.plan?.exercises || [])
    .map((ex, exI) => ({
      name: ex.name,
      sets: (s.log?.[exI] || []).filter(setLogged),
    }))
    .filter((ex) => ex.sets.length > 0);

  return (
    <div className="screen screen--slide-in">
      <Header title={s.plan?.sessionType} onBack={onBack} />

      <div className="eyebrow">
        {[fmtDate(s.date), s.durationMin ? `${s.durationMin} min` : '', kcal ? `~${kcal.toLocaleString()} kcal` : '', s.fin ? `RPE ${s.fin.rpe}` : '']
          .filter(Boolean)
          .join(' · ')}
      </div>
      {s.fin?.pain && (
        <div style={{ fontSize: 14, color: 'var(--amber)' }}>Pain: {s.fin.pain}</div>
      )}

      {/* every exercise in one card: name, then its sets on one line */}
      {exercises.length > 0 && (
        <div className="card">
          {exercises.map((ex, i) => (
            <div key={ex.name} style={i ? { borderTop: '1px solid var(--border)', marginTop: 10, paddingTop: 10 } : undefined}>
              <div style={{ fontSize: 15, fontWeight: 600 }}>{ex.name}</div>
              <div style={{ fontSize: 13.5, color: 'var(--muted)' }}>{ex.sets.map(fmtSet).join('  ·  ')}</div>
            </div>
          ))}
        </div>
      )}

      {exercises.length === 0 && (
        <p className="body" style={{ fontSize: 13.5, color: 'var(--muted)', marginTop: 10 }}>
          {s.fin?.feedback || 'No sets were logged for this session.'}
        </p>
      )}

      {s.fin?.feedback && exercises.length > 0 && (
        <p className="body" style={{ fontSize: 13.5, color: 'var(--muted)', marginTop: 10 }}>
          "{s.fin.feedback}"
        </p>
      )}

      {s.debrief && (
        <div className="card">
          <div className="card__label">Coach debrief</div>
          <p className="body">{s.debrief}</p>
        </div>
      )}

      <div
        className="q-label"
        style={{ margin: '22px 0 10px', borderTop: '1px solid var(--border)', paddingTop: 16 }}
      >
        Ask about this session
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        {messages.map((m, i) => (
          <div key={i} className={'chat-bubble' + (m.role === 'user' ? ' chat-bubble--user' : '')}>
            {m.text}
          </div>
        ))}
        {busy && <div className="chat-bubble pulse">…</div>}
        {error && <div className="err-box" style={{ marginTop: 0 }}>{error}</div>}
      </div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 12 }}>
        <input
          className="input"
          style={{ marginTop: 0, flex: 1 }}
          placeholder="Ask about this session…"
          value={input}
          onChange={(e) => setInput(e.target.value.slice(0, 500))}
          onKeyDown={(e) => e.key === 'Enter' && send()}
        />
        <button className="chat-send" onClick={send} disabled={busy || !input.trim()}>
          ↑
        </button>
      </div>
      <div style={{ height: 24 }} />
    </div>
  );
}
