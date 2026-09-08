# Adrian Ingram

Adrian Ingram is a real-time AI facilitation system for EOS/Traction strategic planning sessions. A facilitator-facing control console listens to a live session, uses an LLM to surface Rocks, Roadblocks, 1-Year Boulders, To-Dos, Pebbles, and Long Term Parking items in real time, and pushes a synced board out to an audience-facing display for the room to watch.

## How it's built

Both apps are single-file, no-build static HTML — no npm, no bundler, no backend server. Everything (HTML, CSS, JS) lives inline in one file per view, plus a small shared config file for credentials. Opening the HTML file in a browser is the entire "deployment."

- `adrian-facilitator-v15.html` — the control console. Runs speech-to-text on the facilitator's laptop, calls the LLM, manages the board state, and pushes updates out.
- `adrian-audience-v14.html` — the read-only display shown to the room (e.g., on a TV or projector via a second browser tab/window). Polls for board updates and renders them.
- `config.js` — local-only file holding the Supabase URL/key (see Credentials & Security below). **Not committed.**
- `config.example.js` — committed template showing the shape of `config.js` with placeholder values.

## Resource inventory

| Resource | Provider | Role | Notes |
|---|---|---|---|
| Database / real-time sync | **Supabase** (Postgres + REST API) | Single-row state store (`ai_sessions` table, `main-session` row) that the facilitator writes to and the audience view polls every 1.5s | Accessed directly via Supabase's REST endpoint (`/rest/v1/...`) with an anon key — no Supabase client library, just `fetch()` |
| LLM / AI reasoning | **Anthropic Claude API** (`claude-sonnet-4-6`) | Classifies live transcript into EOS categories, generates facilitation insights, answers ad hoc questions ("Ask Adrian") | Called directly from the browser (`anthropic-dangerous-direct-browser-access` header) — no backend proxy. API key is entered by the facilitator into a password field at runtime and lives only in page memory; it is never written to disk, localStorage, or committed to the repo |
| Speech-to-text | **Web Speech API** (`SpeechRecognition` / `webkitSpeechRecognition`) | Continuous live transcription of the room | Browser-native (Chrome/Edge), no external API key or service — the audio never leaves the browser except as text sent to Claude |
| Web server / hosting | *(none required)* | Both files can be opened directly as local files, hosted on any static host (GitHub Pages, Netlify, S3, etc.), or served from a laptop for the room's display | No server-side code exists; "hosting" is just serving two static HTML files |
| Fonts | **Google Fonts** (CDN) | Roboto typeface | Loaded via `<link>` to `fonts.googleapis.com` |
| Browser storage | *(none)* | — | The app intentionally avoids localStorage/sessionStorage; all state lives in memory and in the Supabase row |

## Credentials & security

**This repository is public.** The following was done to keep secrets out of it:

- The Supabase project URL and anon key have been moved out of both HTML files and into `config.js`, which is listed in `.gitignore` and will never be committed. `config.example.js` is committed in its place as a template — copy it to `config.js` and fill in real values to run the app.
- Older file versions (`adrian-*-v12.html`, `v13.html`, `v14 (facilitator).html`) still have the Supabase key hardcoded inline from before this change and have been added to `.gitignore` so they don't get pushed. Delete them locally once you've confirmed you don't need them.
- The Anthropic API key is never stored in a file at all — it's typed into the facilitator console each session and kept only in browser memory.
- The Supabase key in use is the **anon/public key**, which is designed by Supabase to be exposed in client-side code — the actual security boundary is Row Level Security (RLS) policies on the `ai_sessions` table, not secrecy of the key. **Before relying on this being public-safe, confirm RLS is enabled and locked down** on that table (e.g., restrict writes, or at minimum ensure nothing sensitive is stored there beyond session board state). If RLS is not configured, anyone with this key — including anyone browsing this public repo — can read and write session data directly.

## Client data

`CLIENT_PROFILES` (leadership names, active strategic themes, ICPs, internal terminology for each client) has been moved out of `adrian-facilitator-v15.html` into `clients.js`, which is gitignored just like `config.js`. `clients.example.js` is committed as the template. The client dropdown in the facilitator now builds its list dynamically from whatever is in `clients.js`, so no client name appears in the committed HTML either.

The "hard hat" animation's logo badge (in `orb-hat`, `aud-hat`, `sb-hat`) follows the same pattern: the real path data lives in `cef-logo.js`, gitignored just like `config.js`/`clients.js`, loaded at runtime via `<script src="cef-logo.js">`. `cef-logo.example.js` is the committed template. Without a local `cef-logo.js`, the badge renders a generic placeholder circle instead — the committed, public HTML never contains any client-specific logo/trademark asset.

## Running it

1. Copy `config.example.js` to `config.js` and fill in your Supabase project URL and anon key.
2. Copy `clients.example.js` to `clients.js` and add a profile for each client you'll facilitate for.
3. Double-click `start-adrian.bat` (see below) rather than opening the HTML files directly — it launches the facilitator console in your browser via `http://localhost`. Requires nothing beyond what Windows already has.
4. Open `adrian-audience-v14.html` from that same `http://localhost:...` address in a second window/tab, cast or project it for the room — not by opening the file directly.
5. Enter a Claude API key in the facilitator console before starting a session — it's not saved anywhere, so you'll re-enter it each time you reload the page. Without a key entered, Adrian will not classify anything or suggest captures — this is expected, not a bug.

### Why `start-adrian.bat` instead of just opening the HTML files

Opening either HTML file directly (`file://...`) mostly works, but the live-mic path doesn't: Chrome's continuous speech recognition auto-restarts roughly every 60 seconds, and on a `file://` origin Chrome doesn't reliably remember the microphone permission across those restarts — so it re-prompts for mic access repeatedly through a session, which is disruptive mid-facilitation.

`start-adrian.bat` runs `serve-adrian.ps1`, a small local static file server built entirely from what ships with Windows (PowerShell's `HttpListener` — no Node, Python, or any install required), and opens the facilitator console at a real `http://localhost` address instead. Chrome treats `localhost` as a secure origin and keeps the mic permission properly, so the repeated prompt goes away. Close the console window it opens to stop serving. This matters most when the app is being run from a synced/downloaded local copy (e.g. from SharePoint) on a machine that isn't a dev environment — the same `config.js`/`clients.js`/`cef-logo.js` files described above still need to be sitting alongside the HTML files either way, since they're gitignored and won't come from a plain `git clone` or a copy of just the tracked repo files.
