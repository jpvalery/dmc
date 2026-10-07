// Page copy that repeats in a pattern. Strings may hold inline HTML (<code>, <kbd>); they are
// written here, never taken from users.

export const panes = [
  {
    pos: 'Stage left',
    name: 'Scenes',
    text: 'Every scene is one click. Click again to fade it out. Collapsed, the rail keeps its icons.',
  },
  {
    pos: 'Centre stage',
    name: 'Browser',
    text: 'D&amp;D Beyond in tabs, with a side-by-side split. <kbd>⌘⌥C</kbd> swaps in the combat tracker, and the pages stay loaded.',
  },
  {
    pos: 'Stage right',
    name: 'Notes',
    text: 'Markdown per campaign, one note per session. Cues in your notes start scenes.',
  },
];

export const sides = [
  {
    side: 'A',
    label: 'Sound',
    tracks: [
      ['Layered scenes', 'Stack stems at their own volume. They loop until you say stop.'],
      ['Smooth crossfades', 'Equal-power fades, so the room never dips between scenes.'],
      ['Sporadic layers', 'A crow, a creak, a distant bell, at random gaps you set.'],
      ['Effects on top', 'Door slams, dice, dragon roars. Several takes each, so repeats don’t sound canned.'],
      ['Ducking', 'An effect can lower the ambience while it plays, then bring it back.'],
      ['Templates', '13 scenes and 67 effects to start from. DMC downloads the files for you.'],
    ],
  },
  {
    side: 'B',
    label: 'The table',
    tracks: [
      ['Combat tracker', 'Initiative that sorts itself. Type <code>-7</code> or <code>+5</code> for HP. Death saves, timed conditions, lair actions, undo.'],
      ['Monster lookup', 'Find a monster on Open5e and fill in its HP, AC and initiative bonus.'],
      ['Prepared encounters', 'Line up the night’s fights, each with the scene that starts with it.'],
      ['Notes that cue', 'Write <code>[[scene:Tavern]]</code> and it becomes a button.'],
      ['A log that writes itself', 'Scenes, rounds and knockouts land in today’s note, with the time.'],
      ['Hotkeys and macropads', '<kbd>⌘K</kbd> for everything. 32 global hotkeys for any pad that sends F13–F20.'],
      ['Your files', 'Plain JSON, Markdown and audio in <code>~/DMConsole</code>. Autosave, rolling backups, no account.'],
    ],
  },
] as const;

// Gallery order. A shot whose file is missing is skipped.
export const shots = [
  { file: 'scene-editor', caption: 'Scene editor: layers, levels, random gaps' },
  { file: 'combat', caption: 'Combat tracker, round 3' },
  { file: 'notes', caption: 'Notes in reading mode, with cues and the log' },
  { file: 'tabletop', caption: 'The Tabletop Audio browser' },
  { file: 'palette', caption: 'The command palette, ⌘K' },
  { file: 'pad-mapper', caption: 'Macropad & Hotkeys' },
];

export const sounds = [
  { name: 'Tabletop Audio', url: 'https://tabletopaudio.com', what: '500+ ten-minute ambiences', licence: 'CC BY-NC-ND 4.0', how: 'In the app · ⌘⇧L' },
  { name: 'Turbo Bard', url: 'https://turbobard.com', what: 'Layered packs, loops and one-shots', licence: 'Per file, from its source libraries', how: 'Scene templates' },
  { name: 'Sonniss GDC bundles', url: 'https://sonniss.com/gameaudiogdc', what: 'Gigabytes of game sound effects', licence: 'Royalty-free', how: 'Download yourself' },
  { name: 'Freesound', url: 'https://freesound.org', what: 'Community sound effects', licence: 'CC0, CC BY or CC BY-NC, per sound', how: 'Download yourself' },
  { name: 'FreePD', url: 'https://freepd.com', what: 'Music', licence: 'Public domain', how: 'Download yourself' },
  { name: 'Incompetech', url: 'https://incompetech.com', what: 'Music by Kevin MacLeod', licence: 'CC BY 4.0', how: 'Download yourself' },
];

export const faq = [
  ['Is DMC free?', 'Yes. It’s MIT-licensed, with no account, no ads and no tracking.'],
  ['Will it run on an Intel Mac?', 'No. DMC needs Apple Silicon (M1 or newer) and macOS 15 Sequoia or later.'],
  ['Do I need D&amp;D Beyond?', 'No. The browser opens any site, and the combat tracker is made for tables that play in person.'],
  ['Why can’t I sign in with Google?', 'Google blocks its sign-in inside apps’ built-in browsers. Sign in to D&amp;D Beyond with your Wizards account email and password.'],
  ['Where does my data live?', 'In <code>~/DMConsole</code> on your Mac, as plain files. Back it up like any folder.'],
  ['Does it work offline?', 'Sounds, notes and combat do. D&amp;D Beyond and monster lookup need a connection.'],
];
