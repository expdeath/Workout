import React from 'react';

// Material Symbols Outlined (Apache-2.0), from a bundled subset font
// (src/assets/fonts) so icons work offline. Short app names map to the
// symbol names below; any other string is used as a symbol name directly.
// The subset's icon list is in src/assets/fonts/material-symbols-subset.txt;
// to add an icon, re-download the font from Google Fonts' css2 API with
// that list plus the new name as `icon_names` (names sorted).
const NAMES = {
  home: 'bolt',
  list: 'edit_calendar',
  chart: 'bar_chart',
  trophy: 'emoji_events',
  settings: 'tune',
  back: 'chevron_left',
  down: 'expand_more',
  right: 'chevron_right',
  plus: 'add',
  minus: 'remove',
  x: 'close',
  chat: 'chat_bubble',
  more: 'more_horiz',
  weight: 'scale',
  swap: 'swap_horiz',
  play: 'play_circle',
  note: 'edit_note',
  trash: 'delete',
  alert: 'warning',
  bell: 'notifications',
  run: 'directions_run',
  ride: 'directions_bike',
  walk: 'directions_walk',
  hike: 'hiking',
  dumbbell: 'fitness_center',
  flame: 'local_fire_department',
  medal: 'military_tech',
  target: 'track_changes',
  heart: 'ecg_heart',
  shield: 'health_and_safety',
};

export default function Icon({ name, size = 20, fill = false, style, className = '', ...rest }) {
  return (
    <span
      className={`msym${fill ? ' msym--fill' : ''}${className ? ' ' + className : ''}`}
      style={{ fontSize: typeof size === 'number' ? size : undefined, ...style }}
      aria-hidden="true"
      {...rest}
    >
      {NAMES[name] || name}
    </span>
  );
}
