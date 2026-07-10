import React from 'react';

export default function Pill({ on, warn, onClick, children, style }) {
  return (
    <button
      className={'pill' + (on ? (warn ? ' pill-warn' : ' pill-on') : '')}
      onClick={onClick}
      style={style}
    >
      {children}
    </button>
  );
}
