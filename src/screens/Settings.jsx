import React, { useState, useEffect, useRef } from 'react';
import Icon from '../components/Icon';
import { TabHeader, SectionHead, SettingsRow, RowGroup, PanelSheet, Avatar, StatusPill, IconWell, PageHero, useShell, useDesktop } from '../components/Shell';
import { weeklyTarget } from '../utils/dashboard';
import { getApiKey, setApiKey, canSetApiKey, getAISettings, setAISettings, getPrefs, setPref, hasAIConsent, setAIConsent } from '../utils/storage';
import { AI_SHARED } from './AIConsent';
import { exportAll, importAll, countEvents, logEvent } from '../db/db';
import { getSyncConfig, setSyncConfig, syncNow, getLastSync, getLastInbox, sendFeedback } from '../db/sync';
import { getAccount, signOut, deleteAccount } from '../utils/account';
import { cloudState } from '../db/cloud';
import { todaysHealth } from '../utils/healthIngest';
import { parseHealthNumbers, fmtHealthLine } from '../utils/stats';
import { todayStr, parsePlates, DEFAULT_BAR_KG, DEFAULT_PLATES } from '../utils/helpers';

// Raw shortcut payload → compact readable summary for the Watch card
const fmtWatchData = (raw) => fmtHealthLine(parseHealthNumbers(raw));

// Desktop shows every section as an open card (with a left-hand nav) instead of rows + sheets.
const DeskContext = React.createContext(false);

/** One settings row; its form opens in a sheet (desktop: an always-open card). */
function Section({ id, title, status, icon, tint, value, open, onToggle, children }) {
  if (React.useContext(DeskContext)) {
    return (
      <section className="card set-card" id={`set-${id}`}>
        <div className="set-card__head">
          <IconWell icon={icon} tint={tint} />
          <span className="settings-row__text">
            <span className="hero-title" style={{ fontSize: 22 }}>{title}</span>
            {status && <span className="settings-row__sub">{status}</span>}
          </span>
          {value != null && <span className="caps settings-row__value">{value}</span>}
        </div>
        {children}
      </section>
    );
  }
  return (
    <>
      <SettingsRow icon={icon} tint={tint} title={title} subtitle={status} value={value} onClick={onToggle} />
      {open && (
        <PanelSheet title={title} onClose={onToggle}>
          {children}
        </PanelSheet>
      )}
    </>
  );
}

export default function Settings({ onClearHistory, onDataImported, onSynced, sessionCount }) {
  const desktop = useDesktop();
  const [key, setKey] = useState(getApiKey());
  const [showKey, setShowKey] = useState(false);
  const [saved, setSaved] = useState(false);
  const [confirmClear, setConfirmClear] = useState(false);
  const [eventCount, setEventCount] = useState(null);
  const [dataMsg, setDataMsg] = useState('');
  const fileRef = useRef(null);

  const account = getAccount();
  const { openSheet, displayName } = useShell();

  // first run (no key yet) lands here — open the coach sheet for them
  const [open, setOpen] = useState(() => ({
    account: false,
    coach: !getApiKey(),
    sync: false,
    data: false,
    gym: false,
    watch: false,
    alerts: false,
    about: false,
  }));
  const toggle = (k) => setOpen((o) => ({ ...o, [k]: !o[k] }));

  const [ai, setAi] = useState(() => {
    const s = getAISettings();
    return {
      profile: s.profile || '',
      routine: s.routine || '',
      goals: s.goals || '',
      equipment: s.equipment || '',
    };
  });
  const handleCoachSave = () => {
    setApiKey(key.trim()); // no-op for invited members (the owner's shared key)
    setAISettings({
      profile: ai.profile.trim(),
      routine: ai.routine.trim(),
      goals: ai.goals.trim(),
      equipment: ai.equipment.trim(),
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
      const r = await syncNow({ force: true });
      if (r.status === 'unconfigured') {
        setSyncMsg('Add your token and repo first, then Save.');
      } else {
        if (r.changedLocal) await onSynced?.();
        setSyncMsg(`✓ Backed up — ${r.sessions} sessions on GitHub`);
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

  // ── Beta account: feedback + sign out ──
  const [feedback, setFeedback] = useState('');
  const [feedbackMsg, setFeedbackMsg] = useState('');
  const [sendingFb, setSendingFb] = useState(false);
  const [confirmOut, setConfirmOut] = useState(false);
  const [outMsg, setOutMsg] = useState(''); // why sign-out refused
  const [aiOn, setAiOn] = useState(hasAIConsent);
  // Delete account: a sheet that asks you to type DELETE
  const [deleting, setDeleting] = useState(null); // null | { typed, busy, error }
  const runDelete = async () => {
    setDeleting({ ...deleting, busy: true, error: '' });
    try {
      await deleteAccount(); // reloads into the login screen
    } catch (e) {
      const msg = /popup/i.test(e.code || e.message || '')
        ? 'Your browser blocked the sign-in window — allow pop-ups for this site and try again. Nothing was deleted.'
        : e.code === 'auth/user-mismatch'
        ? 'That was a different Google account — sign in as the one you want to delete.'
        : e.message || "Couldn't delete — try again.";
      setDeleting((d) => ({ ...d, busy: false, error: msg }));
    }
  };
  // Alerts & reports switches (account state 'prefs')
  const [prefs, setPrefs] = useState(getPrefs);
  const flip = (key) => (e) => {
    setPref(key, e.target.checked);
    setPrefs({ ...prefs, [key]: e.target.checked });
    logEvent('pref_changed', { key, on: e.target.checked });
  };
  const PREF_ROWS = [
    ['Rest timer', [
      ['restSound', 'Sound', 'Two beeps when the rest ends'],
      ['restVibrate', 'Vibration', 'Buzz when the rest ends (phones that support it)'],
      ['restNotify', 'Notification', 'Alert when you’ve switched to another app'],
    ]],
    ['During a workout', [
      ['keepAwake', 'Keep screen awake', 'Stops the phone sleeping mid-rest, so the timer always fires'],
    ]],
    ['AI reports', [
      ['weeklyReview', 'Weekly review', 'Written every Sunday from your week'],
      ['monthlyReport', 'Monthly report', 'Written in the first week of a new month'],
      ['debrief', 'Post-workout debrief', 'Two sentences from the coach after each session'],
    ]],
  ];
  const prefsOn = PREF_ROWS.flatMap(([, rows]) => rows).filter(([k]) => prefs[k]).length;

  const handleSendFeedback = async () => {
    setSendingFb(true);
    setFeedbackMsg('');
    try {
      await sendFeedback(feedback);
      logEvent('feedback_sent', { chars: feedback.length });
      setFeedback('');
      setFeedbackMsg('✓ Sent — thank you!');
    } catch (e) {
      setFeedbackMsg(e.message);
    }
    setSendingFb(false);
  };

  const handleSignOut = () => {
    if (!confirmOut) {
      setConfirmOut(true);
      return;
    }
    logEvent('signed_out', { name: account?.name });
    signOut().then((refusal) => {
      if (refusal) {
        setOutMsg(refusal);
        setConfirmOut(false);
      }
    });
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
  const coachStatus = !aiOn
    ? 'Off — nothing is sent to Google Gemini'
    : getApiKey()
    ? getAISettings().profile ? 'Ready · profile set' : 'Ready · add your profile'
    : canSetApiKey()
    ? 'No API key yet — add one to start'
    : 'No API key yet — ask Abhi to add one';
  const lastSync = getLastSync();
  const syncStatus =
    lastSync?.status === 'ok'
      ? `Live sync · backed up ${new Date(lastSync.at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}`
      : lastSync?.status === 'error'
      ? `Backup failed: ${lastSync.message}`
      : sync.repo && sync.token
      ? 'Live sync · backup pending'
      : 'Live sync · no GitHub backup';
  const watchReceived = todaysHealth();

  const profileCard = account && (
    <button className="profile-card" aria-label="Edit profile" onClick={() => openSheet('profile')}>
      <span style={{ position: 'relative' }}>
        <Avatar name={displayName} size={54} />
        <span className="profile-card__online" />
      </span>
      <span style={{ flex: 1, minWidth: 0, textAlign: 'left' }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 5, fontWeight: 700, fontSize: 18 }}>
          {displayName}
          {account.admin && <Icon name="verified" size={16} fill style={{ color: 'var(--amber-text)' }} />}
        </span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 5 }}>
          <StatusPill text={account.admin ? 'Admin' : 'Member'} color="var(--amber-text)" dot={false} />
          <span style={{ fontSize: 12.5, color: 'var(--muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{account.email}</span>
        </span>
      </span>
      <span className="icon-well" style={{ borderRadius: '50%', color: 'var(--muted)' }}><Icon name="edit" size={18} /></span>
    </button>
  );

  const groups = (
    <>
      <SectionHead title="Preferences" trailing="Coach logic" trailingColor="var(--muted)" />
      <RowGroup>
      <Section
        id="coach"
        title="AI Coach"
        icon="psychology"
        status={coachStatus}
        open={open.coach}
        onToggle={() => toggle('coach')}
      >

        <label className="toggle-row" style={{ paddingTop: 0 }}>
          <span>
            <span className="toggle-row__title">Use the AI coach (Google Gemini)</span>
            <span className="toggle-row__sub">
              {aiOn
                ? 'Sends your workouts, check-ins, chats and Health data to Google Gemini to plan sessions.'
                : 'Off — nothing goes to Gemini. You can still log workouts and run saved ones as written.'}
            </span>
          </span>
          <input
            type="checkbox"
            role="switch"
            className="switch"
            checked={aiOn}
            onChange={(e) => {
              setAIConsent(e.target.checked);
              setAiOn(e.target.checked);
              logEvent('ai_consent', { allowed: e.target.checked, from: 'settings' });
            }}
          />
        </label>
        {aiOn && (
          <details className="consent__details">
            <summary>What's shared</summary>
            {AI_SHARED.map(([, title, sub]) => <p key={title}><b>{title}</b> — {sub}</p>)}
          </details>
        )}

        {canSetApiKey() ? (
          <>
            <div className="q-label">{account.selfServe ? 'Your Gemini API key' : 'Gemini API key (shared)'}</div>
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
              {account.selfServe ? 'Only your account uses it.' : 'Shared by everyone you invited.'} Free at{' '}
              <a
                href="https://aistudio.google.com/apikey"
                target="_blank"
                rel="noopener noreferrer"
                className="link"
              >
                aistudio.google.com/apikey
              </a>
            </p>
          </>
        ) : null}

        <div className="q-label" style={canSetApiKey() ? undefined : { marginTop: 0 }}>About you</div>
        <textarea
          className="input textarea"
          style={{ marginTop: 6, minHeight: 80 }}
          placeholder="e.g. Desk job, lower back gets tight"
          value={ai.profile}
          onChange={(e) => setAi({ ...ai, profile: e.target.value.slice(0, 1500) })}
        />
        <div className="q-label">Goals (one per line)</div>
        <textarea
          className="input textarea"
          style={{ marginTop: 6, minHeight: 60 }}
          placeholder={'e.g.\nBench Press 80kg\n4 sessions a week'}
          value={ai.goals}
          onChange={(e) => setAi({ ...ai, goals: e.target.value.slice(0, 600) })}
        />
        <div className="q-label">Equipment</div>
        <textarea
          className="input textarea"
          style={{ marginTop: 6, minHeight: 60 }}
          placeholder="e.g. no cable tower, dumbbells to 40kg"
          value={ai.equipment}
          onChange={(e) => setAi({ ...ai, equipment: e.target.value.slice(0, 600) })}
        />
        <div className="q-label">Base routine</div>
        <textarea
          className="input textarea"
          style={{ marginTop: 6, minHeight: 80 }}
          placeholder="Empty = built-in Push/Pull/Legs"
          value={ai.routine}
          onChange={(e) => setAi({ ...ai, routine: e.target.value.slice(0, 4000) })}
        />
        <button className="big-btn" onClick={handleCoachSave} style={{ marginTop: 14, padding: 14, fontSize: 15 }}>
          {saved ? '✓ Saved' : 'Save coach setup'}
        </button>
      </Section>

      <Section
        id="alerts"
        title="Alerts & reports"
        icon="notifications"
        status={`${prefsOn} of 7 on · rest timer, screen, AI reports`}
        open={open.alerts}
        onToggle={() => toggle('alerts')}
      >
        {PREF_ROWS.map(([group, rows], gi) => (
          <div key={group}>
            <div className="q-label" style={gi ? undefined : { marginTop: 0 }}>{group}</div>
            {rows.map(([key, title, sub]) => (
              <label key={key} className="toggle-row">
                <span>
                  <span className="toggle-row__title">{title}</span>
                  <span className="toggle-row__sub">{sub}</span>
                </span>
                <input type="checkbox" role="switch" className="switch" checked={!!prefs[key]} onChange={flip(key)} />
              </label>
            ))}
          </div>
        ))}
      </Section>

      <SettingsRow
        icon="track_changes"
        tint="var(--green)"
        title="Weekly target"
        subtitle="Streak, consistency and the target bar"
        value={`${weeklyTarget(getAISettings())}/wk`}
        onClick={() => openSheet('profile')}
      />
      </RowGroup>

      <SectionHead title="Devices & sensors" trailing={watchReceived ? 'All synced' : null} trailingColor="var(--green)" />
      <RowGroup>
      <Section
        id="watch"
        title="Apple Watch"
        icon="watch"
        tint="var(--green)"
        status={watchReceived ? 'Synced today' : 'Nothing today yet'}
        open={open.watch}
        onToggle={() => toggle('watch')}
      >
        {watchReceived && (
          <p className="body" style={{ color: 'var(--green)' }}>
            Today: {fmtWatchData(watchReceived) || watchReceived}
          </p>
        )}
        {(() => {
          const inbox = getLastInbox();
          return inbox ? (
            <p style={{ fontSize: 13, color: 'var(--muted)', marginTop: 6 }}>
              Last delivery {new Date(inbox.at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}
            </p>
          ) : null;
        })()}
        <p className="body" style={{ fontSize: 13, color: 'var(--muted)', marginTop: 8 }}>
          A Shortcut uploads your Health data; it pre-fills each check-in.
        </p>

        <details style={{ marginTop: 12 }}>
          <summary style={{ fontSize: 13, color: 'var(--dim)', cursor: 'pointer' }}>
            Install or reinstall the shortcut
          </summary>
          {sync.repo && sync.token ? (
            <>
              <p className="body" style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 8 }}>
                1. Delete older "gym-checkin" copies from the Shortcuts app.
                <br />
                2. Install <b>from Safari</b> (iOS won't import from inside
                this app): copy the install link, paste it into Safari, tap{' '}
                <b>Download</b>, open it from Safari's Downloads (⬇) →{' '}
                <b>Add Shortcut</b>. Answer the two questions with the repo
                and token:
              </p>
              <div style={{ display: 'flex', gap: 10, marginTop: 10, flexWrap: 'wrap' }}>
                <button
                  className="ghost-btn"
                  onClick={() =>
                    navigator.clipboard?.writeText(
                      new URL('gym-checkin-v10.shortcut', window.location.href).toString()
                    )
                  }
                >
                  Copy install link
                </button>
                <button
                  className="ghost-btn"
                  onClick={() => navigator.clipboard?.writeText(sync.repo)}
                >
                  Copy repo
                </button>
                <button
                  className="ghost-btn"
                  onClick={() => navigator.clipboard?.writeText(sync.token)}
                >
                  Copy token
                </button>
              </div>
              <p className="body" style={{ marginTop: 10, fontSize: 12.5, color: 'var(--muted)' }}>
                3. Run it once and allow the Health prompts. The final{' '}
                <b>"GitHub said:"</b> popup shows the upload result:{' '}
                <span className="mono">content</span>/<span className="mono">commit</span>{' '}
                = landed · <span className="mono">Bad credentials</span> = wrong
                token · <span className="mono">Not Found</span> = wrong repo
                (fix either in the shortcut's first two Text boxes; same place
                if iOS skipped the questions).
                <br />
                4. Automate: Shortcuts → Automation → + → Time of Day → Run
                Immediately → pick the gym-checkin shortcut.
              </p>
              <p className="body" style={{ marginTop: 8, fontSize: 12.5, color: 'var(--dim)' }}>
                Fallback if it won't install:{' '}
                <a className="link" href="gym-checkin-v8.shortcut" download>
                  v8 shortcut
                </a>{' '}
                — hands data over by opening the app; unreliable when the
                phone is locked.
              </p>
              {(() => {
                try {
                  const d = cloudState('urlDebug', null);
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
            </>
          ) : (
            <p className="body" style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 8 }}>
              Set up <b>Sync & Backup</b> above first — the shortcut delivers
              into that same private repo, using the same token.
            </p>
          )}
        </details>
      </Section>
      <Section
        id="gym"
        title="Barbell & plate setup"
        icon="scale"
        value={`${parseFloat(gym.barKg) || DEFAULT_BAR_KG}kg bar`}
        status={`${(parsePlates(gym.plates) || DEFAULT_PLATES).join(' / ')} kg plates`}
        open={open.gym}
        onToggle={() => toggle('gym')}
      >
        <div className="q-label" style={{ marginTop: 0 }}>Bar weight (kg)</div>
        <input
          className="input"
          inputMode="decimal"
          value={gym.barKg}
          onChange={(e) => setGym({ ...gym, barKg: e.target.value.replace(/[^\d.]/g, '') })}
          style={{ marginTop: 6 }}
        />
        <div className="q-label">Plates (kg, per pair)</div>
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
      </RowGroup>

      <SectionHead title="Data & account" trailing="Cloud vault" trailingColor="var(--muted)" />
      <RowGroup>
      <Section
        id="sync"
        title="Cloud backup"
        icon="cloud"
        tint="var(--green)"
        status={syncStatus}
        open={open.sync}
        onToggle={() => toggle('sync')}
      >
        <div className="q-label" style={{ marginTop: 0 }}>GitHub backup</div>
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
            {syncing ? 'Backing up…' : 'Back up now'}
          </button>
        </div>
        {syncMsg && (
          <p className="body" style={{ marginTop: 8, color: 'var(--amber)' }}>
            {syncMsg}
          </p>
        )}
        <p className="body" style={{ marginTop: 10, color: 'var(--muted)', fontSize: 13 }}>
          Fine-grained token, your data repo only, Contents: read &amp; write.
        </p>

      </Section>
      <Section
        id="data"
        title="Export workout log"
        icon="upload"
        status="CSV · JSON backup · import"
        open={open.data}
        onToggle={() => toggle('data')}
      >
        <div className="q-label" style={{ marginTop: 0 }}>Your data</div>
        {sessionCount != null && (
          <p style={{ fontSize: 13, color: 'var(--muted)', marginBottom: 10 }}>
            {sessionCount} sessions · {eventCount ?? '…'} events
          </p>
        )}
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <button
            className="big-btn"
            onClick={handleExport}
            style={{ marginTop: 0, padding: 12, fontSize: 14 }}
          >
            Export
          </button>
          <button
            className="big-btn"
            onClick={() => fileRef.current?.click()}
            style={{ marginTop: 0, padding: 12, fontSize: 14 }}
          >
            Import
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

      {account && (
        <Section id="account" title="Send feedback" icon="chat_bubble" status="Straight to Abhi" open={open.account} onToggle={() => toggle('account')}>
          <div className="q-label" style={{ marginTop: 0 }}>Send feedback to Abhi</div>
          <textarea
            className="input textarea"
            style={{ marginTop: 0, minHeight: 80 }}
            placeholder="Bugs, ideas, anything…"
            value={feedback}
            onChange={(e) => setFeedback(e.target.value.slice(0, 2000))}
          />
          <button
            className="big-btn"
            onClick={handleSendFeedback}
            disabled={sendingFb || !feedback.trim()}
            style={{ marginTop: 10, padding: 12, fontSize: 14 }}
          >
            {sendingFb ? 'Sending…' : 'Send feedback'}
          </button>
          {feedbackMsg && (
            <p className="body" style={{ marginTop: 8, color: 'var(--amber)' }}>
              {feedbackMsg}
            </p>
          )}
        </Section>
      )}
      <Section id="about" title="About COACH" icon="info" tint="var(--muted)" open={open.about} onToggle={() => toggle('about')}>
        <p className="body" style={{ color: 'var(--muted)' }}>
          COACH plans each session with Google Gemini from your check-in, history and recovery data. Your log lives in Firestore, backed up to your GitHub repo.
        </p>
      </Section>
      </RowGroup>
    </>
  );

  const signOutBlock = account && (
    <>
      <button className="outline-btn outline-btn--danger" style={{ width: '100%', justifyContent: 'center', marginTop: 20, padding: 12 }} onClick={handleSignOut}>
        <Icon name="logout" size={18} /> {confirmOut ? 'Tap again — this wipes this device' : 'Sign out'}
      </button>
      {outMsg && <p className="body" style={{ marginTop: 8, color: 'var(--amber-text)' }}>{outMsg}</p>}
      <p className="body" style={{ marginTop: 8, fontSize: 12.5, color: 'var(--dim)' }}>
        Signing out clears this device, including exercise photos. Your log stays in the cloud.
      </p>
      <button className="link-btn link-btn--danger" style={{ marginTop: 14 }} onClick={() => setDeleting({ typed: '', busy: false, error: '' })}>
        <Icon name="trash" size={15} /> Delete account
      </button>
      {deleting && (
        <PanelSheet title="Delete account" onClose={() => !deleting.busy && setDeleting(null)}>
          <p className="body">This permanently deletes your COACH account and everything in it:</p>
          <ul className="body consent__small" style={{ paddingLeft: 18 }}>
            <li>every logged session, set and personal record</li>
            <li>Apple Health / Watch data, check-ins, coach chats and reports</li>
            <li>saved workouts, settings, your Gemini key and GitHub token</li>
            <li>your sign-in — signing in again starts a brand-new, empty account</li>
          </ul>
          <p className="body consent__small">
            Your GitHub backup repository is yours and isn't touched — delete it on github.com if you want it gone too. You'll be asked to sign in once more to confirm it's you.
          </p>
          <div className="q-label">Type DELETE to confirm</div>
          <input className="input" style={{ marginTop: 0 }} autoCapitalize="characters" value={deleting.typed} onChange={(e) => setDeleting({ ...deleting, typed: e.target.value })} />
          {deleting.error && <div className="err-box">{deleting.error}</div>}
          <button className="big-btn big-btn--danger" disabled={deleting.typed.trim() !== 'DELETE' || deleting.busy} onClick={runDelete}>
            {deleting.busy ? 'Deleting…' : 'Delete my account'}
          </button>
        </PanelSheet>
      )}
    </>
  );

  if (desktop) {
    const nav = [
      ['coach', 'AI Coach', 'psychology'],
      ['alerts', 'Alerts & reports', 'notifications'],
      ['watch', 'Apple Watch', 'watch'],
      ['gym', 'Barbell & plates', 'scale'],
      ['sync', 'Cloud backup', 'cloud'],
      ['data', 'Export & import', 'upload'],
      ...(account ? [['account', 'Send feedback', 'chat_bubble']] : []),
      ['about', 'About COACH', 'info'],
    ];
    return (
      <div className="screen screen--fade-in">
        <TabHeader title="Settings" />
        <PageHero kicker={account?.email} title="Settings" sub="Coach setup, devices, backups and your data — changes save to your account." />
        <DeskContext.Provider value={true}>
          <div className="settings-desk">
            <aside className="settings-nav">
              {profileCard}
              <nav className="settings-nav__links" aria-label="Settings sections">
                {nav.map(([id, label, icon]) => (
                  <button key={id} className="settings-nav__link" onClick={() => document.getElementById(`set-${id}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })}>
                    <Icon name={icon} size={18} /> {label}
                  </button>
                ))}
              </nav>
              {signOutBlock}
            </aside>
            <div className="settings-main">{groups}</div>
          </div>
        </DeskContext.Provider>
      </div>
    );
  }

  return (
    <div className="screen screen--slide-in">
      <TabHeader title="Settings" />
      {profileCard}

      {groups}

      {signOutBlock}
      <div className="caps" style={{ textAlign: 'center', fontSize: 11, color: 'var(--dim)', marginTop: 18 }}>COACH · web</div>

    </div>
  );
}
