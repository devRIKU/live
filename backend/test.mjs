import { strict as assert } from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

const BASE = 'http://localhost:3001';
const ROOT = path.resolve(import.meta.dirname, '..');
let child = null;

/** Use an already-running backend, or start one and wait for health. */
async function ensureServer() {
  try {
    const res = await fetch(`${BASE}/api/health`);
    if (res.ok) return;
  } catch {}
  child = spawn(process.execPath, [path.join(ROOT, 'backend', 'server.mjs')], {
    cwd: ROOT,
    env: { ...process.env, PORT: '3001' },
    stdio: 'ignore',
  });
  for (let i = 0; i < 50; i++) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    try {
      const res = await fetch(`${BASE}/api/health`);
      if (res.ok) return;
    } catch {}
  }
  throw new Error('Backend did not start on port 3001');
}

async function fetchJson(url, options = {}) {
  const res = await fetch(url, options);
  const data = await res.json();
  return { status: res.status, ok: res.ok, headers: res.headers, data };
}

async function run() {
  console.log('=== Lively Prototype Verification Suite ===\n');

  // Test 1: Health endpoint
  console.log('1. Testing /api/health...');
  const health = await fetchJson(`${BASE}/api/health`);
  assert.equal(health.status, 200);
  assert.equal(health.data.status, 'ok');
  console.log('   ✓ Health OK');

  // Test 2: Models catalog
  console.log('2. Testing /api/models catalog...');
  const models = await fetchJson(`${BASE}/api/models`);
  assert.equal(models.status, 200);
  assert(Array.isArray(models.data.data));
  assert(models.data.data.length >= 15);
  console.log(`   ✓ Catalog OK (${models.data.data.length} models)`);

  // Test 3: Providers capabilities
  console.log('3. Testing /api/providers...');
  const providers = await fetchJson(`${BASE}/api/providers`);
  assert.equal(providers.status, 200);
  assert(Array.isArray(providers.data.providers));
  console.log(`   ✓ Providers OK (${providers.data.providers.length} registered)`);

  // Test 4: Streaming SSE Chat Completion with usage
  console.log('4. Testing streaming SSE chat completions...');
  const streamRes = await fetch(`${BASE}/api/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'lively/prototype-smart',
      messages: [{ role: 'user', content: 'Explain streaming architecture' }],
      stream: true,
      stream_options: { include_usage: true }
    })
  });
  assert.equal(streamRes.status, 200);
  assert(streamRes.headers.get('content-type').includes('text/event-stream'));

  const reader = streamRes.body.getReader();
  const decoder = new TextDecoder();
  let receivedDone = false;
  let receivedUsage = false;
  let chunkCount = 0;
  let textAccum = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const chunkStr = decoder.decode(value);
    for (const line of chunkStr.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith(':')) continue;
      if (trimmed === 'data: [DONE]') {
        receivedDone = true;
      } else if (trimmed.startsWith('data: ')) {
        const payload = JSON.parse(trimmed.slice(6));
        chunkCount++;
        if (payload.choices?.[0]?.delta?.content) {
          textAccum += payload.choices[0].delta.content;
        }
        if (payload.usage) {
          receivedUsage = true;
        }
      }
    }
  }
  assert(receivedDone, 'Must terminate with [DONE]');
  assert(receivedUsage, 'Must report usage when requested');
  assert(chunkCount > 5, 'Must stream multiple tokens');
  console.log(`   ✓ SSE Streaming OK (${chunkCount} chunks, ${textAccum.length} chars)`);

  // Test 5: Non-streaming JSON completion
  console.log('5. Testing non-streaming (stream: false) completions...');
  const nonStream = await fetchJson(`${BASE}/api/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'groq/llama-3.3-70b-versatile',
      messages: [{ role: 'user', content: 'Status check' }],
      stream: false
    })
  });
  assert.equal(nonStream.status, 200);
  assert.equal(nonStream.data.object, 'chat.completion');
  assert(nonStream.data.choices[0].message.content.length > 0);
  console.log('   ✓ Non-streaming JSON completion OK');

  // Test 6: Path rewrite endpoint (/api/llm/<provider>/chat/completions)
  console.log('6. Testing /api/llm/ rewrite endpoint for OpenAll proxy...');
  const llmRes = await fetchJson(`${BASE}/api/llm/groq/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'llama-3.3-70b-versatile',
      messages: [{ role: 'user', content: 'Hello' }],
      stream: false
    })
  });
  assert.equal(llmRes.status, 200);
  assert.equal(llmRes.data.model, 'llama-3.3-70b-versatile');
  console.log('   ✓ Proxy rewrite OK');

  // Test 7: Static file serving
  console.log('7. Testing static file serving for Chat UI v3 & root...');
  const rootRes = await fetch(`${BASE}/`);
  assert.equal(rootRes.status, 200);
  const rootText = await rootRes.text();
  assert(rootText.includes('Lively — Chat'));
  console.log('   ✓ Static serving OK');

  // Test 8: Client cancellation mid-stream
  console.log('8. Testing client abort mid-stream...');
  const controller = new AbortController();
  const abortReq = await fetch(`${BASE}/api/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'lively/prototype-smart',
      messages: [{ role: 'user', content: 'Cancel test' }],
      stream: true
    }),
    signal: controller.signal
  });
  const abortReader = abortReq.body.getReader();
  await abortReader.read();
  controller.abort();
  console.log('   ✓ Abort handled cleanly');

  // Test 9: Markdown parsing and XSS verification
  console.log('9. Testing Chat UI markdown rendering & XSS sanitization...');
  const htmlContent = fs.readFileSync(path.join(ROOT, 'Chat UI v3.html'), 'utf8');
  const escapeHtmlMatch = htmlContent.match(/function escapeHtml[\s\S]*?^  \}/m);
  const renderMarkdownMatch = htmlContent.match(/function renderMarkdown[\s\S]*?^  \}/m);
  assert(escapeHtmlMatch && renderMarkdownMatch);
  const { escapeHtml, renderMarkdown } = new Function(`${escapeHtmlMatch[0]}\n${renderMarkdownMatch[0]}\nreturn { escapeHtml, renderMarkdown };`)();

  // Test XSS sanitization
  const malicious = '<script>alert(1)</script><img src=x onerror=alert(2)>';
  const sanitized = renderMarkdown(malicious);
  assert(!sanitized.includes('<script>') && !sanitized.includes('<img'));
  assert(sanitized.includes('&lt;script&gt;'));

  // Test streaming unclosed code fence
  const streamingCode = '```typescript\nconst a = 1;';
  const renderedCode = renderMarkdown(streamingCode);
  assert(renderedCode.includes('<pre><div class="code-topbar">'));
  assert(renderedCode.includes('TYPESCRIPT (streaming)'));

  // Test reasoning thought block
  const thought = '<thought>Synthesizing response</thought>Answer text';
  const renderedThought = renderMarkdown(thought);
  assert(renderedThought.includes('<details class="thought-box" open>'));
  assert(renderedThought.includes('Reasoning process'));

  // Test safe links
  const safeLink = renderMarkdown('[Lively](https://example.com) [Bad](javascript:alert(1))');
  assert(safeLink.includes('<a href="https://example.com" target="_blank" rel="noopener noreferrer">Lively</a>'));
  assert(!safeLink.includes('<a href="javascript:'));
  assert(!safeLink.includes('href="javascript:'));

  // Image URLs must be escaped before they reach the src/href attributes.
  const evilImage = renderMarkdown('![x](https://a/"><img src=x onerror=alert`1`>)');
  assert(!evilImage.includes('"><img'), 'image URL must not break out of the attribute');
  assert(evilImage.includes('&quot;&gt;&lt;img'), 'image URL must be HTML-escaped');
  console.log('   ✓ Markdown rendering & security tests OK');

  // Test 10: Origin allowlist
  console.log('10. Testing CORS origin allowlist...');
  const foreign = await fetch(`${BASE}/api/health`, {
    headers: { Origin: 'https://evil.example' },
  });
  assert.equal(foreign.status, 403, 'Foreign origins must be rejected');

  const local = await fetch(`${BASE}/api/health`, {
    headers: { Origin: 'http://localhost:5173' },
  });
  assert.equal(local.status, 200, 'Local origins must be allowed');
  assert.equal(
    local.headers.get('access-control-allow-origin'),
    'http://localhost:5173',
    'The allowed origin must be echoed, never a wildcard',
  );
  console.log('   ✓ Origin allowlist OK');

  // Test 11: Oversized request bodies are rejected
  console.log('11. Testing 1 MB body cap...');
  const oversized = await fetch(`${BASE}/api/providers/keys`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ providerId: 'openrouter', key: 'a'.repeat(1024 * 1024 + 64) }),
  });
  assert.equal(oversized.status, 413, 'Bodies over the cap must be rejected');
  console.log('   ✓ Body cap OK');

  // Test 12: SSRF guard rejects private targets, including mapped IPv6 forms
  console.log('12. Testing SSRF guard...');
  const blockedUrls = [
    'http://127.0.0.1:3001/api/health',
    'http://localhost:3001/api/health',
    'http://169.254.169.254/latest/meta-data',
    'http://[::ffff:127.0.0.1]:3001/api/health',
    'http://[::7f00:1]:3001/api/health',
  ];
  for (const blockedUrl of blockedUrls) {
    const blocked = await fetchJson(`${BASE}/api/connectors/test`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: blockedUrl }),
    });
    assert.equal(blocked.status, 400, `${blockedUrl} must be rejected`);
    assert.equal(blocked.data.ok, false);
  }
  console.log('   ✓ SSRF guard OK');

  console.log('\n===========================================');
  console.log('  ALL VERIFICATION TESTS COMPLETED SUCCESSFULLY!');
  console.log('===========================================');
}

ensureServer()
  .then(run)
  .catch(err => {
    console.error('\n❌ Test failure:', err);
    process.exitCode = 1;
  })
  .finally(() => {
    if (child) child.kill();
  });
