import React, { useState } from 'react';
import { signInWithGoogle, signInWithApple, APPLE_SIGN_IN } from '../db/cloud';

// Sign-in gate. Any Google account gets in: the first sign-in creates
// its account (src/db/cloud.js signUp), later ones reopen it.
export default function Login({ error: bootError, onSignedIn }) {
  const [error, setError] = useState(bootError || '');
  const [busy, setBusy] = useState(false);

  const signIn = async (provider = 'google') => {
    setError('');
    setBusy(true);
    try {
      const user = provider === 'apple' ? await signInWithApple() : await signInWithGoogle();
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
          Your AI training coach.
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
          onClick={() => signIn('google')}
        >
          {busy ? 'Signing in…' : 'Sign in with Google'}
        </button>
        {APPLE_SIGN_IN && (
          <button className="apple-btn" disabled={busy} onClick={() => signIn('apple')}>
            <svg viewBox="0 0 17 20" width="15" height="18" aria-hidden="true"><path fill="currentColor" d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9C3.6 4.8 2 5.8 1 7.4c-1.9 3.3-.5 8.2 1.4 10.9.9 1.3 2 2.8 3.4 2.7 1.4-.1 1.9-.9 3.5-.9s2.1.9 3.5.8c1.5 0 2.4-1.3 3.3-2.7 1-1.5 1.5-3 1.5-3.1 0 0-2.8-1.1-2.9-4.3zM11.5 2.9C12.2 2 12.8.8 12.6-.4c-1 .1-2.3.7-3 1.6-.7.8-1.3 2-1.1 3.2 1.1.1 2.3-.6 3-1.5z"/></svg>
            Sign in with Apple
          </button>
        )}
        <p className="body" style={{ marginTop: 16, fontSize: 12.5, color: 'var(--dim)' }}>
          Any Google account works — new here? Your account is created on first sign-in.
        </p>
      </div>
    </div>
  );
}
