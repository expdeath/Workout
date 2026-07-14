import React, { useState, useEffect } from 'react';
import { fmtDate, setLogged } from '../utils/helpers';
import { askCoach } from '../api/gemini';
import { getAllHealth } from '../db/db';

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

  const exercises = (s.plan?.exercises || [])
    .map((ex, exI) => ({
      name: ex.name,
      sets: (s.log?.[exI] || []).filter(setLogged),
    }))
    .filter((ex) => ex.sets.length > 0);

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Log</button>
        <div className="brand-sm">{s.plan?.sessionType?.toUpperCase()}</div>
        <div />
      </header>

      <div className="eyebrow">
        {fmtDate(s.date)}
        {s.durationMin ? ` · ${s.durationMin} min` : ''}
      </div>
      {s.fin && (
        <div className="mono" style={{ fontSize: 13, color: 'var(--amber)', marginBottom: 14 }}>
          RPE {s.fin.rpe}/10
          {s.fin.pain ? ` · pain: ${s.fin.pain}` : ''}
        </div>
      )}

      {exercises.map((ex) => (
        <div key={ex.name} className="card" style={{ marginTop: 10, padding: '14px 16px' }}>
          <div className="ex-name" style={{ fontSize: 16, marginBottom: 4 }}>{ex.name}</div>
          {ex.sets.map((st, i) => (
            <div key={i} className="mono" style={{ fontSize: 13, color: 'var(--muted)', marginTop: 3 }}>
              Set {i + 1}: {st.weight || '?'}kg × {st.reps || '?'}
            </div>
          ))}
        </div>
      ))}

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
        {messages.length === 0 && (
          <div className="chat-bubble">
            Ask me anything about this {s.plan?.sessionType} session.
          </div>
        )}
        {messages.map((m, i) => (
          <div key={i} className={'chat-bubble' + (m.role === 'user' ? ' chat-bubble--user' : '')}>
            {m.text}
          </div>
        ))}
        {busy && <div className="chat-bubble mono pulse">…</div>}
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
