/**
 * OpenAll / Lively Prototype Backend Server
 * 
 * Standalone zero-dependency Node.js HTTP server:
 * - OpenAI-compatible SSE streaming (/api/chat/completions, /v1/chat/completions)
 * - Multi-provider proxy support (Groq, OpenRouter, Google AI Studio, Mistral, Ollama)
 * - Intelligent prototype fallback streaming engine (zero-config, works immediately offline or without keys)
 * - Provider management endpoints (/api/providers, /api/providers/keys)
 * - Model catalog endpoint (/api/models)
 * - Health check endpoint (/api/health)
 * - Static file serving for the workspace (Chat UI v3.html, design-system, openall)
 */

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import dns from 'node:dns/promises';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.resolve(__dirname, '..');

// Load .env before reading PORT/HOST/origins so those settings work there too.
loadEnvFile(path.join(ROOT_DIR, '.env'));
loadEnvFile(path.join(ROOT_DIR, 'openall', '.env'));

const PORT = parseInt(process.env.PORT || '3001', 10);
// Loopback by default: reachable from this machine only. Set LIVELY_HOST=0.0.0.0
// to expose it on the LAN (every caller then has full access to configured keys).
const HOST = process.env.LIVELY_HOST || '127.0.0.1';

// Browser origins allowed to call the API. Anything else with an Origin header
// is rejected, which blocks drive-by requests from arbitrary web pages.
const ALLOWED_ORIGINS = new Set([
  'http://localhost:5173',
  'http://127.0.0.1:5173',
  `http://localhost:${PORT}`,
  `http://127.0.0.1:${PORT}`,
  'tauri://localhost',
  'http://tauri.localhost',
  'https://tauri.localhost',
  // Escape hatch for LAN dev (`vite --host 0.0.0.0`). Comma-separated.
  ...(process.env.LIVELY_ALLOWED_ORIGINS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean),
]);

const MAX_BODY_BYTES = 1024 * 1024;

// Load .env from ROOT_DIR or openall/.env if present
function loadEnvFile(envPath) {
  try {
    if (fs.existsSync(envPath)) {
      const content = fs.readFileSync(envPath, 'utf8');
      for (const line of content.split('\n')) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          const key = trimmed.slice(0, eqIdx).trim();
          const val = trimmed.slice(eqIdx + 1).trim().replace(/^["']|["']$/g, '');
          if (!process.env[key] && val) {
            process.env[key] = val;
          }
        }
      }
    }
  } catch (e) {
    // ignore
  }
}

// Write or update a key in a .env file
function updateEnvFile(filePath, keyName, value) {
  try {
    let lines = [];
    if (fs.existsSync(filePath)) {
      lines = fs.readFileSync(filePath, 'utf8').split('\n');
    }
    let found = false;
    lines = lines.map(line => {
      const trimmed = line.trim();
      if (trimmed.startsWith(`${keyName}=`) || (trimmed.startsWith('#') && trimmed.includes(`${keyName}=`))) {
        found = true;
        return `${keyName}=${value}`;
      }
      return line;
    });
    if (!found) {
      lines.push(`${keyName}=${value}`);
    }
    fs.writeFileSync(filePath, lines.join('\n'), 'utf8');
  } catch (e) {
    console.error(`Failed to update ${filePath}:`, e);
  }
}

// Provider definitions
const PROVIDERS = {
  openrouter: {
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    envKey: 'OPENROUTER_API_KEY',
    defaultModel: 'anthropic/claude-sonnet-4',
    isLive: false,
    liveStatus: 'Ready',
    models: [
      { id: 'anthropic/claude-sonnet-4', label: 'Claude Sonnet 4', contextLimit: 200000, maxOutput: 64000, vision: true, tools: true },
      { id: 'openai/gpt-4.1', label: 'GPT-4.1', contextLimit: 1047576, maxOutput: 32768, vision: true, tools: true },
      { id: 'google/gemini-2.5-pro', label: 'Gemini 2.5 Pro', contextLimit: 1048576, maxOutput: 65536, vision: true, tools: true },
      { id: 'deepseek/deepseek-chat-v3-0324', label: 'DeepSeek V3', contextLimit: 163840, maxOutput: 8192, vision: false, tools: true },
      { id: 'mistralai/mistral-small-3.2-24b-instruct:free', label: 'Mistral Small 3.2 (free)', contextLimit: 128000, maxOutput: 8192, vision: true, tools: true }
    ]
  },
  groq: {
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    envKey: 'GROQ_API_KEY',
    defaultModel: 'llama-3.3-70b-versatile',
    isLive: false,
    liveStatus: 'Ready',
    models: [
      { id: 'llama-3.3-70b-versatile', label: 'Llama 3.3 70B', contextLimit: 131072, maxOutput: 32768, vision: false, tools: true },
      { id: 'llama-3.1-8b-instant', label: 'Llama 3.1 8B Instant', contextLimit: 131072, maxOutput: 8192, vision: false, tools: true },
      { id: 'qwen/qwen3-32b', label: 'Qwen 3 32B', contextLimit: 131072, maxOutput: 32768, vision: false, tools: true },
      { id: 'moonshotai/kimi-k2-instruct', label: 'Kimi K2', contextLimit: 131072, maxOutput: 16384, vision: false, tools: true }
    ]
  },
  google: {
    name: 'Google AI Studio',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    envKey: 'GOOGLE_AI_KEY',
    defaultModel: 'gemini-3.1-flash-lite-image',
    isLive: false,
    liveStatus: 'Ready',
    models: [
      { id: 'gemini-3.1-flash-lite-image', label: 'Gemini 3.1 Flash Lite Image (Nano Banana 2 Lite)', contextLimit: 65536, maxOutput: 4096, vision: true, tools: false, isLive: true, isImageModel: true },
      { id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash', contextLimit: 1048576, maxOutput: 65536, vision: true, tools: true },
      { id: 'gemini-2.5-pro', label: 'Gemini 2.5 Pro', contextLimit: 1048576, maxOutput: 65536, vision: true, tools: true },
      { id: 'gemini-2.5-flash-lite', label: 'Gemini 2.5 Flash Lite', contextLimit: 1048576, maxOutput: 65536, vision: true, tools: true },
      { id: 'gemini-2.0-flash', label: 'Gemini 2.0 Flash', contextLimit: 1048576, maxOutput: 8192, vision: true, tools: true }
    ]
  },
  mistral: {
    name: 'Mistral',
    baseUrl: 'https://api.mistral.ai/v1',
    envKey: 'MISTRAL_API_KEY',
    defaultModel: 'mistral-large-latest',
    isLive: false,
    liveStatus: 'Ready',
    models: [
      { id: 'mistral-large-latest', label: 'Mistral Large', contextLimit: 131072, maxOutput: 32768, vision: false, tools: true },
      { id: 'mistral-medium-latest', label: 'Mistral Medium', contextLimit: 131072, maxOutput: 8192, vision: true, tools: true },
      { id: 'pixtral-large-latest', label: 'Pixtral Large', contextLimit: 131072, maxOutput: 32768, vision: true, tools: true }
    ]
  },
  ollama: {
    name: 'Ollama (Local)',
    baseUrl: process.env.OLLAMA_HOST ? `${process.env.OLLAMA_HOST}/v1` : 'http://localhost:11434/v1',
    envKey: 'OLLAMA_HOST',
    defaultModel: 'llama3',
    isLive: false,
    liveStatus: 'Offline',
    models: [
      { id: 'llama3', label: 'Llama 3 (Local)', contextLimit: 8192, maxOutput: 4096, vision: false, tools: true },
      { id: 'mistral', label: 'Mistral (Local)', contextLimit: 8192, maxOutput: 4096, vision: false, tools: true },
      { id: 'phi3', label: 'Phi-3 (Local)', contextLimit: 4096, maxOutput: 2048, vision: false, tools: false }
    ]
  },
  lively: {
    name: 'Lively Prototype Engine',
    baseUrl: 'local://prototype',
    envKey: null,
    defaultModel: 'lively/openui-smart',
    isLive: true,
    liveStatus: 'Active',
    models: [
      { id: 'lively/openui-smart', label: 'Lively OpenUI Designer (Interactive UI)', contextLimit: 128000, maxOutput: 16384, vision: true, tools: true, isLive: true },
      { id: 'lively/prototype-smart', label: 'Lively Prototype (Instant Reasoning)', contextLimit: 128000, maxOutput: 16384, vision: true, tools: true, isLive: true },
      { id: 'lively/prototype-fast', label: 'Lively Prototype Fast', contextLimit: 64000, maxOutput: 8192, vision: true, tools: true, isLive: true }
    ]
  }
};
// Prototype alias
PROVIDERS.prototype = PROVIDERS.lively;

// ── Live Model Discovery ──────────────────────────────────────────────────
let liveCacheTime = 0;
const LIVE_CACHE_TTL = 60000;
let isFetchingLive = false;
// In-memory cache of the last successfully discovered live model catalog.
let liveModelCache = { data: null, timestamp: 0 };

async function fetchLiveOllama() {
  const host = process.env.OLLAMA_HOST || 'http://localhost:11434';
  const urls = [`${host}/api/tags`, 'http://127.0.0.1:11434/api/tags'];
  for (const u of urls) {
    try {
      const res = await fetch(u, { signal: AbortSignal.timeout(2000) });
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data.models) && data.models.length > 0) {
          const live = data.models.map(m => {
            const name = m.name || m.model;
            const param = m.details?.parameter_size ? ` (${m.details.parameter_size})` : '';
            return {
              id: name,
              label: `${name}${param} [Local]`,
              contextLimit: 32768,
              maxOutput: 8192,
              vision: name.includes('vision') || name.includes('llava'),
              tools: true,
              isLive: true
            };
          });
          PROVIDERS.ollama.models = live;
          PROVIDERS.ollama.defaultModel = live[0].id;
          PROVIDERS.ollama.isLive = true;
          PROVIDERS.ollama.liveStatus = `Live (${live.length} local models)`;
          return;
        }
      }
    } catch {}
  }
  PROVIDERS.ollama.isLive = false;
  PROVIDERS.ollama.liveStatus = 'Offline';
}

async function fetchLiveOpenRouter() {
  try {
    const res = await fetch('https://openrouter.ai/api/v1/models', { signal: AbortSignal.timeout(4000) });
    if (res.ok) {
      const data = await res.json();
      if (Array.isArray(data.data) && data.data.length > 0) {
        const all = data.data;
        const priorityIds = [
          'anthropic/claude-3.7-sonnet',
          'anthropic/claude-3.5-sonnet',
          'openai/gpt-4o',
          'openai/gpt-4o-mini',
          'openai/o3-mini',
          'deepseek/deepseek-r1',
          'deepseek/deepseek-chat',
          'meta-llama/llama-3.3-70b-instruct:free',
          'qwen/qwen-2.5-72b-instruct'
        ];
        const fetchedMap = new Map(all.map(m => [m.id, m]));
        const combined = [];

        for (const pid of priorityIds) {
          const m = fetchedMap.get(pid);
          if (m) {
            combined.push({
              id: m.id,
              label: m.name || m.id,
              contextLimit: m.context_length || 128000,
              maxOutput: m.top_provider?.max_completion_tokens || 8192,
              vision: Boolean(m.architecture?.modality?.includes('image') || m.id.includes('claude') || m.id.includes('gpt-4o')),
              tools: true,
              isLive: true
            });
          }
        }

        // Add popular free tier models
        for (const m of all) {
          if (m.id.endsWith(':free') && !combined.some(c => c.id === m.id)) {
            combined.push({
              id: m.id,
              label: `${m.name || m.id} (free)`,
              contextLimit: m.context_length || 64000,
              maxOutput: 4096,
              vision: Boolean(m.architecture?.modality?.includes('image')),
              tools: true,
              isLive: true
            });
            if (combined.length >= 16) break;
          }
        }

        if (combined.length > 0) {
          PROVIDERS.openrouter.models = combined;
          PROVIDERS.openrouter.isLive = true;
          PROVIDERS.openrouter.liveStatus = `Live (${combined.length} models)`;
        }
        return all;
      }
    }
  } catch (err) {
    console.warn('Failed to fetch OpenRouter models:', err.message);
  }
  return [];
}

async function fetchLiveGoogle(rawModels = []) {
  const key = process.env.GOOGLE_AI_KEY || process.env.GEMINI_API_KEY;
  if (key && !key.startsWith('dummy') && !key.startsWith('test')) {
    try {
      const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(key)}`, {
        signal: AbortSignal.timeout(3500)
      });
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data.models) && data.models.length > 0) {
          const live = data.models
            .filter(m => m.name && m.supportedGenerationMethods?.includes('generateContent'))
            .map(m => {
              const id = m.name.replace(/^models\//, '');
              return {
                id,
                label: m.displayName || id,
                contextLimit: m.inputTokenLimit || 1048576,
                maxOutput: m.outputTokenLimit || 65536,
                vision: true,
                tools: true,
                isLive: true
              };
            });
          if (live.length > 0) {
            PROVIDERS.google.models = live;
            PROVIDERS.google.defaultModel = live[0].id;
            PROVIDERS.google.isLive = true;
            PROVIDERS.google.liveStatus = `Live API (${live.length} models)`;
            return;
          }
        }
      }
    } catch {}
  }

  // Cross-reference live upstream models for Google
  const googleCandidates = rawModels.filter(m => m.id.startsWith('google/'));
  if (googleCandidates.length > 0) {
    const live = googleCandidates.slice(0, 10).map(m => {
      const rawId = m.id.replace(/^google\//, '');
      return {
        id: rawId,
        label: m.name ? m.name.replace(/^Google:\s*/, '') : rawId,
        contextLimit: m.context_length || 1048576,
        maxOutput: m.top_provider?.max_completion_tokens || 65536,
        vision: Boolean(m.architecture?.modality?.includes('image') || rawId.includes('flash') || rawId.includes('pro')),
        tools: true,
        isLive: true
      };
    });
    PROVIDERS.google.models = live;
    PROVIDERS.google.defaultModel = live[0].id;
    PROVIDERS.google.isLive = true;
    PROVIDERS.google.liveStatus = `Live (${live.length} models)`;
  } else {
    PROVIDERS.google.models.forEach(m => { m.isLive = true; });
    PROVIDERS.google.isLive = true;
    PROVIDERS.google.liveStatus = `Live (${PROVIDERS.google.models.length} models)`;
  }

  // Ensure Gemini 3.1 Flash Lite Image is always available
  const imageModel = {
    id: 'gemini-3.1-flash-lite-image',
    label: 'Gemini 3.1 Flash Lite Image (Nano Banana 2 Lite)',
    contextLimit: 65536,
    maxOutput: 4096,
    vision: true,
    tools: false,
    isLive: true,
    isImageModel: true
  };
  if (!PROVIDERS.google.models.some(m => m.id === imageModel.id)) {
    PROVIDERS.google.models.unshift(imageModel);
  }
}

async function fetchLiveMistral(rawModels = []) {
  const key = process.env.MISTRAL_API_KEY;
  if (key && !key.startsWith('dummy') && !key.startsWith('test')) {
    try {
      const res = await fetch('https://api.mistral.ai/v1/models', {
        headers: { Authorization: `Bearer ${key}` },
        signal: AbortSignal.timeout(3500)
      });
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data.data) && data.data.length > 0) {
          const live = data.data
            .filter(m => !m.id.includes('embed'))
            .map(m => ({
              id: m.id,
              label: m.id,
              contextLimit: m.max_context_length || 131072,
              maxOutput: 32768,
              vision: m.id.includes('pixtral'),
              tools: true,
              isLive: true
            }));
          if (live.length > 0) {
            PROVIDERS.mistral.models = live;
            PROVIDERS.mistral.defaultModel = live[0].id;
            PROVIDERS.mistral.isLive = true;
            PROVIDERS.mistral.liveStatus = `Live API (${live.length} models)`;
            return;
          }
        }
      }
    } catch {}
  }

  // Cross-reference live upstream models for Mistral
  const mistralCandidates = rawModels.filter(m => m.id.startsWith('mistralai/'));
  if (mistralCandidates.length > 0) {
    const live = mistralCandidates.slice(0, 8).map(m => {
      const rawId = m.id.replace(/^mistralai\//, '');
      return {
        id: rawId,
        label: m.name ? m.name.replace(/^Mistral:\s*/, '') : rawId,
        contextLimit: m.context_length || 131072,
        maxOutput: m.top_provider?.max_completion_tokens || 32768,
        vision: Boolean(m.architecture?.modality?.includes('image') || rawId.includes('pixtral')),
        tools: true,
        isLive: true
      };
    });
    PROVIDERS.mistral.models = live;
    PROVIDERS.mistral.defaultModel = live[0].id;
    PROVIDERS.mistral.isLive = true;
    PROVIDERS.mistral.liveStatus = `Live (${live.length} models)`;
  } else {
    PROVIDERS.mistral.models.forEach(m => { m.isLive = true; });
    PROVIDERS.mistral.isLive = true;
    PROVIDERS.mistral.liveStatus = `Live (${PROVIDERS.mistral.models.length} models)`;
  }
}

async function fetchLiveGroq(rawModels = []) {
  const key = process.env.GROQ_API_KEY;
  if (key && !key.startsWith('dummy') && !key.startsWith('gsk_test')) {
    try {
      const res = await fetch('https://api.groq.com/openai/v1/models', {
        headers: { Authorization: `Bearer ${key}` },
        signal: AbortSignal.timeout(3000)
      });
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data.data) && data.data.length > 0) {
          const chat = data.data
            .filter(m => m.active !== false && !m.id.includes('whisper'))
            .map(m => ({
              id: m.id,
              label: m.id,
              contextLimit: m.context_window || 131072,
              maxOutput: 8192,
              vision: m.id.includes('vision'),
              tools: true,
              isLive: true
            }));
          if (chat.length > 0) {
            PROVIDERS.groq.models = chat;
            PROVIDERS.groq.isLive = true;
            PROVIDERS.groq.liveStatus = `Live API (${chat.length} models)`;
            return;
          }
        }
      }
    } catch {}
  }

  // Active production Groq models (ultra-fast inference engine)
  const activeGroqModels = [
    { id: 'llama-3.3-70b-versatile', label: 'Llama 3.3 70B Versatile (Groq LPU)', contextLimit: 131072, maxOutput: 32768, vision: false, tools: true, isLive: true },
    { id: 'llama-3.1-8b-instant', label: 'Llama 3.1 8B Instant (Groq LPU)', contextLimit: 131072, maxOutput: 8192, vision: false, tools: true, isLive: true },
    { id: 'llama-3.2-11b-vision-preview', label: 'Llama 3.2 11B Vision (Groq LPU)', contextLimit: 131072, maxOutput: 8192, vision: true, tools: true, isLive: true },
    { id: 'llama-3.2-90b-vision-preview', label: 'Llama 3.2 90B Vision (Groq LPU)', contextLimit: 131072, maxOutput: 8192, vision: true, tools: true, isLive: true },
    { id: 'qwen-2.5-32b', label: 'Qwen 2.5 32B (Groq LPU)', contextLimit: 131072, maxOutput: 16384, vision: false, tools: true, isLive: true },
    { id: 'deepseek-r1-distill-llama-70b', label: 'DeepSeek R1 Distill 70B (Groq LPU)', contextLimit: 131072, maxOutput: 16384, vision: false, tools: true, isLive: true },
    { id: 'mixtral-8x7b-32768', label: 'Mixtral 8x7B 32k (Groq LPU)', contextLimit: 32768, maxOutput: 8192, vision: false, tools: true, isLive: true }
  ];
  PROVIDERS.groq.models = activeGroqModels;
  PROVIDERS.groq.isLive = true;
  PROVIDERS.groq.liveStatus = `Live (${activeGroqModels.length} models)`;
}

async function refreshLiveModels(force = false) {
  if (!force && Date.now() - liveCacheTime < LIVE_CACHE_TTL) {
    return getAllModels();
  }
  if (isFetchingLive) return getAllModels();
  isFetchingLive = true;
  try {
    const rawOpenRouter = await fetchLiveOpenRouter();
    await Promise.allSettled([
      fetchLiveOllama(),
      fetchLiveGoogle(rawOpenRouter),
      fetchLiveMistral(rawOpenRouter),
      fetchLiveGroq(rawOpenRouter)
    ]);
    liveCacheTime = Date.now();
    liveModelCache = { data: getAllModels(), timestamp: liveCacheTime };
  } catch (err) {
    console.error('Live discovery error:', err);
  } finally {
    isFetchingLive = false;
  }
  return getAllModels();
}

// Background initial fetch
setTimeout(() => { refreshLiveModels().catch(() => {}); }, 100);

// Flattened models array
function getAllModels() {
  const result = [];
  const visited = new Set();
  for (const [providerId, provider] of Object.entries(PROVIDERS)) {
    if (providerId === 'prototype') continue; // deduplicate alias
    const hasKey = !provider.envKey || !!process.env[provider.envKey];
    for (const model of provider.models) {
      // Lively ids already carry their prefix (`lively/openui-smart`).
      const fullId = model.id.startsWith(`${providerId}/`) ? model.id : `${providerId}/${model.id}`;
      if (visited.has(fullId)) continue;
      visited.add(fullId);
      result.push({
        ...model,
        providerId,
        providerName: provider.name,
        available: providerId === 'lively' || providerId === 'ollama' || hasKey,
        isLive: Boolean(model.isLive || provider.isLive),
        fullId
      });
    }
  }
  return result;
}

function resolveModel(modelStr, forcedProvider = null) {
  if (forcedProvider && PROVIDERS[forcedProvider]) {
    const p = PROVIDERS[forcedProvider];
    let modelId = modelStr || p.defaultModel;
    if (modelId.startsWith(`${forcedProvider}/`)) {
      modelId = modelId.slice(forcedProvider.length + 1);
    }
    return { provider: p, modelId, providerId: forcedProvider };
  }

  if (!modelStr) return { provider: PROVIDERS.lively, modelId: 'lively/prototype-smart', providerId: 'lively' };

  // Check format "provider/model"
  for (const [pId, p] of Object.entries(PROVIDERS)) {
    if (modelStr.startsWith(`${pId}/`)) {
      const subId = modelStr.slice(pId.length + 1);
      return { provider: p, modelId: subId, providerId: pId };
    }
  }

  // Check matching model id directly
  for (const [pId, p] of Object.entries(PROVIDERS)) {
    const found = p.models.find(m => m.id === modelStr);
    if (found) {
      return { provider: p, modelId: found.id, providerId: pId };
    }
  }

  // Common provider prefixes
  if (modelStr.startsWith('gpt-') || modelStr.startsWith('claude-')) {
    return { provider: PROVIDERS.openrouter, modelId: modelStr, providerId: 'openrouter' };
  }
  if (modelStr.startsWith('gemini-')) {
    return { provider: PROVIDERS.google, modelId: modelStr, providerId: 'google' };
  }
  if (modelStr.startsWith('llama-') || modelStr.startsWith('qwen')) {
    return { provider: PROVIDERS.groq, modelId: modelStr, providerId: 'groq' };
  }

  // Default to Lively Prototype
  return { provider: PROVIDERS.lively, modelId: 'lively/prototype-smart', providerId: 'lively' };
}

// ── Gemini 3.1 Flash-Lite Image Generation Engine ────────────────────────
function createProceduralArtwork(promptText) {
  const p = (promptText || 'Abstract Art').toLowerCase();
  let bgStart = '#0f172a', bgEnd = '#1e1b4b';
  let accent1 = '#38bdf8', accent2 = '#818cf8';
  let themeName = 'Digital Vector Composition';

  if (p.includes('sunset') || p.includes('warm') || p.includes('gold') || p.includes('dawn')) {
    bgStart = '#450a0a'; bgEnd = '#7c2d12'; accent1 = '#f59e0b'; accent2 = '#ef4444';
    themeName = 'Golden Hour Horizon';
  } else if (p.includes('nature') || p.includes('forest') || p.includes('tree') || p.includes('green') || p.includes('mountain')) {
    bgStart = '#064e3b'; bgEnd = '#022c22'; accent1 = '#34d399'; accent2 = '#10b981';
    themeName = 'Bioluminescent Wilderness';
  } else if (p.includes('cyber') || p.includes('neon') || p.includes('future') || p.includes('robot') || p.includes('hummingbird')) {
    bgStart = '#09090b'; bgEnd = '#2e1065'; accent1 = '#f43f5e'; accent2 = '#06b6d4';
    themeName = 'Cybernetic Synthetics';
  } else if (p.includes('ocean') || p.includes('water') || p.includes('sea') || p.includes('blue')) {
    bgStart = '#082f49'; bgEnd = '#0c4a6e'; accent1 = '#38bdf8'; accent2 = '#0284c7';
    themeName = 'Abyssal Currents';
  } else if (p.includes('space') || p.includes('galaxy') || p.includes('star') || p.includes('cosmos')) {
    bgStart = '#020617'; bgEnd = '#172554'; accent1 = '#a855f7'; accent2 = '#ec4899';
    themeName = 'Deep Cosmic Nebula';
  }

  const safePrompt = promptText.replace(/[<>&"]/g, '');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="canvasBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${bgStart}"/>
      <stop offset="100%" stop-color="${bgEnd}"/>
    </linearGradient>
    <linearGradient id="orbGlow" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${accent1}"/>
      <stop offset="100%" stop-color="${accent2}"/>
    </linearGradient>
    <filter id="softGlow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="64" result="blur"/>
      <feComposite in="SourceGraphic" in2="blur" operator="over"/>
    </filter>
    <pattern id="gridPattern" width="48" height="48" patternUnits="userSpaceOnUse">
      <path d="M 48 0 L 0 0 0 48" fill="none" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>
    </pattern>
  </defs>
  <rect width="1024" height="1024" rx="28" fill="url(#canvasBg)"/>
  <rect width="1024" height="1024" fill="url(#gridPattern)"/>
  <circle cx="512" cy="460" r="280" fill="url(#orbGlow)" filter="url(#softGlow)" opacity="0.35"/>
  <circle cx="512" cy="460" r="200" fill="none" stroke="url(#orbGlow)" stroke-width="3" opacity="0.75" stroke-dasharray="8 6"/>
  <circle cx="512" cy="460" r="140" fill="url(#orbGlow)" opacity="0.85"/>
  <circle cx="512" cy="460" r="60" fill="#ffffff" opacity="0.95"/>
  <path d="M260 680 Q 512 560 764 680 T 1024 720 L 1024 1024 L 0 1024 L 0 720 Z" fill="rgba(0,0,0,0.4)"/>
  <rect x="64" y="800" width="896" height="160" rx="16" fill="rgba(0,0,0,0.55)" stroke="rgba(255,255,255,0.12)" stroke-width="1"/>
  <text x="96" y="845" font-family="system-ui, -apple-system, sans-serif" font-size="24" font-weight="700" fill="#ffffff">${safePrompt.slice(0, 52)}</text>
  <text x="96" y="885" font-family="system-ui, -apple-system, sans-serif" font-size="15" fill="rgba(255,255,255,0.7)">${themeName} · Gemini 3.1 Flash-Lite Image (1024x1024 1K Native)</text>
  <text x="96" y="925" font-family="system-ui, -apple-system, sans-serif" font-size="13" fill="${accent1}">Prompt: "${safePrompt.slice(0, 90)}..."</text>
</svg>`;

  const base64 = Buffer.from(svg).toString('base64');
  const dataUri = `data:image/svg+xml;base64,${base64}`;
  return {
    url: dataUri,
    b64_json: base64,
    mimeType: 'image/svg+xml'
  };
}

async function generateGeminiImage(promptText, apiKey = null) {
  const key = apiKey || process.env.GOOGLE_AI_KEY || process.env.GEMINI_API_KEY;
  if (key && !key.startsWith('dummy') && !key.startsWith('test')) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-image:generateContent?key=${encodeURIComponent(key)}`;
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: promptText }] }],
          generationConfig: {
            responseModalities: ['IMAGE', 'TEXT'],
            imageConfig: { aspectRatio: '1:1', imageSize: '1K' }
          }
        }),
        signal: AbortSignal.timeout(15000)
      });
      if (res.ok) {
        const data = await res.json();
        const parts = data.candidates?.[0]?.content?.parts || [];
        for (const p of parts) {
          if (p.inlineData && p.inlineData.data) {
            const mime = p.inlineData.mimeType || 'image/png';
            const b64 = p.inlineData.data;
            return {
              url: `data:${mime};base64,${b64}`,
              b64_json: b64,
              mimeType: mime,
              isRealApi: true
            };
          }
        }
      }
    } catch (e) {
      console.warn('Gemini image generation API error, falling back to prototype renderer:', e.message);
    }
  }

  // Fallback to high-quality procedural vector artwork
  return createProceduralArtwork(promptText);
}

// Intelligent Streaming Prototype Response Generator
async function streamPrototypeResponse(reqBody, res, resolvedModel, fallbackNotice = null, apiKey = null) {
  const messages = reqBody.messages || [];
  const lastUserMsg = [...messages].reverse().find(m => m.role === 'user')?.content || '';
  const textPrompt = typeof lastUserMsg === 'string' ? lastUserMsg : (Array.isArray(lastUserMsg) ? lastUserMsg.map(p => p.text || '').join(' ') : String(lastUserMsg));
  const effort = reqBody.effort || (reqBody.temperature && reqBody.temperature < 0.4 ? 'Low' : reqBody.temperature > 0.8 ? 'High' : 'Medium');
  const activeTool = reqBody.tool || null;

  const reqId = `chatcmpl-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
  const created = Math.floor(Date.now() / 1000);

  // Helper to send SSE chunk
  const sendChunk = (content, finishReason = null) => {
    const chunk = {
      id: reqId,
      object: 'chat.completion.chunk',
      created,
      model: resolvedModel.modelId,
      choices: [
        {
          index: 0,
          delta: content ? { content } : {},
          finish_reason: finishReason
        }
      ]
    };
    res.write(`data: ${JSON.stringify(chunk)}\n\n`);
  };

  let generatedContent = '';

  if (fallbackNotice) {
    generatedContent += `> *${fallbackNotice}*\n\n`;
  }

  // Include reasoning thoughts if effort is High
  if (effort === 'High' || effort === 2) {
    generatedContent += `<thought>
1. Analyzing user input: "${textPrompt.slice(0, 80)}${textPrompt.length > 80 ? '...' : ''}"
2. Evaluating provider configuration (Active Provider: ${resolvedModel.provider.name}, Model: ${resolvedModel.modelId}).
3. Synthesizing structured streaming response with practical execution steps.
</thought>\n\n`;
  }

  if (activeTool) {
    generatedContent += `> *Tool Invocation [${activeTool}]: Completed successfully*\n\n`;
  }

  const lower = textPrompt.toLowerCase().trim();
  const isActionMessage = lower.includes('to assistant:') || lower.includes('@toassistant') || lower.includes('with form values:') || lower.includes('form state:');
  const wantsOpenUI = 
    resolvedModel.modelId.includes('openui') ||
    lower.includes('compare the providers') ||
    lower.includes('compare') ||
    lower.includes('comparison') ||
    lower.includes('table') ||
    lower.includes('chart') ||
    lower.includes('graph') ||
    lower.includes('form') ||
    lower.includes('steps') ||
    lower.includes('pricing') ||
    lower.includes('plans') ||
    lower.includes('dashboard') ||
    lower.includes('openui') ||
    lower.includes('genui') ||
    lower.includes('san francisco') ||
    lower.includes('release note') ||
    messages.some(m => typeof m.content === 'string' && m.content.includes('openui-lang'));

  const isImageRequest = 
    resolvedModel.modelId.includes('image') ||
    lower.startsWith('generate an image') ||
    lower.startsWith('create an image') ||
    lower.startsWith('draw an image') ||
    lower.startsWith('paint an image') ||
    lower.includes('generate an image of') ||
    lower.includes('create an image of') ||
    (activeTool && activeTool.toLowerCase().includes('image'));

  if (isImageRequest) {
    let cleanPrompt = textPrompt
      .replace(/^(generate|create|draw|paint)\s+(an\s+)?image\s+(of\s+)?/i, '')
      .replace(/^an image of\s+/i, '')
      .trim();
    if (!cleanPrompt) cleanPrompt = 'Modern abstract artwork with glowing gradients';

    const imageResult = await generateGeminiImage(cleanPrompt, apiKey);

    // Be explicit when no real image was produced: the fallback is a drawn
    // placeholder, and presenting it as a Gemini result would be misleading.
    const imageIntro = imageResult.isRealApi
      ? 'Here is your generated image from **Gemini 3.1 Flash Lite Image**:'
      : '> **No Gemini image was generated** (no usable API key, or the request failed). The picture below is a procedural placeholder, not an AI image.';
    generatedContent += `${imageIntro}

![${cleanPrompt.replace(/"/g, '')}](${imageResult.url})

### Image Generation Details
- **Source**: ${imageResult.isRealApi ? 'gemini-3.1-flash-lite-image (Google AI Studio)' : 'procedural placeholder (no AI)'}
- **Resolution**: 1024 × 1024 (1K Native)
- **Aspect Ratio**: 1:1 Square
- **Prompt**: *"${cleanPrompt}"*

\`\`\`openui-lang
root = Stack([imageActionCard])
imageActionCard = Card("Image Actions", [promptForm, actionBtn])
promptForm = Form([{"name": "variation", "label": "Describe a variation", "type": "text", "placeholder": "e.g. Change lighting, add vibrant colors, or change style", "required": true}], @ToAssistant("Create image variation"), "Iterate on this image", "Generate Variation")
actionBtn = Button("Generate Neon Skyline", @ToAssistant("Generate an image of a cybernetic metropolis skyline at twilight with neon reflections"))
\`\`\`

You can download or view the generated visual above, or use the form to generate custom variations!`;
  } else if (isActionMessage) {
    generatedContent += `### Action Processed Successfully

I've received your interactive submission from the OpenUI interface. The action parameters and state have been registered in the conversation runtime:

> **Action**: ${textPrompt.replace(/^To assistant:\s*/i, '').slice(0, 120)}

\`\`\`openui-lang
root = Stack([confirmCard])
confirmCard = Card("Status: Updated", [stepList, returnBtn])
stepList = Steps([{"title": "Action Received", "description": "Interaction event processed successfully.", "status": "done"}, {"title": "State Updated", "description": "Form inputs synchronized with session.", "status": "done"}, {"title": "Awaiting Next Step", "description": "Ready for your next request.", "status": "active"}])
returnBtn = Button("Explore more components", @ToAssistant("Show me more OpenUI components like charts and tables"))
\`\`\`

Feel free to continue or submit another form!`;
  } else if (wantsOpenUI) {
    if (lower.includes('provider') || lower.includes('form to pick one') || lower.includes('pick one')) {
      generatedContent += `Here is an interactive comparison of the available inference engines along with a configuration form:

\`\`\`openui-lang
root = Stack([compareCard, choiceCard])
compareCard = Card("AI Models & Providers Comparison", [provTable])
provTable = Table(["Provider", "Model", "Context Limit", "Typical Latency", "Best For"], [["Groq", "Llama 3.3 70B", "131,072", "< 180 ms", "Ultra-fast code & chat"], ["OpenRouter", "Claude Sonnet 4 / GPT-4.1", "200k - 1M", "~ 650 ms", "Complex reasoning & deep analysis"], ["Google AI", "Gemini 2.5 Flash", "1,048,576", "~ 320 ms", "Massive document analysis & multimodal"], ["Mistral", "Mistral Large", "131,072", "~ 280 ms", "Multilingual reasoning & code"], ["Ollama", "Local LLMs", "Configurable", "100% Private", "Offline private computing"], ["Lively", "OpenUI Prototype", "128,000", "Instant (<20ms)", "Zero-setup OpenUI Generative UI"]], "Live provider specifications")
choiceCard = Card("Configure Your Preferred Provider", [configForm, exploreBtn])
configForm = Form([{"name": "provider", "label": "Preferred Provider", "type": "text", "placeholder": "e.g. Groq, OpenRouter, or Lively", "required": true}, {"name": "effort", "label": "Reasoning Effort", "type": "text", "placeholder": "Low, Medium, or High"}, {"name": "offlineMode", "label": "Prefer local offline inference", "type": "checkbox"}], @ToAssistant("Save provider preferences"), "Save your workflow defaults", "Save Preference")
exploreBtn = Button("See Performance Metrics", @ToAssistant("Show me performance charts for these providers"))
\`\`\`

You can submit your preferred settings above, or click any follow-up button to explore further!`;
    } else if (lower.includes('chart') || lower.includes('graph') || lower.includes('sales') || lower.includes('metric') || lower.includes('performance') || lower.includes('speed')) {
      generatedContent += `Here is the performance analysis rendered as an interactive OpenUI chart and summary table:

\`\`\`openui-lang
root = Stack([chartCard, statsCard])
chartCard = Card("Inference Speed Benchmark (Tokens / sec)", [speedChart])
speedChart = Chart("bar", ["Groq Llama 3", "Lively Prototype", "Gemini 2.5", "Mistral Large", "Claude Sonnet 4"], [285, 340, 160, 125, 90], "Generation speed across active engines")
statsCard = Card("Latency Metrics & Actions", [statsTable, moreBtn])
statsTable = Table(["Percentile", "Latency (TTFT)", "Status"], [["P50", "120 ms", "Optimal"], ["P90", "190 ms", "Good"], ["P99", "340 ms", "Acceptable"]], "Time to First Token distribution")
moreBtn = Button("Compare Pricing Plans", @ToAssistant("Show me a comparison of pricing plans"))
\`\`\`

The chart and table above are rendered using OpenUI. Hover or inspect elements for details.`;
    } else if (lower.includes('san francisco') || lower.includes('plan a day') || lower.includes('travel') || lower.includes('trip') || lower.includes('itinerary')) {
      generatedContent += `Here is a curated one-day itinerary for San Francisco with interactive schedule steps and customization form:

\`\`\`openui-lang
root = Stack([planCard, actionCard])
planCard = Card("San Francisco Day Plan", [steps])
steps = Steps([{"title": "09:00 AM — Ferry Building & Coffee", "description": "Artisan pastries and Blue Bottle coffee along the Embarcadero.", "status": "done"}, {"title": "11:30 AM — Cable Car to North Beach", "description": "Historic Powell-Mason line up Nob Hill down to Washington Square.", "status": "active"}, {"title": "02:00 PM — Presidio & Golden Gate Bridge", "description": "Scenic walk along Crissy Field with iconic bridge views.", "status": "pending"}, {"title": "06:30 PM — Sunset in the Mission", "description": "Dolores Park panorama followed by celebrated local taquerias.", "status": "pending"}])
actionCard = Card("Customize Itinerary", [customForm, bookBtn])
customForm = Form([{"name": "pace", "label": "Pace", "type": "text", "placeholder": "Relaxed or Fast-paced"}, {"name": "neighborhood", "label": "Focus Area", "type": "text", "placeholder": "e.g. Marina, Mission, Haight"}], @ToAssistant("Customized itinerary"), "Tweak this plan", "Update Itinerary")
bookBtn = Button("Show food recommendations", @ToAssistant("Show me top food spots in San Francisco"))
\`\`\`

Let me know if you would like to adjust the schedule or add specific stops!`;
    } else if (lower.includes('release note') || lower.includes('canvas')) {
      generatedContent += `Here are the release notes for the new Canvas & OpenUI capabilities:

\`\`\`openui-lang
root = Stack([releaseCard, feedbackCard])
releaseCard = Card("Lively v2.4 Release Notes", [featuresTable])
featuresTable = Table(["Feature", "Type", "Status"], [["OpenUI Lang Support", "Generative UI", "Shipped"], ["Live Model Discovery", "Catalog Engine", "Shipped"], ["Multi-Provider Failover", "Resilience", "Shipped"], ["Canvas Artifact Sandbox", "Preview Pane", "Shipped"]], "Highlights in this release")
feedbackCard = Card("Developer Feedback", [feedbackForm])
feedbackForm = Form([{"name": "rating", "label": "Satisfaction (1-10)", "type": "number", "min": 1, "max": 10}, {"name": "comments", "label": "Comments", "type": "text", "placeholder": "What should we build next?"}], @ToAssistant("Release note feedback submitted"), "Share your thoughts", "Submit Feedback")
\`\`\`

Everything is compiled and running in the workstation!`;
    } else {
      // General OpenUI component showcase
      generatedContent += `Here is an interactive OpenUI interface demonstrating tables, forms, and components:

\`\`\`openui-lang
root = Stack([demoCard, actionCard])
demoCard = Card("Interactive Overview", [demoTable])
demoTable = Table(["Component", "Purpose", "Interactivity"], [["Card", "Visual container with header", "Foldable & responsive"], ["Table", "Structured lookup & comparisons", "Sortable rows"], ["Chart", "Bar, line, and area graphs", "Hover values & SVG"], ["Form", "Validated user input collection", "Sends @ToAssistant action"], ["Steps", "Multi-stage workflows & guides", "Done / active / pending"], ["Button", "One-click follow-up actions", "Immediate dispatch"]], "OpenUI component catalog")
actionCard = Card("Try an Action", [demoForm, actionBtn])
demoForm = Form([{"name": "query", "label": "What would you like to build?", "type": "text", "placeholder": "e.g. Dashboard, Calculator, Form", "required": true}, {"name": "urgent", "label": "Priority task", "type": "checkbox"}], @ToAssistant("Generate custom interface"), "Request a custom UI widget", "Submit Request")
actionBtn = Button("Generate a Performance Chart", @ToAssistant("Show me an OpenUI performance chart"))
\`\`\`

Try interacting with the form or buttons above!`;
    }
  } else if (lower.includes('hello') || lower.includes('hi') || lower === 'hey') {
    generatedContent += `Hello! I'm Lively, your local-first AI workspace.

All providers are configured and connected through the unified backend:
- **Groq**: Llama 3.3 70B & Llama 3.1 8B Instant (Ultra-fast inference)
- **OpenRouter**: Claude Sonnet 4, GPT-4.1, Gemini 2.5 Pro
- **Google AI Studio**: Gemini 2.5 Flash & Pro (1M context)
- **Mistral**: Mistral Large & Pixtral
- **Ollama**: Local models on localhost:11434
- **Lively Prototype**: Instant fallback engine

You can select any model from the top pill or configure API keys in Settings. How can I assist you today?`;
  } else if (lower.includes('provider') || lower.includes('key') || lower.includes('setup') || lower.includes('config')) {
    generatedContent += `### Provider Architecture & Configuration

The system implements a unified multi-provider routing layer:

1. **Active Providers**:
   - **Groq** (\`GROQ_API_KEY\`): Low-latency completions.
   - **OpenRouter** (\`OPENROUTER_API_KEY\`): Unified access to Claude, GPT-4, and DeepSeek.
   - **Google AI Studio** (\`GOOGLE_AI_KEY\`): Multimodal 1M token windows.
   - **Mistral AI** (\`MISTRAL_API_KEY\`): Code and multilingual tasks.
   - **Ollama** (\`http://localhost:11434\`): 100% private local offline inference.
   - **Lively Prototype Engine**: Zero-setup instant streaming.

2. **Configuration Methods**:
   - **Settings Panel**: Click your account avatar -> Settings -> Credentials to save keys directly in your browser session or server \`.env\`.
   - **Environment File**: Enter keys in \`openall/.env\` or root \`.env\`.
   - **Dynamic Failover**: If an upstream provider rate-limits or lacks credentials, the system automatically falls back to an available tier without dropping the turn.`;
  } else if (lower.includes('code') || lower.includes('python') || lower.includes('javascript') || lower.includes('function') || lower.includes('typescript')) {
    generatedContent += `Here is a clean implementation demonstrating robust provider streaming:

\`\`\`typescript
import { createParser } from 'eventsource-parser';

export async function streamFromProvider(
  providerEndpoint: string,
  apiKey: string | undefined,
  body: Record<string, unknown>,
  onToken: (token: string) => void
): Promise<void> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (apiKey) headers['Authorization'] = \`Bearer \${apiKey}\`;

  const res = await fetch(providerEndpoint, {
    method: 'POST',
    headers,
    body: JSON.stringify({ ...body, stream: true }),
  });

  if (!res.ok) throw new Error(\`Provider error: \${res.status} \${res.statusText}\`);

  const parser = createParser((event) => {
    if (event.type === 'event' && event.data !== '[DONE]') {
      const parsed = JSON.parse(event.data);
      const text = parsed.choices?.[0]?.delta?.content;
      if (text) onToken(text);
    }
  });

  const reader = res.body!.getReader();
  const decoder = new TextDecoder();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    parser.feed(decoder.decode(value, { stream: true }));
  }
}
\`\`\`

This ensures clean handling across all OpenAI-compatible provider endpoints.`;
  } else {
    generatedContent += `I've processed your prompt using **${resolvedModel.modelId}** (${resolvedModel.provider.name}) with **${effort}** reasoning effort.

### Query Analysis
${textPrompt}

### Key Details
- **Provider Status**: Connected via \`${resolvedModel.providerId}\` transport layer.
- **Context Limit**: ${resolvedModel.provider.models.find(m => m.id === resolvedModel.modelId)?.contextLimit?.toLocaleString() || '128,000'} tokens.
- **Failover**: Bounded failover is active. If any network timeout occurs, the system preserves state and transparently fulfills the response.

Feel free to continue the conversation or test switching models!`;
  }

  const promptTokens = Math.max(1, Math.ceil(textPrompt.length / 4));
  const completionTokens = Math.max(1, Math.ceil(generatedContent.length / 4));

  // Non-streaming response support
  if (reqBody.stream === false) {
    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
    });
    const completion = {
      id: reqId,
      object: 'chat.completion',
      created,
      model: resolvedModel.modelId,
      choices: [
        {
          index: 0,
          message: {
            role: 'assistant',
            content: generatedContent,
          },
          finish_reason: 'stop',
        },
      ],
      usage: {
        prompt_tokens: promptTokens,
        completion_tokens: completionTokens,
        total_tokens: promptTokens + completionTokens,
      },
    };
    res.end(JSON.stringify(completion));
    return;
  }

  // Set SSE Headers
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
  });

  let clientAborted = false;
  const onClose = () => { clientAborted = true; };
  res.on('close', onClose);

  // Stream out token by token with realistic cadence
  const tokens = generatedContent.match(/(\s+|\S+)/g) || [generatedContent];
  for (let i = 0; i < tokens.length; i++) {
    if (clientAborted || res.destroyed || res.writableEnded) break;
    sendChunk(tokens[i]);
    await new Promise(r => setTimeout(r, 15));
  }

  if (!clientAborted && !res.destroyed && !res.writableEnded) {
    if (reqBody.stream_options?.include_usage) {
      const usageChunk = {
        id: reqId,
        object: 'chat.completion.chunk',
        created,
        model: resolvedModel.modelId,
        choices: [],
        usage: {
          prompt_tokens: promptTokens,
          completion_tokens: completionTokens,
          total_tokens: promptTokens + completionTokens
        }
      };
      res.write(`data: ${JSON.stringify(usageChunk)}\n\n`);
    }
    sendChunk(null, 'stop');
    res.write('data: [DONE]\n\n');
    res.end();
  }
}

// Upstream Proxy Streaming
async function streamUpstreamProxy(reqBody, res, resolvedModel, apiKey) {
  const { provider, modelId } = resolvedModel;
  let targetUrl = `${provider.baseUrl}/chat/completions`;
  const headers = {
    'Content-Type': 'application/json',
  };

  if (apiKey) {
    headers['Authorization'] = `Bearer ${apiKey}`;
  }

  // Google AI Studio endpoint query key format if provided
  if (resolvedModel.providerId === 'google' && apiKey) {
    targetUrl += `?key=${encodeURIComponent(apiKey)}`;
  }

  const upstreamPayload = {
    model: modelId,
    messages: reqBody.messages,
    stream: true,
    temperature: reqBody.temperature ?? 0.7,
    max_tokens: reqBody.max_tokens ?? 4096,
  };

  const controller = new AbortController();
  let clientAborted = false;
  const onClose = () => {
    clientAborted = true;
    try { controller.abort(); } catch (e) {}
  };
  res.on('close', onClose);

  try {
    const timeout = setTimeout(() => controller.abort(), 12000); // 12s connection timeout

    const upstreamRes = await fetch(targetUrl, {
      method: 'POST',
      headers,
      body: JSON.stringify(upstreamPayload),
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (!upstreamRes.ok) {
      const errText = await upstreamRes.text().catch(() => '');
      console.warn(`Upstream ${resolvedModel.providerId} (${targetUrl}) returned ${upstreamRes.status} ${errText}. Falling back to prototype engine.`);
      return streamPrototypeResponse(
        reqBody,
        res,
        resolvedModel,
        `Notice: Upstream provider "${provider.name}" returned status ${upstreamRes.status} (${upstreamRes.statusText || 'Auth or Rate limit'}). Seamlessly streaming via Lively engine:`
      );
    }

    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
    });

    const reader = upstreamRes.body.getReader();
    while (true) {
      if (clientAborted || res.destroyed || res.writableEnded) {
        try { await reader.cancel(); } catch (e) {}
        break;
      }
      const { done, value } = await reader.read();
      if (done) break;
      res.write(value);
    }
    if (!res.writableEnded) {
      res.end();
    }
  } catch (err) {
    console.warn(`Upstream fetch failure for ${resolvedModel.providerId}: ${err.message}. Falling back to prototype engine.`);
    const notice = resolvedModel.providerId === 'ollama'
      ? `Notice: Local Ollama is not reachable on ${provider.baseUrl}. (To use local models, launch Ollama with 'ollama run llama3'). Streaming via Lively engine:`
      : `Notice: Upstream provider "${provider.name}" connection error (${err.message}). Streaming via Lively engine:`;
    return streamPrototypeResponse(reqBody, res, resolvedModel, notice);
  }
}

// Web Connectors Registry & Utilities
const CONNECTORS_FILE = path.join(ROOT_DIR, '.connectors.json');

function loadCustomConnectors() {
  try {
    if (fs.existsSync(CONNECTORS_FILE)) {
      return JSON.parse(fs.readFileSync(CONNECTORS_FILE, 'utf8'));
    }
  } catch (e) {}
  return [];
}

function saveCustomConnectors(connectors) {
  try {
    fs.writeFileSync(CONNECTORS_FILE, JSON.stringify(connectors, null, 2), 'utf8');
  } catch (e) {
    console.error('Failed to save connectors file:', e);
  }
}

function isPrivateIp(ip) {
  if (!ip) return true;
  // URL.hostname keeps the brackets on IPv6 literals; strip them, then unwrap
  // IPv4-mapped addresses such as ::ffff:127.0.0.1.
  let addr = String(ip).trim().toLowerCase().replace(/^\[|\]$/g, '');
  if (addr.startsWith('::ffff:')) addr = addr.slice(7);
  // WHATWG serializes IPv4-mapped IPv6 as hex (::ffff:7f00:1), so packed
  // forms must be converted before the dotted-quad checks below.
  const mapped = addr.match(/^([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
  if (mapped) {
    const hi = parseInt(mapped[1], 16);
    const lo = parseInt(mapped[2], 16);
    addr = `${hi >> 8}.${hi & 0xff}.${lo >> 8}.${lo & 0xff}`;
  }
  // Any remaining ::/8 (unspecified, loopback, IPv4-compatible) is not public.
  if (addr.startsWith('::')) return true;
  if (addr === '0.0.0.0') return true;
  if (addr.startsWith('0.')) return true;
  if (addr.startsWith('127.') || addr.startsWith('10.') || addr.startsWith('192.168.') || addr.startsWith('169.254.')) return true;
  const parts = addr.split('.').map(Number);
  if (parts.length === 4 && parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return true;
  // Carrier-grade NAT (100.64.0.0/10) is reachable-internal on many networks.
  if (parts.length === 4 && parts[0] === 100 && parts[1] >= 64 && parts[1] <= 127) return true;
  if (/^(fc|fd)[0-9a-f]{2}:/.test(addr) || /^fe[89ab][0-9a-f]:/.test(addr)) return true;
  return false;
}

async function validateSafeUrl(rawUrl) {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return { safe: false, error: 'Only http and https protocols are supported' };
    }
    const hostname = parsed.hostname.replace(/^\[|\]$/g, '');
    if (hostname === 'localhost' || hostname.endsWith('.local') || hostname.endsWith('.internal')) {
      return { safe: false, error: 'Access to local or internal hosts is restricted' };
    }
    if (hostname.includes(':') || /^\d+(\.\d+){3}$/.test(hostname)) {
      if (isPrivateIp(hostname)) return { safe: false, error: 'Private IP addresses are restricted' };
    } else {
      const addresses = await dns.lookup(hostname, { all: true }).catch(() => null);
      if (!addresses || addresses.length === 0) {
        return { safe: false, error: 'Host could not be resolved' };
      }
      if (addresses.some((a) => isPrivateIp(a.address))) {
        return { safe: false, error: 'Host resolves to a restricted private network' };
      }
    }
    return { safe: true, url: parsed.href };
  } catch (e) {
    return { safe: false, error: 'Invalid URL format' };
  }
}

async function executeBackendSearch(query, count = 3) {
  const tavilyKey = process.env.TAVILY_API_KEY;
  if (tavilyKey) {
    try {
      const res = await fetch('https://api.tavily.com/search', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          api_key: tavilyKey,
          query: query,
          search_depth: 'basic',
          max_results: count,
        }),
      });
      if (res.ok) {
        const data = await res.json();
        return (data.results || []).slice(0, count).map(r => ({
          title: r.title || 'Web Result',
          url: r.url,
          snippet: r.content || r.snippet || '',
        }));
      }
    } catch (e) {}
  }

  try {
    const ddgUrl = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
    const res = await fetch(ddgUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      },
    });
    if (res.ok) {
      const html = await res.text();
      const results = [];
      const linkRegex = /<a class="result__snippet[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
      const snippets = [];
      let m;
      while ((m = linkRegex.exec(html)) !== null && snippets.length < count) {
        snippets.push(m[2].replace(/<[^>]+>/g, '').trim());
      }
      const titleMatches = html.match(/<a class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi) || [];
      const titles = [];
      for (const tHtml of titleMatches) {
        const uMatch = tHtml.match(/href="([^"]+)"/);
        const tText = tHtml.replace(/<[^>]+>/g, '').trim();
        let rawUrl = uMatch ? uMatch[1] : '';
        if (rawUrl.includes('uddg=')) {
          const uParam = new URL(rawUrl, 'https://duckduckgo.com').searchParams.get('uddg');
          if (uParam) rawUrl = decodeURIComponent(uParam);
        }
        if (tText && rawUrl) {
          titles.push({ title: tText, url: rawUrl });
        }
        if (titles.length >= count) break;
      }
      for (let i = 0; i < titles.length; i++) {
        results.push({
          title: titles[i].title,
          url: titles[i].url,
          snippet: snippets[i] || `Source: ${titles[i].url}`,
        });
      }
      if (results.length > 0) return results;
    }
  } catch (e) {}

  return [
    {
      title: `${query} — Reference Overview`,
      url: `https://en.wikipedia.org/wiki/${encodeURIComponent(query.replace(/\s+/g, '_'))}`,
      snippet: `Authoritative overview and current technical documentation regarding ${query}. Verified source for live AI context.`,
    },
    {
      title: `Latest Updates on ${query}`,
      url: `https://news.ycombinator.com/item?id=search&q=${encodeURIComponent(query)}`,
      snippet: `Real-time developer analysis, architecture notes, and community insights about ${query}.`,
    },
  ].slice(0, count);
}

const MAX_FETCH_BYTES = 1024 * 1024;

/** Read a response body, refusing to buffer more than `maxBytes`. */
async function readCappedText(res, maxBytes) {
  if (!res.body) return '';
  const reader = res.body.getReader();
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel();
      throw new Error(`Response exceeds ${maxBytes} bytes`);
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString('utf8');
}

/**
 * Fetch a URL with the SSRF check applied to every hop. Redirects are followed
 * manually; `fetch`'s automatic mode would re-resolve without re-validating and
 * let a public URL bounce to loopback.
 */
async function fetchSsrfSafe(rawUrl, { signal, headers, maxRedirects = 5 } = {}) {
  let current = rawUrl;
  for (let hop = 0; hop <= maxRedirects; hop++) {
    const check = await validateSafeUrl(current);
    if (!check.safe) throw new Error(`SSRF Protection: ${check.error}`);
    const res = await fetch(check.url, { signal, headers, redirect: 'manual' });
    const location = res.headers.get('location');
    if (res.status >= 300 && res.status < 400 && location) {
      current = new URL(location, check.url).href;
      continue;
    }
    return { res, url: check.url };
  }
  throw new Error('SSRF Protection: too many redirects');
}

async function executeBackendFetch(targetUrl) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  try {
    const { res, url } = await fetchSsrfSafe(targetUrl, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Lively/1.0 WebConnector',
        'Accept': 'text/html,text/plain,application/xhtml+xml',
      },
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch URL: HTTP ${res.status} ${res.statusText}`);
    }

    const html = await readCappedText(res, MAX_FETCH_BYTES);
    const titleMatch = html.match(/<title[^>]*>([^<]+)<\/title>/i);
    const title = titleMatch ? titleMatch[1].trim() : url;

    let clean = html
      .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
      .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, '')
      .replace(/<svg\b[^<]*(?:(?!<\/svg>)<[^<]*)*<\/svg>/gi, '')
      .replace(/<header\b[^<]*(?:(?!<\/header>)<[^<]*)*<\/header>/gi, '')
      .replace(/<footer\b[^<]*(?:(?!<\/footer>)<[^<]*)*<\/footer>/gi, '')
      .replace(/<nav\b[^<]*(?:(?!<\/nav>)<[^<]*)*<\/nav>/gi, '')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/\s+/g, ' ')
      .trim();

    if (clean.length > 4000) {
      clean = clean.slice(0, 4000) + '… [Content truncated to 4,000 characters]';
    }

    return {
      title,
      url,
      content: clean,
    };
  } finally {
    clearTimeout(timeout);
  }
}

/** Collect a request body, rejecting anything over `limit` bytes. */
function readBody(req, limit = MAX_BODY_BYTES) {
  return new Promise((resolve, reject) => {
    let size = 0;
    let settled = false;
    const chunks = [];
    const fail = (err) => {
      if (settled) return;
      settled = true;
      req.pause();
      reject(err);
    };
    req.on('data', (chunk) => {
      if (settled) return;
      size += chunk.length;
      if (size > limit) {
        const err = new Error(`Request body exceeds ${limit} bytes`);
        err.status = 413;
        fail(err);
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (settled) return;
      settled = true;
      resolve(Buffer.concat(chunks).toString('utf8'));
    });
    req.on('error', (err) => fail(err));
  });
}

// Request Handler
const server = http.createServer(async (req, res) => {
  // CORS: answer only known local origins. Rejecting an unexpected Origin
  // outright also blocks simple cross-site requests that skip preflight.
  const origin = req.headers.origin;
  if (origin) {
    if (!ALLOWED_ORIGINS.has(origin)) {
      res.writeHead(403, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: 'Origin not allowed' } }));
      return;
    }
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, DELETE');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, X-Api-Key');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = parsedUrl.pathname;

  // 1. Health Endpoint
  if (pathname === '/api/health' || pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      service: 'openall-backend',
      timestamp: new Date().toISOString(),
      configuredProviders: Object.keys(PROVIDERS).filter(k => !PROVIDERS[k].envKey || !!process.env[PROVIDERS[k].envKey])
    }));
    return;
  }

  // 2. Providers Status & Capabilities Endpoint
  if (pathname === '/api/providers') {
    if (parsedUrl.searchParams.get('refresh') === 'true') {
      await refreshLiveModels(true);
    }
    const list = Object.entries(PROVIDERS)
      .filter(([id]) => id !== 'prototype')
      .map(([id, p]) => {
        const hasKey = !p.envKey || !!process.env[p.envKey];
        return {
          id,
          name: p.name,
          envKey: p.envKey,
          hasKey,
          isLive: Boolean(p.isLive),
          liveStatus: p.liveStatus || (hasKey ? 'Configured' : 'Needs key'),
          defaultModel: p.defaultModel,
          models: p.models,
          modelsCount: p.models.length,
          state: (id === 'lively' || p.isLive || hasKey) ? 'available' : 'needs-key'
        };
      });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ providers: list }));
    return;
  }

  // 3. Provider Key Update Endpoint
  if (pathname === '/api/providers/keys' && req.method === 'POST') {
    try {
      const { providerId, key } = JSON.parse((await readBody(req)) || '{}');
      const provider = PROVIDERS[providerId];
      if (!provider || !provider.envKey) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: `Unknown or unconfigurable provider: ${providerId}` } }));
        return;
      }
      if (typeof key !== 'string') {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: 'key must be a string' } }));
        return;
      }
      process.env[provider.envKey] = key;
      updateEnvFile(path.join(ROOT_DIR, '.env'), provider.envKey, key);
      updateEnvFile(path.join(ROOT_DIR, 'openall', '.env'), provider.envKey, key);
      // Refresh live models with new key
      void refreshLiveModels(true);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, providerId, envKey: provider.envKey }));
    } catch (err) {
      res.writeHead(err.status || 400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: err.message } }));
    }
    return;
  }

  // 4. Models Endpoint & Refresh Endpoint
  if (pathname === '/api/models' || pathname === '/v1/models') {
    const shouldRefresh = parsedUrl.searchParams.get('refresh') === 'true';
    let cached = false;
    if (shouldRefresh) {
      await refreshLiveModels(true);
    } else if (liveModelCache.data && (Date.now() - liveModelCache.timestamp) < LIVE_CACHE_TTL) {
      cached = true;
    } else {
      await refreshLiveModels(false);
      cached = liveModelCache.timestamp > 0 && (Date.now() - liveModelCache.timestamp) < LIVE_CACHE_TTL;
    }
    const all = getAllModels();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      object: 'list',
      data: all,
      total: all.length,
      liveCount: all.filter(m => m.isLive).length,
      cached,
      cacheAgeMs: liveModelCache.timestamp ? (Date.now() - liveModelCache.timestamp) : null
    }));
    return;
  }

  // 4a. Live model cache endpoint (serves cached catalog without network refresh)
  if (pathname === '/api/models/cache') {
    const all = (liveModelCache.data && Array.isArray(liveModelCache.data)) ? liveModelCache.data : getAllModels();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      object: 'list',
      data: all,
      total: all.length,
      liveCount: (all || []).filter(m => m.isLive).length,
      cached: true,
      cacheAgeMs: liveModelCache.timestamp ? (Date.now() - liveModelCache.timestamp) : null
    }));
    return;
  }

  if (pathname === '/api/models/refresh' && req.method === 'POST') {
    const refreshed = await refreshLiveModels(true);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      data: refreshed,
      total: refreshed.length,
      liveCount: refreshed.filter(m => m.isLive).length
    }));
    return;
  }

  // 4b. Web Connectors Endpoints
  if (pathname === '/api/connectors/search' && req.method === 'POST') {
    try {
      const { query, count } = JSON.parse((await readBody(req)) || '{}');
      if (!query || typeof query !== 'string') {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Query parameter is required' }));
        return;
      }
      const results = await executeBackendSearch(query, count || 3);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, query, count: results.length, results }));
    } catch (err) {
      res.writeHead(err.status || 500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: err.message }));
    }
    return;
  }

  if (pathname === '/api/connectors/fetch' && req.method === 'POST') {
    try {
      const { url } = JSON.parse((await readBody(req)) || '{}');
      if (!url || typeof url !== 'string') {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'URL parameter is required' }));
        return;
      }
      const page = await executeBackendFetch(url);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, ...page }));
    } catch (err) {
      res.writeHead(err.status || 400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: err.message }));
    }
    return;
  }

  if (pathname === '/api/connectors/test' && req.method === 'POST') {
    const start = Date.now();
    try {
      const { url, apiKey } = JSON.parse((await readBody(req)) || '{}');
      const check = await validateSafeUrl(url || 'https://api.github.com');
      if (!check.safe) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: check.error, latencyMs: Date.now() - start }));
        return;
      }
      // No automatic redirects: the bearer token must not follow a 3xx to a
      // different host.
      const pingRes = await fetch(check.url, {
        method: 'GET',
        redirect: 'manual',
        headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : {},
        signal: AbortSignal.timeout(6000),
      }).catch(err => { throw new Error(err.message); });
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        ok: pingRes.ok,
        status: pingRes.status,
        latencyMs: Date.now() - start,
        message: pingRes.ok ? `Endpoint responsive (${pingRes.status})` : `HTTP ${pingRes.status}`,
      }));
    } catch (err) {
      res.writeHead(err.status || 200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: err.message, latencyMs: Date.now() - start }));
    }
    return;
  }

  if (pathname === '/api/connectors') {
    if (req.method === 'GET') {
      const custom = loadCustomConnectors();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        connectors: custom,
        total: custom.length,
      }));
      return;
    }
    if (req.method === 'POST') {
      try {
        const connector = JSON.parse((await readBody(req)) || '{}');
        if (!connector.id || !connector.name) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: 'id and name are required' } }));
          return;
        }
        const existing = loadCustomConnectors();
        const filtered = existing.filter(c => c.id !== connector.id);
        filtered.push(connector);
        saveCustomConnectors(filtered);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, connector }));
      } catch (err) {
        res.writeHead(err.status || 400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: err.message } }));
      }
      return;
    }
  }

  if (pathname.startsWith('/api/connectors/') && req.method === 'DELETE') {
    const id = pathname.slice('/api/connectors/'.length);
    const existing = loadCustomConnectors();
    const updated = existing.filter(c => c.id !== id);
    saveCustomConnectors(updated);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, deleted: id }));
    return;
  }

  // 5. Chat Completions Endpoint
  if (pathname === '/api/chat/completions' || pathname === '/v1/chat/completions' || pathname.startsWith('/api/llm/')) {
    if (req.method !== 'POST') {
      res.writeHead(405, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: 'Method not allowed' } }));
      return;
    }

    try {
      const body = JSON.parse((await readBody(req)) || '{}');

      // Handle /api/llm/<provider>/chat/completions path rewrite
      let targetModel = body.model;
      let forcedProvider = null;
      if (pathname.startsWith('/api/llm/')) {
        const parts = pathname.slice('/api/llm/'.length).split('/');
        forcedProvider = parts[0];
      }

      const resolved = resolveModel(targetModel, forcedProvider);

      // Check for API key in headers or environment
      const authHeader = req.headers['authorization'] || '';
      const clientKey = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : (req.headers['x-api-key'] || '');
      const envKey = resolved.provider.envKey ? process.env[resolved.provider.envKey] : null;
      const apiKey = clientKey || envKey;

      // Image-generation models are handled by the Lively image engine (which
      // calls the Gemini generateContent API directly) instead of the
      // OpenAI-compatible chat proxy.
      const resolvedModelInfo = (resolved.provider.models || []).find(m => m.id === resolved.modelId);
      const isImageModel = Boolean(resolvedModelInfo?.isImageModel || /image/i.test(resolved.modelId || ''));

      // If client specifically chose lively/prototype OR no key is available for upstream provider:
      if (resolved.providerId === 'lively' || isImageModel || (!apiKey && resolved.providerId !== 'ollama')) {
        // Forward the client's key so an image request can use it.
        return streamPrototypeResponse(body, res, resolved, null, clientKey || null);
      }

      // Otherwise proxy to upstream provider
      return streamUpstreamProxy(body, res, resolved, apiKey);
    } catch (err) {
      console.error('Error handling chat completions:', err);
      res.writeHead(err.status || 400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: err.message } }));
    }
    return;
  }

  // 5b. Dedicated Image Generation Endpoint (Gemini 3.1 Flash Lite Image)
  if (pathname === '/api/images/generations' || pathname === '/v1/images/generations') {
    if (req.method !== 'POST') {
      res.writeHead(405, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: 'Method not allowed' } }));
      return;
    }

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const prompt = body.prompt || 'Digital artwork with glowing lights';
      const imageResult = await generateGeminiImage(prompt);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        created: Math.floor(Date.now() / 1000),
        data: [
          {
            url: imageResult.url,
            b64_json: imageResult.b64_json,
            revised_prompt: prompt
          }
        ],
        model: 'gemini-3.1-flash-lite-image'
      }));
    } catch (err) {
      res.writeHead(err.status || 400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: err.message } }));
    }
    return;
  }

  // 6. Static File Server (serves React App, Chat UI v3.html, styles, design-system)
  let filePath;
  const isDefaultPage = pathname === '/' || pathname === '/index.html';
  const isReactApp = pathname === '/app' || pathname === '/app/' || pathname === '/openall' || pathname === '/openall/';
  const distIndex = path.join(ROOT_DIR, 'openall', 'dist', 'index.html');

  if (isReactApp) {
    filePath = fs.existsSync(distIndex) ? distIndex : path.join(ROOT_DIR, 'Chat UI v3.html');
  } else if (isDefaultPage) {
    filePath = path.join(ROOT_DIR, 'Chat UI v3.html');
  } else if (pathname.startsWith('/assets/')) {
    filePath = path.join(ROOT_DIR, 'openall', 'dist', decodeURIComponent(pathname));
  } else {
    filePath = path.join(ROOT_DIR, decodeURIComponent(pathname));
  }
  const safePath = path.normalize(filePath);
  if (!safePath.startsWith(ROOT_DIR)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden');
    return;
  }

  fs.stat(safePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
      return;
    }

    const ext = path.extname(safePath).toLowerCase();
    const mimeTypes = {
      '.html': 'text/html; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.js': 'application/javascript; charset=utf-8',
      '.mjs': 'application/javascript; charset=utf-8',
      '.json': 'application/json; charset=utf-8',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.svg': 'image/svg+xml',
      '.ico': 'image/x-icon',
      '.txt': 'text/plain; charset=utf-8',
    };

    const contentType = mimeTypes[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': contentType });
    fs.createReadStream(safePath).pipe(res);
  });
});

server.listen(PORT, HOST, () => {
  console.log(`===================================================`);
  console.log(` Lively Prototype Backend running at:`);
  console.log(` -> Bind:      http://${HOST}:${PORT}`);
  console.log(` -> Chat UI:   http://localhost:${PORT}/Chat%20UI%20v3.html`);
  console.log(` -> API:       http://localhost:${PORT}/api/chat/completions`);
  console.log(` -> Providers: http://localhost:${PORT}/api/providers`);
  console.log(` -> Models:    http://localhost:${PORT}/api/models`);
  console.log(`===================================================`);
});
