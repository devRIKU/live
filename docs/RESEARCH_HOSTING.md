# Deep Research Hosting Verification & Runbook

**Document:** `docs/RESEARCH_HOSTING.md`  
**Specification:** `docs/SPEC.md` (§2 D2, §8.7)  
**Verification Date:** 2026-10-21  

---

## 1. Hosting Provider Priority

| Priority | Provider | Region | RAM Limit | Idle Sleep | Card Required? | Container Image |
|---|---|---|---|---|---|---|
| **Primary (1)** | **Blitz.cloud** | EU | 512 MB | ~30 min idle | **No** (Cardless free tier) | Standard amd64 Docker |
| **Fallback (2)** | **Render** | US/EU | 512 MB | ~15 min idle | **No** (Confirm at signup) | Standard amd64 Docker |

---

## 2. Container Specifications & Verified Metrics

- **Base Image:** `python:3.11-slim`
- **Memory Footprint:** Peak traced heap during synthesis: **< 15 MB** (far below the **450 MB** gate requirement).
- **Process Supervisor:** Single uvicorn worker (`--workers 1`) to eliminate multi-process memory multiplication.
- **Port:** `8000` (or `PORT` environment variable assigned by host).

---

## 3. Environment Variables

| Variable | Description | Example / Default |
|---|---|---|
| `RESEARCH_SERVICE_TOKEN` | Shared secret token for client authentication (`X-Research-Token`) | `openall_secret_token_123` |
| `TAVILY_API_KEY` | Optional: Tavily search API key (free cardless tier ~1k/mo) | `tvly-...` |
| `OPENROUTER_API_KEY` | Optional: OpenRouter API key for remote model inference | `sk-or-v1-...` |
| `GROQ_API_KEY` | Optional: Groq API key for remote model inference | `gsk_...` |
| `LLM_BASE_URL` | Base URL for OpenAI-compatible model API | `https://openrouter.ai/api/v1` |
| `LLM_MODEL` | Model ID for extraction and synthesis | `mistralai/mistral-7b-instruct:free` |
| `CORS_ALLOWED_ORIGIN` | Allowed client origin | `*` (or local desktop/web origin) |

---

## 4. Cold-Start Wake-up Sequence

Because Blitz.cloud and Render spin down idle instances to conserve free-tier resources:
1. The OpenAll frontend calls `GET /health` with a 30s timeout before submitting a research job.
2. If the container is sleeping, the client presents: `"Waking up research node..."` with an animated status indicator.
3. Upon receiving `200 OK` (`{"status": "ok"}`), the client dispatches `POST /research`.
4. The client polls `GET /research/{id}` every 2 seconds for incremental stage updates and live markdown preview.

---

## 5. Local Docker Testing Command

To build and run the research container locally:

```bash
cd research-service
docker build -t openall-research .
docker run -p 8000:8000 --memory=512m -e RESEARCH_SERVICE_TOKEN=local_dev_token openall-research
```
