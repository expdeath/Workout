import React, { useState, useEffect, useRef } from "react";

// ------------------------------------------------------------------
// COACH — zero-friction daily training app
// Flow: Home → 60-second check-in → AI plans the session → guided
// workout with set logging → session saved → history feeds tomorrow.
// ------------------------------------------------------------------

const WORKOUT_DB = `
PUSH DAY — Warm-up: 15min Stairmaster OR chest press warm-up sets.
1. Flat Dumbbell Press 3x10-12 (alt: Seated Chest Press Machine)
2. Incline Dumbbell Press 3x10-12 (alt: Low-to-High Cable Fly)
3. Machine Shoulder Press 3x10-12
4. Cable Lateral Raise 3x12-15
5. Rope Tricep Pushdown 3x12-15
Cooldown: doorway chest stretch, overhead tricep stretch.

PULL DAY — Warm-up: 15min stationary bike.
1. Chest Supported Row 3x8-10
2. Lat Pulldown 3x8-10
3. Machine Rear Delt Fly 3x12-15
4. Cable Curl 3x10-12
Cooldown: lat stretch, bicep stretch.

LEG DAY — Warm-up: 15min stationary bike.
1. Leg Press 3x10-12
2. Seated Leg Curl 3x10-12
3. Leg Extension 3x12-15
4. Calf Press 3x15
Cooldown: quad stretch, hamstring stretch.

ACTIVE RECOVERY — Option 1: 30min stationary bike zone 2.
Option 2: 3 rounds — dead bugs x10/side, bird dog x10/side, plank 45s, side plank 30s/side, hollow hold 20-30s.
`;

const COACH_RULES = `
You are this person's long-term strength coach. Profile: IT desk job, long sitting periods. Goals: fat loss, muscle preservation/building, fitness, posture, avoid lower back pain, sustainable habits. Trains Push/Pull/Legs (flexible). Walks 12 min each way to the gym — count it in total time, treat as light warm-up/cool-down. Trains after 4PM day job, before a 1-2h evening job, so sessions must be efficient. Prefers 4-5 sessions/week Mon-Fri. Sessions 45-75 min.
Lower back: occasionally tight from sitting. Don't prohibit exercises; prefer supported/machine variations when appropriate, add technique cues. Adapt if sore today.
Progression: recommend small weight increases, extra reps, or holding, based on logged history. NEVER increase load if recovery looks poor. If returning from 1+ week break: reduce volume, avoid failure, reduce weights, expect DOMS.
Rotate exercises sensibly, avoid repeating identical sessions, keep the split balanced based on the history provided. Do not invent history that isn't in the log.
Be direct and analytical. No hype. State uncertainty when the data is thin.
`;

const JSON_SPEC = `
Respond with ONLY minified valid JSON — no markdown fences, no preamble, no trailing text. BE EXTREMELY CONCISE in every string; total response must stay under 900 tokens. Schema:
{"sessionType":"Push|Pull|Legs|Active Recovery|Mobility|Rest Day|Light Cardio",
"title":"max 6 words",
"recoveryScore":0-100,
"reasoning":"max 2 short sentences",
"warmup":["max 3 items, max 8 words each"],
"exercises":[{"name":"","sets":3,"reps":"10-12","rpe":"7-8","rest":"90s","notes":"max 10 words or empty","alt":"max 5 words or empty","suggestedWeight":"e.g. 24kg or empty"}],
"cardio":{"desc":"max 8 words","duration":"e.g. 15min"} or null,
"cooldown":["max 3 items, max 6 words each"],
"estTimeMin":number including 24min walking,
"concerns":"max 12 words or empty"}
Max 6 exercises. If Rest Day, exercises=[]. For Active Recovery put the circuit in exercises.`;

// ---------------- storage helpers ----------------
async function loadKey(key, fallback) {
  try {
    const r = await window.storage.get(key);
    return r ? JSON.parse(r.value) : fallback;
  } catch {
    return fallback;
  }
}
async function saveKey(key, value) {
  try {
    await window.storage.set(key, JSON.stringify(value));
  } catch (e) {
    console.error("storage save failed", e);
  }
}

// Forgiving parser: strips fences/preamble, extracts the {...} span,
// and repairs a truncated tail by closing open brackets/strings.
function parsePlan(raw) {
  let s = (raw || "").replace(/```json|```/g, "").trim();
  const start = s.indexOf("{");
  if (start === -1) throw new Error("no JSON in response");
  s = s.slice(start);
  const end = s.lastIndexOf("}");
  // First: try the clean span.
  if (end !== -1) {
    try { return validatePlan(JSON.parse(s.slice(0, end + 1))); } catch {}
  }
  // Repair pass: walk the string, track open structures, close them.
  let out = "", stack = [], inStr = false, esc = false;
  for (const ch of s) {
    out += ch;
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === "{") stack.push("}");
    else if (ch === "[") stack.push("]");
    else if (ch === "}" || ch === "]") stack.pop();
  }
  if (inStr) out += '"';
  out = out.replace(/,\s*$/, "");
  while (stack.length) out += stack.pop();
  return validatePlan(JSON.parse(out));
}

function validatePlan(p) {
  if (!p || !p.sessionType) throw new Error("plan missing sessionType");
  p.exercises = Array.isArray(p.exercises) ? p.exercises : [];
  p.warmup = Array.isArray(p.warmup) ? p.warmup : [];
  p.cooldown = Array.isArray(p.cooldown) ? p.cooldown : [];
  p.recoveryScore = Math.max(0, Math.min(100, Number(p.recoveryScore) || 50));
  p.estTimeMin = Number(p.estTimeMin) || 60;
  p.reasoning = p.reasoning || "Session chosen from your check-in and recent log.";
  p.concerns = p.concerns || "";
  return p;
}

const todayStr = () => new Date().toISOString().slice(0, 10);const fmtDate = (iso) =>
  new Date(iso + "T12:00:00").toLocaleDateString(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
  });

// ---------------- readiness estimate (client-side, pre-AI) ----------------
function quickReadiness(c) {
  let s = 50;
  s += (c.energy - 5) * 5;
  if (c.sleep === "Great") s += 15;
  if (c.sleep === "OK") s += 5;
  if (c.sleep === "Poor") s -= 15;
  if (c.soreness === "None") s += 10;
  if (c.soreness === "Light") s -= 5;
  if (c.soreness === "Very sore") s -= 20;
  if (c.backTight) s -= 8;
  return Math.max(5, Math.min(98, Math.round(s)));
}

// ==================================================================
export default function CoachApp() {
  const [screen, setScreen] = useState("loading"); // loading|home|checkin|generating|workout|finish|history
  const [history, setHistory] = useState([]);
  const [todayPlan, setTodayPlan] = useState(null); // {date, plan, log, finished}
  const [error, setError] = useState("");

  // check-in state — pre-filled with a "normal day" so zero taps are required
  const [ci, setCi] = useState({
    energy: 7,
    sleep: "OK",
    soreness: "None",
    soreAreas: "",
    backTight: false,
    timeAvail: "60",
    health: "",
    notes: "",
  });

  // finish state
  const [fin, setFin] = useState({ rpe: 7, pain: "", feedback: "" });

  useEffect(() => {
    (async () => {
      const h = await loadKey("coach:history", []);
      const t = await loadKey("coach:today", null);
      setHistory(h);
      if (t && t.date === todayStr()) setTodayPlan(t);
      setScreen("home");
    })();
  }, []);

  const persistToday = async (t) => {
    setTodayPlan(t);
    await saveKey("coach:today", t);
  };

  // ---------------- AI call ----------------
  async function generateWorkout(checkin) {
    setScreen("generating");
    setError("");
    const recent = history.slice(-6);
    const histText = recent.length
      ? recent
          .map(
            (h) =>
              `${h.date} — ${h.plan.sessionType}: ` +
              (h.plan.exercises || [])
                .map((ex, i) => {
                  const sets = (h.log?.[i] || [])
                    .filter((s) => s.done)
                    .map((s) => `${s.weight || "?"}x${s.reps || "?"}`)
                    .join(", ");
                  return `${ex.name} [${sets || "no sets logged"}]`;
                })
                .join("; ") +
              (h.finished
                ? ` | session RPE ${h.fin?.rpe ?? "?"}${h.fin?.pain ? " | pain: " + h.fin.pain : ""}${h.fin?.feedback ? " | notes: " + h.fin.feedback : ""}`
                : " | NOT COMPLETED")
          )
          .join("\n")
      : "No logged sessions yet in this app. Treat as a fresh start — use the base workout database, moderate volume, and ask nothing (choose sensibly).";

    const daysSince = recent.length
      ? Math.round(
          (new Date(todayStr()) - new Date(recent[recent.length - 1].date)) /
            86400000
        )
      : null;

    const userMsg = `
TODAY: ${todayStr()} (${new Date().toLocaleDateString(undefined, { weekday: "long" })})

CHECK-IN:
- Energy: ${checkin.energy}/10
- Sleep last night: ${checkin.sleep}
- Soreness: ${checkin.soreness}${checkin.soreAreas ? " (" + checkin.soreAreas + ")" : ""}
- Lower back tight today: ${checkin.backTight ? "YES — adapt exercise selection" : "no"}
- Time available today (gym time, walking excluded): ${checkin.timeAvail} min
${checkin.notes ? "- Other notes: " + checkin.notes : ""}

APPLE HEALTH DATA (pasted by user, may be empty):
${checkin.health || "None provided today — rely on check-in + history."}

TRAINING LOG (most recent last):
${histText}
${daysSince !== null ? `Days since last logged session: ${daysSince}${daysSince >= 7 ? " — RETURNING FROM BREAK, apply reduced-volume rules." : ""}` : ""}

BASE WORKOUT DATABASE:
${WORKOUT_DB}

Decide the right session for today and build it. ${JSON_SPEC}`;

    async function callOnce() {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model: "claude-sonnet-4-6",
          max_tokens: 1000,
          system: COACH_RULES,
          messages: [{ role: "user", content: userMsg }],
        }),
      });
      const data = await response.json();
      const text = (data.content || [])
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("\n");
      return parsePlan(text);
    }

    try {
      let plan;
      try {
        plan = await callOnce();
      } catch (firstErr) {
        console.warn("first attempt failed, retrying once", firstErr);
        plan = await callOnce(); // one silent retry
      }
      const log = (plan.exercises || []).map((ex) =>
        Array.from({ length: Number(ex.sets) || 3 }, () => ({
          weight: "",
          reps: "",
          done: false,
        }))
      );
      const t = { date: todayStr(), checkin, plan, log, finished: false };
      await persistToday(t);
      setScreen("workout");
    } catch (e) {
      console.error(e);
      setError(
        "Couldn't build today's session after two tries — likely a network hiccup. Hit the button again."
      );
      setScreen("checkin");
    }
  }

  // ---------------- set logging ----------------
  const updateSet = (exI, setI, field, val) => {
    const t = { ...todayPlan, log: todayPlan.log.map((a) => a.map((s) => ({ ...s }))) };
    t.log[exI][setI][field] = val;
    persistToday(t);
  };

  async function finishSession() {
    const t = { ...todayPlan, finished: true, fin };
    const newHist = [...history.filter((h) => h.date !== t.date), t].slice(-30);
    setHistory(newHist);
    await saveKey("coach:history", newHist);
    await persistToday(t);
    setScreen("home");
  }

  // ================= RENDER =================
  const S = styles;

  if (screen === "loading")
    return (
      <div style={S.app}>
        <GlobalStyle />
        <div style={S.centerFill}>
          <div className="pulse" style={S.brand}>COACH</div>
        </div>
      </div>
    );

  return (
    <div style={S.app}>
      <GlobalStyle />
      <div style={S.frame}>
        {screen === "home" && (
          <Home
            todayPlan={todayPlan}
            history={history}
            onStart={() => {
              setCi({
                energy: 7, sleep: "OK", soreness: "None", soreAreas: "",
                backTight: false, timeAvail: "60", health: "", notes: "",
              });
              setError("");
              setScreen("checkin");
            }}
            onResume={() => setScreen("workout")}
            onHistory={() => setScreen("history")}
          />
        )}

        {screen === "checkin" && (
          <CheckIn
            ci={ci} setCi={setCi}
            error={error}
            onCancel={() => setScreen("home")}
            onSubmit={() => generateWorkout(ci)}
          />
        )}

        {screen === "generating" && <Generating readiness={quickReadiness(ci)} />}

        {screen === "workout" && todayPlan && (
          <Workout
            t={todayPlan}
            updateSet={updateSet}
            onBack={() => setScreen("home")}
            onFinish={() => {
              setFin({ rpe: 7, pain: "", feedback: "" });
              setScreen("finish");
            }}
          />
        )}

        {screen === "finish" && (
          <Finish fin={fin} setFin={setFin} onSave={finishSession} onBack={() => setScreen("workout")} />
        )}

        {screen === "history" && (
          <History history={history} onBack={() => setScreen("home")} />
        )}
      </div>
    </div>
  );
}

// ================= SCREENS =================

function Home({ todayPlan, history, onStart, onResume, onHistory }) {
  const S = styles;
  const last = history[history.length - 1];
  const doneToday = todayPlan && todayPlan.finished;
  const inProgress = todayPlan && !todayPlan.finished;
  return (
    <>
      <header style={S.header}>
        <div style={S.brandSm}>COACH</div>
        <button className="ghostBtn" onClick={onHistory}>Log</button>
      </header>

      <div style={S.heroBlock}>
        <div style={S.eyebrow}>{new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</div>
        <h1 style={S.h1}>
          {doneToday ? "Session done." : inProgress ? "Session in progress" : "Ready when you are."}
        </h1>
        <p style={S.sub}>
          {doneToday
            ? `${todayPlan.plan.sessionType} logged. Recovery feeds tomorrow's plan.`
            : inProgress
            ? `${todayPlan.plan.sessionType} — pick up where you left off.`
            : "60-second check-in. The plan, the weights, the timing — handled."}
        </p>
      </div>

      {inProgress ? (
        <button className="bigBtn" onClick={onResume}>Resume {todayPlan.plan.sessionType}</button>
      ) : (
        <button className="bigBtn" onClick={onStart}>{doneToday ? "Plan another session" : "Start check-in"}</button>
      )}

      {last && (
        <div style={S.card}>
          <div style={S.cardLabel}>Last session</div>
          <div style={S.rowBetween}>
            <span style={S.mono}>{fmtDate(last.date)}</span>
            <span style={{ ...S.mono, color: "#F5A623" }}>{last.plan.sessionType}</span>
          </div>
          {last.fin && (
            <div style={{ ...S.mono, marginTop: 6, color: "#8A93A6", fontSize: 13 }}>
              Session RPE {last.fin.rpe}/10{last.fin.pain ? ` · pain: ${last.fin.pain}` : ""}
            </div>
          )}
        </div>
      )}

      <div style={S.footNote}>
        Tip: paste today's Apple Health numbers during check-in (sleep, HRV, resting HR, steps) — the coach reads them. Health data can't sync automatically here.
      </div>
    </>
  );
}

// ---------------- Check-in: ONE screen, pre-filled ----------------
// Defaults describe a normal day. If nothing's unusual, the user taps
// nothing and goes straight to "Build today's session".

function Pill({ on, warn, onClick, children, style }) {
  return (
    <button
      className={"pill" + (on ? (warn ? " pillWarn" : " pillOn") : "")}
      onClick={onClick}
      style={style}
    >
      {children}
    </button>
  );
}

function Seg({ options, value, onChange }) {
  return (
    <div style={{ display: "flex", gap: 8 }}>
      {options.map(([v, l]) => (
        <button
          key={v}
          className={"segBtn" + (value === v ? " segOn" : "")}
          onClick={() => onChange(v)}
        >
          {l}
        </button>
      ))}
    </div>
  );
}

function CheckIn({ ci, setCi, error, onCancel, onSubmit }) {
  const S = styles;
  const [showHealth, setShowHealth] = useState(false);
  const set = (patch) => setCi({ ...ci, ...patch });

  return (
    <>
      <header style={S.header}>
        <button className="ghostBtn" onClick={onCancel}>Cancel</button>
        <div style={S.brandSm}>CHECK-IN</div>
      </header>

      <p style={{ ...S.sub, marginTop: 0 }}>
        Pre-set for a normal day. Only tap what's different — then build.
      </p>

      <div style={S.qLabel}>Energy</div>
      <div style={S.energyRow}>
        {[1,2,3,4,5,6,7,8,9,10].map((n) => (
          <button
            key={n}
            className={"numBtn" + (ci.energy === n ? " numOn" : "")}
            onClick={() => set({ energy: n })}
          >{n}</button>
        ))}
      </div>

      <div style={S.qLabel}>Sleep last night</div>
      <Seg
        options={[["Great","Great"],["OK","OK"],["Poor","Poor"]]}
        value={ci.sleep}
        onChange={(v) => set({ sleep: v })}
      />

      <div style={S.qLabel}>Soreness</div>
      <Seg
        options={[["None","None"],["Light","Light"],["Very sore","Very sore"]]}
        value={ci.soreness}
        onChange={(v) => set({ soreness: v })}
      />
      {ci.soreness !== "None" && (
        <input
          style={S.input}
          placeholder="Where? e.g. chest, quads"
          value={ci.soreAreas}
          onChange={(e) => set({ soreAreas: e.target.value })}
        />
      )}
      <Pill
        on={ci.backTight}
        warn
        style={{ marginTop: 10, marginBottom: 0 }}
        onClick={() => set({ backTight: !ci.backTight })}
      >
        {ci.backTight ? "✓ Lower back tight today — coach will adapt" : "Lower back tight today?"}
      </Pill>

      <div style={S.qLabel}>Gym time (walk not included)</div>
      <Seg
        options={[["30","30m"],["45","45m"],["60","60m"],["75","75m+"]]}
        value={ci.timeAvail}
        onChange={(v) => set({ timeAvail: v })}
      />

      <button className="ghostBtn" style={{ marginTop: 22, padding: 0 }} onClick={() => setShowHealth(!showHealth)}>
        {showHealth ? "− Hide health data" : "+ Paste Apple Health data (optional)"}
      </button>
      {showHealth && (
        <>
          <textarea
            style={{ ...S.input, minHeight: 100, resize: "vertical" }}
            placeholder={"Paste anything — sleep, HRV, resting HR, steps.\ne.g. Sleep 6h40m · HRV 48 · RHR 58"}
            value={ci.health}
            onChange={(e) => set({ health: e.target.value })}
          />
          <input
            style={S.input}
            placeholder="Anything else? (injury, plans — optional)"
            value={ci.notes}
            onChange={(e) => set({ notes: e.target.value })}
          />
        </>
      )}

      <div style={{ marginTop: 24 }}>
        <ReadinessBar value={quickReadiness(ci)} label="Quick readiness estimate" />
      </div>

      {error && <div style={S.errBox}>{error}</div>}

      <button className="bigBtn" onClick={onSubmit}>Build today's session</button>
      <div style={{ height: 24 }} />
    </>
  );
}

function ReadinessBar({ value, label }) {
  const segs = 20;
  const filled = Math.round((value / 100) * segs);
  const color = value >= 70 ? "#39D0B8" : value >= 45 ? "#F5A623" : "#F26D5B";
  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 8 }}>
        <span style={{ fontFamily: "'Barlow Condensed', sans-serif", textTransform: "uppercase", letterSpacing: "0.12em", fontSize: 13, color: "#8A93A6" }}>{label}</span>
        <span style={{ fontFamily: "'IBM Plex Mono', monospace", fontSize: 22, color }}>{value}</span>
      </div>
      <div style={{ display: "flex", gap: 3 }}>
        {Array.from({ length: segs }, (_, i) => (
          <div key={i} style={{
            flex: 1, height: 22, borderRadius: 2,
            background: i < filled ? color : "#232B3A",
            opacity: i < filled ? 0.5 + 0.5 * (i / segs) : 1,
            transition: "background 0.3s",
          }} />
        ))}
      </div>
    </div>
  );
}

function Generating({ readiness }) {
  const S = styles;
  const [msg, setMsg] = useState(0);
  const msgs = [
    "Reading your training log…",
    "Checking recovery signals…",
    "Weighing volume vs. your evening…",
    "Building the session…",
  ];
  useEffect(() => {
    const id = setInterval(() => setMsg((m) => (m + 1) % msgs.length), 1800);
    return () => clearInterval(id);
  }, []);
  return (
    <div style={S.centerFill}>
      <div className="pulse" style={S.brand}>COACH</div>
      <div style={{ marginTop: 28, width: "100%", maxWidth: 320 }}>
        <ReadinessBar value={readiness} label="Readiness (initial estimate)" />
      </div>
      <div style={{ ...S.mono, color: "#8A93A6", marginTop: 24, fontSize: 14 }}>{msgs[msg]}</div>
    </div>
  );
}

// ---------------- Workout ----------------
function Workout({ t, updateSet, onBack, onFinish }) {
  const S = styles;
  const p = t.plan;
  const totalSets = t.log.reduce((a, ex) => a + ex.length, 0);
  const doneSets = t.log.reduce((a, ex) => a + ex.filter((s) => s.done).length, 0);
  return (
    <>
      <header style={S.header}>
        <button className="ghostBtn" onClick={onBack}>Home</button>
        <span style={{ ...S.mono, fontSize: 13, color: "#8A93A6" }}>{doneSets}/{totalSets} sets</span>
      </header>

      <div style={S.heroBlock}>
        <div style={S.eyebrow}>{fmtDate(t.date)} · est. {p.estTimeMin} min door-to-door</div>
        <h1 style={{ ...S.h1, color: "#F5A623" }}>{p.sessionType.toUpperCase()}</h1>
        {p.title && <p style={S.sub}>{p.title}</p>}
      </div>

      <ReadinessBar value={p.recoveryScore} label="Coach recovery score" />

      <div style={{ ...S.card, marginTop: 16 }}>
        <div style={S.cardLabel}>Why this session</div>
        <p style={S.body}>{p.reasoning}</p>
        {p.concerns ? <p style={{ ...S.body, color: "#F26D5B", marginTop: 8 }}>⚠ {p.concerns}</p> : null}
      </div>

      {p.warmup?.length > 0 && (
        <div style={S.card}>
          <div style={S.cardLabel}>Warm-up</div>
          {p.warmup.map((w, i) => <p key={i} style={S.body}>· {w}</p>)}
        </div>
      )}

      {(p.exercises || []).map((ex, exI) => (
        <div key={exI} style={S.exCard}>
          <div style={S.rowBetween}>
            <div style={S.exName}>{ex.name}</div>
            <div style={{ ...S.mono, color: "#8A93A6", fontSize: 13 }}>RPE {ex.rpe} · rest {ex.rest}</div>
          </div>
          <div style={{ ...S.mono, fontSize: 13, color: "#39D0B8", margin: "4px 0 2px" }}>
            {ex.sets} × {ex.reps}{ex.suggestedWeight ? ` · try ${ex.suggestedWeight}` : ""}
          </div>
          {ex.notes && <p style={{ ...S.body, fontSize: 13, color: "#8A93A6" }}>{ex.notes}</p>}
          <div style={{ marginTop: 10 }}>
            {t.log[exI].map((set, setI) => (
              <div key={setI} style={S.setRow}>
                <button
                  className={"setChk" + (set.done ? " setChkOn" : "")}
                  onClick={() => updateSet(exI, setI, "done", !set.done)}
                >{set.done ? "✓" : setI + 1}</button>
                <input
                  style={S.setInput} inputMode="decimal" placeholder="kg"
                  value={set.weight}
                  onChange={(e) => updateSet(exI, setI, "weight", e.target.value)}
                />
                <span style={{ color: "#4A5468" }}>×</span>
                <input
                  style={S.setInput} inputMode="numeric" placeholder="reps"
                  value={set.reps}
                  onChange={(e) => updateSet(exI, setI, "reps", e.target.value)}
                />
              </div>
            ))}
          </div>
          {ex.alt && <div style={{ ...S.mono, fontSize: 12, color: "#4A5468", marginTop: 8 }}>Machine busy? → {ex.alt}</div>}
        </div>
      ))}

      {p.cardio && (
        <div style={S.card}>
          <div style={S.cardLabel}>Cardio</div>
          <p style={S.body}>{p.cardio.desc} — {p.cardio.duration}</p>
        </div>
      )}

      {p.cooldown?.length > 0 && (
        <div style={S.card}>
          <div style={S.cardLabel}>Cool-down</div>
          {p.cooldown.map((c, i) => <p key={i} style={S.body}>· {c}</p>)}
        </div>
      )}

      <button className="bigBtn" onClick={onFinish}>Finish session</button>
      <div style={{ height: 24 }} />
    </>
  );
}

// ---------------- Finish ----------------
function Finish({ fin, setFin, onSave, onBack }) {
  const S = styles;
  return (
    <>
      <header style={S.header}>
        <button className="ghostBtn" onClick={onBack}>Back</button>
      </header>
      <h2 style={S.h2}>Log it. 20 seconds.</h2>

      <div style={S.cardLabel}>Overall session RPE</div>
      <div style={S.energyRow}>
        {[1,2,3,4,5,6,7,8,9,10].map((n) => (
          <button key={n} className={"numBtn" + (fin.rpe === n ? " numOn" : "")}
            onClick={() => setFin({ ...fin, rpe: n })}>{n}</button>
        ))}
      </div>

      <div style={{ ...S.cardLabel, marginTop: 20 }}>Any pain or discomfort?</div>
      <input style={S.input} placeholder="e.g. none / left shoulder on incline press"
        value={fin.pain} onChange={(e) => setFin({ ...fin, pain: e.target.value })} />

      <div style={{ ...S.cardLabel, marginTop: 20 }}>Too easy / too hard?</div>
      <input style={S.input} placeholder="e.g. leg press felt light, curls brutal"
        value={fin.feedback} onChange={(e) => setFin({ ...fin, feedback: e.target.value })} />

      <button className="bigBtn" onClick={onSave} style={{ marginTop: 28 }}>Save session</button>
      <p style={S.footNote}>Weights and reps you logged per set are saved automatically. This feeds tomorrow's plan.</p>
    </>
  );
}

// ---------------- History ----------------
function History({ history, onBack }) {
  const S = styles;
  const rev = [...history].reverse();
  return (
    <>
      <header style={S.header}>
        <button className="ghostBtn" onClick={onBack}>Home</button>
        <div style={S.brandSm}>LOG</div>
      </header>
      {rev.length === 0 && (
        <div style={S.centerFill}>
          <p style={{ ...S.body, color: "#8A93A6", textAlign: "center" }}>
            Nothing logged yet.<br />Your first session will show up here — and every one after it makes the coach smarter.
          </p>
        </div>
      )}
      {rev.map((h, i) => (
        <div key={i} style={S.card}>
          <div style={S.rowBetween}>
            <span style={{ ...S.exName, fontSize: 18 }}>{h.plan.sessionType}</span>
            <span style={{ ...S.mono, fontSize: 13, color: "#8A93A6" }}>{fmtDate(h.date)}</span>
          </div>
          {(h.plan.exercises || []).map((ex, exI) => {
            const sets = (h.log?.[exI] || []).filter((s) => s.done);
            return (
              <div key={exI} style={{ ...S.mono, fontSize: 13, color: "#8A93A6", marginTop: 6 }}>
                {ex.name}: {sets.length ? sets.map((s) => `${s.weight || "?"}×${s.reps || "?"}`).join("  ") : "—"}
              </div>
            );
          })}
          {h.fin && (
            <div style={{ ...S.mono, fontSize: 13, color: "#F5A623", marginTop: 8 }}>
              RPE {h.fin.rpe}/10{h.fin.pain ? ` · ${h.fin.pain}` : ""}{h.fin.feedback ? ` · ${h.fin.feedback}` : ""}
            </div>
          )}
        </div>
      ))}
      <div style={{ height: 24 }} />
    </>
  );
}

// ================= STYLES =================
function GlobalStyle() {
  return (
    <style>{`
      @import url('https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500&family=Archivo:wght@400;500;600&display=swap');
      * { box-sizing: border-box; margin: 0; }
      button { cursor: pointer; font-family: inherit; }
      input, textarea { font-family: 'IBM Plex Mono', monospace; }
      input:focus, textarea:focus, button:focus-visible { outline: 2px solid #39D0B8; outline-offset: 2px; }
      .pulse { animation: pulse 1.6s ease-in-out infinite; }
      @keyframes pulse { 0%,100% { opacity: 1 } 50% { opacity: 0.35 } }
      @media (prefers-reduced-motion: reduce) { .pulse { animation: none } * { transition: none !important } }
      .bigBtn {
        width: 100%; padding: 18px; border: none; border-radius: 10px;
        background: #F5A623; color: #10141C;
        font-family: 'Barlow Condensed', sans-serif; font-weight: 700;
        font-size: 20px; letter-spacing: 0.08em; text-transform: uppercase;
        margin-top: 20px; transition: transform 0.1s;
      }
      .bigBtn:active { transform: scale(0.98); }
      .nextBtn {
        padding: 14px 28px; border: none; border-radius: 10px;
        background: #232B3A; color: #E8ECF4;
        font-family: 'Barlow Condensed', sans-serif; font-weight: 600;
        font-size: 17px; letter-spacing: 0.08em; text-transform: uppercase;
      }
      .nextBtn:disabled { opacity: 0.35; cursor: default; }
      .ghostBtn {
        background: none; border: none; color: #8A93A6;
        font-family: 'Barlow Condensed', sans-serif; font-size: 16px;
        letter-spacing: 0.08em; text-transform: uppercase; padding: 6px 4px;
      }
      .pill {
        display: block; width: 100%; text-align: left;
        padding: 15px 18px; border-radius: 10px; margin-bottom: 10px;
        background: #1A2130; border: 1px solid #2A3242; color: #E8ECF4;
        font-family: 'Archivo', sans-serif; font-size: 16px;
        transition: border-color 0.15s, background 0.15s;
      }
      .pillOn { border-color: #F5A623; background: #241F14; color: #F5A623; }
      .pillWarn { border-color: #F26D5B; background: #241614; color: #F26D5B; }
      .numBtn {
        flex: 1; aspect-ratio: 1; min-width: 0; border-radius: 8px;
        background: #1A2130; border: 1px solid #2A3242; color: #8A93A6;
        font-family: 'IBM Plex Mono', monospace; font-size: 15px;
      }
      .numOn { background: #F5A623; border-color: #F5A623; color: #10141C; font-weight: 600; }
      .setChk {
        width: 40px; height: 40px; border-radius: 8px; flex-shrink: 0;
        background: #1A2130; border: 1px solid #2A3242; color: #8A93A6;
        font-family: 'IBM Plex Mono', monospace; font-size: 15px;
      }
      .setChkOn { background: #0F2B26; border-color: #39D0B8; color: #39D0B8; }
      .segBtn {
        flex: 1; padding: 13px 6px; border-radius: 10px;
        background: #1A2130; border: 1px solid #2A3242; color: #C7CEDC;
        font-family: 'Archivo', sans-serif; font-size: 15px;
        transition: border-color 0.15s, background 0.15s;
      }
      .segOn { border-color: #F5A623; background: #241F14; color: #F5A623; font-weight: 600; }
    `}</style>
  );
}

const styles = {
  app: {
    minHeight: "100vh", background: "#10141C", color: "#E8ECF4",
    fontFamily: "'Archivo', sans-serif",
  },
  frame: { maxWidth: 520, margin: "0 auto", padding: "16px 18px 32px" },
  centerFill: {
    minHeight: "70vh", display: "flex", flexDirection: "column",
    alignItems: "center", justifyContent: "center", padding: 24,
  },
  header: {
    display: "flex", justifyContent: "space-between", alignItems: "center",
    paddingBottom: 14, marginBottom: 8,
  },
  brand: {
    fontFamily: "'Barlow Condensed', sans-serif", fontWeight: 700,
    fontSize: 40, letterSpacing: "0.35em", color: "#F5A623", paddingLeft: "0.35em",
  },
  brandSm: {
    fontFamily: "'Barlow Condensed', sans-serif", fontWeight: 700,
    fontSize: 18, letterSpacing: "0.3em", color: "#F5A623",
  },
  heroBlock: { margin: "18px 0 10px" },
  eyebrow: {
    fontFamily: "'IBM Plex Mono', monospace", fontSize: 12,
    color: "#8A93A6", textTransform: "uppercase", letterSpacing: "0.1em",
    marginBottom: 8,
  },
  h1: {
    fontFamily: "'Barlow Condensed', sans-serif", fontWeight: 700,
    fontSize: 42, lineHeight: 1.02, letterSpacing: "0.01em",
  },
  h2: {
    fontFamily: "'Barlow Condensed', sans-serif", fontWeight: 600,
    fontSize: 30, margin: "10px 0 18px",
  },
  sub: { color: "#8A93A6", fontSize: 15, lineHeight: 1.5, marginTop: 10 },
  body: { fontSize: 14.5, lineHeight: 1.55, color: "#C7CEDC" },
  mono: { fontFamily: "'IBM Plex Mono', monospace" },
  card: {
    background: "#161C28", border: "1px solid #232B3A", borderRadius: 12,
    padding: 16, marginTop: 14,
  },
  exCard: {
    background: "#161C28", border: "1px solid #232B3A", borderRadius: 12,
    padding: 16, marginTop: 14, borderLeft: "3px solid #F5A623",
  },
  exName: {
    fontFamily: "'Barlow Condensed', sans-serif", fontWeight: 600,
    fontSize: 21, letterSpacing: "0.02em",
  },
  cardLabel: {
    fontFamily: "'Barlow Condensed', sans-serif", textTransform: "uppercase",
    letterSpacing: "0.14em", fontSize: 13, color: "#8A93A6", marginBottom: 8,
  },
  rowBetween: { display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10 },
  setRow: { display: "flex", alignItems: "center", gap: 8, marginTop: 8 },
  setInput: {
    width: 78, padding: "10px 10px", borderRadius: 8,
    background: "#10141C", border: "1px solid #2A3242", color: "#E8ECF4",
    fontSize: 15, textAlign: "center",
  },
  input: {
    width: "100%", padding: "13px 14px", borderRadius: 10, marginTop: 10,
    background: "#10141C", border: "1px solid #2A3242", color: "#E8ECF4",
    fontSize: 14.5,
  },
  energyRow: { display: "flex", gap: 6 },
  hintRow: {
    display: "flex", justifyContent: "space-between", marginTop: 8,
    fontSize: 12, color: "#4A5468",
    fontFamily: "'IBM Plex Mono', monospace",
  },
  qLabel: {
    fontFamily: "'Barlow Condensed', sans-serif", textTransform: "uppercase",
    letterSpacing: "0.14em", fontSize: 13, color: "#8A93A6",
    margin: "22px 0 8px",
  },
  footNote: {
    marginTop: 22, fontSize: 12.5, lineHeight: 1.5, color: "#4A5468",
    fontFamily: "'IBM Plex Mono', monospace",
  },
  errBox: {
    marginTop: 14, padding: 12, borderRadius: 10, fontSize: 13.5,
    background: "#241614", border: "1px solid #F26D5B", color: "#F26D5B",
  },
};
