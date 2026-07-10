import React from 'react';

export default function Header({ left, right, center }) {
  return (
    <header className="header">
      <div className="header__left">{left}</div>
      {center && <div className="header__center">{center}</div>}
      <div className="header__right">{right}</div>
    </header>
  );
}
