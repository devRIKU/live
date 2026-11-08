# OpenAll Consolidated Spec v1.0

**One document. One source of truth.** This merges the Prototype Spec, the Research Service Spec, and the four improvement reviews (ChatGPT, Kimi, Gemini, Spec Review) into a single consistent specification. Where the originals disagreed, the decision is stated here once, with the reasoning kept to one line. This file supersedes all earlier versions.

**Guiding principle:** Glue, don't build — but make every boundary explicit. A prototype may have mocks and known limitations; it must not hide them or weaken security to look complete.

---

## 0. How to read this (for the coding agent)

1. **Glue, don't build.** If an open-source library does the thing, install and wire it. Write only the thin connecting layer.
2. **Verify before installing.** Each package must exist, have a recent release, and be maintained. Record what you tested (see §12.2).
3. **Stop at each milestone.** Run the "done when" check, report in the format in §12.5, then wait.
4. **Stub, don't sink.** More than about half a day or a missing GPU → mock behind the same interface and move on.
5. **Line budgets are scope warnings, not laws.** Security and correctness override a line count. If a feature overruns, explain why and name the smallest alternative.
6. **Ask once, early.** One short question at milestone start, not five mid-build.
7. **No polish.** Default styles, light/dark themes only.

---

## 1. What we're building

A single-user, local-first desktop app (Windows now, Android later as a thin client) that puts the main features of ChatGPT, Claude, and Meta Muse in one place using open-source parts:

- Streaming chat with a model switcher
- Canvas / artifacts (live preview of code and documents)
- Generative UI (model replies with real interactive components)
- MCP connectors and Skills (the plugin system)
- Deep research (separate 512 MB cloud service)
- Code agent (OpenCode in a terminal pane)
- Voice v1 (push-to-talk), full-duplex later
- Muse-style always-on agent, later

Honest scope: the prototype is one compiled shell. Heavy features (research, voice v2, personal agent) run as **separate services** reached by URL. A single-binary bundle is a later step.

**Users and hardware:** one builder (student), no accounts. Dev laptop: i3 10th gen, 12 GB RAM, no strong GPU. Develop as a web app first; wrap in the desktop shell later. No local big models — models come from free-tier APIs; small Ollama model for offline tests only.

---

## 2. Resolved decisions (these were the contradictions)

The original docs disagreed on the following. These decisions are final:

| # | Question | Decision | Why |
|---|---|---|---|
| D1 | Agent loop: forbidden (main spec) or required (research spec)? | The general app **must not** implement its own planner, agent runtime, or orchestration framework. The research service is the **one permitted exception**: a bounded, deterministic pipeline (see §8). No autonomous tool discovery, browser automation, recursive planning, or unbounded self-reflection. | Gemini's "deterministic linear pipeline" framing resolves the ChatGPT/GPT-Researcher fork without breaking the glue rule. |
| D2 | Primary cloud host: Blitz.cloud or Render? | Try **Blitz.cloud first** (no card, EU, 512 MB, sleeps after ~30 min idle, public amd64 image), **Render as fallback** (512 MB, sleeps ~15 min, confirm no card at signup). Same image for both, so switching is config. Verify current free-tier terms *before* committing; record the host and verification date in `docs/RESEARCH_HOSTING.md`. If neither works card-free, stop and report — never silently add a paid dependency. | Blitz's longer idle window and explicit ordering; Render unverified. |
| D3 | Memory test timing: "before any UI" vs Milestone 7? | **Early spike first:** container + health endpoint + one research job, no UI, at the start of the research milestone — and the full acceptance gate (§8.7) must pass **before** any research UI is built. | The test exists to prevent UI rework; running it late defeats it. |
| D4 | Search provider: unnamed | **Tavily Search API** primary (cardless signup, ~1,000 free queries/month — verify current terms; check whether direct page fetches violate their ToS). Fallback: `duckduckgo-search` (`ddgs`) library (no key, no account). | The no-card constraint and RAM budget both ride on this dependency. |
| D5 | Embeddings: remote API or skip? | **Skip embeddings in v0.** Retrieval is top-N search results ranked by the search provider. No local embeddings, no remote embedding API, no vector DB. | Smallest footprint, no extra provider, acceptable for a 5-source prototype. |
| D6 | "Mobile apps" hard-no vs Android milestone | §13 forbids **native store apps** (iOS/Android app-store builds), browser extensions, and cloud sync — **not** the Tauri Android target in M10. | One-line qualifier; keeps the platform plan intact. |
| D7 | Storage by runtime | Web/PWA phase: **IndexedDB** behind a `StorageAdapter`. Tauri desktop phase: add a **SQLite adapter** if the chosen Tauri plugin supports it. Include a tested export/import path; never promise automatic migration between isolated browser and desktop origins. Never store provider keys in conversation data or ordinary settings. If a storage adapter fails to init, show a clear error — never pretend data was saved. | Don't call native SQLite plugins from a browser-only Vite app. |
| D8 | Secrets by runtime | **Local web dev:** local backend/proxy reading secrets from env vars or a local secret store — never in Vite variables that ship in the public bundle. **Compiled Windows app:** OS-keychain integration; route provider requests through a native command where practical so keys stay out of app JavaScript. **PWA / remote web:** never a shared provider key in client code — use an authenticated HTTPS host, or clearly label a session-only user-entered key option as less protected. Never keys in prompts, chat history, logs, crash messages, exports, source control, or telemetry. Redact authorization headers and secret-bearing query params from logs and errors. | A browser cannot keep a key secret from its own devtools. |

---

## 3. Tech choices (use these, don't debate them)

| Layer | Choice | Why |
|---|---|---|
| App shell | Tauri v2 (Windows first, Android target later). Not Electron | Small compiled app; Electron has no Android target |
| UI framework | React + TypeScript + Vite | Everything supports it |
| Styling | Lively design system (`design-system/`) — tokens, motion, shell, surfaces | One palette with two themes, one shell definition shared by the app and the mockups |
| Chat UI | assistant-ui | Ready-made streaming chat primitives |
| Generative UI | OpenUI (`@openuidev/react-lang`, `@openuidev/react-ui`) | Model streams real components |
| Model access | One OpenAI-compatible endpoint (base URL + key). Short **ordered provider list** (not a router). Ollama only for offline tests | Model switching via dropdown |
| Streaming / tools glue | Vercel AI SDK (or plain OpenAI-compatible client if it gets in the way) | Handles streaming and tool calls |
| MCP | Official MCP TypeScript SDK (client) | Open standard |
| Skills | Agent Skills format (`SKILL.md` folders, agentskills.io) | Only a loader needed |
| Code editor | Monaco or CodeMirror | Never write an editor |
| Terminal pane | xterm.js | For the code agent |
| Markdown / code render | react-markdown + shadcn/assistant-ui defaults | Don't write a renderer |
| Local storage | IndexedDB (web phase) → SQLite via Tauri plugin (desktop phase), both behind `StorageAdapter` | Platform-correct |
| Secrets | OS keychain (desktop); env vars via local proxy (dev); never in the repo | See D8 |

Confirm assistant-ui, Vercel AI SDK, OpenUI, Tauri plugins, and MCP SDK versions are mutually compatible before implementation.

---

## 4. Architecture

```
[ Desktop shell (Tauri) ]
   └── React app
        ├── Chat (assistant-ui)  ──► ModelProvider (OpenAI-compatible URL)
        ├── Canvas panel (sandboxed iframe + Monaco)
        ├── GenUI renderer (OpenUI)
        ├── Tool layer ──► MCP client ──► any MCP server
        │              └─► Skills loader (reads SKILL.md folders)
        ├── Memory (SQLite table of facts, user-controlled)
        └── Adapters (all optional, all by URL, mock first):
              ├── ResearchProvider  → research service (§8)
              ├── CodeAgentProvider → OpenCode in a terminal pane
              ├── VoiceProvider     → push-to-talk now, full-duplex service later
              └── AgentProvider     → Hermes or OpenClaw, later
```

**Adapter rule:** every heavy feature is a small interface (`start`, `stream`, `stop`) with a **mock implementation first**. The UI never depends on a service's internals — it goes through the adapter.

**Model-name rule:** never hardcode a model name in application logic; model names live only in the runtime-refreshed provider list.

---

## 5. Providers, failover, and rate limits

**Provider capability records.** Each provider/model entry stores: `baseUrl`, `model`, a secret *reference* (never the value), `supportsStreaming`, `supportsTools`, `supportsStructuredOutput`, known context limit, and local state (`ready` / `rate_limited` / `unavailable` / `not_configured`). Keep the initial list short; no sophisticated router in v0.

**Ordered list (decided):** OpenRouter (`:free` model IDs, 2–3 fallbacks because free models rotate — Space Bunny is also listed there as `stealth/space-bunny-alpha`, verify at runtime), then Groq, Google AI Studio (Gemini), Mistral free plan. Zen free models (Space Bunny, Beam, Nemotron 3.5, DeepSeek 4.1 Flash) work great **inside OpenCode itself** (M7 code agent) but return 403 when called from outside the OpenCode client — never put them in the chat panel's provider list. Route deep research to the provider with the largest daily allowance, not OpenRouter.

**Failover rules:**
- Fail over only for errors safe to retry (connection failure before the request was accepted, a clearly returned rate-limit response).
- Never blindly retry if the provider may already have completed a tool action or side effect.
- Bounded retries: **max 1 retry per call**, per-call HTTP timeout **~30 s**. Never retry in a loop. Surface the final error.
- Show which provider/model actually answered; explain when a fallback was used.
- Support a setting to **disable cross-provider failover** (prompts may otherwise go to another company).
- If a fallback lacks a required capability, say it's incompatible — don't silently change behavior.

**Rate limits:**
- Free-tier limits change often; verify current numbers before relying on them. Historically: OpenRouter free ~20 req/min, 50/day; Groq ~30 req/min, 14,400/day. Never hardcode these as guarantees.
- Track local request attempts and reset times; treat the provider's returned rate-limit response as authoritative. Never claim a local counter is the provider's exact account-wide usage — label it clearly as local.
- When all providers are exhausted, return a clear "out of quota" status with a friendly message; never crash or auto-retry in a loop.
- **Privacy on free tiers:** some free tiers may use prompts for product improvement. Never send passwords, API keys, or private personal files through a free provider; keep memory to non-sensitive facts.

**Provider verification:** before adopting a model/provider, verify endpoint compatibility, package maintenance, license, free-tier requirements, tool-call and streaming behavior, and rate limits. Record the tested configuration.

---

## 6. Milestones (build in this order)

Each milestone is independently testable. Keep mocks behind the adapter interfaces until real services exist. Suggested durations are pacing signals, not deadlines.

**M1. Chat and provider adapter** (~1 day). Web UI, streaming chat, markdown/code rendering, model selector, provider capability records, bounded failover. *Done when:* two configured models respond; provider errors are legible; the UI shows the actual provider; retries are bounded.

**M2. Browser persistence** (~0.5 day). `StorageAdapter` on IndexedDB; credentials excluded from stored conversations. *Done when:* history survives refresh; storage failures show clearly; export/import or migration is documented.

**M3. Artifacts** (~1 day). Artifact recognition, Preview/Code tabs, format validation, sandboxed preview (§7.1). *Done when:* a generated tip calculator works in isolation; an invalid artifact falls back to text; the preview cannot reach parent storage or keys.

**M4. Generative UI** (~1 day). Small component registry, structured protocol, schema validation, resource limits (§7.2). *Done when:* comparison data renders a real table; invalid output falls back safely; oversized output is rejected.

**M5. Tauri desktop shell** (~1 day). Wrap the stable web app; OS-keychain secrets and SQLite storage if supported and tested. *Done when:* a Windows build runs core chat, history, and artifacts; keys are not in plaintext settings; storage behavior is documented.

**M6. Remote tools, Skills, and memory.** Remote HTTP MCP, safe Skills loader, inspectable memory controls (§9). Local stdio MCP stays disabled until native process handling exists. *Done when:* a remote test tool works through the approval dialog; a skill loads by metadata and can't bypass approval; a saved fact can be viewed, edited, deleted, and recalled.

**M7. Local MCP and code agent.** Local stdio MCP plus launching/managing the code agent through the native integration, each behind an adapter with its own smoke test. *Done when:* a local tool works only within its configured scope; the code agent runs in an approved test folder; the user can stop the process and inspect errors.

**M8. Research service benchmark, then UI integration.** Deploy and benchmark the research service **independently** (§8.7); only after passing the acceptance gate, connect its job states and validated report to the app. Includes an early feasibility spike: container + health endpoint + one research job, before the app UI wraps it. *Done when:* the host meets the measured resource requirement; a job produces validated citations; timeout, partial, interruption, and unavailable-service states display correctly.

**M9. Voice v1** (~1 day). Push-to-talk input and spoken output behind `VoiceProvider`; full-duplex stays a stub. *Done when:* a real push-to-talk exchange works; unavailable speech services fail cleanly.

**M10. Android thin client.** Verify every dependency and Tauri plugin for Android support first. Local-process features route through a secured HTTPS host or are marked unavailable. *Done when:* a real Android device chats, shows artifacts, and calls the secured research service; desktop-only features are clearly identified.

Free early test: M1–M5 are a normal web app, so install the PWA on the phone to try the mobile layout before any Android build. Build for touch from day one (responsive Tailwind; canvas opens full-screen on small screens).

**Later (not in this prototype):** full-duplex voice, Muse-style agent tab, single-installer bundling, "always allow" tool mode.

---

## 7. Artifacts and generative UI

### 7.1 Artifact sandbox

- Only render artifacts matching an explicitly supported format; arbitrary code in an answer is never auto-executed. Invalid/unsupported artifacts display as text.
- Preview lives in a sandboxed iframe with `sandbox="allow-scripts"` **only** — never `allow-same-origin`. Popups, forms, top-level navigation, and external script loading blocked by default. Restrictive CSP; for offline artifacts use `connect-src 'none'` unless a documented requirement justifies an exception.
- Artifacts must not access application storage, provider keys, chat history, native commands, or parent-window APIs. Validate size and format before rendering.

### 7.2 Generative UI protocol

Generative UI is **structured data**, not model-written React code. The format is **OpenUI Lang 1.0** — a line-oriented language the model writes and the app parses:

```text
root = Stack([card])
card = Card("Plans", [table])
table = Table(["Plan", "Price"], [["Basic", "$5"], ["Pro", "$12"]])
```

1. The model emits an OpenUI Lang program: one `identifier = Expression` statement per line, with a `root = ...` entry statement.
2. The app parses it against the **component library**, which *is* the allowlist: only components defined in `src/genui/library.ts` (card, table, chart, form, steps, text, button, stack) render. Anything else is dropped with an `unknown-component` error.
3. The library's schemas carry the resource bounds (max table rows 50, chart points 100, form fields 20, children 10, text 4000 characters, nesting depth 3). Output over a bound is trimmed and reported; a program over 64 KB is rejected outright.
4. Invalid or unsupported output falls back to readable text with a non-fatal error.
5. Forms and interactive components validate values before any tool or network action fires.
6. A component never acts on its own: it emits a structured action event, and the host decides what happens (a follow-up becomes the next chat turn; a link is opened only when its scheme is http(s)).

Ordinary answers stay prose. A message may mix both: text outside a ```` ```openui-lang ```` fence is rendered as markdown, the program inside it as an interface.

No arbitrary imports or executable scripts through generative UI.

---

## 8. Research service

A deep-research service that runs in under 512 MB RAM, as one Docker container, using remote model APIs only, with no payment card anywhere in the chain.

### 8.1 Execution model

A **deterministic sequential pipeline** — the one permitted exception (D1) to the no-agent-loop rule, kept small (~300–500 lines) and bounded. Fixed four-step sequence:

1. **Search** — query the search endpoint for top candidate URLs (Tavily; `ddgs` fallback, see D4).
2. **Extract** — fetch raw text from retrieved URLs with SSRF controls (§8.5).
3. **Map (Summarize)** — targeted summarization per source.
4. **Reduce (Synthesize)** — compile summaries into the final cited report.

Keep it behind the `ResearchProvider` adapter so the UI never depends on internals. A third-party research framework may be considered only if it passes the same memory, reliability, and citation tests without disallowed infrastructure.

**Banned inside the container:** local embeddings, vector databases, headless browsers/Chromium/Playwright, full SearXNG stacks, browser automation. **Runtime:** `python:3.11-slim`; HTML extraction via `trafilatura` (or `readability-lxml` with stream parsing) — not BeautifulSoup with full lxml trees.

### 8.2 API surface

| Endpoint | Behavior |
|---|---|
| `GET /health` | `{"status": "ok"}` — no secrets or environment details leaked |
| `POST /research` | Validated question in, job ID out promptly (`202`, `{"job_id": "<uuid v4>"}`) |
| `GET /research/{id}` | State, progress, partial output when available, final report when complete |

- **Authentication (required):** the client sends a shared secret token in a header; the service rejects requests without it. Token lives in an environment variable, never in the repo. HTTPS in deployment. Restrict CORS to the app's expected origin — CORS is not authentication.
- Validate request size and question length before starting model work. `POST` payload: `{"query": "string (required)", "max_sources": "integer (optional, default 5, max 5)"}`.
- Predictable error responses for: malformed requests, unauthorized, unknown job IDs, rate limits, timeouts, host-level failures.
- **One active job at a time** — this is a lock, not a queue (queues are banned). While a job runs, `POST /research` returns `429` (or `409`/`503`) with a `Retry-After: 60` header.
- Client polls `GET /research/{id}` every 2 seconds.

### 8.3 Job states

`queued` (only if a queue exists — it doesn't in v0), `running`, `completed`, `partial`, `failed`, `timed_out`, `interrupted`.

- Persist progress and finished source summaries **incrementally to disk** (SQLite or the JSON job file) as they complete — a crash must keep partial output, and a restart must not reset the daily request counter.
- An interrupted or restarted job must never be presented as completed.
- Delete finished job records after **24 h**; storage must not grow forever.
- If the host's filesystem is ephemeral, document honestly that in-flight jobs and reports may vanish after restart/redeploy; the UI must communicate this accurately. Never claim durable storage without a durable mechanism.

### 8.4 Resource limits (enforced in code, not in prompts)

- Max **5 sources** per run; max **4,000 cleaned characters** per source into summarization. A "source" is one successfully fetched URL; "cleaned" means main-content text after tags, scripts, and navigation are removed, measured before truncation.
- Max **25 model calls per run** — counting *every* model request including the planning call and final report call; the per-source cap of **3 model calls** applies only to summarization.
- Max **5 minutes** per run; the timer starts when the container accepts the job (excluding provider cold-start). Per-stage budgets: plan ≤ 20 s, search ≤ 15 s, fetch+clean ≤ 20 s per source, model calls ≤ 40 s per source; on breach, emit the partial report and stop. Explicit per-request timeouts for search, fetch, and model calls (~30 s per HTTP call).
- Max **2 MB raw response** before HTML parsing (separate from the cleaned-text cap); bounded redirect count; bounded final report length.
- Check local call budgets and the daily request counter **before each model call**; stop cleanly when out of quota.
- **Fallback gate:** if the first resource test exceeds limits, reduce to 3 sources and a 2,000-character cap and retest. If it still fails, report actual metrics and stop — never move to paid hosting.

### 8.5 Safe URL fetching (SSRF protections)

All destinations are untrusted:

- Only `http`/`https` schemes.
- Reject localhost, loopback, link-local, private, reserved, and cloud-metadata IP ranges (IPv4 **and** IPv6). Resolve hostnames and validate resolved addresses before connecting; revalidate each redirect hop to defeat DNS-rebinding and redirect bypasses. Block non-public IPs even when a public hostname resolves to one.
- Cap redirect count, response size, connection time, total fetch time, and accepted content types.
- No JavaScript execution, no browser binaries, no automatic page resources. HTML → plain text via the lightweight parser; treat extracted content as **untrusted source material, not instructions**.
- Never forward internal service tokens or model-provider credentials to source websites.
- Check the search provider's ToS before direct page fetches; some free APIs ban them.

### 8.6 Citations and report integrity

- Each source record: stable source ID, page title when available, canonical URL, retrieval timestamp, and the cleaned text the model saw.
- The model must cite source IDs from the retrieved list; **validate citations before returning** — remove or flag unknown IDs; never fabricate titles, URLs, quotations, or retrieval status. Render verified citations as clickable links.
- **Pass requires:** at least one citation per report section, every citation links to a source actually fetched, and the report names the number of sources used.
- Clearly separate source-supported claims from analysis and assumptions; preserve meaningful disagreements between sources. Too few useful sources → a clearly labelled **partial report**, not implied broad coverage. Never describe the 5-source pipeline as guaranteed comprehensive deep research — it is lightweight cited research with explicit coverage limits.

### 8.7 Memory benchmark and acceptance gate

Run **before building UI around the service**. Record: peak container memory, total runtime, model-call count, sources fetched and cited, citation validation result, one cold-start run on the selected host, behavior after one source failure + one model timeout + one rate limit, and what happens to an active job and completed report after a host restart or redeploy.

**Pass only if:** peak under **450 MB** on the defined benchmark (normal and worst-case cases — a single happy-path run is insufficient), a representative job completes, and citations validate. Record the numbers in project notes.

### 8.8 Cold-start / wake-up flow

1. Client sends `GET /health` before starting a research run.
2. If the container is sleeping, the client shows "Waking up research node…".
3. The client dispatches `POST /research` only after `200` from `/health`.

---

## 9. MCP, Skills, memory, and code agent

### 9.1 MCP and consequential actions

- In v0, **user approval before every MCP tool call** and every consequential code-agent action. No always-allow mode. The approval dialog shows the exact tool name, arguments, target resource, and a concise description of the intended effect.
- Reject calls outside configured filesystem/command scopes. Treat tool output as untrusted data — it must not alter approval rules or grant itself permissions.
- **Remote HTTP MCP** may work during the web phase; **local stdio MCP** requires the native host and moves to the desktop phase. Never start local MCP servers from the browser.

### 9.2 Skills

- Every `SKILL.md` and referenced file is untrusted instruction, especially third-party content. Skills describe behavior but cannot override safety rules, permission checks, or approval requirements, and cannot add executable code, trusted tools, or permissions.
- Load metadata first; full text only when relevant.

### 9.3 Memory controls

Simple SQLite-backed (or browser-storage equivalent) fact store, with user control: view, edit, delete individual facts, clear all. **Approve explicit memory writes in v0** rather than auto-storing model-suggested facts. Exclude credentials and sensitive personal data. Keep saved memory clearly separate from conversation history.

### 9.4 Code-agent terminal

`xterm.js` is a terminal UI, not a process supervisor — the app must separately launch and manage the code-agent process through the native integration. Never launch OpenCode or shell processes from the browser-only phase. Scope the working directory to a user-approved project folder; show commands and consequential file operations before execution in v0; stop processes reliably with exit codes and errors surfaced. If process integration isn't ready, use the adapter mock — never a decorative terminal that implies commands are running.

Code agent: OpenCode with its free Zen models, read at runtime, never hardcoded — but Zen models are not trusted for the chat panel.

---

## 10. Safety basics (non-negotiable)

- Artifact iframe: `allow-scripts` only, no parent access (§7.1).
- Server-side fetches follow the SSRF policy (§8.5).
- Every tool call needs approval in v0 (§9.1).
- Keys: env var in dev, OS keychain in the compiled app, env-var token for the research service — never in the repo, bundles, logs, or chat history (D8).
- Redact secrets from all errors and logs (tested, §12.1).
- Check each model's and library's license before anyone shares or sells the app; some open models use custom licenses.

---

## 11. Platform notes

- **Windows now:** Tauri v2 + WebView2 (already on Windows, no bundled Chromium).
- **Android later (M10):** same React code via Tauri's Android target. Android Studio + NDK are heavy on 12 GB RAM — do it last. Thin client: command-line MCP servers, the OpenCode terminal, and local Ollama won't work on a phone; route them through an HTTPS host or mark `desktopOnly`.
- Browser code never calls native APIs before the native shell exists; unsupported Android features are explicit in the UI.

---

## 12. Testing, reporting, and dependencies

### 12.1 Minimum focused tests (no blanket test ban, no coverage chase)

- URL validation, redirect checks, private-network blocking in research fetches.
- Research resource limits, deadline handling, job-state transitions, citation validation.
- Provider capability checks, retry limits, fallback behavior.
- Artifact format validation and sandbox configuration.
- Generative UI schema validation and output-size limits.
- MCP approval enforcement and configured tool scopes.
- Secret redaction in logs and errors.
- Storage persistence, migration, and failure behavior.

One smoke test per milestone stays required. No large test framework, no arbitrary coverage percentages.

### 12.2 Dependency verification record

For each major dependency record: package + version, last release / maintenance status checked, license and restrictions, required runtime/native dependencies, the exact feature tested in a minimal example, and any replacement considered and why chosen/rejected. Never swap a failed dependency for a vaguely similar package without reporting it.

### 12.3 Feature budgets

| Feature | Use (don't write) | Custom code | Budget |
|---|---|---|---|
| Chat + history | assistant-ui, StorageAdapter | Save/load conversations | ~200 |
| Model switcher | OpenAI-compatible endpoint | Settings form | ~100 |
| Canvas / artifacts | Sandboxed iframe, Monaco | Artifact detect + panel + tabs | ~250 |
| Generative UI | OpenUI | Registry + prompt + render | ~200 |
| MCP connectors | Official MCP SDK | Config, connect list, approval dialog | ~250 |
| Skills | Agent Skills spec | Scanner + loader | ~150 |
| Plugins | Nothing extra (MCP + Skills are the plugin system) | none | 0 |
| Memory | SQLite / IndexedDB | Table + remember/recall tools + controls | ~120 |
| Deep research (app side) | Research service (§8) | HTTP call, progress, report in canvas | ~150 |
| Deep research (service) | Own bounded pipeline | Search→extract→map→reduce + API | ~300–500 |
| Code agent | OpenCode | Terminal pane + process management | ~100 |
| Voice v1 | Browser speech / Whisper + Kokoro/Piper | Push-to-talk + playback | ~150 |
| Voice v2 | NVIDIA PersonaPlex / VoiceChat on rented GPU | `VoiceProvider` WebSocket streaming — **stub in prototype** | ~200 later |
| Muse-style agent | Hermes / OpenClaw on a cheap VPS | Chat tab via API | ~100 later |

App-side total target for M1–M7: **under ~2,000 lines** excluding shadcn-generated components; the service's 300–500 lines live in the separate container and are accounted separately. Overruns: explain why, name the smallest alternative, never stop midway through security behavior for a line count.

### 12.4 Graceful failure is part of completion

Every milestone handles its expected failures: missing API keys, provider unavailability, rate limits, malformed model output, failed storage init, denied tool approvals, cold starts, research timeouts, unsupported platform features. No endless spinners; no silently discarded output.

### 12.5 Milestone report format (5 lines + 2 optional)

1. What works.
2. What was stubbed.
3. Custom lines written vs budget, with justified overruns.
4. Any package that appeared unmaintained or incompatible.
5. Test result and any security/reliability issue found.
6. *(If relevant)* Dependency changes from §12.2.
7. *(Only if blocked)* One question.

Report actual test results. Never claim a test passed that wasn't run.

---

## 13. Do NOT build (hard no list)

- Login, accounts, multi-user, billing, teams
- A custom model, fine-tuning, or training anything
- An agent loop, planner, or orchestration framework in the **app** — the research service's bounded pipeline (§8.1) is the sole exception
- A vector database, local embeddings, or a RAG pipeline (file-upload Q&A is out for v0)
- A markdown renderer, code editor, terminal, or chart library
- A plugin marketplace, plugin SDK, or app store
- A sandbox beyond the sandboxed iframe
- Native store apps (iOS/Android app-store builds), browser extensions, cloud sync — the Tauri Android target (M10) is explicitly **not** included in this ban
- Durable distributed queues or multiple research workers
- PDF/image/upload support in the research service in v0
- Full-duplex voice, an always-on personal agent, cloud sync in v0
- Analytics, telemetry, crash reporting
- Fancy animations, onboarding tours, theming beyond light/dark, accessibility audits, translations
- CI/CD, auto-update, code signing
- **Any paid service or anything requiring a payment card**

---

## 14. Acceptance criteria (prototype handoff)

| Area | Passes when |
|---|---|
| Secrets | No keys in frontend bundles, repo files, chat history, artifacts, or logs |
| Providers | Bounded retries; active provider visible; failover can be disabled |
| Storage | History survives refresh; desktop storage and migration documented and tested |
| Artifacts | Previews can't reach app secrets or parent storage; unsupported artifacts never execute |
| Generative UI | Only allowlisted components render from schema-validated data |
| MCP & Skills | Tool calls require approval; tools stay in scope; skills can't change permissions |
| Memory | Facts viewable, editable, individually deletable, clearable |
| Research | Memory under target (measured); citations validated; unsafe URLs blocked; honest failure states |
| Hosting | One host order across the project, selected against verified no-card + memory + persistence requirements |
| Platform | No native calls before the native shell exists; Android gaps explicit |
| Reliability | Smoke tests + focused critical tests pass; failure states exercised, not assumed |

---

## 15. Repo layout

```
openall/
  src/
    app/            # pages and layout
    chat/           # assistant-ui setup
    canvas/         # artifact panel
    genui/          # OpenUI component registry
    tools/          # mcp.ts, skills.ts, memory.ts
    adapters/       # research.ts, codeagent.ts, voice.ts, agent.ts (+ mocks)
    db/             # StorageAdapter implementations
  skills/           # SKILL.md folders
  mcp.config.json   # list of MCP servers
  src-tauri/        # added at M5
  docs/SPEC.md      # this file
  docs/RESEARCH_HOSTING.md  # selected host + verification date
```
