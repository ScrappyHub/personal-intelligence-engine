'use strict';

if (!window.__PIE_APP_STARTED__) {
window.__PIE_APP_STARTED__ = true;

const bootstrap = window.__PIE_BOOTSTRAP__ || {};
const ids = [
  'surfaceLabel','installButton','runtimeDot','runtimeLabel','runtimeButton','refreshButton','sessionState','sessionSelect','newSessionButton','sessionId','targetRepo','repoPickerButton','recentProjects','recentRepoSelect','goal',
  'startButton','stopButton','modelCount','modelSelect','modelNote','catalogSelect','downloadButton','modelDetails','downloadNote',
  'downloadProgress','downloadProgressBar','downloadProgressLabel','downloadProgressPercent','integrationList',
  'conversationTitle','conversationMeta','haaiButton','backupButton','restoreButton','notice','messages','emptyState','composer','modelHeading','catalogBlock','integrationsSection','privacyLabel','emptyDescription',
  'messageInput','sendButton','thinkingStatus','characterCount','backupDialog','backupDialogForm','backupDialogTitle','backupPassphrase','backupConfirmField','backupPassphraseConfirm','backupDialogError','backupDialogCancel'
];
const el = Object.fromEntries(ids.map(id => [id, document.getElementById(id)]));
let activeSession = null;
let selectedSession = null;
let asking = false;
let thinkingTimer = null;
let noticeTimer = null;
let monitoredDownloadId = '';
let catalogModels = [];
let systemState = {};
let haaiState = {};
let installPrompt = null;
let loadedConversationKey = '';
let knownSessions = [];

const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');
const requestedTheme = new URLSearchParams(window.location.search).get('theme');
const VALID_THEMES = ['auto', 'sunset', 'dusk', 'system'];
// Default to time-of-day 'auto' for first-time users; any stored/explicit choice still wins.
let themePreference = requestedTheme || localStorage.getItem('pie.theme') || 'auto';

// Device-clock resolution — no location permission required. The browser/Electron already
// knows the real local time and zone (Intl + Date), so there is no hardcoded default state.
// Sunset (light: reds/oranges/yellows) during the day, Dusk (dark) at night.
function resolveByClock() {
  const hour = new Date().getHours();
  return (hour >= 6 && hour < 18) ? 'sunset' : 'dusk';
}

function applyTheme(preference) {
  themePreference = VALID_THEMES.includes(preference) ? preference : 'auto';
  let resolved;
  if (themePreference === 'system') resolved = systemTheme.matches ? 'dusk' : 'sunset';
  else if (themePreference === 'auto') resolved = resolveByClock();
  else resolved = themePreference;
  document.documentElement.dataset.theme = resolved;
  document.documentElement.dataset.themePreference = themePreference;
  document.querySelectorAll('[data-theme-choice]').forEach(button => {
    const selected = button.dataset.themeChoice === themePreference;
    button.classList.toggle('active', selected);
    button.setAttribute('aria-pressed', String(selected));
  });
}

// Time-aware greeting from the same device clock (updates as the day advances).
function partOfDay(hour) {
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 22) return 'Good evening';
  return 'Working late';
}
function applyTimeAwareText() {
  const heading = document.getElementById('emptyHeading');
  if (heading) heading.textContent = partOfDay(new Date().getHours()) + ' — your workspace is ready';
}

applyTheme(themePreference);
applyTimeAwareText();
document.querySelectorAll('[data-theme-choice]').forEach(button => button.addEventListener('click', () => {
  localStorage.setItem('pie.theme', button.dataset.themeChoice);
  applyTheme(button.dataset.themeChoice);
}));
systemTheme.addEventListener('change', () => { if (themePreference === 'system') applyTheme('system'); });

// Re-resolve on a cadence and when the tab regains focus, so the theme flips at the day/night
// boundary and the greeting stays current — all from the device clock, no permission, no default.
function pieTimeTick() {
  if (themePreference === 'auto') applyTheme('auto');
  applyTimeAwareText();
}
setInterval(pieTimeTick, 60 * 1000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) pieTimeTick(); });

const surface = new URLSearchParams(window.location.search).get('surface') || bootstrap.surface || 'web';
const isHosted = surface === 'hosted';
document.documentElement.dataset.surface = surface;
if (isHosted) {
  el.surfaceLabel.textContent = 'Hosted';
  el.targetRepo.placeholder = 'Imported workspace';
  el.targetRepo.readOnly = true;
  el.modelHeading.textContent = 'Model';
  el.catalogBlock.hidden = true;
  el.downloadNote.hidden = true;
  el.integrationsSection.hidden = true;
  el.privacyLabel.innerHTML = '<span aria-hidden="true">&#9679;</span> Private workspace';
  el.emptyDescription.textContent = 'Choose an imported project, start a session, and build from here.';
}
if ('serviceWorker' in navigator && !window.pieDesktop) navigator.serviceWorker.register('/service-worker.js').catch(() => {});
window.addEventListener('beforeinstallprompt', event => {
  event.preventDefault();
  installPrompt = event;
  el.installButton.hidden = false;
});
el.installButton.addEventListener('click', async () => {
  if (!installPrompt) return;
  installPrompt.prompt();
  await installPrompt.userChoice;
  installPrompt = null;
  el.installButton.hidden = true;
});

el.sessionId.value = localStorage.getItem('pie.sessionId') || bootstrap.defaultSessionId || 'work';
el.targetRepo.value = bootstrap.repoRoot || '';

if (window.pieDesktop) {
  el.surfaceLabel.textContent = 'Desktop';
  el.repoPickerButton.hidden = false;
  el.restoreButton.hidden = false;
  el.recentRepoSelect.addEventListener('change', () => {
    if (el.recentRepoSelect.value) el.targetRepo.value = el.recentRepoSelect.value;
  });
  el.repoPickerButton.addEventListener('click', async () => {
    const result = await window.pieDesktop.chooseRepository();
    if (!result || result.canceled || !result.path) return;
    el.targetRepo.value = result.path;
    if (!Array.from(el.recentRepoSelect.options).some(option => option.value === result.path)) {
      el.recentRepoSelect.append(new Option(result.name, result.path));
    }
    el.recentProjects.hidden = false;
    el.recentRepoSelect.value = result.path;
    if (!el.goal.value.trim()) el.goal.value = 'Inspect and improve this repository';
  });
}

async function refreshProjects() {
  const result = await api('/api/projects');
  const repositories = Array.isArray(result.projects) ? [...result.projects] : [];
  if (window.pieDesktop) {
    const desktopRepositories = await window.pieDesktop.listRepositories();
    if (Array.isArray(desktopRepositories)) repositories.unshift(...desktopRepositories);
  }
  const seen = new Set();
  el.recentRepoSelect.replaceChildren(new Option('Choose a project', ''));
  for (const repository of repositories) {
    if (!repository || typeof repository.path !== 'string') continue;
    const key = repository.path.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    el.recentRepoSelect.append(new Option(repository.name || repository.path, repository.path));
  }
  el.recentProjects.hidden = seen.size === 0;
}

async function api(route, options = {}) {
  const apiBase = typeof bootstrap.apiBase === 'string' ? bootstrap.apiBase.replace(/\/$/, '') : '';
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
  if (bootstrap.requestToken) headers['X-PIE-Workbench-Token'] = bootstrap.requestToken;
  const response = await fetch(`${apiBase}${route}`, {
    ...options,
    credentials: apiBase ? 'include' : 'same-origin',
    headers,
  });
  const data = await response.json().catch(() => ({ error: `Request failed (${response.status})` }));
  if (!response.ok) throw new Error(humanizeError(data.error || `Request failed (${response.status})`));
  return data;
}

function humanizeError(message) {
  const known = {
    PIE_WORKBENCH_SESSION_BUSY: 'This session is already answering a request.',
    PIE_WORKBENCH_SESSION_ID_INVALID: 'Use letters, numbers, dots, dashes, or underscores for the session name.',
    PIE_WORKBENCH_TARGET_REPO_INVALID: 'That project folder does not exist.',
    PIE_WORKBENCH_ASK_TEXT_REQUIRED: 'Write a message before sending.',
    PIE_WORKBENCH_CHILD_TIMEOUT: 'The local model took too long to respond.',
    PIE_WORKBENCH_MODEL_INVALID: 'That model name is not valid.',
    PIE_WORKBENCH_MODEL_PULL_BUSY: 'A model download is already in progress.'
    ,PIE_AGENT_SESSION_BINDING_MISMATCH: 'That conversation name belongs to a different project, model, or goal. Choose a new conversation name.'
    ,PIE_AGENT_SESSION_BINDING_DRIFT: 'This conversation has conflicting project state and was blocked.'
    ,PIE_AGENT_SESSION_BINDING_HASH_MISMATCH: 'This conversation failed its integrity check and was blocked.'
    ,PIE_CONVERSATION_HASH_MISMATCH: 'This conversation history failed its integrity check and was blocked.'
    ,PIE_AGENT_SESSION_LEGACY_READ_ONLY: 'This older conversation is read-only because it predates repository, model, and history integrity checks. Choose a new conversation name to continue safely.'
  };
  if (known[message]) return known[message];
  if (String(message).startsWith('PIE_WORKBENCH_DISK_SPACE_LOW:')) return 'There is not enough free disk space for that model.';
  if (message === 'PIE_WORKBENCH_MODEL_NOT_IN_CATALOG') return 'That download is not in PIE\'s verified model catalog.';
  return String(message).replace(/^PIE_[A-Z0-9_]+:\s*/, '').trim() || 'Something went wrong.';
}

function showNotice(message, kind = 'error') {
  clearTimeout(noticeTimer);
  el.notice.textContent = message;
  el.notice.className = kind === 'success' ? 'notice success' : 'notice';
  el.notice.hidden = false;
  noticeTimer = setTimeout(() => { el.notice.hidden = true; }, 7000);
}

function setBusy(button, busy, label) {
  if (busy) {
    button.dataset.label = button.textContent;
    button.textContent = label;
    button.disabled = true;
  } else {
    button.textContent = button.dataset.label || button.textContent;
    button.disabled = false;
  }
}

function requestBackupPassphrase(confirmValue) {
  return new Promise(resolve => {
    const finish = value => {
      el.backupPassphrase.value = '';
      el.backupPassphraseConfirm.value = '';
      el.backupDialogError.hidden = true;
      if (el.backupDialog.open) el.backupDialog.close();
      resolve(value);
    };
    el.backupDialogTitle.textContent = confirmValue ? 'Encrypt conversation backup' : 'Unlock conversation backup';
    el.backupConfirmField.hidden = !confirmValue;
    el.backupPassphraseConfirm.required = confirmValue;
    el.backupDialogForm.onsubmit = event => {
      event.preventDefault();
      const value = el.backupPassphrase.value;
      if (value.length < 14 || value.length > 1024 || /[\r\n]/.test(value)) {
        el.backupDialogError.textContent = 'Use a passphrase of at least 14 characters without line breaks.';
        el.backupDialogError.hidden = false;
        return;
      }
      if (confirmValue && value !== el.backupPassphraseConfirm.value) {
        el.backupDialogError.textContent = 'The passphrases do not match.';
        el.backupDialogError.hidden = false;
        return;
      }
      finish(value);
    };
    el.backupDialogCancel.onclick = () => finish(null);
    el.backupDialog.oncancel = event => { event.preventDefault(); finish(null); };
    el.backupDialog.showModal();
    el.backupPassphrase.focus();
  });
}

function setSession(session) {
  activeSession = session && session.status === 'running' ? session : null;
  const boundSession = session || null;
  selectedSession = boundSession;
  const running = Boolean(activeSession);
  if (boundSession) {
    el.sessionId.value = boundSession.id;
    el.targetRepo.value = boundSession.projectRepo || '';
    el.goal.value = boundSession.goal || '';
    if (Array.from(el.modelSelect.options).some(option => option.value === boundSession.model)) el.modelSelect.value = boundSession.model;
  }
  el.sessionState.textContent = running ? 'Running' : 'Stopped';
  el.sessionState.classList.toggle('running', running);
  el.startButton.disabled = running || asking;
  el.stopButton.disabled = !running || asking;
  el.messageInput.disabled = !running || asking;
  el.sendButton.disabled = !running || asking || !el.messageInput.value.trim();
  el.sessionId.disabled = running;
  el.targetRepo.disabled = Boolean(boundSession);
  el.goal.disabled = Boolean(boundSession);
  if (el.repoPickerButton) el.repoPickerButton.disabled = Boolean(boundSession);
  if (el.recentRepoSelect) el.recentRepoSelect.disabled = Boolean(boundSession);
  el.modelSelect.disabled = Boolean(boundSession) || !el.modelSelect.options.length;
  el.conversationTitle.textContent = boundSession ? boundSession.id : 'Local conversation';
  el.conversationMeta.textContent = boundSession
    ? `${boundSession.model || 'Local model'} · ${boundSession.projectRepo || 'No project'} · ${boundSession.status} · ${boundSession.integrity || 'unknown integrity'}`
    : 'Start a session to begin';
  el.thinkingStatus.textContent = running ? 'Ready' : 'Local session inactive';
  el.haaiButton.hidden = !haaiState.available || !boundSession || Number(boundSession.turns || 0) < 1;
  el.haaiButton.disabled = asking;
  el.backupButton.hidden = isHosted || !boundSession || boundSession.integrity !== 'verified';
  el.backupButton.disabled = asking;
}

function renderState(state) {
  const ready = Boolean(state.runtime && state.runtime.running);
  el.runtimeDot.className = `status-dot ${ready ? 'ready' : 'warning'}`;
  el.runtimeLabel.textContent = isHosted ? (ready ? 'Workspace ready' : 'Workspace unavailable') : (ready ? 'Local runtime ready' : (state.runtime && state.runtime.installed ? 'Local runtime stopped' : 'Ollama not installed'));
  el.runtimeButton.hidden = isHosted || ready;
  el.runtimeButton.dataset.action = state.runtime && state.runtime.installed ? 'start' : 'install';
  el.runtimeButton.textContent = state.runtime && state.runtime.installed ? 'Start runtime' : 'Install Ollama';

  const models = state.models && Array.isArray(state.models.models) ? state.models.models : [];
  const selected = (state.models && state.models.selected) || (state.runtime && state.runtime.selectedModel) || '';
  el.modelSelect.replaceChildren();
  if (!models.length) {
    el.modelSelect.append(new Option('No downloaded models', ''));
    el.modelSelect.disabled = true;
  } else {
    for (const model of models) el.modelSelect.append(new Option(`${model.name}${model.size ? ` · ${model.size}` : ''}`, model.name));
    if (models.some(model => model.name === selected)) el.modelSelect.value = selected;
    el.modelSelect.disabled = false;
  }
  el.modelCount.textContent = `${models.length} downloaded`;
  el.modelNote.textContent = selected ? `Default: ${selected}` : 'Models stay on this machine.';

  const catalog = state.models && Array.isArray(state.models.catalog) ? state.models.catalog : [];
  catalogModels = catalog;
  systemState = state.system || {};
  haaiState = state.haai || {};
  const downloadedNames = new Set(models.map(model => model.name.toLowerCase()));
  el.catalogSelect.replaceChildren();
  for (const item of catalog) {
    const suffix = downloadedNames.has(item.name.toLowerCase()) ? ' · downloaded' : ` · ${formatBytes(Number(item.size_bytes))}`;
    el.catalogSelect.append(new Option(`${item.title}${suffix}`, item.name));
  }
  el.catalogSelect.disabled = !catalog.length;
  el.downloadButton.disabled = !catalog.length;
  renderCatalogDetails();
  if (state.download && state.download.id !== monitoredDownloadId) monitorDownload(state.download.id, state.download.model);

  const names = ['supabase','figma','vercel','cloudflare','haai'];
  el.integrationList.replaceChildren(...names.map(name => {
    const provider = state.integrations && state.integrations[name];
    const configured = name === 'haai' ? Boolean(state.haai && state.haai.available) : provider && provider.auth === 'configured';
    const li = document.createElement('li');
    const label = document.createElement('span');
    const status = document.createElement('span');
    label.textContent = name[0].toUpperCase() + name.slice(1);
    status.textContent = name === 'haai' ? (configured ? 'Ready' : 'Unavailable') : (configured ? 'Connected' : 'Not connected');
    status.className = `integration-state ${configured ? 'configured' : 'missing'}`;
    li.append(label, status);
    return li;
  }));
  setSession(state.session);
  if (state.session) syncConversation(state.session).catch(error => showNotice(error.message));
  else if (loadedConversationKey) clearConversation();
}

function clearConversation() {
  el.messages.replaceChildren();
  loadedConversationKey = '';
}

function newSessionId() {
  const now = new Date();
  const pad = value => String(value).padStart(2, '0');
  const milliseconds = String(now.getMilliseconds()).padStart(3, '0');
  return `work-${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}-${milliseconds}`;
}

async function refreshSessions() {
  const result = await api('/api/sessions');
  knownSessions = result.sessions || [];
  const current = el.sessionId.value.trim();
  el.sessionSelect.replaceChildren(new Option('New conversation', ''));
  for (const session of knownSessions) {
    const project = session.project_repo ? session.project_repo.split(/[\\/]/).filter(Boolean).pop() : 'unbound';
    const state = session.integrity === 'verified' ? session.status : session.integrity;
    el.sessionSelect.append(new Option(`${session.id} · ${project} · ${state}`, session.id));
  }
  if (knownSessions.some(session => session.id === current)) el.sessionSelect.value = current;
}

async function syncConversation(session, force = false) {
  if (!session || asking) return;
  const key = `${session.id}:${session.turns}`;
  if (!force && key === loadedConversationKey) return;
  const history = await api(`/api/session/history?sessionId=${encodeURIComponent(session.id)}`);
  if (el.sessionId.value.trim() !== history.session_id) return;
  el.messages.replaceChildren();
  for (const turn of history.turns) {
    addMessage('user', turn.message);
    addMessage('assistant', turn.response);
  }
  loadedConversationKey = `${history.session_id}:${history.total_turns}`;
}

function formatBytes(value) {
  if (!Number.isFinite(value) || value <= 0) return '';
  const units = ['B','KB','MB','GB','TB'];
  const place = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1);
  return `${(value / (1024 ** place)).toFixed(place > 1 ? 1 : 0)} ${units[place]}`;
}

function renderCatalogDetails() {
  const item = catalogModels.find(model => model.name === el.catalogSelect.value) || catalogModels[0];
  el.modelDetails.replaceChildren();
  if (!item) return;
  const title = document.createElement('strong');
  title.textContent = `${item.tier} · ${item.purpose}`;
  const details = document.createElement('span');
  const modalities = Array.isArray(item.modalities) ? item.modalities.join(' + ') : 'text';
  details.textContent = `${formatBytes(Number(item.size_bytes))} download · ${item.min_ram_gb} GB RAM guide · ${modalities}`;
  const lowMemory = Number(systemState.memoryBytes) > 0 && Number(systemState.memoryBytes) < Number(item.min_ram_gb) * 1024 ** 3;
  el.modelDetails.classList.toggle('warning', lowMemory);
  if (lowMemory) details.textContent += ' · may be too large for this machine';
  el.modelDetails.append(title, details);
}

function renderDownload(job) {
  const percent = Math.max(0, Math.min(100, Number(job.percent) || 0));
  el.downloadProgress.hidden = false;
  el.downloadProgressBar.style.width = `${percent}%`;
  el.downloadProgressPercent.textContent = `${percent}%`;
  const bytes = job.total > 0 ? `${formatBytes(job.completed)} / ${formatBytes(job.total)}` : '';
  el.downloadProgressLabel.textContent = [job.status || 'Downloading', bytes].filter(Boolean).join(' · ');
  el.downloadNote.textContent = `${job.model} is downloading locally. You can reload this page.`;
}

async function monitorDownload(jobId, model) {
  if (!jobId || monitoredDownloadId === jobId) return;
  monitoredDownloadId = jobId;
  el.downloadButton.disabled = true;
  el.catalogSelect.disabled = true;
  try {
    while (true) {
      const result = await api(`/api/models/pull/status?jobId=${encodeURIComponent(jobId)}`);
      const job = result.job;
      renderDownload(job);
      if (job.state === 'complete') {
        showNotice(`${model || job.model} is downloaded, verified, and selected.`, 'success');
        break;
      }
      if (job.state === 'failed') throw new Error(humanizeError(job.error || 'Model download failed.'));
      await new Promise(resolve => setTimeout(resolve, 750));
    }
  } catch (error) { showNotice(error.message); }
  finally {
    monitoredDownloadId = '';
    el.downloadProgress.hidden = true;
    el.downloadProgressBar.style.width = '0';
    el.downloadNote.textContent = 'Downloads are stored by Ollama on this machine.';
    await refreshState({ quiet: true });
  }
}

async function refreshState({ quiet = false } = {}) {
  el.refreshButton.disabled = true;
  try {
    renderState(await api(`/api/state?sessionId=${encodeURIComponent(el.sessionId.value.trim())}`));
  } catch (error) {
    if (!quiet) showNotice(error.message);
    el.runtimeLabel.textContent = 'Workbench unavailable';
    el.runtimeDot.className = 'status-dot warning';
  } finally {
    el.refreshButton.disabled = false;
  }
}

function appendText(container, text) {
  const lines = String(text).split(/\r?\n/);
  let paragraph = null;
  let code = null;
  for (const line of lines) {
    if (line.trim().startsWith('```')) {
      if (code) { container.append(code); code = null; }
      else { code = document.createElement('pre'); code.append(document.createElement('code')); }
      paragraph = null;
      continue;
    }
    if (code) { code.firstChild.textContent += `${code.firstChild.textContent ? '\n' : ''}${line}`; continue; }
    if (!line.trim()) { paragraph = null; continue; }
    if (!paragraph) { paragraph = document.createElement('p'); container.append(paragraph); }
    if (paragraph.textContent) paragraph.append(document.createElement('br'));
    paragraph.append(document.createTextNode(line));
  }
  if (code) container.append(code);
}

function addMessage(role, text, { thinking = false } = {}) {
  if (el.emptyState) { el.emptyState.remove(); el.emptyState = null; }
  const article = document.createElement('article');
  article.className = `message ${role}${thinking ? ' thinking' : ''}`;
  const avatar = document.createElement('div');
  avatar.className = 'message-avatar';
  avatar.textContent = role === 'user' ? 'You' : 'P';
  const content = document.createElement('div');
  const heading = document.createElement('div');
  heading.className = 'message-heading';
  const author = document.createElement('strong');
  author.textContent = role === 'user' ? 'You' : 'PIE';
  const time = document.createElement('time');
  time.textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  heading.append(author, time);
  const body = document.createElement('div');
  body.className = `message-body${thinking ? ' thinking-pulse' : ''}`;
  appendText(body, text);
  content.append(heading, body);
  article.append(avatar, content);
  el.messages.append(article);
  el.messages.scrollTop = el.messages.scrollHeight;
  return { article, body };
}

function updateComposer() {
  const count = el.messageInput.value.length;
  el.characterCount.textContent = `${count.toLocaleString()} / 30,000`;
  el.sendButton.disabled = !activeSession || asking || !el.messageInput.value.trim();
  el.messageInput.style.height = 'auto';
  el.messageInput.style.height = `${Math.min(el.messageInput.scrollHeight, 180)}px`;
}

el.refreshButton.addEventListener('click', () => refreshState());
el.sessionSelect.addEventListener('change', () => {
  if (!el.sessionSelect.value) return;
  el.sessionId.value = el.sessionSelect.value;
  localStorage.setItem('pie.sessionId', el.sessionId.value);
  clearConversation();
  refreshState();
});
el.newSessionButton.addEventListener('click', () => {
  setSession(null);
  el.sessionId.value = newSessionId();
  el.sessionSelect.value = '';
  el.goal.value = '';
  localStorage.setItem('pie.sessionId', el.sessionId.value);
  clearConversation();
  el.goal.focus();
});
el.runtimeButton.addEventListener('click', async () => {
  const action = el.runtimeButton.dataset.action || 'start';
  setBusy(el.runtimeButton, true, action === 'install' ? 'Installing...' : 'Starting...');
  try {
    if (action === 'install') await api('/api/runtime/install', { method: 'POST', body: '{}' });
    await api('/api/runtime/start', { method: 'POST', body: '{}' });
    showNotice('The local model runtime is ready.', 'success');
    await refreshState({ quiet: true });
  } catch (error) { showNotice(error.message); }
  finally { setBusy(el.runtimeButton, false, action === 'install' ? 'Install Ollama' : 'Start runtime'); }
});
el.sessionId.addEventListener('change', () => {
  localStorage.setItem('pie.sessionId', el.sessionId.value.trim());
  clearConversation();
  refreshState({ quiet: true });
});

el.startButton.addEventListener('click', async () => {
  const sessionId = el.sessionId.value.trim();
  localStorage.setItem('pie.sessionId', sessionId);
  setBusy(el.startButton, true, 'Starting...');
  try {
    const result = await api('/api/session/start', { method: 'POST', body: JSON.stringify({
      sessionId, targetRepo: el.targetRepo.value.trim(), goal: el.goal.value.trim(), model: el.modelSelect.value
    }) });
    setSession(result.session);
    await syncConversation(result.session, true);
    await refreshSessions();
    showNotice(`Session ${sessionId} is running${isHosted ? ' in your private workspace' : ' locally'}.`, 'success');
    el.messageInput.focus();
  } catch (error) { showNotice(error.message); }
  finally {
    setBusy(el.startButton, false, 'Start');
    if (activeSession) el.startButton.disabled = true;
  }
});

el.stopButton.addEventListener('click', async () => {
  setBusy(el.stopButton, true, 'Stopping...');
  try {
    await api('/api/session/stop', { method: 'POST', body: JSON.stringify({ sessionId: activeSession.id }) });
    setSession({ ...activeSession, status: 'stopped' });
    await refreshSessions();
    showNotice(isHosted ? 'Session stopped. Its workspace history remains available.' : 'Session stopped. Its local artifacts remain available.', 'success');
  } catch (error) { showNotice(error.message); }
  finally {
    setBusy(el.stopButton, false, 'Stop');
    if (!activeSession) el.stopButton.disabled = true;
  }
});

el.haaiButton.addEventListener('click', async () => {
  const session = activeSession || (el.sessionId.value.trim() ? { id: el.sessionId.value.trim() } : null);
  if (!session) return;
  setBusy(el.haaiButton, true, 'Preserving...');
  try {
    const result = await api('/api/haai/capture', { method: 'POST', body: JSON.stringify({ sessionId: session.id, turnIndex: 0 }) });
    showNotice(`Verified HAAI packet ${result.packetId.slice(0, 12)}... preserved${isHosted ? ' in your workspace' : ' locally'}.`, 'success');
  } catch (error) { showNotice(error.message); }
  finally { setBusy(el.haaiButton, false, 'Preserve'); }
});

el.backupButton.addEventListener('click', async () => {
  if (!selectedSession) return;
  const passphrase = await requestBackupPassphrase(true);
  if (!passphrase) return;
  setBusy(el.backupButton, true, '...');
  try {
    const result = await api('/api/session/backup', { method: 'POST', body: JSON.stringify({ sessionId: selectedSession.id, passphrase }) });
    showNotice(`Verified backup ${result.backupId.slice(0, 12)}... saved to ${result.archive}.`, 'success');
  } catch (error) { showNotice(error.message); }
  finally { setBusy(el.backupButton, false, '\u2193'); }
});

el.restoreButton.addEventListener('click', async () => {
  if (!window.pieDesktop) return;
  const chosen = await window.pieDesktop.chooseSessionBackup();
  if (!chosen || chosen.canceled || !chosen.path) return;
  const passphrase = await requestBackupPassphrase(false);
  if (!passphrase) return;
  setBusy(el.restoreButton, true, '...');
  try {
    const result = await api('/api/session/restore', { method: 'POST', body: JSON.stringify({ archivePath: chosen.path, passphrase }) });
    el.sessionId.value = result.session.id;
    localStorage.setItem('pie.sessionId', result.session.id);
    await refreshSessions();
    setSession(result.session);
    await syncConversation(result.session, true);
    showNotice(`Conversation ${result.session.id} restored and verified.`, 'success');
  } catch (error) { showNotice(error.message); }
  finally { setBusy(el.restoreButton, false, '\u21ba'); }
});

el.modelSelect.addEventListener('change', async () => {
  const model = el.modelSelect.value;
  if (!model) return;
  try {
    await api('/api/models/select', { method: 'POST', body: JSON.stringify({ model }) });
    el.modelNote.textContent = activeSession ? `Default: ${model} · restart session to switch` : `Default: ${model}`;
    showNotice(`${model} is now the default${isHosted ? '' : ' local'} model.`, 'success');
  } catch (error) { showNotice(error.message); refreshState({ quiet: true }); }
});
el.catalogSelect.addEventListener('change', renderCatalogDetails);

el.downloadButton.addEventListener('click', async () => {
  const model = el.catalogSelect.value;
  if (!model) return;
  setBusy(el.downloadButton, true, 'Starting...');
  el.catalogSelect.disabled = true;
  try {
    const result = await api('/api/models/pull', { method: 'POST', body: JSON.stringify({ model }) });
    setBusy(el.downloadButton, false, 'Download');
    await monitorDownload(result.job.id, model);
  } catch (error) { showNotice(error.message); }
  finally {
    setBusy(el.downloadButton, false, 'Download');
    if (!monitoredDownloadId) el.catalogSelect.disabled = !el.catalogSelect.options.length;
  }
});

el.messageInput.addEventListener('input', updateComposer);
el.messageInput.addEventListener('keydown', event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    if (!el.sendButton.disabled) el.composer.requestSubmit();
  }
});

el.composer.addEventListener('submit', async event => {
  event.preventDefault();
  const text = el.messageInput.value.trim();
  if (!activeSession || !text || asking) return;
  const session = activeSession;
  addMessage('user', text);
  el.messageInput.value = '';
  asking = true;
  setSession(session);
  const thinking = addMessage('assistant', 'Thinking locally · 0s', { thinking: true });
  const started = Date.now();
  thinkingTimer = setInterval(() => {
    const seconds = Math.floor((Date.now() - started) / 1000);
    thinking.body.firstChild.textContent = `Thinking locally · ${seconds}s`;
    el.thinkingStatus.textContent = `Thinking · ${seconds}s`;
  }, 1000);
  try {
    const result = await api('/api/ask', { method: 'POST', body: JSON.stringify({ sessionId: session.id, text, timeoutSeconds: 180 }) });
    thinking.article.remove();
    addMessage('assistant', result.answer || 'PIE completed the request without a text response.');
    session.turns = Number(session.turns || 0) + 1;
    loadedConversationKey = `${session.id}:${session.turns}`;
  } catch (error) {
    thinking.article.remove();
    addMessage('assistant', `Request failed: ${error.message}`);
    showNotice(error.message);
  } finally {
    clearInterval(thinkingTimer);
    asking = false;
    setSession(session);
    updateComposer();
    el.messageInput.focus();
  }
});

updateComposer();
Promise.all([refreshProjects(), refreshSessions(), refreshState()]).catch(error => showNotice(error.message));
}
