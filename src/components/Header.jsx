import React from 'react';
import Icon from './Icon';

// Optional back chevron, large left-aligned title, optional trailing
// icon button — every screen's header.
export default function Header({ title, onBack, backLabel = 'Back', trailing }) {
  return (
    <header className="screen-header">
      {onBack && (
        <button className="icon-btn icon-btn--back" aria-label={backLabel} onClick={onBack}>
          <Icon name="back" size={24} />
        </button>
      )}
      <h1 className="screen-header__title">{title}</h1>
      {trailing && (
        <button className="icon-btn" aria-label={trailing.label} onClick={trailing.onClick}>
          <Icon name={trailing.icon} size={22} />
        </button>
      )}
    </header>
  );
}
