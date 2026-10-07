import React, { useState } from 'react';
import { signInWithGoogle } from '../db/cloud';

// Sign-in gate. There is deliberately no signup: Google proves who you
// are, and only emails the owner has added to the allowlist get in.
export default function Login({ error: bootError, onSignedIn }) {
  const [error, setError] = useState(bootError || '');
  const [busy, setBusy] = useState(false);

  const signIn = async () => {
    setError('');
    setBusy(true);
    try {
      const user = await signInWithGoogle();
      if (user) await onSignedIn(); // null → redirecting away
    } catch (e) {
      if (e.code !== 'auth/popup-closed-by-user' && e.code !== 'auth/cancelled-popup-request') {
        setError(e.message || "Couldn't sign in — try again.");
      }
      setBusy(false);
    }
  };

  return (
    <div className="screen">
      <div className="center-fill" style={{ padding: 24, textAlign: 'center' }}>
        <div className="brand">COACH</div>
        <p className="body" style={{ marginTop: 10, color: 'var(--muted)' }}>
          Your AI training coach. This is a private beta — sign in with the
          Google account Abhi added for you.
        </p>
        {error && (
          <p className="body" style={{ marginTop: 14, color: 'var(--amber)' }}>
            {error}
          </p>
        )}
        <button
          className="big-btn"
          style={{ marginTop: 18, width: '100%' }}
          disabled={busy}
          onClick={signIn}
        >
          {busy ? 'Signing in…' : 'Sign in with Google'}
        </button>
        <p className="body" style={{ marginTop: 16, fontSize: 12.5, color: 'var(--dim)' }}>
          Not on the list yet? Ask Abhi to add your Google email.
        </p>
      </div>
    </div>
  );
}
