import React, { createContext, useContext, useEffect, useState } from 'react';
import Icon from './Icon';
import { TABS } from './TabBar';
import { ago } from '../utils/dashboard';
import { getAccount } from '../utils/account';
import { SearchBox } from './Search';

// App-wide chrome shared by the five tab screens: the header (COACH •
// TITLE, desktop nav, chat, notifications, profile), and the small
// building blocks of the dashboard look. The iOS twins live in
// Components/CoachUI.swift.

export const ShellContext = createContext({
  screen: 'home',
  go: () => {},
  openWorkouts: () => {},
  openSession: () => {},
  openRecord: () => {},
  history: [],
  openChat: () => {},
  openSheet: () => {},
  unread: 0,
  displayName: '',
});
export const useShell = () => useContext(ShellContext);

export function Avatar({ name, size = 32 }) {
  const initials = String(name || '')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0])
    .join('')
    .toUpperCase();
  return (
    <span className="avatar" style={{ width: size, height: size, fontSize: size * 0.45 }}>
      {initials || '?'}
    </span>
  );
}

/** COACH • TITLE · (desktop: tab links) · chat · bell · avatar */
export function TabHeader({ title }) {
  const { screen, go, openWorkouts, openChat, openSheet, unread, displayName } = useShell();
  // desktop nav: the five tabs, with My workouts after Log
  const links = [...TABS.slice(0, 2), { screen: 'workouts', label: 'Workouts' }, ...TABS.slice(2)];
  return (
    <header className="tab-header">
      <div className="tab-header__brand">
        <span className="caps tab-header__coach">COACH</span>
        <span className="tab-header__dot" />
        <span className="tab-header__title">{title}</span>
      </div>
      <nav className="tab-header__nav" aria-label="Main">
        {links.map((t) => (
          <button
            key={t.screen}
            className={'tab-header__link' + (screen === t.screen ? ' tab-header__link--on' : '')}
            aria-current={screen === t.screen ? 'page' : undefined}
            onClick={() => (t.screen === 'workouts' ? openWorkouts() : go(t.screen))}
          >
            {t.label}
          </button>
        ))}
      </nav>
      <SearchBox />
      <div className="tab-header__actions">
        <button className="icon-btn tab-header__search" aria-label="Search" onClick={() => openSheet('search')}>
          <Icon name="search" size={22} />
        </button>
        <button className="icon-btn" aria-label="Ask the coach" onClick={openChat}>
          <Icon name="chat" size={21} />
        </button>
        <button
          className="icon-btn icon-btn--badge"
          aria-label={unread ? `Notifications, ${unread} new` : 'Notifications'}
          onClick={() => openSheet('notifications')}
        >
          <Icon name="bell" size={22} />
          {unread > 0 && <span className="icon-btn__dot" />}
        </button>
        <button className="tab-header__me" aria-label="Profile" onClick={() => openSheet('profile')}>
          <span className="tab-header__name">{displayName}</span>
          <Avatar name={displayName} size={32} />
        </button>
      </div>
    </header>
  );
}

const DESKTOP = '(min-width: 1024px)';

/** True on desktop-width windows — tab screens switch to their wide layout. */
export function useDesktop() {
  const [on, setOn] = useState(() => typeof window !== 'undefined' && !!window.matchMedia?.(DESKTOP).matches);
  useEffect(() => {
    const mq = window.matchMedia?.(DESKTOP);
    if (!mq) return undefined;
    const onChange = (e) => setOn(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);
  return on;
}

/** Desktop page head: kicker line, big title, a one-line summary, actions on the right. */
export function PageHero({ kicker, title, sub, children }) {
  return (
    <div className="dash-hero">
      <div style={{ minWidth: 0 }}>
        {kicker && <div className="page-kicker">{kicker}</div>}
        <h1 className="hero-title">{title}</h1>
        {sub && <p className="page-sub">{sub}</p>}
      </div>
      {children && <div className="dash-hero__actions">{children}</div>}
    </div>
  );
}

/** Desktop stat card: caps label + icon, a big number, a note, optional footer. */
export function KpiCard({ label, icon, value, unit, note, noteColor = 'var(--muted)', children }) {
  return (
    <div className="card kpi">
      <div className="row-between">
        <span className="caps">{label}</span>
        {icon && <Icon name={icon} size={18} style={{ color: 'var(--amber-text)' }} />}
      </div>
      <div className="kpi__row">
        <span className="hero-title kpi__value">
          {value}
          {unit && <span className="kpi__unit">{unit}</span>}
        </span>
        {note && <span className="caps kpi__note" style={{ color: noteColor }}>{note}</span>}
      </div>
      {children && <div className="kpi__foot">{children}</div>}
    </div>
  );
}

export function StatusPill({ text, color = 'var(--green)', dot = true }) {
  return (
    <span className="status-pill" style={{ color, background: `color-mix(in srgb, ${color} 13%, transparent)` }}>
      {dot && <span className="status-pill__dot" style={{ background: color }} />}
      {text}
    </span>
  );
}

export function SectionHead({ title, trailing, trailingColor = 'var(--amber-text)', onTrailing }) {
  return (
    <div className="section-head">
      <span className="caps">{title}</span>
      {trailing &&
        (onTrailing ? (
          <button className="caps section-head__action" style={{ color: trailingColor }} onClick={onTrailing}>
            {trailing}
          </button>
        ) : (
          <span className="caps section-head__note" style={{ color: trailingColor }}>{trailing}</span>
        ))}
    </div>
  );
}

export function ProgressLine({ fraction, color = 'var(--amber)', height = 6 }) {
  return (
    <div className="progress-line" style={{ height }}>
      <div style={{ width: `${Math.max(0, Math.min(1, fraction || 0)) * 100}%`, background: color }} />
    </div>
  );
}

export function StatBlock({ value, label, color }) {
  return (
    <div className="stat-block">
      <div className="stat-block__value" style={color ? { color } : undefined}>{value}</div>
      <div className="caps stat-block__label">{label}</div>
    </div>
  );
}

export function LaunchTile({ icon, label, tint = 'var(--amber-text)', onClick }) {
  return (
    <button className="launch-tile" aria-label={label} onClick={onClick}>
      <span className="icon-well" style={{ color: tint }}><Icon name={icon} size={20} /></span>
      <span className="caps launch-tile__label">{label}</span>
    </button>
  );
}

export function IconWell({ icon, tint = 'var(--amber-text)', size = 36, fill = false }) {
  return (
    <span className="icon-well" style={{ color: tint, width: size, height: size }}>
      <Icon name={icon} size={Math.round(size * 0.55)} fill={fill} />
    </span>
  );
}

export function Segmented({ options, value, onChange }) {
  return (
    <div className="segmented" role="tablist">
      {options.map(([v, l]) => (
        <button
          key={v}
          role="tab"
          aria-selected={v === value}
          className={'caps segmented__btn' + (v === value ? ' segmented__btn--on' : '')}
          onClick={() => onChange(v)}
        >
          {l}
        </button>
      ))}
    </div>
  );
}

export function RowGroup({ children }) {
  return <div className="row-group">{children}</div>;
}

export function SettingsRow({ icon, tint, title, subtitle, value, onClick }) {
  const Tag = onClick ? 'button' : 'div';
  return (
    <Tag className="settings-row" onClick={onClick}>
      <IconWell icon={icon} tint={tint} />
      <span className="settings-row__text">
        <span className="settings-row__title">{title}</span>
        {subtitle && <span className="settings-row__sub">{subtitle}</span>}
      </span>
      {value != null && <span className="caps settings-row__value">{value}</span>}
      {onClick && <Icon name="right" size={20} className="settings-row__chev" />}
    </Tag>
  );
}

/** Tall bottom sheet with a title and a close button. */
export function PanelSheet({ title, onClose, children }) {
  return (
    <>
      <div className="chat-sheet-backdrop" onClick={onClose} />
      <div className="panel-sheet" role="dialog" aria-label={title}>
        <div className="panel-sheet__head">
          <span className="screen-header__title" style={{ fontSize: 26 }}>{title}</span>
          <button className="icon-btn" aria-label="Close" onClick={onClose}>
            <Icon name="x" size={22} />
          </button>
        </div>
        <div className="panel-sheet__body">{children}</div>
      </div>
    </>
  );
}

/** The bell's inbox. Opening it marks everything read (done by the caller). */
export function NotificationsSheet({ items, seenBefore, onOpen, onClose }) {
  return (
    <PanelSheet title="Notifications" onClose={onClose}>
      {!items.length && (
        <p className="body" style={{ color: 'var(--muted)', textAlign: 'center', padding: '32px 8px' }}>
          Nothing yet — reviews, records and milestones show up here.
        </p>
      )}
      {items.map((n) => (
        <button key={n.id} className="notice-row" onClick={() => onOpen(n)}>
          <IconWell icon={n.icon} tint={n.icon === 'warning' ? 'var(--red)' : 'var(--amber-text)'} size={34} />
          <span className="notice-row__text">
            <span className="notice-row__top">
              <span className="notice-row__title">{n.title}</span>
              <span className="notice-row__ago">{ago(n.at)}</span>
            </span>
            <span className="notice-row__body">{n.body}</span>
          </span>
          {n.at > seenBefore && <span className="notice-row__dot" />}
        </button>
      ))}
    </PanelSheet>
  );
}

/** Edit profile: display name (state `displayName`) + weekly target. */
export function ProfileSheet({ displayName, nameOverride, target, onSave, onClose }) {
  const account = getAccount();
  const [name, setName] = useState(nameOverride || account?.name || '');
  const [t, setT] = useState(target);
  return (
    <PanelSheet title="Profile" onClose={onClose}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '6px 0 4px' }}>
        <Avatar name={name || displayName} size={56} />
        <div style={{ minWidth: 0 }}>
          <div style={{ fontWeight: 700, fontSize: 18 }}>{name || displayName}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 4 }}>
            <StatusPill text={account?.admin ? 'Admin' : 'Member'} color="var(--amber-text)" dot={false} />
            <span style={{ fontSize: 12.5, color: 'var(--muted)', overflow: 'hidden', textOverflow: 'ellipsis' }}>{account?.email}</span>
          </div>
        </div>
      </div>
      <div className="q-label">Display name</div>
      <input
        className="input"
        style={{ marginTop: 0 }}
        placeholder={account?.name || 'Your name'}
        value={name}
        onChange={(e) => setName(e.target.value.slice(0, 40))}
      />
      <div className="q-label q-label--row">
        <span>Weekly target</span>
        <span className="q-label__value">{t} / week</span>
      </div>
      <div className="stepper">
        <button className="icon-btn" aria-label="Fewer sessions" disabled={t <= 1} onClick={() => setT(t - 1)}>
          <Icon name="minus" size={22} />
        </button>
        <span className="stepper__value">{t}</span>
        <button className="icon-btn" aria-label="More sessions" disabled={t >= 14} onClick={() => setT(t + 1)}>
          <Icon name="plus" size={22} />
        </button>
      </div>
      <p className="body" style={{ fontSize: 13, color: 'var(--muted)', marginTop: 6 }}>
        Sets your streak, consistency and the weekly target bar.
      </p>
      <button className="big-btn" onClick={() => onSave(name.trim(), t)}>Save</button>
    </PanelSheet>
  );
}
