import React, { useState } from 'react';
import Icon from '../components/Icon';
import { StatusPill } from '../components/Shell';
import { cloudPro, cloudProActive, cloudRefreshPro, currentAccount, REVENUECAT_WEB_KEY, PRO_PRICE } from '../db/cloud';
import { logEvent } from '../db/db';

// COACH Pro: the AI coach without bringing your own Gemini key — the
// COACH server answers with the owner's key (functions/index.js).
// Sold here through RevenueCat Web Billing (Stripe) and on iPhone through
// Apple; either way one entitlement, entitlements/{accountId}, written by
// the server. docs/subscriptions.md has the setup.

const fmtDate = (ms) => new Date(ms).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' });

export const PRO_FEATURES = [
  'The AI coach with no API key to set up',
  'Session plans, check-ins, coach chat, reviews and “Build with coach”',
  `Up to ${PRO_PRICE.dailyLimit} coach requests a day`,
  'Everything else in COACH stays free',
];

export default function ProSection({ onChange }) {
  const pro = cloudPro();
  const active = cloudProActive();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  const subscribe = async () => {
    setBusy(true);
    setMsg('');
    try {
      const { Purchases } = await import('@revenuecat/purchases-js');
      const purchases = Purchases.configure(REVENUECAT_WEB_KEY, currentAccount().accountId);
      const offerings = await purchases.getOfferings();
      const pkg = offerings.current?.monthly || offerings.current?.availablePackages?.[0];
      if (!pkg) throw new Error('COACH Pro isn’t on sale yet — try again later.');
      logEvent('pro_checkout_started', {});
      await purchases.purchase({ rcPackage: pkg });
      await cloudRefreshPro();
      logEvent('pro_purchased', { via: 'web' });
      setMsg('Welcome to COACH Pro!');
      onChange?.();
    } catch (e) {
      if (!/cancel/i.test(e?.message || '') && e?.errorCode !== 1) setMsg(e?.message || 'The purchase didn’t go through — you weren’t charged.');
    }
    setBusy(false);
  };

  if (active) {
    return (
      <>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <StatusPill text={pro.trial ? 'Pro · free trial' : 'Pro'} color="var(--green)" />
          {pro.store && <span className="caps" style={{ fontSize: 11 }}>{pro.store === 'app_store' ? 'via App Store' : 'via the website'}</span>}
        </div>
        <p className="body" style={{ marginTop: 10 }}>
          The AI coach runs on COACH's server — no key needed.{' '}
          {pro.expiresAt ? `${pro.willRenew ? 'Renews' : 'Ends'} ${fmtDate(pro.expiresAt)}.` : ''}
        </p>
        <p className="body consent__small">Up to {PRO_PRICE.dailyLimit} coach requests a day.</p>
        {pro.store === 'app_store' ? (
          <p className="body consent__small">Bought on iPhone — manage or cancel it in your iPhone's Settings → Apple ID → Subscriptions.</p>
        ) : pro.managementUrl ? (
          <a className="outline-btn" style={{ marginTop: 10, display: 'inline-flex' }} href={pro.managementUrl} target="_blank" rel="noopener noreferrer">
            Manage or cancel
          </a>
        ) : null}
      </>
    );
  }

  return (
    <>
      <div className="pro-offer">
        <div className="hero-title" style={{ fontSize: 26 }}>COACH Pro</div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, marginTop: 4 }}>
          <span className="hero-title" style={{ fontSize: 34, color: 'var(--amber-text)' }}>{PRO_PRICE.label}</span>
          <span className="caps">/ {PRO_PRICE.period}</span>
          <StatusPill text={`${PRO_PRICE.trialDays}-day free trial`} color="var(--green)" dot={false} />
        </div>
        <ul className="pro-offer__list">
          {PRO_FEATURES.map((f) => (
            <li key={f}><Icon name="check_circle" size={16} fill style={{ color: 'var(--green)' }} /> {f}</li>
          ))}
        </ul>
      </div>
      {REVENUECAT_WEB_KEY ? (
        <button className="big-btn" disabled={busy} onClick={subscribe}>
          {busy ? 'Opening checkout…' : `Start ${PRO_PRICE.trialDays}-day free trial`}
        </button>
      ) : (
        <p className="body" style={{ marginTop: 12, color: 'var(--amber-text)' }}>Coming soon — you can keep using your own key meanwhile.</p>
      )}
      {msg && <p className="body" style={{ marginTop: 8, color: 'var(--amber-text)' }}>{msg}</p>}
      <p className="body consent__small" style={{ marginTop: 10 }}>
        Free for {PRO_PRICE.trialDays} days, then {PRO_PRICE.label} a {PRO_PRICE.period}. Renews automatically until you cancel — cancel any time before the trial ends and you won't be charged.{' '}
        <a className="link" href="./terms.html" target="_blank" rel="noopener noreferrer">Terms</a> ·{' '}
        <a className="link" href="./privacy.html" target="_blank" rel="noopener noreferrer">Privacy</a>
      </p>
    </>
  );
}
