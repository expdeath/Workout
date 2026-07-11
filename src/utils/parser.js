// ── Forgiving JSON parser ────────────────────────────────────────
// Strips fences / preamble, extracts the {...} span, and repairs
// a truncated tail by closing open brackets / strings.

export function parsePlan(raw) {
  let s = (raw || '').replace(/```json|```/g, '').trim();
  const start = s.indexOf('{');
  if (start === -1) throw new Error('no JSON in response');
  s = s.slice(start);
  const end = s.lastIndexOf('}');

  // First: try the clean span.
  if (end !== -1) {
    try {
      return validatePlan(JSON.parse(s.slice(0, end + 1)));
    } catch {
      /* fall through to repair */
    }
  }

  // Repair pass: walk the string, track open structures, close them.
  let out = '';
  let stack = [];
  let inStr = false;
  let esc = false;
  for (const ch of s) {
    out += ch;
    if (inStr) {
      if (esc) esc = false;
      else if (ch === '\\') esc = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === '{') stack.push('}');
    else if (ch === '[') stack.push(']');
    else if (ch === '}' || ch === ']') stack.pop();
  }
  if (inStr) out += '"';
  out = out.replace(/,\s*$/, '');
  while (stack.length) out += stack.pop();
  return validatePlan(JSON.parse(out));
}

export function validatePlan(p) {
  if (!p || !p.sessionType) throw new Error('plan missing sessionType');
  p.exercises = Array.isArray(p.exercises) ? p.exercises : [];
  // A training day with no exercises means the response was truncated —
  // throw so the caller falls back to the next model instead of showing
  // an empty workout
  if (!/rest/i.test(p.sessionType) && p.exercises.length === 0) {
    throw new Error('plan has no exercises (truncated response)');
  }
  p.warmup = Array.isArray(p.warmup) ? p.warmup : [];
  p.cooldown = Array.isArray(p.cooldown) ? p.cooldown : [];
  p.recoveryScore = Math.max(0, Math.min(100, Number(p.recoveryScore) || 50));
  p.estTimeMin = Number(p.estTimeMin) || 60;
  p.reasoning = p.reasoning || 'Session chosen from your check-in and recent log.';
  p.concerns = p.concerns || '';
  return p;
}
