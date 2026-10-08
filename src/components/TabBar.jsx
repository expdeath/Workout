import React from 'react';
import Icon from './Icon';

export const TABS = [
  { screen: 'home', icon: 'bolt', label: 'Today' },
  { screen: 'history', icon: 'edit_calendar', label: 'Log' },
  { screen: 'progress', icon: 'bar_chart', label: 'Progress' },
  { screen: 'records', icon: 'emoji_events', label: 'Records' },
  { screen: 'settings', icon: 'tune', label: 'Settings' },
];

// Bottom tab bar on the five top-level screens.
export default function TabBar({ screen, onSelect }) {
  return (
    <nav className="tab-bar" aria-label="Main">
      {TABS.map((t) => (
        <button
          key={t.screen}
          className={`tab-bar__item${screen === t.screen ? ' tab-bar__item--on' : ''}`}
          aria-current={screen === t.screen ? 'page' : undefined}
          onClick={() => onSelect(t.screen)}
        >
          <Icon name={t.icon} size={23} fill={screen === t.screen} />
          <span>{t.label}</span>
        </button>
      ))}
    </nav>
  );
}
