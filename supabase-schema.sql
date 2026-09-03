-- Adrian Ingram — Phase 0 schema
-- Run this once in the Supabase SQL Editor (Project → SQL Editor → New query → paste → Run).
-- Safe to re-run: every statement is idempotent (IF NOT EXISTS / OR REPLACE).
--
-- What this does: replaces "one row that gets overwritten forever" with real,
-- queryable history. The existing `ai_sessions` table and its live-sync
-- behavior are untouched — the audience view keeps working exactly as it
-- does today. These new tables run alongside it, durably storing everything
-- so it survives a refresh and can be queried later (carryover, testing,
-- segment review, etc. from later roadmap phases).

create extension if not exists pgcrypto;

-- One row per facilitated session (a single client meeting/planning day).
create table if not exists sessions (
  id uuid primary key default gen_random_uuid(),
  client_key text,              -- matches the keys used in clients.js, e.g. 'cef'
  name text,
  quarter text,                 -- e.g. '2026-Q3'
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

-- Reusable agenda templates per client (Phase 1 will build the UI for these).
create table if not exists agendas (
  id uuid primary key default gen_random_uuid(),
  client_key text,
  name text not null,
  items jsonb not null default '[]',  -- [{ "label": "Rocks Review", "segment_type": "rocks" }, ...]
  created_at timestamptz not null default now()
);

-- A named block of time within a session, tied to an agenda item (Phase 1).
create table if not exists segments (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  agenda_item_label text,
  segment_type text,            -- 'rocks' | 'issues' | 'people' | 'custom' ...
  sort_order int,
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

-- Durable transcript, chunked as it's captured. Also what future replay/testing
-- (Phase 7) and "recent audio" queries (Phase 4) will read from.
create table if not exists transcript_chunks (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  segment_id uuid references segments(id) on delete set null,
  speaker text,                 -- nullable until voice-aware ships
  text text not null,
  created_at timestamptz not null default now()
);

-- The actual Rocks/Roadblocks/Boulders/To-Dos/Pebbles/Long-Term items —
-- now a real row per item instead of a JSON blob that gets overwritten.
create table if not exists items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  segment_id uuid references segments(id) on delete set null,
  client_key text,
  category text not null check (category in ('rock','roadblock','boulder','todo','pebble','parking')),
  text text not null,
  quarter text,
  status text not null default 'open' check (status in ('open','complete','incomplete','carried_over')),
  num int,                      -- keeps the existing "#1, #2..." per-category numbering
  speaker text,                 -- nullable — populated once voice-aware/Deepgram is active
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
alter table items add column if not exists speaker text;

-- Every time the same underlying point gets raised again after an item
-- already exists (whether that's one person repeating themselves or a
-- different person independently echoing it), it's logged here instead of
-- creating a second competing item. "speaker" is nullable until voice-aware
-- ships — once it's populated, the same rows here can distinguish true
-- duplicates (same speaker) from corroboration across multiple people
-- (different speakers) without any schema change.
create table if not exists item_mentions (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items(id) on delete cascade,
  session_id uuid not null references sessions(id) on delete cascade,
  speaker text,
  text text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_item_mentions_item on item_mentions(item_id);

-- Notable verbatim quotes captured during a segment (Phase 5).
create table if not exists quotes (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  segment_id uuid references segments(id) on delete set null,
  speaker text,
  text text not null,
  created_at timestamptz not null default now()
);

-- Rolling 5-min, segment-end, and ad hoc AI summaries (Phase 3+).
create table if not exists summaries (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  segment_id uuid references segments(id) on delete set null,
  type text not null check (type in ('rolling_5min','segment_end','session','adhoc')),
  text text not null,
  created_at timestamptz not null default now()
);

-- Indexes for the query patterns the app will actually run.
create index if not exists idx_segments_session on segments(session_id);
create index if not exists idx_transcript_chunks_session on transcript_chunks(session_id, created_at);
create index if not exists idx_items_session on items(session_id, created_at);
create index if not exists idx_items_client_quarter_category on items(client_key, quarter, category);
create index if not exists idx_quotes_session on quotes(session_id, created_at);
create index if not exists idx_summaries_session on summaries(session_id, created_at);

-- Row Level Security: the app talks to Supabase directly from the browser
-- using only the anon key (same model as the existing ai_sessions table
-- today). These policies grant the anon role full read/write, matching
-- current exposure — NOT a new security regression, but worth knowing:
-- anyone holding the anon key can now read/write real historical session
-- content (transcripts, quotes, client names), not just live board state.
-- Consider tightening this later (e.g., Supabase Auth for the facilitator,
-- read-only scoped access for the audience view) once real client data is
-- flowing through it regularly.
alter table sessions enable row level security;
alter table agendas enable row level security;
alter table segments enable row level security;
alter table transcript_chunks enable row level security;
alter table items enable row level security;
alter table item_mentions enable row level security;
alter table quotes enable row level security;
alter table summaries enable row level security;

drop policy if exists "anon full access" on sessions;
create policy "anon full access" on sessions for all to anon using (true) with check (true);

drop policy if exists "anon full access" on agendas;
create policy "anon full access" on agendas for all to anon using (true) with check (true);

drop policy if exists "anon full access" on segments;
create policy "anon full access" on segments for all to anon using (true) with check (true);

drop policy if exists "anon full access" on transcript_chunks;
create policy "anon full access" on transcript_chunks for all to anon using (true) with check (true);

drop policy if exists "anon full access" on items;
create policy "anon full access" on items for all to anon using (true) with check (true);

drop policy if exists "anon full access" on item_mentions;
create policy "anon full access" on item_mentions for all to anon using (true) with check (true);

drop policy if exists "anon full access" on quotes;
create policy "anon full access" on quotes for all to anon using (true) with check (true);

drop policy if exists "anon full access" on summaries;
create policy "anon full access" on summaries for all to anon using (true) with check (true);
