'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');
const { spawn } = require('child_process');

const args = process.argv.slice(2);
const valueAfter = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};

const repoRoot = path.resolve(valueAfter('--repo-root', path.join(__dirname, '..')));
const port = Number.parseInt(valueAfter('--port', '4317'), 10);
const allowMock = args.includes('--allow-mock');
const host = '127.0.0.1';
const publicRoot = path.join(__dirname, 'public');
const pieScript = path.join(repoRoot, 'pie.ps1');
const requestToken = crypto.randomBytes(24).toString('base64url');
const sessionLocks = new Set();
const modelPullJobs = new Map();
let activeModelPullJobId = '';
const workbenchBuild = '2026.08.06.5';

if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error('PIE_WORKBENCH_PORT_INVALID');
}
if (!fs.existsSync(pieScript)) {
  throw new Error(`PIE_WORKBENCH_CLI_MISSING: ${pieScript}`);
}

const securityHeaders = {
  'Cache-Control': 'no-store',
  'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
};

function send(res, status, body, contentType = 'application/json; charset=utf-8') {
  const payload = contentType.startsWith('application/json') ? JSON.stringify(body) : body;
  res.writeHead(status, { ...securityHeaders, 'Content-Type': contentType, 'Content-Length': Buffer.byteLength(payload) });
  res.end(payload);
}

function runPie(commandArgs, timeoutMs = 420000, onOutput = null, stdinText = null) {
  return new Promise((resolve, reject) => {
    const childArgs = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', pieScript, ...commandArgs, '-RepoRoot', repoRoot];
    const child = spawn('powershell.exe', childArgs, { cwd: repoRoot, windowsHide: true });
    let stdout = '';
    let stderr = '';
    let lineBuffer = '';
    const capture = (chunk, target) => {
      const value = chunk.toString('utf8');
      if (target === 'stdout') stdout += value;
      else stderr += value;
      if (!onOutput) return;
      lineBuffer += value;
      const lines = lineBuffer.split(/\r?\n/);
      lineBuffer = lines.pop() || '';
      for (const line of lines) onOutput(line);
    };
    const timer = setTimeout(() => {
      child.kill();
      reject(Object.assign(new Error('PIE_WORKBENCH_CHILD_TIMEOUT'), { status: 504 }));
    }, timeoutMs);

    child.stdout.on('data', chunk => capture(chunk, 'stdout'));
    child.stderr.on('data', chunk => capture(chunk, 'stderr'));
    if (stdinText !== null) child.stdin.end(stdinText);
    else child.stdin.end();
    child.on('error', error => {
      clearTimeout(timer);
      reject(error);
    });
    child.on('close', code => {
      clearTimeout(timer);
      if (onOutput && lineBuffer) onOutput(lineBuffer);
      const output = [stdout.trim(), stderr.trim()].filter(Boolean).join('\n');
      if (code !== 0) {
        reject(Object.assign(new Error(output || `PIE_WORKBENCH_CHILD_EXIT_${code}`), { status: 422, code, output }));
        return;
      }
      resolve(output);
    });
  });
}

function publicDownloadJob(job) {
  return {
    id: job.id,
    model: job.model,
    state: job.state,
    status: job.status,
    completed: job.completed,
    total: job.total,
    percent: job.percent,
    startedUtc: job.startedUtc,
    finishedUtc: job.finishedUtc,
    error: job.error,
  };
}

function updateDownloadProgress(job, line) {
  const match = line.match(/^PIE_MODEL_PULL_PROGRESS:\s+\S+\s+status=(.*?)\s+completed=(\d+)\s+total=(\d+)\s+percent=(\d+)$/);
  if (!match) return;
  job.state = 'downloading';
  job.status = match[1];
  job.completed = Number.parseInt(match[2], 10);
  job.total = Number.parseInt(match[3], 10);
  job.percent = Number.parseInt(match[4], 10);
}

function startModelPull(model, alreadyLocal = false) {
  const job = {
    id: crypto.randomUUID(), model, state: 'starting', status: 'Preparing download', completed: 0,
    total: 0, percent: 0, startedUtc: new Date().toISOString(), finishedUtc: '', error: '',
  };
  modelPullJobs.set(job.id, job);
  activeModelPullJobId = job.id;
  while (modelPullJobs.size > 25) modelPullJobs.delete(modelPullJobs.keys().next().value);

  if (alreadyLocal) {
    job.state = 'complete'; job.status = 'Already downloaded and verified'; job.completed = 1; job.total = 1; job.percent = 100;
    job.finishedUtc = new Date().toISOString(); activeModelPullJobId = '';
    return job;
  }

  if (allowMock) {
    setTimeout(() => {
      job.state = 'complete'; job.status = 'Verified locally'; job.completed = 1; job.total = 1; job.percent = 100;
      job.finishedUtc = new Date().toISOString(); activeModelPullJobId = '';
    }, 150);
    return job;
  }

  runPie(['pull', '-Model', model, '-SetDefault'], 2 * 60 * 60 * 1000, line => updateDownloadProgress(job, line))
    .then(() => {
      job.state = 'complete'; job.status = 'Verified locally'; job.percent = 100;
      if (job.total > 0) job.completed = job.total;
      job.finishedUtc = new Date().toISOString(); activeModelPullJobId = '';
    })
    .catch(error => {
      job.state = 'failed'; job.status = 'Download failed'; job.error = error.message || 'PIE_WORKBENCH_MODEL_PULL_FAILED';
      job.finishedUtc = new Date().toISOString(); activeModelPullJobId = '';
    });
  return job;
}

function parseRuntime(output) {
  const read = label => {
    const line = output.split(/\r?\n/).find(item => item.toLowerCase().startsWith(`${label}:`));
    return line ? line.slice(line.indexOf(':') + 1).trim() : '';
  };
  return {
    installed: read('installed') === 'yes',
    running: read('running') === 'yes',
    selectedModel: read('selected model'),
    loadedModels: output.split(/\r?\n/).filter(line => line.trim().startsWith('loaded:')).map(line => line.split(':').slice(1).join(':').trim()),
  };
}

function parseModels(output) {
  const models = [];
  let selected = '';
  for (const line of output.split(/\r?\n/)) {
    const model = line.match(/^\s{2}(\S+)\s{2,}(.+)$/);
    if (model) models.push({ name: model[1], size: model[2].trim() });
    if (line.startsWith('selected:')) selected = line.slice('selected:'.length).trim();
  }
  return { models, selected };
}

function parseCatalog(output) {
  try {
    const parsed = JSON.parse(output.trim());
    if (parsed.schema !== 'pie.model.catalog.v1' || !Array.isArray(parsed.models)) throw new Error('catalog schema');
    return parsed.models;
  } catch (error) {
    throw Object.assign(new Error(`PIE_WORKBENCH_MODEL_CATALOG_INVALID: ${error.message}`), { status: 500 });
  }
}

function storageState() {
  const configured = process.env.OLLAMA_MODELS ? path.resolve(process.env.OLLAMA_MODELS) : path.join(os.homedir(), '.ollama', 'models');
  let probe = configured;
  while (!fs.existsSync(probe) && path.dirname(probe) !== probe) probe = path.dirname(probe);
  try {
    const stats = fs.statfsSync(probe);
    return { modelRoot: configured, freeBytes: stats.bavail * stats.bsize, totalBytes: stats.blocks * stats.bsize, memoryBytes: os.totalmem() };
  } catch {
    return { modelRoot: configured, freeBytes: 0, totalBytes: 0, memoryBytes: os.totalmem() };
  }
}

function localHaaiState() {
  if (allowMock) return { available: true, repository: 'mock', mode: 'explicit-export' };
  const repository = path.resolve(process.env.PIE_HAAI_REPO || 'C:\\dev\\haai');
  const cli = path.join(repository, 'core', 'python', 'haai_core', 'cli.py');
  return { available: fs.existsSync(cli), repository, mode: 'explicit-export' };
}

function parseIntegrations(output) {
  const providers = {};
  for (const line of output.split(/\r?\n/)) {
    const match = line.match(/^(supabase|figma|vercel|cloudflare): auth=(\S+) cli=(\S+)$/);
    if (match) providers[match[1]] = { auth: match[2], cli: match[3] };
  }
  return providers;
}

function parseSession(output) {
  const values = {};
  for (const line of output.split(/\r?\n/)) {
    const index = line.indexOf(':');
    if (index > 0) values[line.slice(0, index).trim().toLowerCase()] = line.slice(index + 1).trim();
  }
  if (!values.session) return null;
  return {
    id: values.session,
    status: values.status,
    integrity: values.integrity,
    backend: values.backend,
    model: values.model,
    projectRepo: values['project repo'],
    goal: values.goal,
    turns: Number.parseInt(values['conversation turns'] || '0', 10),
    receipts: Number.parseInt(values['execution receipts'] || '0', 10),
  };
}

function parseHistory(output) {
  const marker = 'PIE_AGENT_HISTORY_JSON:';
  const line = output.split(/\r?\n/).find(item => item.startsWith(marker));
  if (!line) throw new Error('PIE_WORKBENCH_HISTORY_OUTPUT_INVALID');
  const parsed = JSON.parse(line.slice(marker.length));
  if (parsed.schema !== 'pie.conversation.history.v1' || !Array.isArray(parsed.turns)) {
    throw new Error('PIE_WORKBENCH_HISTORY_SCHEMA_INVALID');
  }
  return parsed;
}

function parseSessionIndex(output) {
  const marker = 'PIE_AGENT_SESSIONS_JSON:';
  const line = output.split(/\r?\n/).find(item => item.startsWith(marker));
  if (!line) throw new Error('PIE_WORKBENCH_SESSION_INDEX_OUTPUT_INVALID');
  const parsed = JSON.parse(line.slice(marker.length));
  if (parsed.schema !== 'pie.session.index.v1' || !Array.isArray(parsed.sessions)) throw new Error('PIE_WORKBENCH_SESSION_INDEX_SCHEMA_INVALID');
  return parsed;
}

async function readState(sessionId) {
  const [runtimeOutput, modelsOutput, catalogOutput, integrationsOutput] = await Promise.all([
    runPie(['runtime', 'status'], 30000),
    runPie(['models', 'list'], 30000),
    runPie(['models', 'catalog-json'], 30000),
    runPie(['integrations', 'status'], 30000),
  ]);
  let session = null;
  if (sessionId) {
    try { session = parseSession(await runPie(['agent', 'status', '-SessionId', sessionId], 30000)); }
    catch (error) {
      if (!String(error.message).includes('PIE_AGENT_SESSION_NOT_FOUND')) throw error;
      session = null;
    }
  }
  return {
    schema: 'pie.workbench.state.v1',
    runtime: parseRuntime(runtimeOutput),
    models: { ...parseModels(modelsOutput), catalog: parseCatalog(catalogOutput) },
    integrations: parseIntegrations(integrationsOutput),
    haai: localHaaiState(),
    session,
    download: activeModelPullJobId && modelPullJobs.has(activeModelPullJobId) ? publicDownloadJob(modelPullJobs.get(activeModelPullJobId)) : null,
    system: storageState(),
  };
}

async function readProjectIndex() {
  const sessions = parseSessionIndex(await runPie(['agent', 'sessions'], 30000)).sessions;
  const candidates = [{ name: path.basename(repoRoot), path: repoRoot, source: 'runtime' }];
  const haai = localHaaiState();
  if (haai.available) candidates.push({ name: path.basename(haai.repository), path: haai.repository, source: 'haai' });
  for (const session of sessions) {
    if (session.test_only) continue;
    if (typeof session.project_repo === 'string' && session.project_repo && fs.existsSync(session.project_repo)) {
      candidates.push({ name: path.basename(session.project_repo), path: path.resolve(session.project_repo), source: 'session' });
    }
  }
  const seen = new Set();
  const projects = candidates.filter(project => {
    const key = project.path.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return { schema: 'pie.project.index.v1', projects };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => {
      data += chunk.toString('utf8');
      if (Buffer.byteLength(data) > 1024 * 1024) {
        reject(Object.assign(new Error('PIE_WORKBENCH_BODY_TOO_LARGE'), { status: 413 }));
        req.destroy();
      }
    });
    req.on('end', () => {
      try { resolve(data ? JSON.parse(data) : {}); }
      catch { reject(Object.assign(new Error('PIE_WORKBENCH_JSON_INVALID'), { status: 400 })); }
    });
    req.on('error', reject);
  });
}

function requireToken(req) {
  const supplied = req.headers['x-pie-workbench-token'];
  if (typeof supplied !== 'string') return false;
  const expected = Buffer.from(requestToken);
  const actual = Buffer.from(supplied);
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}

function validSessionId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(value);
}

function answerFromOutput(output) {
  const marker = 'PIE_AGENT_SEND_OK:';
  const index = output.indexOf(marker);
  if (index < 0) return output.trim();
  const after = output.slice(index).split(/\r?\n/);
  after.shift();
  return after.join('\n').trim();
}

async function handleApi(req, res, url) {
  if (!requireToken(req)) {
    send(res, 403, { error: 'PIE_WORKBENCH_TOKEN_REQUIRED' });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/state') {
    send(res, 200, await readState(url.searchParams.get('sessionId') || ''));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/models/pull/status') {
    const job = modelPullJobs.get(url.searchParams.get('jobId') || '');
    if (!job) throw Object.assign(new Error('PIE_WORKBENCH_MODEL_PULL_JOB_NOT_FOUND'), { status: 404 });
    send(res, 200, { job: publicDownloadJob(job) });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/session/history') {
    const sessionId = url.searchParams.get('sessionId') || '';
    if (!validSessionId(sessionId)) throw Object.assign(new Error('PIE_WORKBENCH_SESSION_ID_INVALID'), { status: 400 });
    send(res, 200, parseHistory(await runPie(['agent', 'history', '-SessionId', sessionId], 30000)));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/sessions') {
    const index = parseSessionIndex(await runPie(['agent', 'sessions'], 30000));
    if (url.searchParams.get('includeFixtures') !== '1') index.sessions = index.sessions.filter(session => !session.test_only);
    send(res, 200, index);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/projects') {
    send(res, 200, await readProjectIndex());
    return;
  }

  if (req.method !== 'POST') {
    send(res, 405, { error: 'PIE_WORKBENCH_METHOD_NOT_ALLOWED' });
    return;
  }

  const body = await readBody(req);
  if (url.pathname === '/api/runtime/install') {
    if (allowMock) { send(res, 200, { ok: true, output: 'PIE_RUNTIME_INSTALL_OK' }); return; }
    const output = await runPie(['runtime', 'install'], 15 * 60 * 1000);
    send(res, 200, { ok: true, output });
    return;
  }
  if (url.pathname === '/api/runtime/start') {
    if (allowMock) { send(res, 200, { ok: true, output: 'PIE_RUNTIME_START_OK' }); return; }
    const output = await runPie(['runtime', 'start'], 60000);
    send(res, 200, { ok: true, output });
    return;
  }

  if (url.pathname === '/api/session/start') {
    if (!validSessionId(body.sessionId)) throw Object.assign(new Error('PIE_WORKBENCH_SESSION_ID_INVALID'), { status: 400 });
    const targetRepo = path.resolve(body.targetRepo || repoRoot);
    if (!fs.existsSync(targetRepo) || !fs.statSync(targetRepo).isDirectory()) throw Object.assign(new Error('PIE_WORKBENCH_TARGET_REPO_INVALID'), { status: 400 });
    const backend = allowMock && body.backend === 'mock' ? 'mock' : 'ollama';
    const model = typeof body.model === 'string' && body.model.trim() ? body.model.trim() : 'qwen2.5-coder:7b';
    const goal = typeof body.goal === 'string' ? body.goal.trim().slice(0, 500) : '';
    const output = await runPie(['agent', 'start', '-SessionId', body.sessionId, '-TargetRepo', targetRepo, '-Goal', goal, '-Backend', backend, '-Model', model], 30000);
    send(res, 200, { ok: true, output, session: parseSession(await runPie(['agent', 'status', '-SessionId', body.sessionId], 30000)) });
    return;
  }

  if (url.pathname === '/api/session/stop') {
    if (!validSessionId(body.sessionId)) throw Object.assign(new Error('PIE_WORKBENCH_SESSION_ID_INVALID'), { status: 400 });
    const output = await runPie(['agent', 'stop', '-SessionId', body.sessionId], 30000);
    send(res, 200, { ok: true, output });
    return;
  }
  if (url.pathname === '/api/session/backup') {
    if (!validSessionId(body.sessionId)) throw Object.assign(new Error('PIE_WORKBENCH_SESSION_ID_INVALID'), { status: 400 });
    if (typeof body.passphrase !== 'string' || body.passphrase.length < 14 || body.passphrase.length > 1024 || /[\r\n]/.test(body.passphrase)) throw Object.assign(new Error('PIE_WORKBENCH_BACKUP_PASSPHRASE_INVALID'), { status: 400 });
    const output = await runPie(['session', 'export', '-SessionId', body.sessionId, '-PassphraseStdin'], 120000, null, `${body.passphrase}\n`);
    const archiveMatch = output.match(/PIE_SESSION_BACKUP_EXPORT_(?:OK|ALREADY_VERIFIED):\s*([^\r\n]+)/i);
    const idMatch = output.match(/backup_id:\s*([0-9a-f]{64})/i);
    if (!archiveMatch || !idMatch) throw Object.assign(new Error('PIE_WORKBENCH_BACKUP_OUTPUT_INVALID'), { status: 500 });
    send(res, 200, { ok: true, archive: archiveMatch[1].trim(), backupId: idMatch[1].toLowerCase() });
    return;
  }
  if (url.pathname === '/api/session/restore') {
    if (typeof body.archivePath !== 'string' || !body.archivePath.trim()) throw Object.assign(new Error('PIE_WORKBENCH_BACKUP_PATH_REQUIRED'), { status: 400 });
    if (typeof body.passphrase !== 'string' || body.passphrase.length < 14 || body.passphrase.length > 1024 || /[\r\n]/.test(body.passphrase)) throw Object.assign(new Error('PIE_WORKBENCH_BACKUP_PASSPHRASE_INVALID'), { status: 400 });
    const archivePath = path.resolve(body.archivePath.trim());
    if (path.extname(archivePath).toLowerCase() !== '.piebak') throw Object.assign(new Error('PIE_WORKBENCH_BACKUP_PATH_INVALID'), { status: 400 });
    const output = await runPie(['session', 'restore', '-Path', archivePath, '-PassphraseStdin'], 120000, null, `${body.passphrase}\n`);
    const sessionMatch = output.match(/PIE_SESSION_RESTORE_OK:\s*([A-Za-z0-9][A-Za-z0-9._-]{0,63})/);
    if (!sessionMatch) throw Object.assign(new Error('PIE_WORKBENCH_RESTORE_OUTPUT_INVALID'), { status: 500 });
    const sessionId = sessionMatch[1];
    send(res, 200, { ok: true, session: parseSession(await runPie(['agent', 'status', '-SessionId', sessionId], 30000)) });
    return;
  }
  if (url.pathname === '/api/haai/capture') {
    if (!validSessionId(body.sessionId)) throw Object.assign(new Error('PIE_WORKBENCH_SESSION_ID_INVALID'), { status: 400 });
    const haai = localHaaiState();
    if (!haai.available) throw Object.assign(new Error('PIE_HAAI_UNAVAILABLE'), { status: 409 });
    if (allowMock) { send(res, 200, { ok: true, packetId: '0'.repeat(64), output: 'PIE_HAAI_CAPTURE_OK' }); return; }
    const turnIndex = Number.isInteger(body.turnIndex) && body.turnIndex >= 0 ? body.turnIndex : 0;
    const output = await runPie(['haai', 'capture', '-SessionId', body.sessionId, '-TurnIndex', String(turnIndex), '-HaaiRepo', haai.repository], 120000);
    const match = output.match(/PIE_HAAI_CAPTURE_(?:OK|ALREADY_VERIFIED):\s*([0-9a-f]{64})/i);
    if (!match) throw Object.assign(new Error('PIE_WORKBENCH_HAAI_OUTPUT_INVALID'), { status: 500 });
    send(res, 200, { ok: true, packetId: match[1].toLowerCase(), output });
    return;
  }

  if (url.pathname === '/api/models/select') {
    if (typeof body.model !== 'string' || !body.model.trim()) throw Object.assign(new Error('PIE_WORKBENCH_MODEL_REQUIRED'), { status: 400 });
    const output = await runPie(['models', 'use', '-Model', body.model.trim()], 30000);
    send(res, 200, { ok: true, output });
    return;
  }

  if (url.pathname === '/api/models/pull') {
    if (typeof body.model !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}(?::[A-Za-z0-9][A-Za-z0-9._-]{0,63})?$/.test(body.model.trim())) {
      throw Object.assign(new Error('PIE_WORKBENCH_MODEL_INVALID'), { status: 400 });
    }
    if (activeModelPullJobId) throw Object.assign(new Error('PIE_WORKBENCH_MODEL_PULL_BUSY'), { status: 409 });
    const requestedModel = body.model.trim();
    if (!allowMock) {
      const catalog = parseCatalog(await runPie(['models', 'catalog-json'], 30000));
      const catalogEntry = catalog.find(item => item.name.toLowerCase() === requestedModel.toLowerCase());
      if (!catalogEntry) throw Object.assign(new Error('PIE_WORKBENCH_MODEL_NOT_IN_CATALOG'), { status: 400 });
      const storage = storageState();
      const requiredBytes = Math.ceil(Number(catalogEntry.size_bytes) * 1.15 + 256 * 1024 * 1024);
      if (storage.freeBytes > 0 && storage.freeBytes < requiredBytes) {
        throw Object.assign(new Error(`PIE_WORKBENCH_DISK_SPACE_LOW: required=${requiredBytes} free=${storage.freeBytes}`), { status: 507 });
      }
    }
    const alreadyLocal = allowMock ? false : parseModels(await runPie(['models', 'list'], 30000)).models.some(item => item.name.toLowerCase() === requestedModel.toLowerCase());
    if (alreadyLocal) await runPie(['models', 'use', '-Model', requestedModel], 30000);
    const job = startModelPull(requestedModel, alreadyLocal);
    send(res, 202, { ok: true, job: publicDownloadJob(job) });
    return;
  }

  if (url.pathname === '/api/ask') {
    if (!validSessionId(body.sessionId)) throw Object.assign(new Error('PIE_WORKBENCH_SESSION_ID_INVALID'), { status: 400 });
    if (typeof body.text !== 'string' || !body.text.trim()) throw Object.assign(new Error('PIE_WORKBENCH_ASK_TEXT_REQUIRED'), { status: 400 });
    if (body.text.length > 30000) throw Object.assign(new Error('PIE_WORKBENCH_ASK_TEXT_TOO_LONG'), { status: 413 });
    if (sessionLocks.has(body.sessionId)) throw Object.assign(new Error('PIE_WORKBENCH_SESSION_BUSY'), { status: 409 });
    sessionLocks.add(body.sessionId);
    try {
      const timeout = Math.min(Math.max(Number.parseInt(body.timeoutSeconds || '180', 10), 30), 600);
      const output = await runPie(['agent', 'ask', '-SessionId', body.sessionId, '-Text', body.text.trim(), '-TimeoutSeconds', String(timeout), '-Retries', '1'], (timeout * 2 + 30) * 1000);
      send(res, 200, { ok: true, answer: answerFromOutput(output), output });
    } finally {
      sessionLocks.delete(body.sessionId);
    }
    return;
  }

  send(res, 404, { error: 'PIE_WORKBENCH_API_NOT_FOUND' });
}

function serveAsset(res, pathname) {
  const relative = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const filePath = path.resolve(publicRoot, relative);
  if (!filePath.startsWith(publicRoot + path.sep) && filePath !== path.join(publicRoot, 'index.html')) {
    send(res, 404, 'Not found', 'text/plain; charset=utf-8');
    return;
  }
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    send(res, 404, 'Not found', 'text/plain; charset=utf-8');
    return;
  }
  const types = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.webmanifest': 'application/manifest+json; charset=utf-8',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
  };
  const extension = path.extname(filePath).toLowerCase();
  let content = extension === '.html' ? fs.readFileSync(filePath, 'utf8') : fs.readFileSync(filePath);
  if (relative === 'index.html') {
    const styles = fs.readFileSync(path.join(publicRoot, 'styles.css'), 'utf8');
    const application = fs.readFileSync(path.join(publicRoot, 'app.js'), 'utf8').replace(/<\/script/gi, '<\\/script');
    content = content
      .replace('__PIE_BOOTSTRAP_JSON__', JSON.stringify({ requestToken, repoRoot, defaultSessionId: 'work' }))
      .replace('__PIE_STYLES__', styles)
      .replace('__PIE_APP_JS__', application);
  }
  send(res, 200, content, types[extension] || 'application/octet-stream');
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${host}:${port}`);
  try {
    if (req.method === 'GET' && url.pathname === '/health') {
      send(res, 200, { schema: 'pie.workbench.health.v1', status: 'ok', build: workbenchBuild });
      return;
    }
    if (url.pathname.startsWith('/api/')) {
      await handleApi(req, res, url);
      return;
    }
    if (req.method !== 'GET') {
      send(res, 405, 'Method not allowed', 'text/plain; charset=utf-8');
      return;
    }
    serveAsset(res, url.pathname);
  } catch (error) {
    send(res, error.status || 500, { error: error.message || 'PIE_WORKBENCH_INTERNAL_ERROR' });
  }
});

server.listen(port, host, () => {
  process.stdout.write(`PIE_WORKBENCH_READY: http://${host}:${port}\n`);
  process.stdout.write(`repo: ${repoRoot}\n`);
});

process.on('SIGINT', () => server.close(() => process.exit(0)));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
