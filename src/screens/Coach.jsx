import React, { useState, useRef, useEffect } from 'react';
import Icon from '../components/Icon';

const STARTERS = [
  'Shoulder feels off — what do I swap?',
  'Too tired for legs. Alternatives?',
  'How heavy should warm-up sets be?',
];
import { askCoach } from '../api/gemini';
import { getAllHealth } from '../db/db';
import { todayStr } from '../utils/helpers';
import { cloudState, cloudSetState, cloudStateKeys } from '../db/cloud';

// Today's chat is account state in Firestore (chat-<date>), so it
// follows you between devices.
const CHAT_KEY = 'chat-';

function loadChat() {
  return cloudState(CHAT_KEY + todayStr(), []) || [];
}

function saveChat(messages) {
  // today's chat only — yesterday's questions rarely matter tomorrow
  for (const k of cloudStateKeys()) {
    if (k.startsWith(CHAT_KEY) && k !== CHAT_KEY + todayStr()) cloudSetState(k, null);
  }
  cloudSetState(CHAT_KEY + todayStr(), messages.slice(-30));
}

// Coach chat as a bottom sheet — reachable from any screen via the
// floating bubble, without leaving what you were doing.
export default function Coach({ history, todayPlan, onClose }) {
  const [messages, setMessages] = useState(loadChat);
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [healthLog, setHealthLog] = useState([]);
  const endRef = useRef(null);

  useEffect(() => {
    getAllHealth().then(setHealthLog).catch(() => {});
  }, []);

  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' });
  }, [messages, busy]);

  const send = async () => {
    const text = input.trim();
    if (!text || busy) return;
    const next = [...messages, { role: 'user', text }];
    setMessages(next);
    saveChat(next);
    setInput('');
    setError('');
    setBusy(true);
    try {
      const reply = await askCoach(next, { history, todayPlan, healthLog });
      const done = [...next, { role: 'coach', text: reply }];
      setMessages(done);
      saveChat(done);
    } catch (e) {
      setError(
        /status|empty/i.test(e.message || '')
          ? 'The coach didn’t answer — check your API key in Settings, then try again.'
          : e.message || 'The coach is unreachable — try again.'
      );
    }
    setBusy(false);
  };

  return (
    <>
      <div className="chat-sheet-backdrop" onClick={onClose} />
      <div className="chat-sheet">
        <div className="chat-sheet__head">
          <div className="screen-header__title" style={{ fontSize: 26 }}>Coach</div>
          <button className="icon-btn" aria-label="Close chat" onClick={onClose}>
            <Icon name="x" size={22} />
          </button>
        </div>

        <div className="chat-scroll">
          {/* tap a starter instead of reading a paragraph of examples */}
          {messages.length === 0 &&
            STARTERS.map((q) => (
              <button key={q} className="chat-starter" onClick={() => setInput(q)}>
                {q}
              </button>
            ))}
          {messages.map((m, i) => (
            <div key={i} className={'chat-bubble' + (m.role === 'user' ? ' chat-bubble--user' : '')}>
              {m.text}
            </div>
          ))}
          {busy && <div className="chat-bubble pulse">…</div>}
          {error && <div className="err-box">{error}</div>}
          <div ref={endRef} />
        </div>

        <div className="chat-input-row">
          <input
            className="input"
            style={{ marginTop: 0, flex: 1 }}
            placeholder="Ask the coach…"
            value={input}
            onChange={(e) => setInput(e.target.value.slice(0, 500))}
            onKeyDown={(e) => e.key === 'Enter' && send()}
          />
          <button className="chat-send" onClick={send} disabled={busy || !input.trim()}>
            ↑
          </button>
        </div>
      </div>
    </>
  );
}
