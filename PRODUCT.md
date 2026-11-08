# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary user: the builder (a student) working alone on their own AI tasks. No accounts, no sharing, no multi-tenant use. Success means the app replaces their ChatGPT/Claude browser tabs for daily work: streaming chat with a model switcher, generative UI, and the other glued capabilities without leaving the local machine.

## Product Purpose

A single-user, local-first AI workspace that puts the main features of ChatGPT, Claude, and Meta Muse in one place by gluing best-in-class open-source parts behind one OpenAI-compatible endpoint. Heavy features (deep research, voice v2, personal agent) run as separate services reached by URL rather than one binary.

## Positioning

One shell that glues best-in-class open-source parts (chat, generative UI via OpenUI Lang, MCP connectors, skills, deep research) with honest, explicit boundaries — no proprietary lock-in, no hidden mocks, no own agent loop except the bounded research pipeline.

## Operating Context

- Developer laptop: i3 10th gen, 12 GB RAM, no strong GPU. Web app first; Tauri v2 desktop wrapper later.
- Models come from free-tier APIs (OpenRouter, Groq, Google AI Studio, Mistral, Ollama for offline tests). No local big models.
- Dev workflow: `npm run dev` in `openall/` on port 5173, backend on port 3001; `start-prototype.bat` for one-click launch.
- Deep research runs as a separate 512 MB cloud service (Blitz.cloud first, Render fallback) reached by URL.

## Capabilities and Constraints

**Shipped (prototype scope):** streaming chat with model switcher, generative UI (OpenUI Lang), settings (providers/keys/storage/profile), failover, markdown rendering, deep research surface with honest demo labelling, XSS sanitization.

**Planned:** deep research service integration, voice v1 (push-to-talk), code agent (OpenCode terminal pane), MCP connectors, skills loader, canvas/artifacts, desktop shell (Tauri), Android thin client.

**Constraints:**
- Single user, no accounts, no cloud sync, no native store apps, no browser extensions.
- Local-first; provider keys never in client bundle, logs, exports, or chat history.
- "Glue, don't build": use open-source libraries; write only the thin connecting layer.
- No own planner/agent runtime except the bounded, deterministic research pipeline.
- No embeddings in v0 (top-N search results only).
- Tavily Search primary, `duckduckgo-search` fallback.
- Line budgets are scope warnings, not laws; security and correctness override.
- Honest scope: mocks and known limitations must be visible, never hidden.

## Brand Commitments

- Product name: Lively / OpenAll.
- Visual system: Lively Design System (`design-system/`) — tokens, motion, shell, surfaces; one palette with two themes (light/dark).
- Voice: technical, direct, honest about limits; no fabricated testimonials, customers, benchmarks, or pricing.

## Evidence on Hand

- `docs/SPEC.md` — consolidated spec (v1.0), authoritative for resolved decisions.
- `README.md` — quick start, security defaults, test commands.
- `design-system/` — tokens and stylesheets.
- `openall/` — React 19 + TypeScript + Vite app with smoke tests (`tests/smoke_*.ts`).
- `backend/server.mjs` + `backend/test.mjs` — proxy, catalog, SSE, CORS, SSRF hardening.
- Absence: no user accounts, no telemetry, no real customer evidence — future work must not fabricate these.

## Product Principles

1. Glue, don't build — but make every boundary explicit.
2. Honest scope over apparent completeness: mocks and limitations are labelled, never hidden.
3. Local-first and key-safe: the user owns their keys and data; nothing leaves without intent.
4. Verify before installing; record what was tested.
5. Security and correctness override line budgets and polish.

## Accessibility & Inclusion

No product-specific accessibility requirement has been established beyond standard keyboard and screen-reader support in the UI. Undecided; record when a concrete need arises.