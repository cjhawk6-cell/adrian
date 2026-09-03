// Adrian Ingram — client context template
//
// 1. Copy this file to "clients.js" in the same folder.
// 2. Add a profile per client, keyed by a short client code.
// 3. clients.js is listed in .gitignore and will NEVER be committed —
//    this is where real client names, leadership, and strategy notes live.

window.CLIENT_PROFILES = {
  acme: {
    name: 'Acme Corp',
    shortName: 'ACME',
    industry: 'Industry description',
    location: 'City, State',
    size: '~N team members',
    leadership: 'Name (Title), Name (Title)',
    icps: 'Ideal client profile segments',
    flywheel: 'Step → Step → Step → Step',
    activeThemes: [
      'Current strategic focus #1',
      'Current strategic focus #2',
    ],
    terminology: 'Client-specific acronyms and jargon, comma separated',
    toneGuidance: 'Notes on how Adrian should sound and what to emphasize for this client.',
  },
};
