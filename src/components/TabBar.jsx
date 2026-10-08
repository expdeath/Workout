import React from 'react';
import Icon from './Icon';

export const TABS = [
  { screen: 'home', icon: 'home', label: 'Today' },
  { screen: 'history', icon: 'list', label: 'Log' },
  { screen: 'progress', icon: 'chart', label: 'Progress' },
  { screen: 'records', icon: 'trophy', label: 'Records' },
  { screen: 'settings', icon: 'settings', label: 'Settings' },
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
          <Icon name={t.icon} size={22} strokeWidth={screen === t.screen ? 2.2 : 1.8} />
          <span>{t.label}</span>
        </button>
      ))}
    </nav>
  );
}
