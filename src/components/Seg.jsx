import React from 'react';

export default function Seg({ options, value, onChange }) {
  return (
    <div className="seg-group">
      {options.map(([v, l]) => (
        <button
          key={v}
          className={'seg-btn' + (value === v ? ' seg-on' : '')}
          onClick={() => onChange(v)}
        >
          {l}
        </button>
      ))}
    </div>
  );
}
