import React, { useState, useEffect, useRef } from 'react';
import { getApiKey, setApiKey, getAISettings, setAISettings } from '../utils/storage';
import { exportAll, importAll, countEvents, logEvent } from '../db/db';
import { getSyncConfig, setSyncConfig, syncNow, getLastSync, getLastInbox } from '../db/sync';
import { todaysHealth } from '../utils/healthIngest';
import { todayStr, parsePlates, DEFAULT_BAR_KG, DEFAULT_PLATES } from '../utils/helpers';

function Section({ title, status, statusColor, open, onToggle, children }) {
  return (
    <div className="section">
      <button className="section__head" onClick={onToggle}>
        <div>
          <div className="section__title">{title}</div>
          {status && (
            <div className="section__status" style={statusColor ? { color: statusColor } : undefined}>
              {status}
            </div>
          )}
        </div>
        <span className={'chevron' + (open ? ' chevron--open' : '')}>⌄</span>
      </button>
      {open && <div className="section__body">{children}</div>}
    </div>
  );
}

export default function Settings({ onBack, onClearHistory, onDataImported, onSynced, sessionCount }) {
  const [key, setKey] = useState(getApiKey());
  const [showKey, setShowKey] = useState(false);
  const [saved, setSaved] = useState(false);
  const [confirmClear, setConfirmClear] = useState(false);
  const [eventCount, setEventCount] = useState(null);
  const [dataMsg, setDataMsg] = useState('');
  const fileRef = useRef(null);

  // first run (no key yet) lands here — open the coach section for them
  const [open, setOpen] = useState(() => ({
    coach: !getApiKey(),
    sync: false,
    gym: false,
    watch: false,
    about: false,
  }));
  const toggle = (k) => setOpen((o) => ({ ...o, [k]: !o[k] }));

  const [ai, setAi] = useState(() => {
    const s = getAISettings();
    return { profile: s.profile || '', routine: s.routine || '', goals: s.goals || '' };
  });
  const handleCoachSave = () => {
    setApiKey(key.trim());
    setAISettings({
      profile: ai.profile.trim(),
      routine: ai.routine.trim(),
      goals: ai.goals.trim(),
    });
    setSaved(true);
    logEvent('api_key_saved');
    logEvent('ai_settings_saved');
    setTimeout(() => setSaved(false), 2000);
  };

  // ── Plates & bar (used by the in-workout plate calculator) ──
  const [gym, setGym] = useState(() => {
    const s = getAISettings();
    return {
      barKg: s.barKg ?? DEFAULT_BAR_KG,
      plates: s.plates || DEFAULT_PLATES.join(', '),
    };
  });
  const [gymSaved, setGymSaved] = useState(false);
  const handleGymSave = () => {
    setAISettings({
      barKg: Math.min(Math.max(parseFloat(gym.barKg) || DEFAULT_BAR_KG, 0), 40),
      plates: gym.plates.trim(),
    });
    setGymSaved(true);
    logEvent('gym_settings_saved');
    setTimeout(() => setGymSaved(false), 2000);
  };

  const [sync, setSync] = useState(getSyncConfig());
  const [showToken, setShowToken] = useState(false);
  const [syncSaved, setSyncSaved] = useState(false);
  const [syncMsg, setSyncMsg] = useState('');
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

  // Spreadsheet-friendly flat export: one row per logged set
  const handleExportCsv = async () => {
    const backup = await exportAll();
    const sessions = (backup.sessions || []).filter((s) => !s.deleted);
    const esc = (v) => {
      const s = String(v ?? '');
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const rows = [
      ['date', 'session_type', 'exercise', 'set', 'weight_kg', 'reps', 'effort', 'session_rpe', 'pain', 'duration_min'],
    ];
    for (const s of sessions) {
      (s.plan?.exercises || []).forEach((ex, i) => {
        (s.log?.[i] || []).forEach((set, si) => {
          if (!(set.done || set.weight || set.reps)) return;
          rows.push([
            s.date,
            s.plan?.sessionType || '',
            ex?.name || '',
            si + 1,
            set.weight || '',
            set.reps || '',
            set.effort || '',
            s.fin?.rpe ?? '',
            s.fin?.pain || '',
            s.durationMin ?? '',
          ]);
        });
      });
    }
    const blob = new Blob([rows.map((r) => r.map(esc).join(',')).join('\n')], {
      type: 'text/csv',
    });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `coach-sessions-${todayStr()}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
    logEvent('data_exported_csv', { rows: rows.length - 1 });
    setDataMsg(`Exported ${rows.length - 1} sets as CSV.`);
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

  // ── Collapsed status lines ──
  const coachStatus = getApiKey()
    ? `API key saved${getAISettings().profile ? ' · custom profile set' : ''}`
    : 'No API key yet — add one to start';
  const lastSync = getLastSync();
  const syncStatus =
    lastSync?.status === 'ok'
      ? `☁ synced ${new Date(lastSync.at).toLocaleString()} · ${lastSync.sessions} sessions in cloud`
      : sync.repo
      ? '☁ configured — not synced yet'
      : 'Back up your log to a private GitHub repo';
  const watchReceived = todaysHealth();

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Home</button>
        <div className="brand-sm">SETTINGS</div>
        <div />
      </header>

      <Section
        title="AI Coach"
        status={coachStatus}
        open={open.coach}
        onToggle={() => toggle('coach')}
      >
        <div className="q-label" style={{ marginTop: 0 }}>Gemini API key</div>
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
        <p className="body" style={{ marginTop: 8, fontSize: 12.5, color: 'var(--muted)' }}>
          Get a free key →{' '}
          <a
            href="https://aistudio.google.com/apikey"
            target="_blank"
            rel="noopener noreferrer"
            className="link"
          >
            aistudio.google.com/apikey
          </a>{' '}
          → "Create API key". Stored locally, only sent to Google's Gemini API.
        </p>

        <div className="q-label">About you</div>
        <textarea
          className="input textarea"
          style={{ marginTop: 6, minHeight: 80 }}
          placeholder="e.g. Desk job, long sitting. Goals: fat loss + muscle. Lower back gets tight — prefer supported/machine variations. Walk 12 min each way to the gym. Train after 4PM, 4-5x/week, 45-75 min."
          value={ai.profile}
          onChange={(e) => setAi({ ...ai, profile: e.target.value.slice(0, 1500) })}
        />
        <div className="q-label">Goals (one per line)</div>
        <textarea
          className="input textarea"
          style={{ marginTop: 6, minHeight: 60 }}
          placeholder={'e.g.\nBench Press 80kg\n4 sessions a week\nRun a 10k in autumn'}
          value={ai.goals}
          onChange={(e) => setAi({ ...ai, goals: e.target.value.slice(0, 600) })}
        />
        <p className="body" style={{ marginTop: 6, fontSize: 12.5, color: 'var(--muted)' }}>
          The coach plans toward these; lift and frequency goals get progress
          bars in Stats.
        </p>
        <div className="q-label">Your base routine</div>
        <textarea
          className="input textarea"
          style={{ marginTop: 6, minHeight: 120 }}
          placeholder="Leave empty to use the built-in Push/Pull/Legs routine, or paste your own — exercises, sets × reps, alternatives, warm-ups."
          value={ai.routine}
          onChange={(e) => setAi({ ...ai, routine: e.target.value.slice(0, 4000) })}
        />
        <button className="big-btn" onClick={handleCoachSave} style={{ marginTop: 14, padding: 14, fontSize: 15 }}>
          {saved ? '✓ Saved' : 'Save coach setup'}
        </button>
      </Section>

      <Section
        title="Sync & Backup"
        status={syncStatus}
        open={open.sync}
        onToggle={() => toggle('sync')}
      >
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
        <div style={{ display: 'flex', gap: 10, marginTop: 12 }}>
          <button className="big-btn" onClick={handleSyncSave} style={{ marginTop: 0, padding: 12, fontSize: 14 }}>
            {syncSaved ? '✓ Saved' : 'Save settings'}
          </button>
          <button
            className="big-btn"
            onClick={handleSyncNow}
            disabled={syncing}
            style={{ marginTop: 0, padding: 12, fontSize: 14 }}
          >
            {syncing ? 'Syncing…' : 'Sync now'}
          </button>
        </div>
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

        <div className="q-label">Local data</div>
        {sessionCount != null && (
          <p className="mono" style={{ fontSize: 13, color: 'var(--muted)', marginBottom: 10 }}>
            {sessionCount} sessions · {eventCount ?? '…'} events logged
          </p>
        )}
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <button
            className="big-btn"
            onClick={handleExport}
            style={{ marginTop: 0, padding: 12, fontSize: 14 }}
          >
            Export backup
          </button>
          <button
            className="big-btn"
            onClick={() => fileRef.current?.click()}
            style={{ marginTop: 0, padding: 12, fontSize: 14 }}
          >
            Import backup
          </button>
          <button
            className="big-btn"
            onClick={handleExportCsv}
            style={{ marginTop: 0, padding: 12, fontSize: 14 }}
          >
            Export CSV
          </button>
        </div>
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
          style={{ marginTop: 10, padding: 12, fontSize: 14 }}
          onClick={handleClear}
        >
          {confirmClear ? 'Tap again to confirm' : 'Clear all history'}
        </button>
      </Section>

      <Section
        title="Plates & Bar"
        status={`${parseFloat(gym.barKg) || DEFAULT_BAR_KG}kg bar · plates ${
          (parsePlates(gym.plates) || DEFAULT_PLATES).join('/')
        }`}
        open={open.gym}
        onToggle={() => toggle('gym')}
      >
        <p className="body" style={{ marginBottom: 12, color: 'var(--muted)' }}>
          Powers the ⚖ plates button during a workout — tap it on any
          exercise to see exactly what to load per side.
        </p>
        <div className="q-label" style={{ marginTop: 0 }}>Bar weight (kg)</div>
        <input
          className="input"
          inputMode="decimal"
          value={gym.barKg}
          onChange={(e) => setGym({ ...gym, barKg: e.target.value.replace(/[^\d.]/g, '') })}
          style={{ marginTop: 6 }}
        />
        <div className="q-label">Available plates (kg, per pair)</div>
        <input
          className="input"
          placeholder={DEFAULT_PLATES.join(', ')}
          value={gym.plates}
          onChange={(e) => setGym({ ...gym, plates: e.target.value })}
          style={{ marginTop: 6 }}
        />
        <button
          className="big-btn"
          onClick={handleGymSave}
          style={{ marginTop: 14, padding: 12, fontSize: 14 }}
        >
          {gymSaved ? '✓ Saved' : 'Save gym setup'}
        </button>
      </Section>

      <Section
        title="⌚ Apple Watch"
        status={watchReceived ? 'Received today' : 'Nothing received today yet'}
        statusColor={watchReceived ? 'var(--teal)' : undefined}
        open={open.watch}
        onToggle={() => toggle('watch')}
      >
        <p className="body" style={{ color: 'var(--muted)' }}>
          Apple only lets native apps talk to the Watch, so a Shortcut reads
          your numbers (HRV, resting HR, steps, sleep) from Health and
          delivers them here — your next check-in arrives pre-filled.
        </p>

        <div className="q-label">Recommended: background delivery</div>
        {sync.repo && sync.token ? (
          <>
            <p className="body" style={{ color: 'var(--muted)' }}>
              The v9 shortcut uploads its numbers straight to your data
              repo — one silent web request, no browser, works with the
              phone locked. The app collects them on its next sync (every
              app open, and every 5 minutes while open).
              <br /><br />
              1. Delete older "gym-checkin" copies from the Shortcuts app
              <br />
              2. On your iPhone, tap:{' '}
              <a
                className="link"
                href={`shortcuts://import-shortcut?url=${encodeURIComponent(
                  new URL('gym-checkin-v9.shortcut', window.location.href).toString()
                )}&name=${encodeURIComponent('Gym Check-in v9')}`}
              >
                Install the Gym Check-in v9 shortcut
              </a>{' '}
              → <b>Add Shortcut</b>. It asks for two values on import —
              copy them from here:
            </p>
            <div style={{ display: 'flex', gap: 10, marginTop: 10, flexWrap: 'wrap' }}>
              <button
                className="ghost-btn"
                onClick={() => navigator.clipboard?.writeText(sync.repo)}
              >
                Copy repo ({sync.repo})
              </button>
              <button
                className="ghost-btn"
                onClick={() => navigator.clipboard?.writeText(sync.token)}
              >
                Copy token
              </button>
            </div>
            <p className="body" style={{ marginTop: 10, fontSize: 12.5, color: 'var(--muted)' }}>
              (If tapping the link doesn't open the Shortcuts app, grab the{' '}
              <a className="link" href="gym-checkin-v9.shortcut" download>
                raw file
              </a>{' '}
              instead — when iOS shows it as a text preview, tap the Share
              icon → <b>Shortcuts</b> to import it.)
              <br /><br />
              (If iOS skips the questions, open the shortcut and paste the
              two values into the first two Text boxes after the "Copy to
              clipboard" step.)
              <br /><br />
              3. Run it once — allow the Health prompts, and a{' '}
              <span className="mono">health-inbox/</span> file appears in
              your repo, vanishing after the app's next sync.
              <br />
              4. Automate it: Shortcuts → Automation → + → Time of Day
              (your usual pre-gym time) → Run Immediately → pick{' '}
              <b>"Gym Check-in v9"</b>.
            </p>
            {(() => {
              const inbox = getLastInbox();
              return inbox ? (
                <p className="mono" style={{ fontSize: 12.5, color: 'var(--teal)' }}>
                  📥 Last delivery collected: {inbox.files} file{inbox.files > 1 ? 's' : ''},{' '}
                  {new Date(inbox.at).toLocaleString()}
                </p>
              ) : (
                <p className="mono" style={{ fontSize: 12.5, color: 'var(--dim)' }}>
                  📥 Nothing collected from the inbox yet.
                </p>
              );
            })()}
          </>
        ) : (
          <p className="body" style={{ color: 'var(--muted)' }}>
            Set up <b>Sync & Backup</b> above first — background delivery
            drops the data into that same private repo, using the same token.
          </p>
        )}

        <div className="q-label">Fallback: URL handoff (v8 shortcut)</div>
        <p className="body" style={{ color: 'var(--muted)' }}>
          The older method — the shortcut opens the app with the data in the
          URL. Simpler to install, but iOS drops the handoff if the phone is
          locked or the app is already open.
          <br />
          1. Delete any older "gym-checkin" copies from the Shortcuts app
          <br />
          2. On your iPhone, tap:{' '}
          <a className="link" href="gym-checkin-v8.shortcut" download>
            Install the Gym Check-in v8 shortcut
          </a>{' '}
          → <b>Add Shortcut</b>
          <br />
          3. Run it once and allow the Health access prompts (first run only)
        </p>
        <p className="mono" style={{ marginTop: 10, fontSize: 12.5, color: watchReceived ? 'var(--teal)' : 'var(--dim)' }}>
          {watchReceived
            ? `⌚ Received today: ${watchReceived}`
            : '⌚ Nothing received today yet — run the shortcut to test.'}
        </p>
        {(() => {
          try {
            const d = JSON.parse(localStorage.getItem('coach:url-debug'));
            if (!d) return null;
            return (
              <p className="mono" style={{ marginTop: 6, fontSize: 11.5, color: 'var(--dim)', wordBreak: 'break-all' }}>
                debug — last URL payload ({new Date(d.at).toLocaleTimeString()}):
                {' '}query "{d.search || '—'}" · fragment "{d.hash || '—'}"
              </p>
            );
          } catch {
            return null;
          }
        })()}
      </Section>

      <Section title="About" open={open.about} onToggle={() => toggle('about')}>
        <p className="body" style={{ color: 'var(--muted)' }}>
          COACH is a personal workout planner powered by Google Gemini AI. It
          builds daily sessions from your check-in, training history, and
          recovery data. Everything runs in your browser — no server, no account.
        </p>
      </Section>

      <div style={{ height: 24 }} />
    </div>
  );
}
