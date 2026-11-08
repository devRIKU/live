# OpenAll / Lively — AI Chat UI with OpenUI Lang & Multi-Provider Architecture

OpenAll (Lively) is a local-first AI workspace featuring an interactive multi-provider Chat UI, Generative UI powered by [OpenUI Lang](https://github.com/thesysdev/openui), live model discovery, and seamless failover.

## Highlights & Features

1. **Dual Chat UI Clients**:
   - **OpenAll React Application** (`openall/`): Full-featured React 19 + TypeScript + Vite app with `@openuidev/react-lang` component rendering, model switching modal, settings, failover, and markdown formatting.
   - **Standalone Lively Chat UI** (`Chat UI v3.html`): High-performance zero-bundle HTML/JS chat client styled with Lively Design System tokens, featuring client-side OpenUI Lang parsing & SVG rendering, live model discovery badges, and action dispatching.

2. **Generative UI via OpenUI Lang**:
   - Implements OpenUI Lang component specifications: `Stack`, `Card`, `Table`, `Chart`, `Form`, `Steps`, `Text`, and `Button`.
   - Live stream parsing: Renders partial or completed OpenUI Lang fenced blocks (` ```openui-lang ... ``` `).
   - Interactive Action Dispatching: Submitting forms or clicking buttons dispatches `@ToAssistant(...)` action payloads back into the chat stream for multi-turn interactive workflows.
   - Dual-mode segmented toggle: Inspect the interactive visual component or switch to `[OpenUI Lang]` code view.

3. **Live Model Discovery & Upstream Proxy**:
   - Unified multi-provider endpoint (`backend/server.mjs` on port `3001`).
   - Dynamically polls and queries live models from:
     - **Ollama** (`http://localhost:11434`)
     - **OpenRouter** (`https://openrouter.ai/api/v1`)
     - **Groq** (`https://api.groq.com/openai/v1`)
     - **Google AI Studio** (`Gemini 2.5 Pro / Flash`)
     - **Mistral AI** (`Mistral Large / Pixtral`)
     - **Lively Prototype Engine** (Instant zero-config fallback generator)
   - Live refresh endpoint: `GET /api/models?refresh=true` and `POST /api/models/refresh`.
   - UI model selector displays real-time `LIVE` badges and a one-click "Live Refresh" button.

4. **Resilient Failover**:
   - If an upstream API returns `401 Unauthorized` (e.g. Missing key) or `429 Rate Limited`, the system automatically falls back to the local OpenUI prototype engine so the conversation turn never fails.

---

## Quick Start

### 1. Launch the Prototype Backend
```powershell
node backend/server.mjs
```
The server will start on `http://localhost:3001` and serve:
- Standalone UI: `http://localhost:3001/` or `http://localhost:3001/Chat%20UI%20v3.html`
- Compiled React App: `http://localhost:3001/app/`
- API Chat Completions: `http://localhost:3001/api/chat/completions`
- Models Catalog: `http://localhost:3001/api/models`
- Provider Details: `http://localhost:3001/api/providers`

### 2. Launch OpenAll React Development Server (Optional)
```powershell
cd openall
npm run dev
```
Open `http://localhost:5173`. Proxies `/api/*` and `/v1/*` requests directly to `http://localhost:3001`.

### 3. One-Click Prototype Launcher
Run `start-prototype.bat` to launch the backend and the React dev server.

### Network & security defaults
- The backend binds `127.0.0.1` and answers only local browser origins
  (`localhost:5173`, `localhost:3001`, and the Tauri shell). Opening the
  standalone UI over `file://` is rejected. Serve it from the backend instead.
- Set `LIVELY_HOST=0.0.0.0` to expose the backend on the LAN. Every caller then
  has full access to any provider keys the backend holds.
- LAN development (`vite --host 0.0.0.0`) needs its origin added to
  `LIVELY_ALLOWED_ORIGINS` (comma-separated).
- `start-prototype.bat` starts the deep-research service when the root `.venv`
  has `fastapi` and `uvicorn`. Otherwise the research surface shows a
  **Demo data** badge, so a simulated report is never mistaken for a real one.

---

## Testing & Verification

Automated test suites can be run via:
```powershell
# Backend test suite (endpoints, catalog, SSE streaming, CORS, body cap, XSS)
node backend/test.mjs

# All UI smoke tests plus the backend suite
npm test --prefix openall

# Production build check
npm run build --prefix openall
```

---

## References & Architecture
- [OpenUI Documentation & Repo](https://github.com/thesysdev/openui)
- `docs/SPEC.md` — OpenAll system specification
- `design-system/` — Lively Design System tokens and stylesheets
