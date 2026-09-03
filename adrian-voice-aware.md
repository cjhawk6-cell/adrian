# Adrian Ingram — Voice Awareness (Speaker Diarization)

Scoped down from "voice aware" to the specific capability confirmed: Adrian should tell voices apart and attribute what's said to the right person — "Chris said X," not "someone said X" — feeding directly into the quotes and rocks features in the main roadmap (`adrian-v16-roadmap.md`, Phase 5).

**Short answer: yes, this is well-established technology and achievable. The catch isn't feasibility, it's that it requires the first real architecture change Adrian has needed — a small backend component — because the free browser API currently doing transcription has no concept of "who."**

## Why this doesn't bolt onto the current setup

Adrian's speech-to-text today is the browser's built-in Web Speech API (`webkitSpeechRecognition`) — free, zero setup, and it works well, but it only ever returns one plain text stream. It has no idea if one person or five people are talking. There's no setting to turn on to fix this; diarization has to come from a different transcription engine entirely, one that processes the raw audio and returns speaker-labeled text (`Speaker 1: ...`, `Speaker 2: ...`).

That means swapping the transcription layer, not extending it. The rest of the pipeline downstream — buffering transcript, calling Claude to classify it into Rocks/Roadblocks/etc, generating summaries — barely changes; it just starts receiving speaker labels alongside the text.

## The part that actually changes the architecture

Diarization-capable providers (Deepgram, AssemblyAI, Azure, Google, AWS) all require an API key, and none of them are designed to have that key sitting in public static HTML the way Anthropic's browser-access flag allows for Claude. Two ways to handle it, both requiring a small server-side piece for the first time in this project:

1. **Token-minting function** — a tiny serverless function (a Supabase Edge Function fits naturally since Supabase is already in the stack) that hands the browser a short-lived, scoped key on session start. The browser then streams audio straight to the provider using that temporary key. Deepgram explicitly supports this pattern.
2. **Full proxy** — a backend relays every audio chunk between the browser and the provider, never exposing a key to the browser at all. More secure, more moving parts.

Option 1 is the lighter lift and keeps Adrian close to its current "as little backend as possible" philosophy — one small function instead of a real server.

## Provider comparison (checked live, August 2026)

| Provider | Real-time diarization | Rough cost | Notes |
|---|---|---|---|
| **Deepgram** (Nova-3) | Yes, streaming, no hard cap on speaker count | ~$1.31/hr | Best price-to-performance for this use case; WebSocket streaming built for exactly this; supports the scoped-token pattern above |
| **AssemblyAI** (Universal-3.5) | Yes, streaming, sub-second latency | ~$0.57/hr ($0.45 base + $0.12 diarization) | Strong accuracy, built for live voice apps |
| **Azure Speech** (Conversation Transcription) | Yes, purpose-built for meetings | Enterprise pricing | The only option with built-in *named* speaker enrollment as a first-party feature; "middle of the road" on raw accuracy but most complete meeting-specific tooling |
| **Google / AWS** | Yes, streaming | Comparable | Reasonable if you're already in that cloud ecosystem; no particular edge for this use case |

Recommendation: **Deepgram** for the best cost/quality balance, unless the named cross-session voice enrollment described below is a priority from day one, in which case Azure's purpose-built meeting transcription is worth a closer look.

## What this actually costs

Checked live pricing as of August 2026:

| Provider | Streaming rate | Diarization add-on | All-in, roughly |
|---|---|---|---|
| **Deepgram Nova-3** | ~$0.005–0.008/min (~$0.29–0.46/hr) | ~$0.001–0.002/min extra | **~$0.35–0.55/hr** |
| **AssemblyAI** | $0.15/hr (Universal Streaming) to $0.45/hr (Universal-3.5 Pro Realtime) | ~$0.02–0.12/hr depending on tier | **~$0.17–0.57/hr** |

Both bill per second, so you only pay for actual session time. Translated into what a real session costs: even a full 8-hour quarterly planning day runs somewhere around **$3.50–$4.50** in transcription costs on Deepgram (Nova-3 streaming ~$0.0077/min + diarization ~$0.0015/min ≈ $0.0092/min × 480 min), and similarly cheap on AssemblyAI. A typical 2-hour session is well under a dollar. This is not a meaningful cost driver either way — for context, Adrian's existing Claude API calls during a live session (classification every ~18 seconds plus periodic summaries) are likely a larger share of the per-session bill than the transcription layer would be. Pick the provider on accuracy, latency, and how it fits the architecture, not on price.

Practically: Deepgram's Pay As You Go tier (no card required, $200 free credit, no minimums/expiration) is the right fit here, not their Growth plan ($4K+/year prepaid, aimed at much higher-volume concurrent usage). At ~$4/session, the free credit alone covers roughly 45–55 full 8-hour sessions before any real spend.

## Could we just use a model built for audio instead of a dedicated transcription vendor?

Worth asking, and the honest answer is: partially, and it's genuinely worth evaluating — but it doesn't remove the backend requirement, and it doesn't replace what Claude is doing for Adrian.

Two audio-native options that showed up as real, current contenders (checked August 2026):

- **Google's Gemini transcribe line** (`gemini-3.5-transcribe` for batch, `gemini-3.5-transcribe-live` for real-time streaming) — this is purpose-built for exactly this: native speaker diarization plus a real-time, low-latency streaming variant over WebSockets. It's not "ask a chat model to guess who's talking" — it's a dedicated transcription model with diarization as a first-class feature, same category as Deepgram/AssemblyAI rather than a workaround. Worth a serious look, especially since Gemini is already one of the tools in regular use at Autobahn.
- **OpenAI's `gpt-4o-transcribe-diarize`** — a dedicated ASR model (not the general chat model) with built-in diarization, priced around $0.006/min (~$0.36/hr) based on published token rates. It's less clear from public docs whether this specific variant supports true real-time streaming or is closer to file-based/batch transcription — that's worth confirming directly against OpenAI's docs before relying on it for a live session, since batch-only would mean transcribing after the fact rather than during the meeting.

Two things that stay true no matter which of these you pick:

1. **The backend requirement doesn't go away.** Whether it's Deepgram, AssemblyAI, or Gemini's transcribe API, the API key still can't sit in public static HTML the way Claude's does. Same small token-minting function either way.
2. **This replaces the ears, not the brain.** Whichever transcription provider is used still hands off to Claude for the actual EOS classification, quote extraction, and facilitation reasoning that makes Adrian useful. Gemini's transcribe model is excellent at "who said what," but it isn't doing the job Claude is doing today in turning that into Rocks, Roadblocks, and insights — swapping the transcription layer doesn't mean swapping what makes Adrian, Adrian.

Given Gemini is already in regular rotation at Autobahn, it's worth a real side-by-side test against Deepgram before committing — cost is close enough between all of these that it shouldn't be the deciding factor; diarization accuracy in an actual conference room, with real overlapping speech, is what will actually separate them.

## Recommendation

**Build the live pipeline on Deepgram.** It's the most purpose-built, proven option for exactly this scenario — real-time streaming diarization with no hard speaker cap, a decade of being the go-to ASR layer behind meeting-transcription products, and it natively supports the scoped-token pattern that solves the backend security question with the least extra engineering. Gemini's transcribe-live is genuinely interesting and worth keeping on the radar, but it's a newer product in this specific category (live, multi-speaker, real-room diarization with cross-talk) — I'd rather pilot it cheaply against a real recorded session before trusting it in front of a paying client, not use it as the first build. AssemblyAI is a fine fallback if Deepgram underperforms in testing, but nothing in the research suggests it's a better starting bet.

**Don't use OpenAI's `gpt-4o-transcribe-diarize` for the live pipeline** — the unconfirmed real-time streaming support is disqualifying for a feature that needs to work during the meeting, not after it. It's a good fit elsewhere, though: Phase 7's testing harness (replaying past transcripts) is exactly the kind of batch, after-the-fact use case where it could shine, or as a second-opinion reprocessing pass on a recorded session to sanity-check Deepgram's output.

**Before writing any integration code**, the cheapest way to de-risk this is to record one real past CE Floyd session (or use an old one if one exists) and run it through Deepgram and Gemini's transcribe-live side by side, since that tells you more about real-room diarization accuracy than any spec sheet will. That test doubles as an early input into Phase 7's replay/testing harness from the main roadmap.

## Two tiers of "who's who" — and a privacy line between them

**Tier 1 — session-only, unsupervised (recommended starting point).** The provider clusters voices into "Speaker 1 / Speaker 2 / Speaker 3" based on how they sound, with no identity attached. At the start of a session, Adrian runs a 30-second calibration: each person says a sentence, and the facilitator maps "Speaker 2" → "Mark" for that session only. Nothing about anyone's voice is stored between sessions. Low complexity, low privacy exposure, ships fast.

**Tier 2 — persistent voice enrollment across sessions.** The provider (most cleanly Azure, which supports this natively) remembers "this is Chris Floyd's voice" quarter over quarter, so Adrian recognizes him automatically without recalibrating every time. This is a meaningfully bigger step: it means storing biometric voice data tied to a named person. A handful of states (Illinois' BIPA being the strictest example) specifically regulate stored voiceprints as biometric identifiers, requiring informed consent and a retention/deletion policy. This isn't a reason to avoid it, but it is a reason to loop in whoever handles Autobahn's client agreements and data policy before enrolling anyone's voice permanently — this is a legal/consent decision, not just an engineering one.

Given that, the sequencing that makes sense: ship Tier 1 first, see how much value speaker attribution actually adds in real sessions, and only invest in Tier 2's consent/legal groundwork if Tier 1 proves the value.

## One thing software can't fix: the room

Diarization accuracy depends heavily on audio quality. A single laptop mic in a conference room with several people talking, overlapping, and sitting at different distances will produce noticeably worse speaker separation than a proper setup. Worth budgeting for a decent USB conference mic (something like a Jabra Speak or similar omnidirectional conference mic) rather than expecting laptop-mic-quality diarization — this is a hardware/room-setup line item, not something a better model fixes.

## How it plugs into the existing roadmap

Directly extends Phase 5 (Rocks/Roadmap segment consolidation) from `adrian-v16-roadmap.md`:

- Add a `speaker` column to the `transcript_chunks` and `quotes` tables from Phase 0.
- The classification/summarization prompts sent to Claude include speaker labels inline (`Speaker 2: We really need to fix estimating`), so quotes and rocks can carry real attribution instead of being anonymous.
- Small bonus this unlocks later, not required now: participation-balance insights ("Chris spoke 60% of this segment") — genuinely useful for a facilitator, worth keeping in mind but not part of the initial build.

## Suggested sequencing

1. Pick a provider (Deepgram or Gemini's transcribe-live worth a head-to-head test; AssemblyAI a close alternative) and stand up the token-minting function.
2. Swap the transcription layer from Web Speech API to the provider's streaming API, carrying speaker labels through to the existing transcript pipeline.
3. Build the session-start calibration step (Tier 1 — map detected speakers to names for that session).
4. Extend Phase 0's schema (`transcript_chunks`, `quotes`) with a `speaker` field and update the classification/summarization prompts to use it.
5. Revisit Tier 2 (persistent voice enrollment) only after Tier 1 has been used in real sessions and only after a privacy/consent review.

This slots in naturally around Phase 5 of the main roadmap — building it right before or alongside quote capture makes sense, since attributed quotes are most of the value here.

Sources:
- [Best Speech-to-Text APIs in 2026: A Comprehensive Comparison Guide](https://deepgram.com/learn/best-speech-to-text-apis-2026)
- [Deepgram Nova-3 Pricing 2026](https://convertaudiototext.com/blog/deepgram-nova-3-explained)
- [Top APIs and models for real-time speech recognition and transcription in 2026](https://www.assemblyai.com/blog/best-api-models-for-real-time-speech-recognition-and-transcription)
- [8 Best Speaker Diarization Solutions & APIs in 2026](https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis)
- [AssemblyAI Billing and Pricing FAQ](https://assemblyai.com/docs/faq/how-does-pricing-work)
- [Speaker Diarization | Deepgram's Docs](https://developers.deepgram.com/docs/diarization)
- [Browser Live Transcription - Protecting Your API Key - Deepgram Blog](https://deepgram.com/learn/protecting-api-key)
- [Gemini 3.5 Transcribe | Gemini API | Google AI for Developers](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe)
- [Audio understanding | Gemini API | Google AI for Developers](https://ai.google.dev/gemini-api/docs/audio)
- [GPT-4o Transcribe Diarize pricing & specs — OpenAI | CloudPrice](https://cloudprice.net/models/openai-gpt-4o-transcribe-diarize)
