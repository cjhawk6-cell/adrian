# Adrian Ingram v16 — Feature Roadmap

Planning doc for the next round of Adrian features. Scope decisions already made:
- Build real Supabase tables — the current single-row "overwrite in place" pattern can't support history, carryover, or testing.
- 5-minute auto-summaries run on a client-side timer (only while the facilitator tab is open and a session is live) — no server-side cron needed.
- "AI-training support" is scoped to summarizing topics and surfacing discussion ideas. Adrian actually leading/speaking parts of the session is out of scope for now.

## Why order matters here

Almost every item on the original list — carryover, quote capture, testing, AI training support — depends on two things that don't exist yet: a real database (instead of one row that gets overwritten) and the concept of a "segment" (instead of one flat session). Building those two things first means every feature after them is additive, not a rebuild. Building them last would mean re-touching every feature twice.

## Current architecture, in brief

Both apps are single-file static HTML with no backend. Supabase holds exactly one row (`ai_sessions`, id `main-session`); the facilitator overwrites a JSONB column on every change, and the audience view polls that same row every 1.5s and re-renders. Nothing is stored once a session ends except a client-side text export. Transcript, items, and thoughts all live in browser memory and vanish on refresh.

That model is fine for "mirror the board live." It can't answer "what were last quarter's incomplete rocks" or "replay Tuesday's session through the new prompt" because that data was never saved anywhere durable.

---

## Phase 0 — Real data model (foundation)

Nothing else on this list works without this. Replace the single overwritten row with real tables, while keeping the fast live-sync polling the audience view already relies on.

**New Supabase tables:**

- `sessions` — id, `client_key` (matches the existing `clients.js` keys — no need to duplicate client data into the DB), name, quarter (e.g. `2026-Q3`), started_at, ended_at
- `segments` — id, session_id, agenda_item_label, segment_type (`rocks` / `issues` / `people` / `custom`...), started_at, ended_at
- `transcript_chunks` — id, session_id, segment_id (nullable), text, created_at — this is what makes "recent audio" queries and replay testing possible; today that text only exists in a JS variable
- `items` — id, session_id, segment_id, category (rock/roadblock/boulder/todo/pebble/parking), text, quarter, status (`open`/`complete`/`incomplete`/`carried_over`), created_at, resolved_at — this becomes the real source of truth instead of the in-memory `items` object
- `quotes` — id, session_id, segment_id, text, created_at
- `summaries` — id, session_id, segment_id (nullable), type (`rolling_5min`/`segment_end`/`session`/`adhoc`), text, created_at
- `agendas` — id, client_key, name, items (JSONB list of labels/types) — reusable per client so you're not retyping an agenda every quarter

**Live sync stays cheap:** the audience view keeps polling on an interval, but instead of one JSONB blob it queries the real tables filtered by `session_id` and an `updated_at` cursor. Latency stays the same; the data underneath just stops disappearing.

This phase is pure plumbing — no new UI. Everything after it plugs in.

## Phase 1 — Agenda-mirrored buckets + segment controls

These two are really one feature: you can't have "start/end segment" without something to start and end. Build them together.

- Facilitator picks or builds an agenda for the session (reusing a saved one from `agendas` if the client has run before, or typing a fresh one). **Done 2026-09-03** — the Agenda tab now saves/loads named templates per client to/from the `agendas` table.
- Board buckets on both facilitator and audience switch from the fixed 6 EOS categories to the agenda's segments — each segment can still be tagged with an EOS category underneath (a "Rocks Review" segment still produces `rock`-type items), but the visible structure now mirrors the actual meeting flow instead of a fixed grid. **Deferred 2026-09-03 by decision** — this is a real visual change to a tool already run live in front of clients, so it's being held as its own dedicated pass rather than bundled in here. The board keeps the fixed 6 columns for now; items are still tagged with `segType`/`segLabel` under the hood.
- Facilitator gets Start/End buttons per segment. Starting a segment writes a `segments` row with `started_at`; ending it sets `ended_at`. The currently active segment is what everything downstream (summaries, quote capture, Ask Adrian's "recent audio") scopes itself to. **Done.**

**Note on Phase 0 (2026-09-03):** the audience view stays on the `ai_sessions` JSONB blob as its live-sync feed permanently — this was a deliberate choice, not a temporary step, since that path is proven and already tested live. The `sessions`/`segments`/`items`/`item_mentions`/`transcript_chunks` tables remain the durable history record for carryover, replay, and testing (Phases 6–7), populated by dual-write alongside the live sync, not by replacing it.

## Phase 2 — Pause / Resume transcription

A clean, independent win — ship it any time, doesn't block on anything above. Adds a third state alongside the existing Start/Stop: "paused" keeps the session live (timer keeps running, segment stays open) but stops feeding the mic into the AI pipeline, versus Stop which ends the session entirely. Mostly a state-machine addition to the existing `startListening`/`stopListening` functions.

**Done 2026-09-03** — a Pause/Resume button now sits between Start and Stop. `pauseListening()` tears down whichever mic path is active (Deepgram socket/recorder or the Web Speech recognizer) without calling `stopTimer()`, `dbEndSession()`, or touching `activeSegmentIndex`/`agenda`, so the elapsed timer and the active segment both keep running. `resumeListening()` just calls the existing `startListening()` dispatcher again — same mic-path detection as a fresh Start, but without resetting speaker calibration or creating a new `sessions` row. Verified with a headless Playwright run against the state variables directly (elapsed time keeps advancing while paused, `isListening` flips off/on correctly, Stop still fully resets state).

## Phase 3 — Summarization engine + 5-minute auto-summaries

Build one reusable function: "summarize transcript chunks in this time/segment window." Wire it to a client-side 5-minute timer while a session is live, writing rows into `summaries`. This is the same function Phase 5 (segment-end consolidation) and Phase 8 (AI training support) will both call again later — building it once here avoids writing three slightly-different summarization prompts.

**Done 2026-09-03** — `summarizeText(text, label)` is the reusable engine: a plain-text-in, plain-text-out call to Claude with its own narrative-summary system prompt, deliberately kept separate from `callAI()`'s EOS classification JSON pipeline. `summaryBuffer` accumulates finalized transcript continuously (alongside, but independent of, the classification `transcriptBuffer`); a `setInterval` wired into Start/Stop calls `runRollingSummary()` every 5 minutes, which skips silently if fewer than 30 words came in that window, otherwise summarizes, writes a `rolling_5min` row via `dbInsertSummary()` (tagged to the active segment if one is running), and surfaces the result in the facilitator's existing Thoughts panel plus a toast. Verified with a headless Playwright run against mocked Claude/Supabase responses: short buffers are skipped, long ones produce a summary, write the DB row, and reset the buffer; the timer starts on Start and clears on Stop.

## Phase 4 — Ask Adrian: recent-audio observations

Adds a one-click option to the existing "Ask Adrian" overlay ("What's happening right now?") that runs the Phase 3 summarization function against the current segment's transcript instead of requiring a typed question. The free-text "ask your own question" mode you already have stays as-is.

## Phase 5 — Rocks / Roadmap segment consolidation

This is the biggest single feature on the list, and it's where quote capture lives:

- Extend the live classification pipeline (the one already turning transcript into Rocks/Roadblocks/etc.) to also pull out notable verbatim quotes into the new `quotes` table, tagged to the active segment.
- When a segment ends, if it's tagged as a "rocks" segment, auto-generate a consolidated view: run the Phase 3 summarizer over everything captured in that segment (items + quotes) into a clean, proposed rocks list rather than a raw item dump.
- Add a manual browse view — scroll everything captured (items, quotes, summaries) for the current segment or the whole session, not just what's currently pinned to the audience board.

**Related:** if voice-aware speaker attribution (see `adrian-voice-aware.md`) gets built, this is where it plugs in — quotes and rocks carry a real speaker label instead of being anonymous.

## Phase 6 — Previous-quarter rocks carryover

Needs the `items` table with `quarter` and `status` from Phase 0, and needs at least one full quarter to have gone through Phase 5 so there's real data to carry forward. At session start (once a client + quarter are selected), query last quarter's `items` where `category='rock'`:

- Incomplete ones get offered as carryover — one click to re-add them into this quarter's board.
- Complete ones get surfaced as a quick "here's what got done" review, useful for opening the meeting.

## Phase 7 — Testing harness (replay past transcripts + agendas)

A "test mode" toggle that feeds a saved transcript into the same pipeline a live mic would, on a simulated timer, using a saved agenda from Phase 0's `agendas` table. This is what lets you validate a new prompt or a new feature against a real past session before running it live in front of a client. Sequenced after the features it needs to test — there's limited value building a replay harness before there's a real segment/summary/rocks pipeline to replay against, though old raw transcript exports from v13/v14 sessions could seed the first tests.

## Phase 8 — AI-training support for CE Floyd

The most product-specific layer, sitting on everything below it:

- **Summarize topics** — reuse the Phase 3 engine against a full past session instead of a live window, for leadership prep/review.
- **Surface ideas to discuss** — using the agenda, this quarter's carried-over rocks (Phase 6), and the active themes already in `clients.js`, have Claude proactively suggest discussion questions or topics before or during a segment.

(Explicitly out of scope for now: Adrian narrating or leading segments via voice.)

## Phase 9 — Sentiment & talk-time + agenda-email intake

Added outside the original sequencing (requested directly, like Phase 2 an independent slot-in) — a facilitator-side read on the room, plus a faster way to set up a session than typing out attendees and agenda by hand.

- **Talk-time breakdown** — per-speaker cumulative speaking duration, shown as a % bar per name. Requires Deepgram diarization to be active (Web Speech has no concept of "who"); tracked from Deepgram's per-word `start`/`end` timestamps, summed per speaker-turn. Keyed by raw speaker index internally (like `dgSpeakerNames`) so a mid-session rename in Speaker Calibration doesn't lose history.
- **Current sentiment** — a 1-2 sentence plain-text read on tone/energy, refreshed on the same 5-minute cadence as the Phase 3 rolling summary (same transcript window, a separate Claude call — kept out of `summarizeText()` so that function's plain-summary contract stays reusable for Phase 5/8). Persisted to a new `sentiment_readings` table alongside a snapshot of talk-time at that moment.
- **Facilitator-controlled audience sharing** — generalized the existing "Show on Audience Display" chip mechanism (previously just the 6 EOS categories) rather than building a one-off toggle: a `sentiment` chip was added to the same row, and the audience view gates a new bottom-left panel on `audienceVisible.has('sentiment')`. Any future facilitator-side panel can follow the same one-line pattern — add a chip, gate the corresponding audience element.
- **Agenda-email intake** — a paste-only textarea in the Agenda tab (no file upload: this app has no backend, so there's no reliable way to parse a real Outlook `.msg` or MIME `.eml` file in-browser; pasting the email body gets Claude the same information). Claude extracts `{attendees, agenda}` as JSON; the agenda replaces the current draft agenda (same shape `addAgendaItem`/`loadDefaultAgenda` already use), and attendee names populate a `<datalist>` of suggestions on the Speaker Calibration inputs — still free text, just faster to fill in correctly.

---

## Suggested build order at a glance

1. Real Supabase schema (Phase 0)
2. Agenda buckets + segment start/end (Phase 1)
3. Pause/resume (Phase 2 — can slot in anytime, it's independent)
4. Summarization engine + 5-min auto-summaries (Phase 3)
5. Ask Adrian recent-audio mode (Phase 4)
6. Rocks/Roadmap segment consolidation + quote capture (Phase 5)
7. Previous-quarter carryover (Phase 6)
8. Transcript replay/testing harness (Phase 7)
9. AI-training support: summaries + discussion ideas (Phase 8)
10. Sentiment & talk-time + agenda-email intake (Phase 9 — independent, built out of order)

Open question worth deciding before Phase 0 starts: do you want `agendas` and historical `items`/`rocks` scoped per client (so CE Floyd's agenda template and rock history stay separate from a future second client), or is everything still single-client for now with multi-client structure added later? The schema above assumes multi-client from day one since it's a small amount of extra design work now versus a migration later.
