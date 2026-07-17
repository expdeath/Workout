import React from 'react';

// Bottom action sheet for touch: full-width thumb-sized rows instead
// of a tiny popover. Tap the backdrop or Cancel to dismiss.
export default function ActionSheet({ title, onClose, children }) {
  return (
    <>
      <div className="chat-sheet-backdrop" onClick={onClose} />
      <div className="action-sheet" role="menu" aria-label={title}>
        <div className="action-sheet__handle" />
        {title && <div className="action-sheet__title">{title}</div>}
        {children}
        <button className="action-sheet__cancel" onClick={onClose}>
          Cancel
        </button>
      </div>
    </>
  );
}
