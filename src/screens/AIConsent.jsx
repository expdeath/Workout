import React from 'react';
import Icon from '../components/Icon';
import { setAIConsent } from '../utils/storage';
import { logEvent } from '../db/db';

// Asked once per account, before anything is sent to Google Gemini
// (App Store guideline 5.1.2(i) — the iOS twin is AIConsentView.swift).
// The answer is account state `aiConsent`; Settings → AI Coach changes it.
export const AI_SHARED = [
  ['fitness_center', 'Your workouts', 'Logged sessions, sets and weights, goals, equipment, profile notes'],
  ['edit_note', 'Your check-ins and chats', 'Energy, sleep, soreness, body weight, notes, questions you ask the coach'],
  ['ecg_heart', 'Apple Health / Watch data', 'HRV, resting heart rate, sleep, steps, active energy'],
  ['upload', 'Photos you choose', 'Only a program photo you add in “Build with coach” — read, never stored by COACH'],
];

export default function AIConsent({ onDone }) {
  const answer = (allowed) => {
    setAIConsent(allowed);
    logEvent('ai_consent', { allowed });
    onDone();
  };
  return (
    <div className="screen screen--fade-in">
      <div className="consent">
        <span className="icon-well consent__icon"><Icon name="psychology" size={30} /></span>
        <h1 className="hero-title" style={{ fontSize: 34, marginTop: 14 }}>Your AI coach</h1>
        <p className="body consent__lead">
          COACH plans your sessions with <b>Google Gemini</b>, an AI service run by Google. To do that it sends Gemini:
        </p>
        <div className="consent__list">
          {AI_SHARED.map(([icon, title, sub]) => (
            <div key={title} className="consent__row">
              <Icon name={icon} size={20} style={{ color: 'var(--amber-text)' }} />
              <span>
                <b>{title}</b>
                <span>{sub}</span>
              </span>
            </div>
          ))}
        </div>
        <p className="body consent__small">
          With your own Gemini key it goes straight from your device to Google, under{' '}
          <a className="link" href="https://ai.google.dev/gemini-api/terms" target="_blank" rel="noopener noreferrer">Google's Gemini API terms</a>
          {' '}— on free keys Google may use it to improve its products. With COACH Pro it goes through COACH's server, which passes it on without keeping it, to COACH's paid Gemini account — which Google doesn't use to improve its products. Nothing is sent until you allow it, and you can turn it off any time in Settings → AI Coach. <a className="link" href="./privacy.html" target="_blank" rel="noopener noreferrer">Privacy policy</a>
        </p>
        <button className="big-btn" onClick={() => answer(true)}>Allow the AI coach</button>
        <button className="ghost-btn consent__no" onClick={() => answer(false)}>Not now</button>
        <p className="body consent__small" style={{ textAlign: 'center' }}>
          Without it you can still log workouts and run your saved workouts as written.
        </p>
      </div>
    </div>
  );
}
