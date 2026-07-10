import React, { useState } from 'react';
import { getApiKey, setApiKey } from '../utils/storage';

export default function Settings({ onBack, onClearHistory }) {
  const [key, setKey] = useState(getApiKey());
  const [showKey, setShowKey] = useState(false);
  const [saved, setSaved] = useState(false);
  const [confirmClear, setConfirmClear] = useState(false);

  const handleSave = () => {
    setApiKey(key.trim());
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  const handleClear = () => {
    if (!confirmClear) {
      setConfirmClear(true);
      return;
    }
    onClearHistory();
    setConfirmClear(false);
  };

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Home</button>
        <div className="brand-sm">SETTINGS</div>
        <div />
      </header>

      <div className="card">
        <div className="card__label">Gemini API Key</div>
        <p className="body" style={{ marginBottom: 12, color: 'var(--muted)' }}>
          Your key is stored locally in your browser. It's only sent to Google's
          Gemini API — never to any other server.
        </p>
        <div className="settings-key-row">
          <input
            className="input"
            type={showKey ? 'text' : 'password'}
            placeholder="AIzaSy..."
            value={key}
            onChange={(e) => setKey(e.target.value)}
            style={{ marginTop: 0, flex: 1 }}
          />
          <button
            className="ghost-btn"
            onClick={() => setShowKey(!showKey)}
            style={{ flexShrink: 0 }}
          >
            {showKey ? 'Hide' : 'Show'}
          </button>
        </div>
        <button
          className="big-btn"
          onClick={handleSave}
          style={{ marginTop: 12 }}
        >
          {saved ? '✓ Saved' : 'Save API Key'}
        </button>
      </div>

      <div className="card">
        <div className="card__label">Get a Gemini API Key</div>
        <p className="body" style={{ color: 'var(--muted)' }}>
          1. Go to{' '}
          <a
            href="https://aistudio.google.com/apikey"
            target="_blank"
            rel="noopener noreferrer"
            className="link"
          >
            aistudio.google.com/apikey
          </a>
          <br />
          2. Click "Create API key"
          <br />
          3. Copy the key and paste it above
        </p>
      </div>

      <div className="card">
        <div className="card__label">Data</div>
        <p className="body" style={{ marginBottom: 12, color: 'var(--muted)' }}>
          All data is stored in your browser's localStorage. Clear it to start
          fresh.
        </p>
        <button
          className="big-btn big-btn--danger"
          onClick={handleClear}
        >
          {confirmClear ? 'Tap again to confirm' : 'Clear all history'}
        </button>
      </div>

      <div className="card">
        <div className="card__label">About</div>
        <p className="body" style={{ color: 'var(--muted)' }}>
          COACH is a personal workout planner powered by Google Gemini AI. It
          builds daily sessions from your check-in, training history, and
          recovery data. Everything runs in your browser — no server, no account.
        </p>
      </div>

      <div style={{ height: 24 }} />
    </div>
  );
}
