import React, { useState } from 'react';
import { parseInviteCode, applyAccount, wipeLocal } from '../utils/account';
import { logEvent } from '../db/db';

// First-run gate for invited users. There is deliberately no signup:
// the only way in is an invite code provisioned by the owner.
export default function Login() {
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const redeem = async () => {
    setError('');
    let acct;
    try {
      acct = parseInviteCode(code);
    } catch (e) {
      setError(e.message);
      return;
    }
    setBusy(true);
    await wipeLocal(); // stale local data must not ride into this account
    applyAccount(acct);
    logEvent('invite_redeemed', { name: acct.name, repo: acct.repo });
    // clean boot: pulls any existing cloud data with the new config
    window.location.reload();
  };

  return (
    <div className="screen">
      <div className="center-fill" style={{ padding: 24, textAlign: 'center' }}>
        <div className="brand">COACH</div>
        <p className="body" style={{ marginTop: 10, color: 'var(--muted)' }}>
          Your AI training coach. This is a private beta — you'll need the
          invite code you were sent.
        </p>
        <textarea
          className="input textarea"
          style={{ marginTop: 18, minHeight: 90, textAlign: 'left' }}
          placeholder="Paste your invite code…"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          value={code}
          onChange={(e) => setCode(e.target.value)}
        />
        {error && (
          <p className="body" style={{ marginTop: 10, color: 'var(--amber)' }}>
            {error}
          </p>
        )}
        <button
          className="big-btn"
          style={{ marginTop: 14, width: '100%' }}
          disabled={busy || !code.trim()}
          onClick={redeem}
        >
          {busy ? 'Setting up…' : "Let's train"}
        </button>
        <p className="body" style={{ marginTop: 16, fontSize: 12.5, color: 'var(--dim)' }}>
          No code? Ask Abhi for one — accounts are invite-only for now.
        </p>
      </div>
    </div>
  );
}
