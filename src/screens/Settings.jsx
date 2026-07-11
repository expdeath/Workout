import React, { useState, useEffect, useRef } from 'react';
import { getApiKey, setApiKey } from '../utils/storage';
import { exportAll, importAll, countEvents, logEvent } from '../db/db';
import { getSyncConfig, setSyncConfig, syncNow, getLastSync } from '../db/sync';
import { todayStr } from '../utils/helpers';

export default function Settings({ onBack, onClearHistory, onDataImported, onSynced, sessionCount }) {
  const [key, setKey] = useState(getApiKey());
  const [showKey, setShowKey] = useState(false);
  const [saved, setSaved] = useState(false);
  const [confirmClear, setConfirmClear] = useState(false);
  const [eventCount, setEventCount] = useState(null);
  const [dataMsg, setDataMsg] = useState('');
  const fileRef = useRef(null);

  const [sync, setSync] = useState(getSyncConfig());
  const [showToken, setShowToken] = useState(false);
  const [syncSaved, setSyncSaved] = useState(false);
  const [syncMsg, setSyncMsg] = useState(() => {
    const last = getLastSync();
    return last?.status === 'ok'
      ? `Last synced ${new Date(last.at).toLocaleString()} (${last.sessions} sessions)`
      : '';
  });
  const [syncing, setSyncing] = useState(false);

  const handleSyncSave = () => {
    setSyncConfig(sync);
    setSync(getSyncConfig());
    setSyncSaved(true);
    logEvent('sync_config_saved', { repo: sync.repo });
    setTimeout(() => setSyncSaved(false), 2000);
  };

  const handleSyncNow = async () => {
    setSyncing(true);
    setSyncMsg('Syncing…');
    try {
      const r = await syncNow();
      if (r.status === 'unconfigured') {
        setSyncMsg('Add your token and repo first, then Save.');
      } else {
        if (r.changedLocal) await onSynced?.();
        setSyncMsg(`✓ Synced — ${r.sessions} sessions in cloud`);
      }
    } catch (e) {
      setSyncMsg(`Sync failed: ${e.message}`);
    }
    setSyncing(false);
  };

  useEffect(() => {
    countEvents().then(setEventCount);
  }, [dataMsg]);

  const handleSave = () => {
    setApiKey(key.trim());
    setSaved(true);
    logEvent('api_key_saved');
    setTimeout(() => setSaved(false), 2000);
  };

  const handleExport = async () => {
    const backup = await exportAll();
    const blob = new Blob([JSON.stringify(backup)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `coach-backup-${todayStr()}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
    logEvent('data_exported', { sessions: backup.sessions.length });
    setDataMsg(`Exported ${backup.sessions.length} sessions.`);
  };

  const handleImportFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    try {
      const backup = JSON.parse(await file.text());
      await importAll(backup);
      await onDataImported?.();
      setDataMsg(`Restored ${backup.sessions.length} sessions from backup.`);
    } catch (err) {
      setDataMsg(`Import failed: ${err.message}`);
    }
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
        <div className="card__label">Cloud Sync</div>
        <p className="body" style={{ marginBottom: 12, color: 'var(--muted)' }}>
          Syncs your full training log to a private GitHub repo you own, so
          it survives this browser and follows you across devices. The app
          syncs automatically when it opens and after each workout.
        </p>
        <input
          className="input"
          type="text"
          placeholder="your-username/workout-data"
          value={sync.repo}
          onChange={(e) => setSync({ ...sync, repo: e.target.value })}
          style={{ marginTop: 0 }}
        />
        <div className="settings-key-row" style={{ marginTop: 8 }}>
          <input
            className="input"
            type={showToken ? 'text' : 'password'}
            placeholder="github_pat_…"
            value={sync.token}
            onChange={(e) => setSync({ ...sync, token: e.target.value })}
            style={{ marginTop: 0, flex: 1 }}
          />
          <button
            className="ghost-btn"
            onClick={() => setShowToken(!showToken)}
            style={{ flexShrink: 0 }}
          >
            {showToken ? 'Hide' : 'Show'}
          </button>
        </div>
        <button className="big-btn" onClick={handleSyncSave} style={{ marginTop: 12 }}>
          {syncSaved ? '✓ Saved' : 'Save sync settings'}
        </button>
        <button
          className="big-btn"
          onClick={handleSyncNow}
          disabled={syncing}
          style={{ marginTop: 8 }}
        >
          {syncing ? 'Syncing…' : 'Sync now'}
        </button>
        {syncMsg && (
          <p className="body" style={{ marginTop: 8, color: 'var(--amber)' }}>
            {syncMsg}
          </p>
        )}
        <p className="body" style={{ marginTop: 12, color: 'var(--muted)', fontSize: 13 }}>
          Token setup (once): github.com → Settings → Developer settings →
          Fine-grained tokens → Generate. Repository access: only your data
          repo. Permissions: Contents → Read and write. Paste the token here —
          it stays in this browser and is only sent to api.github.com.
        </p>
      </div>

      <div className="card">
        <div className="card__label">Data</div>
        <p className="body" style={{ marginBottom: 12, color: 'var(--muted)' }}>
          Your full training history and an activity log of every interaction
          are stored in this browser's database and feed the AI coach.
          {sessionCount != null && (
            <>
              <br />
              <span className="mono" style={{ fontSize: 13 }}>
                {sessionCount} sessions · {eventCount ?? '…'} events logged
              </span>
            </>
          )}
        </p>
        <button className="big-btn" onClick={handleExport}>
          Export backup
        </button>
        <button
          className="big-btn"
          style={{ marginTop: 8 }}
          onClick={() => fileRef.current?.click()}
        >
          Import backup
        </button>
        <input
          ref={fileRef}
          type="file"
          accept="application/json,.json"
          style={{ display: 'none' }}
          onChange={handleImportFile}
        />
        {dataMsg && (
          <p className="body" style={{ marginTop: 8, color: 'var(--amber)' }}>
            {dataMsg}
          </p>
        )}
        <button
          className="big-btn big-btn--danger"
          style={{ marginTop: 8 }}
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
