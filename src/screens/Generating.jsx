import React, { useState, useEffect } from 'react';
import ReadinessBar from '../components/ReadinessBar';

const MESSAGES = [
  'Reading your training log…',
  'Checking recovery signals…',
  'Weighing volume vs. your evening…',
  'Building the session…',
];

export default function Generating({ readiness, statusMsg }) {
  const [msg, setMsg] = useState(0);

  useEffect(() => {
    const id = setInterval(() => setMsg((m) => (m + 1) % MESSAGES.length), 1800);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="center-fill screen--fade-in">
      <div className="brand pulse">COACH</div>
      <div style={{ marginTop: 28, width: '100%', maxWidth: 320 }}>
        <ReadinessBar value={readiness} label="Readiness (initial estimate)" />
      </div>
      <div className="mono generating-msg">
        {statusMsg || MESSAGES[msg]}
      </div>
    </div>
  );
}
