# OpenAll Prototype Implementation Plan

**Target System:** OpenAll Local-First AI Workstation  
**Derived from:** `docs/SPEC.md` (OpenAll Consolidated Spec v1.0)  
**Developer Profile:** Single student builder, no accounts, cardless free tiers only  
**Target Hardware:** Windows dev laptop (i3 10th gen, 12 GB RAM, no dedicated GPU), later Android thin client  
**Architecture Paradigm:** Web-first (React + Vite + Tailwind + shadcn) wrapped into Tauri v2 desktop shell with separate cloud microservices.

---

## 1. Executive Summary & Core Rules

### 1.1 Guiding Principles
1. **Glue, don't build:** Wire battle-tested open-source libraries (`assistant-ui`, `@openuidev`, `@modelcontextprotocol/sdk`, `@xterm/xterm`, `trafilatura`). Only write thin connecting glue.
2. **Verify before installing:** Every dependency must be actively maintained and verified for license and node/browser compatibility before adoption.
3. **Stub, don't sink:** If an external system takes >0.5 day or requires heavy GPU, mock it behind a clean interface (`start`, `stream`, `stop`) and proceed.
4. **Milestone stop-and-verify:** Stop at each milestone, run the acceptance check, format the report (§12.5), and verify safety.
5. **Strict line budgets:** Target total custom app code for M1–M7 is under ~2,000 lines (excluding generated UI components). The research container budget is ~300–500 lines.
6. **No premature polish:** System default styles, light/dark themes only, zero custom animation frameworks.

### 1.2 Decision Matrix (D1–D8 Alignment)
* **D1 (Agent Loop):** No general agent loop or planner in the main app. The Research Service is the sole exception: a deterministic, bounded 4-step pipeline (Search → Extract → Map → Reduce).
* **D2 (Research Hosting):** Deploy on Blitz.cloud (cardless EU free tier, 512 MB RAM, ~30 min idle sleep), fallback to Render (cardless free tier, 512 MB, ~15 min sleep).
* **D3 (Memory Spike):** Deploy and benchmark the standalone containerized research service **before** any research frontend UI is built.
* **D4 (Search API):** Tavily Search API primary (cardless free tier ~1,000 queries/month). Fallback: `duckduckgo-search` (`ddgs`) with zero credentials.
* **D5 (Embeddings):** Zero embeddings, zero vector databases, zero RAG pipelines in v0. Top-N search results only.
* **D6 (Mobile Scope):** No native mobile store releases (App Store / Play Store) or cloud sync. Tauri Android thin-client target in M10 is permitted.
* **D7 (Storage Strategy):** Web/PWA phase uses `IndexedDB` behind `StorageAdapter`. Tauri desktop phase adds SQLite via `@tauri-apps/plugin-sql`. Clear error on init failure; manual JSON export/import.
* **D8 (Secrets Isolation):** Dev phase uses a local Vite API proxy (`/api/llm`) reading `.env`; compiled desktop uses OS Keychain (Windows Credential Manager). Never expose API keys to client JavaScript bundles, logs, or exports.

---

## 2. System Architecture & Dependency Graph

```
                                 +-------------------------------------------------------+
                                 |               OpenAll Shell (Tauri v2)               |
                                 |  +-------------------------------------------------+  |
                                 |  |              React 18/19 Web App                |  |
                                 |  |                                                 |  |
                                 |  |  [ Chat Panel ]         [ Canvas Panel ]        |  |
                                 |  |  - assistant-ui         - Sandboxed Iframe      |  |
                                 |  |  - Provider Failover    - Monaco / CodeMirror   |  |
                                 |  |  - OpenUI (GenUI)       - Verified Citations    |  |
                                 |  +--------+------------------------+---------------+  |
                                 |           |                        |                  |
                                 |  +--------v------------------------v---------------+  |
                                 |  |                 Core Layer                      |  |
                                 |  |  - StorageAdapter (IndexedDB / SQLite)          |  |
                                 |  |  - SecretsManager (Dev Proxy / OS Keychain)     |  |
                                 |  |  - Fact Store Memory (User-Approved Facts)      |  |
                                 |  +--------+------------------------+---------------+  |
                                 |           |                        |                  |
                                 |  +--------v-----------+   +--------v---------------+  |
                                 |  |   Tool / MCP Hub   |   |   Adapter Interfaces   |  |
                                 |  |  - User Approval   |   |  - ResearchProvider    |  |
                                 |  |  - Skills Loader   |   |  - CodeAgentProvider   |  |
                                 |  |  - HTTP MCP Client |   |  - VoiceProvider (v1)  |  |
                                 |  |  - Local stdio MCP |   |  - AgentProvider (stub)|  |
                                 |  +--------------------+   +---+--------+-------+---+  |
                                 +-------------------------------|--------|-------|------+
                                                                 |        |       |
                                          +----------------------+        |       +----------------------+
                                          |                               |                              |
                                          v                               v                              v
                           +------------------------------+  +--------------------------+  +---------------------------+
                           |   Research Microservice      |  |   Terminal Pane          |  |   Voice Subsystem         |
                           |   (Docker / 512 MB Cloud)    |  |   (xterm.js)             |  |   - Push-To-Talk Input    |
                           |   - FastAPI + trafilatura    |  |   - OpenCode Process     |  |   - Web Speech / TTS      |
                           |   - SSRF Protection Filter   |  |   - Native Child Process |  |   - Full-Duplex v2 (Stub) |
                           |   - Tavily / ddgs Search     |  |   - Scoped Directory     |  +---------------------------+
                           +------------------------------+  +--------------------------+
```

---

## 3. Dependency Verification Matrix

| Category | Candidate Package | License | Status / Verification Note | Fallback / Alternative |
|---|---|---|---|---|
| **Chat Primitives** | `@assistant-ui/react` | MIT | Active, streaming support, ready-made primitives | Custom wrapper over Vercel AI SDK UI |
| **Model Streaming** | `ai` (Vercel AI SDK) | Apache 2.0 | Standard OpenAI-compatible fetcher & streaming tools | Direct `fetch` with `EventSource` / SSE parser |
| **Generative UI** | `@openuidev/react-lang` | MIT | OpenUI Lang 1.0 parser, renderer, prompt generation and action runtime | Previous hand-rolled JSON component format |
| **Code Editor** | `@monaco-editor/react` | MIT | Battle-tested for Canvas code tab | `@uiw/react-codemirror` (lighter weight) |
| **Terminal Pane** | `@xterm/xterm`, `@xterm/addon-fit` | MIT | Industry standard xterm emulation | Read-only styled pre block |
| **MCP Client** | `@modelcontextprotocol/sdk` | MIT | Official Anthropic MCP TypeScript client | Minimal JSON-RPC 2.0 client |
| **Browser Storage** | `idb-keyval` or native IndexedDB | Apache 2.0 | Zero-dependency, lightweight promise-based IDB | Plain IndexedDB wrapper (~80 lines) |
| **Desktop Shell** | Tauri v2 CLI & Core (`@tauri-apps/cli`) | MIT/Apache 2.0 | Cross-platform, WebView2 on Windows | Run as local PWA |
| **Research Parsing** | `trafilatura` (Python) | GPLv3 / LGPL | Extremely low memory footprint vs BeautifulSoup | `readability-lxml` with stream parser |
| **Search API** | `tavily-python` | MIT | Cardless free tier (1,000 queries) | `duckduckgo-search` (`ddgs`) |

---

## 4. Work Breakdown Structure & Milestones

```
+----------------------------------------------------------------------------------------------------+
|                                    MILESTONE ROADMAP                                               |
+----------------------------------------------------------------------------------------------------+
|  Phase 1: Web Foundation & Chat Core (Browser Phase)                                               |
|  - M1: Project Setup, Proxy & Streaming Chat Adapter                     [Target: ~300 lines]     |
|  - M2: IndexedDB StorageAdapter & History Management                     [Target: ~200 lines]     |
|                                                                                                    |
|  Phase 2: Live Canvas & Generative Interfaces                                                      |
|  - M3: Canvas Artifacts, Monaco Editor & Sandboxed Iframe                [Target: ~250 lines]     |
|  - M4: Generative UI Schema Engine & OpenUI Renderer                      [Target: ~200 lines]     |
|                                                                                                    |
|  Phase 3: Desktop Shell & Tool Ecosystem                                                           |
|  - M5: Tauri v2 Windows Packaging & OS Keychain Secrets                  [Target: ~250 lines]     |
|  - M6: Remote MCP, Skills Loader & Inspectable Memory                    [Target: ~520 lines]     |
|  - M7: Local stdio MCP & OpenCode Terminal Pane                          [Target: ~150 lines]     |
|                                                                                                    |
|  Phase 4: Cloud Services & Multimodal                                                              |
|  - M8: Research Service Spike, Benchmark & App Canvas Integration        [Service: ~400 lines]    |
|  - M9: Voice v1 (Push-To-Talk) & Audio Playback                          [Target: ~150 lines]     |
|  - M10: Tauri Android Thin Client Verification & Touch Layout            [Target: Config/CSS]     |
+----------------------------------------------------------------------------------------------------+
```

---

### Milestone 1: Chat and Provider Adapter (Web Phase)
**Goal:** Deliver a working web chat interface with model switching, bounded failover, and strict credential isolation.  
**Custom Code Budget:** ~300 lines (Chat ~200, Switcher ~100).

#### Tasks:
* **Task 1.1: Project Scaffolding & Tailwind Setup**
  * Initialize Vite + React + TypeScript in `openall/`.
  * Configure Tailwind CSS and add base shadcn/ui primitives (`Button`, `Select`, `Dialog`, `ScrollArea`, `Card`).
  * *Files:* `package.json`, `vite.config.ts`, `tailwind.config.js`, `src/app/App.tsx`.
* **Task 1.2: Dev Secrets API Proxy (`/api/llm`)**
  * Build a lightweight Vite dev server proxy plugin that injects API keys from local `.env` (`OPENROUTER_API_KEY`, `GROQ_API_KEY`, etc.).
  * Ensure secrets are never emitted in client Vite bundles or logged to console.
  * Implement redaction for `Authorization` headers and query params.
  * *Files:* `vite.config.ts`, `src/adapters/proxy.ts`.
* **Task 1.3: Provider Capability Registry & Bounded Failover**
  * Create `ProviderConfig` type: `id`, `name`, `baseUrl`, `model`, `supportsStreaming`, `supportsTools`, `state` (`ready` | `rate_limited` | `unavailable`).
  * Implement ordered provider list: OpenRouter (`:free` models), Groq, Google AI Studio, Mistral.
  * Implement failover executor: max 1 retry per call, 30s timeout, non-retriable on side effects, setting to toggle cross-provider failover.
  * *Files:* `src/chat/providers.ts`, `src/chat/failover.ts`.
* **Task 1.4: assistant-ui Streaming Chat UI**
  * Integrate `@assistant-ui/react` connected to the active provider stream.
  * Render markdown code blocks using `react-markdown` with syntax highlighting.
  * Add top toolbar with model selector dropdown and active provider/model badge.
  * *Files:* `src/chat/ChatContainer.tsx`, `src/chat/ModelSelector.tsx`.
* **Task 1.5: Milestone 1 Verification & Smoke Test**
  * Verify two configured models respond with streaming tokens.
  * Verify timeout (30s) triggers legible error message.
  * Verify switching providers works and failover honors bounded retry limits.

**Done When (Acceptance Criteria):**
1. At least two free-tier models (e.g. OpenRouter free + Groq) stream text smoothly in the UI.
2. The UI explicitly displays which provider and model generated the response.
3. Failed calls fail over once or present a clear, human-readable error (no endless spinners).
4. No API keys appear in client source code or network payloads inspectable in devtools.

---

### Milestone 2: Browser Persistence (Web Phase)
**Goal:** Persist chat conversations and application settings across browser refreshes with zero credential leaks.  
**Custom Code Budget:** ~200 lines.

#### Tasks:
* **Task 2.1: `StorageAdapter` Interface Definition**
  * Define generic async contract: `getThread(id)`, `saveThread(thread)`, `listThreads()`, `deleteThread(id)`, `getSetting(key)`, `setSetting(key, val)`.
  * Ensure methods reject any payload containing secret keys.
  * *Files:* `src/db/storageAdapter.ts`.
* **Task 2.2: IndexedDB Implementation**
  * Implement `IndexedDBStorageAdapter` using native IndexedDB or `idb-keyval`.
  * Include database schema with stores: `threads`, `messages`, `settings`, `facts`.
  * Handle quota errors and initialization failure with user-facing notification.
  * *Files:* `src/db/indexedDbAdapter.ts`.
* **Task 2.3: Conversation Thread Management UI**
  * Add collapsible sidebar listing past conversations with titles, timestamps, and delete action.
  * Automatically persist assistant-ui message changes.
  * *Files:* `src/app/Sidebar.tsx`, `src/chat/threadHooks.ts`.
* **Task 2.4: Export/Import Tooling**
  * Add "Export All Chats (JSON)" and "Import Chats (JSON)" feature in settings.
  * Validate JSON format on import; strip any potential injected credentials or script tags.
  * *Files:* `src/db/exportImport.ts`.
* **Task 2.5: Milestone 2 Verification & Smoke Test**
  * Refresh browser and confirm active chat and thread list persist intact.
  * Simulate IndexedDB failure (private mode quota breach) and confirm user receives an actionable error.

**Done When (Acceptance Criteria):**
1. Chat history survives full page reload and browser restart.
2. User can create new threads, switch threads, and delete threads.
3. Exported JSON contains conversation threads and facts, but zero API keys or credentials.
4. Storage failure triggers a clear banner rather than silently failing to persist.

---

### Milestone 3: Canvas and Artifacts (Web Phase)
**Goal:** Detect code/document artifacts in model replies and display them in a split-screen canvas with Monaco code view and isolated sandboxed preview.  
**Custom Code Budget:** ~250 lines.

#### Tasks:
* **Task 3.1: Artifact Stream Parser & Detector**
  * Implement parser detecting artifact tags (e.g., `:::artifact{id="x" type="html" title="..."}` or standard fenced codeblocks with artifact headers).
  * Extract metadata: `id`, `title`, `type` (`html`, `react`, `svg`, `markdown`), `content`.
  * Validate size limits (reject artifacts > 1 MB).
  * *Files:* `src/canvas/artifactParser.ts`.
* **Task 3.2: Split-Pane Canvas UI**
  * Build responsive two-pane layout: Chat on left (or full on small screens), Canvas panel on right.
  * Canvas panel header: Artifact title, Type indicator, [Preview | Code] tabs, Close button.
  * *Files:* `src/canvas/CanvasPanel.tsx`, `src/canvas/CanvasTabs.tsx`.
* **Task 3.3: Monaco / CodeMirror Code Tab**
  * Embed `@monaco-editor/react` (or `@uiw/react-codemirror`) in read-only/editable mode for viewing artifact source code.
  * *Files:* `src/canvas/CodeEditorView.tsx`.
* **Task 3.4: Sandboxed Iframe Preview Engine**
  * Create `SandboxedIframe` component with `sandbox="allow-scripts"` **only** (never `allow-same-origin`).
  * Inject restrictive Content Security Policy (`default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'`).
  * Ensure preview iframe cannot access parent `window`, `localStorage`, `indexedDB`, or auth headers.
  * Fall back to raw code/text display if artifact format is invalid.
  * *Files:* `src/canvas/SandboxedPreview.tsx`.
* **Task 3.5: Milestone 3 Verification & Smoke Test**
  * Have model generate an interactive HTML/JS tip calculator.
  * Confirm tip calculator functions properly in the Preview tab.
  * Confirm the preview cannot read `window.parent` or parent `indexedDB` (verify security isolation).

**Done When (Acceptance Criteria):**
1. Interactive code artifacts (HTML/JS/SVG) render and function inside the Preview tab.
2. Invalid or unparseable artifacts cleanly fall back to formatted text.
3. Sandboxed iframe runs with `sandbox="allow-scripts"` and cannot reach parent origin, cookies, or storage.
4. Responsive split-pane collapses gracefully on narrow screen widths.

---

### Milestone 4: Generative UI (Web Phase)
**Goal:** Enable models to return structured interactive components (Cards, Tables, Charts, Forms, Steps) validated against strict schemas.  
**Custom Code Budget:** ~200 lines.

**Status: implemented as OpenUI Lang 1.0** (`@openuidev/react-lang` 1.0.1). The model answers in the OpenUI Lang format; the app parses it with the official parser and renders it with the official `<Renderer>`.

#### Tasks:
* **Task 4.1: Component Registry & Zod Schemas** — done
  * `src/genui/schema.ts` — Zod schemas and the `LIMITS` table (max depth 3, 50 table rows, 100 chart points, 20 form fields, 10 children, 4000-char text).
  * `src/genui/library.ts` — `createLibrary()` over `defineComponent()`; the library is the allowlist (Stack, Card, Text, Table, Chart, Form, Steps, Button).
  * `src/genui/components/` — one file per component.
* **Task 4.2: OpenUI Renderer Integration** — done
  * `src/genui/parser.ts` — the shared parser, built from the library's JSON Schema.
  * `src/genui/split.ts` — decides whether an answer is prose, a program, or both.
  * `src/genui/OpenUIMessage.tsx` — renders prose as markdown and programs with `<Renderer>`.
  * `src/genui/prompt.ts` — `generateSystemPrompt()` builds the system prompt from the library, so the model is taught the exact components it may use.
* **Task 4.3: Interactive Form Pre-Validation** — done
  * `src/genui/components/Form.tsx` — fields are validated against the schema before the action runs.
  * `src/genui/actions.ts` — action events become a follow-up turn; only http(s) links are opened.
* **Task 4.4: Safe Fallback & Milestone 4 Smoke Test** — done
  * `src/genui/validate.ts` — resource-bound checks; oversized collections are trimmed and reported, programs over 64 KB are rejected.
  * `tests/smoke_m4.ts` — allowlist, prompt, parsing, splitting, bounds and action handling.
  * `genui-preview.html` + `src/genui/preview.tsx` — dev-only page that renders hand-written programs.

**Done When (Acceptance Criteria):**
1. Model emitting structured UI data renders a live table/card component inside the chat stream. ✅
2. Malformed or unallowlisted component payloads gracefully fall back to readable text with a non-fatal warning. ✅
3. Oversized payloads (>50 rows or >100 points) are rejected by schema bounds. ✅ (trimmed to the bound and reported; the program itself is rejected above 64 KB)
4. No arbitrary executable JavaScript or unsafe HTML can be injected through generative UI. ✅

**Deviation from the plan:** the plan listed `@openuidev/react-ui` alongside `@openuidev/react-lang`. Only `react-lang` is used — it provides the parser, renderer, prompt generation and action runtime. `react-ui`'s 80-component default library was not adopted because SPEC §7.2 requires a card/table/chart/form/steps allowlist, and its styling does not match this app's design system. The dependency was removed rather than left unused.

---

### The UI build (all milestones)
**Status: the shell and every milestone surface are built on the Lively design system.**

The mockups in `openall-mockups/` and the design system in `design-system/` are the specification. The app now renders the same shell they do, with the real app logic behind it:

| Milestone | Surface | Where |
|---|---|---|
| M1 | Model pill, provider dots, bounded-failover badge | `src/shell/ModelBar.tsx` |
| M2 | Grouped, searchable history; rename and delete on hover | `src/shell/Sidebar.tsx` |
| M3 | Artifact pane with Preview and Code tabs | `src/surfaces/ArtifactPane.tsx` |
| M4 | Generative UI in the reply | `src/genui/` |
| M5 | Settings modal; provider credentials | `src/app/SettingsDialog.tsx` |
| M6 | Inline tool permission; memory facts | `src/surfaces/PermissionCard.tsx`, `src/surfaces/MemoryCard.tsx` |
| M7 | Agent terminal dock | `src/surfaces/TerminalDock.tsx` |
| M8 | Deep research as a full surface | `src/surfaces/ResearchOverlay.tsx` |
| M9 | Voice dock above the composer | `src/surfaces/VoiceDock.tsx` |
| M10 | Personality, custom instructions, memory | `src/surfaces/CustomizeOverlay.tsx` |
| M11 | Tool picker | `src/surfaces/ToolsOverlay.tsx` |
| M12 | Model picker | `src/surfaces/ModelOverlay.tsx` |
| M13 | Account panel | `src/surfaces/AccountPanel.tsx` |

**Styling decision:** Tailwind was removed. The design system is the only styling layer — `src/styles/tokens.css`, `motion.css`, `shell.css` and `surfaces.css` are the design system's files, copied verbatim so the mockups and the app cannot drift. `src/styles/app.css` holds the handful of rules the app needs that the design system does not yet name.

---

### Milestone 5: Tauri Desktop Shell (Windows Desktop Phase)
**Goal:** Wrap the stable web app into a compiled Tauri v2 desktop application for Windows, enabling OS-level secret storage and native platform capabilities.  
**Custom Code Budget:** ~250 lines (Rust bridge ~100, TS adapter ~150).

#### Tasks:
* **Task 5.1: Tauri v2 Project Initialization**
  * Initialize Tauri v2 (`src-tauri/`) targeting Windows x64 WebView2.
  * Configure `tauri.conf.json` (window properties, security CSP, permissions).
  * *Files:* `src-tauri/Cargo.toml`, `src-tauri/tauri.conf.json`, `src-tauri/src/main.rs`.
* **Task 5.2: OS Keychain Secrets Manager**
  * Implement Rust Tauri command for secure credential storage using Windows Credential Manager / DPAPI (`keyring` crate or native Windows API).
  * Implement TypeScript `TauriSecretsAdapter` with `getSecret(key)`, `setSecret(key, val)`, `deleteSecret(key)`.
  * Ensure provider API keys are stored in the OS credential store, completely out of web storage.
  * *Files:* `src-tauri/src/keychain.rs`, `src/adapters/secrets.ts`.
* **Task 5.3: Desktop SQLite Storage Adapter (Optional Enhancement)**
  * Add `@tauri-apps/plugin-sql` adapter for persistent SQLite storage on desktop.
  * Implement migration check and document origin separation between web and desktop.
  * *Files:* `src/db/sqliteAdapter.ts`.
* **Task 5.4: Windows Build & Packaging Verification**
  * Build the release binary (`npm run tauri build`).
  * Verify WebView2 runs smoothly with zero bundled Chromium bloat.
  * *Files:* `src-tauri/tauri.conf.json`.
* **Task 5.5: Milestone 5 Smoke Test**
  * Verify chat, artifacts, and generative UI run inside the compiled Windows `.exe`.
  * Verify API keys are retrieved from Windows Credential Manager and never written to plaintext JSON.

**Done When (Acceptance Criteria):**
1. Tauri v2 compiled Windows executable launches, loads the UI, and supports streaming chat and artifacts.
2. Secrets are saved to and read from the Windows OS Keychain, not stored in plaintext files.
3. Storage failure or permission denial surfaces cleanly in the desktop UI.
4. Web and desktop storage paths are explicitly documented with a working JSON import/export bridge.

---

### Milestone 6: Remote Tools, Skills, and Memory
**Goal:** Implement safe tool invocation, dynamic Agent Skills loading, and inspectable long-term user memory with mandatory human approval.  
**Custom Code Budget:** ~520 lines (MCP ~250, Skills ~150, Memory ~120).

#### Tasks:
* **Task 6.1: Consequential Action Approval Dialog**
  * Build modal dialog intercepting every tool call before execution.
  * Displays: Tool Name, Target Resource, Exact Arguments, and Concise Risk Description.
  * Options: [Approve Once | Reject]. No "Always Allow" mode in v0.
  * *Files:* `src/tools/ApprovalDialog.tsx`, `src/tools/toolInterceptor.ts`.
* **Task 6.2: Remote HTTP MCP Client**
  * Integrate `@modelcontextprotocol/sdk` to connect to remote HTTP MCP endpoints configured in `mcp.config.json`.
  * Convert MCP tools to OpenAI/Vercel AI SDK compatible tool definitions.
  * *Files:* `src/tools/mcpClient.ts`, `mcp.config.json`.
* **Task 6.3: Agent Skills Scanner & Loader**
  * Implement parser for local `skills/*/SKILL.md` folders following the `agentskills.io` standard.
  * Read frontmatter metadata (`name`, `description`) at startup.
  * Inject skill instructions into system prompt dynamically only when relevant.
  * Enforce security rule: Skills are untrusted instructions and cannot bypass tool approval or elevate privileges.
  * *Files:* `src/tools/skillsLoader.ts`.
* **Task 6.4: Inspectable Memory Fact Store**
  * Create `facts` table in storage (`id`, `fact`, `category`, `createdAt`).
  * Provide model with `remember(fact)` and `recall(query)` tools (requiring user confirmation).
  * Build "Memory Management" settings view: list all stored facts, inline edit, single-item delete, and "Clear All" button.
  * Exclude sensitive credentials or personal auth tokens from memory.
  * *Files:* `src/tools/memory.ts`, `src/app/MemoryView.tsx`.
* **Task 6.5: Milestone 6 Smoke Test**
  * Trigger a remote MCP tool call and verify it blocks until the approval dialog is explicitly confirmed.
  * Load a sample `SKILL.md` and verify its instructions appear in model context without privilege bypass.
  * Add a memory fact, verify it in the settings UI, delete it, and verify it is forgotten.

**Done When (Acceptance Criteria):**
1. Every tool call pauses execution and displays the approval modal with arguments and target.
2. Rejecting a tool call returns a graceful cancellation to the model without crashing.
3. Skills load from markdown files with metadata visible in the UI.
4. User can inspect, edit, and delete any saved memory fact.

---

### Milestone 7: Local MCP and Code Agent Pane
**Goal:** Enable local stdio MCP servers and integrate OpenCode inside an embedded xterm.js terminal pane under strict native supervision.  
**Custom Code Budget:** ~250 lines (stdio MCP ~150, OpenCode pane ~100).

#### Tasks:
* **Task 7.1: Local stdio MCP Process Transport (Tauri Native)**
  * Implement Tauri Rust command to spawn and pipe stdio to local MCP servers defined in `mcp.config.json`.
  * Validate execution paths against an approved whitelist.
  * Fall back cleanly to a mock/disabled state when running in the browser phase.
  * *Files:* `src-tauri/src/mcp_process.rs`, `src/tools/localMcp.ts`.
* **Task 7.2: CodeAgentProvider Interface & OpenCode Launcher**
  * Define `CodeAgentProvider` interface (`start(projectPath)`, `sendCommand(cmd)`, `stop()`).
  * Implement native process launcher that initiates OpenCode within a user-selected approved directory.
  * Provide MockCodeAgentProvider for browser dev mode.
  * *Files:* `src/adapters/codeAgent.ts`, `src-tauri/src/opencode.rs`.
* **Task 7.3: xterm.js Terminal Pane Integration**
  * Integrate `@xterm/xterm` with `@xterm/addon-fit` into a collapsible bottom/side terminal panel.
  * Stream stdout/stderr from OpenCode directly into the terminal with ANSI color support.
  * Forward user keystrokes to stdin.
  * *Files:* `src/canvas/TerminalPane.tsx`.
* **Task 7.4: Process Supervision & Kill Switch**
  * Add explicit [Stop Process] button in the terminal header.
  * Surface process exit codes and error logs if OpenCode terminates unexpectedly.
  * *Files:* `src/canvas/TerminalHeader.tsx`.
* **Task 7.5: Milestone 7 Smoke Test**
  * Run a test stdio MCP tool in Tauri and verify scoped execution.
  * Open a test folder in the terminal pane, launch the code agent, run a command, and kill the process.

**Done When (Acceptance Criteria):**
1. Local stdio MCP servers launch and communicate over stdio via native Tauri IPC with approval prompts.
2. xterm.js terminal renders interactive terminal output smoothly.
3. OpenCode runs strictly within the approved target directory.
4. Clicking [Stop Process] immediately terminates child processes cleanly.

---

### Milestone 8: Deep Research Service Benchmark & App Integration
**Goal:** Build and benchmark a standalone 512 MB cloud research container (FastAPI + trafilatura) that passes the memory gate (<450 MB RAM) before integrating with the app Canvas.  
**Custom Code Budget:** Service ~300–500 lines; App side ~150 lines.

#### Sub-Phase 8A: Standalone Research Microservice & Acceptance Gate
* **Task 8.1: Service Scaffolding & API Spec**
  * Create `research-service/` with `Dockerfile` based on `python:3.11-slim`.
  * Implement FastAPI app with:
    * `GET /health` -> `{"status": "ok"}`
    * `POST /research` -> validates token and query, returns 202 `{"job_id": "<uuid>"}`
    * `GET /research/{id}` -> returns job state, progress, partial summaries, and final report.
  * Enforce single active job lock (`429` with `Retry-After: 60` if busy).
  * Require auth token via `X-Research-Token` header.
  * *Files:* `research-service/main.py`, `research-service/requirements.txt`, `research-service/Dockerfile`.
* **Task 8.2: Safe URL Fetching & SSRF Protection**
  * Implement strict SSRF filter:
    * Allow only `http` and `https`.
    * Resolve hostnames via DNS and reject IPv4/IPv6 private ranges (`127.0.0.0/8`, `10.0.0.0/8`, `192.168.0.0/16`, `172.16.0.0/12`, `169.254.0.0/16`, `::1`, link-local).
    * Re-validate resolved IP on every redirect hop.
    * 2 MB raw response cap, 30s connection timeout.
  * Extract clean text using `trafilatura` (max 4,000 clean chars per source).
  * *Files:* `research-service/fetcher.py`.
* **Task 8.3: Deterministic 4-Stage Pipeline**
  * Implement fixed pipeline:
    1. **Search:** Query Tavily API (fallback: `duckduckgo-search`), cap at 5 URLs.
    2. **Extract:** Fetch & parse text via SSRF fetcher.
    3. **Map:** Summarize each source using configured remote model (max 3 calls/source).
    4. **Reduce:** Synthesize summaries into markdown report with verified citations.
  * Enforce hard bounds: max 25 model calls total, max 5 minutes total timeout.
  * Persist incremental progress to SQLite / JSON job record on disk.
  * *Files:* `research-service/pipeline.py`, `research-service/citation_validator.py`.
* **Task 8.4: Memory Benchmark & Deployment Spike**
  * Run benchmark suite simulating normal and worst-case loads.
  * Measure peak container memory: **must stay below 450 MB**.
  * Deploy to Blitz.cloud (fallback: Render) and record deployment date and terms in `docs/RESEARCH_HOSTING.md`.

#### Sub-Phase 8B: Frontend Canvas Integration
* **Task 8.5: App ResearchProvider Adapter**
  * Implement `ResearchProvider` adapter with polling (`GET /research/{id}` every 2s).
  * Handle cold-start flow: ping `GET /health`, display "Waking up research node..." while container starts.
  * *Files:* `src/adapters/research.ts`.
* **Task 8.6: Research Report Canvas Viewer**
  * Render research progress (Search -> Extract -> Map -> Reduce) in the canvas panel.
  * Render final report with clickable, verified citation links.
  * Handle `partial`, `timed_out`, and `interrupted` states clearly.
  * *Files:* `src/canvas/ResearchReportView.tsx`.
* **Task 8.7: Milestone 8 Verification & Acceptance Gate**
  * Run an end-to-end research query from the app.
  * Verify citation validation removes hallucinated references.
  * Verify container memory stayed <450 MB during the run.

**Done When (Acceptance Criteria):**
1. Research container passes acceptance gate: peak RAM < 450 MB and total run < 5 minutes.
2. Every citation in the generated report links directly to a verified retrieved source.
3. SSRF tests block localhost, metadata endpoints (`169.254.169.254`), and private networks.
4. App shows "Waking up research node..." during cold start and renders partial output on timeouts.

---

### Milestone 9: Voice v1 (Push-to-Talk)
**Goal:** Provide lightweight push-to-talk audio input and text-to-speech output behind a clean adapter interface, keeping full-duplex as a stub.  
**Custom Code Budget:** ~150 lines.

#### Tasks:
* **Task 9.1: VoiceProvider Interface & Full-Duplex v2 Stub**
  * Define `VoiceProvider` interface (`startRecording()`, `stopRecording()`, `speak(text)`, `cancelSpeech()`).
  * Create `VoiceProviderStub` for full-duplex v2 (PersonaPlex / VoiceChat) ready for future WebSocket connection.
  * *Files:* `src/adapters/voice.ts`.
* **Task 9.2: Web Speech API / Audio Recording**
  * Implement `BrowserVoiceProvider` using browser Web Speech API (`SpeechRecognition`) or `MediaRecorder` for audio capture.
  * *Files:* `src/adapters/browserVoice.ts`.
* **Task 9.3: Push-to-Talk Microphone Button**
  * Add microphone button to chat input with visual states (Idle, Listening, Processing, Speaking).
  * Automatically append transcribed speech into the input field or dispatch prompt.
  * *Files:* `src/chat/VoiceInputButton.tsx`.
* **Task 9.4: Text-to-Speech Playback**
  * Implement audio playback of assistant replies using `window.speechSynthesis` or local Piper/Kokoro endpoint.
  * Include a quick mute/stop button in the message toolbar.
  * *Files:* `src/chat/SpeechOutput.tsx`.
* **Task 9.5: Milestone 9 Smoke Test**
  * Test push-to-talk speech input and confirm transcribed text appears.
  * Test voice reply playback and verify cancellation when interrupted.

**Done When (Acceptance Criteria):**
1. User can hold/click push-to-talk, speak a prompt, and see transcribed text submitted.
2. Assistant replies can be spoken aloud and cancelled immediately with a mute button.
3. Unavailable microphone permissions fail gracefully with an explanatory notice.
4. Full-duplex voice interface is cleanly stubbed behind `VoiceProvider`.

---

### Milestone 10: Android Thin Client (Tauri v2 Android Target)
**Goal:** Verify touch layout and build the Tauri Android target as a thin client connecting to remote research and cloud services, cleanly disabling desktop-only features.  
**Custom Code Budget:** Responsive CSS adjustments & configuration flags (~50 lines).

#### Tasks:
* **Task 10.1: Touch & Mobile Responsive UI Audit**
  * Test app layout on mobile viewport sizes (via Chrome DevTools and mobile PWA install).
  * Configure Canvas panel to open full-screen on mobile devices with easy swipe-to-dismiss.
  * *Files:* `src/canvas/CanvasPanel.tsx`, `src/app/MobileNav.tsx`.
* **Task 10.2: Feature Capability Gating (`desktopOnly`)**
  * Mark desktop-only features: Local stdio MCP, OpenCode terminal pane, local Ollama.
  * On mobile/Android runtime, render clear badges: "Available on Desktop shell".
  * *Files:* `src/app/capabilities.ts`.
* **Task 10.3: Tauri Android Target Configuration**
  * Configure Tauri Android build (`src-tauri/gen/android`).
  * Verify network permissions (`INTERNET`) and HTTPS endpoints for remote research.
  * *Files:* `src-tauri/tauri.conf.json`.
* **Task 10.4: Milestone 10 Smoke Test**
  * Launch on Android emulator or physical device.
  * Verify chat, artifacts, and remote research work smoothly over touch.

**Done When (Acceptance Criteria):**
1. App compiles and runs as an Android APK via Tauri v2.
2. Chat, Canvas artifacts, and remote research work on a mobile screen.
3. Desktop-only features (OpenCode, stdio MCP) are gracefully disabled with clear labels.

---

## 5. Security Architecture & Threat Mitigations

| Threat Vector | Mitigation Strategy | Enforcement Mechanism |
|---|---|---|
| **API Key Leakage** | Never store keys in frontend bundles or Git. Use Vite dev proxy in web phase, Windows Credential Manager in desktop phase. | Strict code reviews, redaction filters in logger, `.gitignore` rules. |
| **Malicious Artifacts** | Artifacts execute inside sandboxed iframe with `sandbox="allow-scripts"` **only**. CSP blocks external connections (`connect-src 'none'`). | `SandboxedPreview.tsx` iframe sandbox & Content Security Policy. |
| **SSRF in Research Fetcher** | Filter all candidate URLs before connection. Reject loopback, private IPv4/IPv6, cloud metadata (`169.254.169.254`). Revalidate on every redirect hop. | Python `fetcher.py` socket IP resolution and redirect hook. |
| **Runaway Agent / Tool Damage** | Require explicit human confirmation before EVERY tool call in v0. Show tool name, parameters, target path, and action description. | `ApprovalDialog.tsx` interceptor; no auto-approve mode. |
| **Untrusted Skills Injection** | Treat `SKILL.md` as untrusted prompt instructions. Skills cannot execute code or bypass tool approval dialogs. | `skillsLoader.ts` metadata-only parsing and permission wall. |
| **Model Hallucination in Citations** | Strip or flag citation tags that do not match canonical URLs actually retrieved in the research run. | `citation_validator.py` cross-reference filter before report emission. |

---

## 6. Verification, Testing & Quality Gates

### 6.1 Critical Test Suite (§12.1)
The project maintains focused tests for critical paths rather than chasing arbitrary coverage numbers:
1. **SSRF Validator Unit Test:** Test private IP ranges, DNS rebinding, and redirect chains.
2. **Research Resource Enforcer Test:** Test 5-source limit, 4,000 char cap, 25 model call ceiling, and 5-minute timeout.
3. **Citation Validation Test:** Test synthetic report with valid and hallucinated IDs; verify only real sources pass.
4. **Provider Failover Test:** Simulate 429 and network disconnect; verify max 1 retry and cross-provider setting.
5. **Artifact Sandbox Test:** Verify iframe attributes and check that DOM/cookie access from iframe fails.
6. **Secret Redactor Test:** Verify logger strips authorization headers and query parameters containing keys.

### 6.2 Milestone Completion Report Format (§12.5)
At the conclusion of each milestone, report in this standard format:
```markdown
### Milestone [N] Completion Report
1. What works: [Verified working features]
2. What was stubbed: [Interfaces or services currently mocked]
3. Custom lines written vs budget: [e.g. 185 lines written vs 200 budget]
4. Package maintenance & compatibility: [Notes on any dependency verified]
5. Test results & security checks: [Pass/fail for focused tests and sandboxing]
6. Dependency changes: [Any deviations from planned stack]
7. Blockers / Next Step Question: [One focused question if blocked, otherwise None]
```

---

## 7. Immediate Next Steps (Kicking Off Milestone 1)

1. **Phase 1 Scaffolding:** Create `openall/` Vite + React 18/19 + TypeScript + Tailwind CSS project in the workspace.
2. **Dev Secrets Proxy:** Implement Vite plugin in `vite.config.ts` to proxy requests to OpenRouter / Groq without leaking keys into the client bundle.
3. **Model Provider Adapter:** Implement `src/chat/providers.ts` with capability records and bounded failover.
4. **Chat UI:** Wire `@assistant-ui/react` with streaming markdown output and model selector dropdown.
5. **Milestone 1 Verification:** Test with live free-tier API keys, execute failover test, and produce Milestone 1 report.
