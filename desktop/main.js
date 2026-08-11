'use strict';

const { app, BrowserWindow, dialog, ipcMain, session } = require('electron');
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const http = require('http');
const net = require('net');
const path = require('path');
const { materializeRuntime } = require('./runtime-workspace');

let mainWindow = null;
let serverProcess = null;
let localOrigin = '';
let smokeReceiptWritten = false;
const smokeTest = process.argv.includes('--smoke-test');

function logDesktop(message, details = '') {
  try {
    const logPath = path.join(app.getPath('userData'), 'desktop.log');
    const suffix = details ? ` ${String(details).replace(/[\r\n]+/g, ' ')}` : '';
    fs.appendFileSync(logPath, `${new Date().toISOString()} ${message}${suffix}\n`, 'utf8');
  } catch {
    // Diagnostics must never prevent the private local runtime from starting.
  }
}

function completeSmokeTest(reason) {
  if (!smokeTest || smokeReceiptWritten || !mainWindow || mainWindow.isDestroyed()) return;
  const nativeHandle = mainWindow.getNativeWindowHandle().toString('hex');
  const receipt = {
    schema: 'pie.desktop.smoke.v1',
    status: mainWindow.isVisible() && /[1-9a-f]/i.test(nativeHandle) ? 'ok' : 'failed',
    visible: mainWindow.isVisible(),
    native_handle: nativeHandle,
    reveal_reason: reason,
    origin: localOrigin,
    runtime_pid: serverProcess ? serverProcess.pid : null,
  };
  const receiptPath = path.join(app.getPath('userData'), 'desktop-smoke.json');
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, 'utf8');
  smokeReceiptWritten = true;
  logDesktop('smoke.completed', `status=${receipt.status} visible=${receipt.visible} handle=${nativeHandle}`);
  setTimeout(() => app.quit(), 1000).unref();
}

function runtimeRoot() {
  return app.isPackaged ? path.join(app.getPath('userData'), 'workspace') : path.resolve(__dirname, '..');
}

function prepareRuntime() {
  if (!app.isPackaged) return;
  const result = materializeRuntime({
    sourceRoot: path.join(process.resourcesPath, 'runtime'),
    workspaceRoot: runtimeRoot(),
    appVersion: app.getVersion(),
  });
  logDesktop('runtime.materialized', `files=${result.fileCount} manifest=${result.manifestSha256} workspace=${result.workspace}`);
}

function repositoryStorePath() {
  return path.join(app.getPath('userData'), 'repositories.json');
}

function readRepositories() {
  try {
    const data = JSON.parse(fs.readFileSync(repositoryStorePath(), 'utf8'));
    if (!Array.isArray(data.repositories)) return [];
    return data.repositories.filter(item => item && typeof item.path === 'string' && fs.existsSync(item.path)).slice(0, 12);
  } catch {
    return [];
  }
}

function rememberRepository(repositoryPath) {
  const resolved = path.resolve(repositoryPath);
  const repositories = readRepositories().filter(item => item.path.toLowerCase() !== resolved.toLowerCase());
  repositories.unshift({ name: path.basename(resolved), path: resolved, openedUtc: new Date().toISOString() });
  fs.mkdirSync(path.dirname(repositoryStorePath()), { recursive: true });
  fs.writeFileSync(repositoryStorePath(), `${JSON.stringify({ schema: 'pie.desktop.repositories.v1', repositories: repositories.slice(0, 12) }, null, 2)}\n`, 'utf8');
  return repositories[0];
}

function validSender(event) {
  const senderUrl = event.senderFrame && event.senderFrame.url;
  return typeof senderUrl === 'string' && localOrigin && senderUrl.startsWith(`${localOrigin}/`);
}

function registerDesktopApi() {
  ipcMain.handle('pie:list-repositories', event => {
    if (!validSender(event)) throw new Error('PIE_DESKTOP_SENDER_REJECTED');
    return readRepositories();
  });
  ipcMain.handle('pie:choose-repository', async event => {
    if (!validSender(event)) throw new Error('PIE_DESKTOP_SENDER_REJECTED');
    const result = await dialog.showOpenDialog(mainWindow, {
      title: 'Open a repository in PIE',
      properties: ['openDirectory'],
    });
    if (result.canceled || !result.filePaths[0]) return { canceled: true };
    return { canceled: false, ...rememberRepository(result.filePaths[0]) };
  });
  ipcMain.handle('pie:choose-session-backup', async event => {
    if (!validSender(event)) throw new Error('PIE_DESKTOP_SENDER_REJECTED');
    const result = await dialog.showOpenDialog(mainWindow, {
      title: 'Restore a PIE conversation backup',
      properties: ['openFile'],
      filters: [{ name: 'Encrypted PIE session backup', extensions: ['piebak'] }],
    });
    if (result.canceled || !result.filePaths[0]) return { canceled: true };
    return { canceled: false, path: result.filePaths[0] };
  });
}

function availablePort() {
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.unref();
    probe.on('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const address = probe.address();
      probe.close(() => resolve(address.port));
    });
  });
}

function waitForServer(origin, attempts = 80) {
  return new Promise((resolve, reject) => {
    let remaining = attempts;
    const retry = () => {
      remaining -= 1;
      if (remaining <= 0) reject(new Error('PIE_DESKTOP_SERVER_NOT_READY'));
      else setTimeout(check, 150);
    };
    const check = () => {
      const request = http.get(`${origin}/health`, response => {
        response.resume();
        if (response.statusCode === 200) resolve();
        else retry();
      });
      request.setTimeout(1000, () => request.destroy());
      request.on('error', retry);
    };
    check();
  });
}

async function startLocalRuntime() {
  const root = runtimeRoot();
  const server = path.join(root, 'workbench', 'server.js');
  if (!fs.existsSync(server)) throw new Error(`PIE_DESKTOP_SERVER_MISSING: ${server}`);
  const port = await availablePort();
  localOrigin = `http://127.0.0.1:${port}`;
  serverProcess = spawn(process.execPath, [server, '--repo-root', root, '--port', String(port)], {
    cwd: root,
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  logDesktop('runtime.spawned', `pid=${serverProcess.pid} origin=${localOrigin}`);
  let serverError = '';
  serverProcess.stdout.on('data', chunk => logDesktop('runtime.stdout', chunk.toString('utf8')));
  serverProcess.stderr.on('data', chunk => {
    serverError += chunk.toString('utf8');
    logDesktop('runtime.stderr', chunk.toString('utf8'));
  });
  serverProcess.on('exit', code => {
    logDesktop('runtime.exited', `code=${code}`);
    if (code && !app.isQuitting) dialog.showErrorBox('PIE runtime stopped', serverError || `The local runtime exited with code ${code}.`);
  });
  await waitForServer(localOrigin);
  logDesktop('runtime.ready', localOrigin);
}

function createWindow() {
  logDesktop('window.creating');
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 940,
    minWidth: 980,
    minHeight: 680,
    backgroundColor: '#181419',
    show: false,
    title: 'PIE',
    icon: path.join(runtimeRoot(), 'workbench', 'public', 'pie-icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
    },
  });
  logDesktop('window.created', `id=${mainWindow.id}`);
  let revealed = false;
  const revealWindow = reason => {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    if (!revealed) logDesktop('window.revealed', reason);
    revealed = true;
    mainWindow.center();
    mainWindow.show();
    mainWindow.focus();
    logDesktop('window.state', `visible=${mainWindow.isVisible()} focused=${mainWindow.isFocused()} handle=${mainWindow.getNativeWindowHandle().toString('hex')}`);
    completeSmokeTest(reason);
  };
  mainWindow.once('ready-to-show', () => revealWindow('ready-to-show'));
  mainWindow.webContents.once('did-finish-load', () => revealWindow('did-finish-load'));
  mainWindow.webContents.on('did-fail-load', (_event, code, description, url) => {
    logDesktop('window.load-failed', `code=${code} description=${description} url=${url}`);
  });
  mainWindow.webContents.on('render-process-gone', (_event, details) => {
    logDesktop('window.renderer-gone', JSON.stringify(details));
  });
  mainWindow.on('closed', () => {
    logDesktop('window.closed');
    mainWindow = null;
  });
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!url.startsWith(`${localOrigin}/`)) event.preventDefault();
  });
  mainWindow.loadURL(`${localOrigin}/?surface=desktop`).catch(error => {
    logDesktop('window.load-rejected', error.message);
    dialog.showErrorBox('PIE workbench could not load', error.message);
    app.quit();
  });
  setTimeout(() => revealWindow('startup-fallback'), 5000).unref();
}

function stopLocalRuntime() {
  if (!serverProcess || serverProcess.killed) return;
  if (process.platform === 'win32' && Number.isInteger(serverProcess.pid)) {
    spawnSync('taskkill.exe', ['/pid', String(serverProcess.pid), '/t', '/f'], { windowsHide: true, stdio: 'ignore' });
  } else {
    serverProcess.kill('SIGTERM');
  }
  serverProcess = null;
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  });
  app.whenReady().then(async () => {
    logDesktop('app.ready', `version=${app.getVersion()} packaged=${app.isPackaged} smoke=${smokeTest}`);
    prepareRuntime();
    session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
    registerDesktopApi();
    await startLocalRuntime();
    createWindow();
  }).catch(error => {
    logDesktop('app.start-failed', error.stack || error.message);
    dialog.showErrorBox('PIE could not start', error.message);
    app.quit();
  });
}

app.on('before-quit', () => {
  app.isQuitting = true;
  logDesktop('app.before-quit');
});
app.on('window-all-closed', () => app.quit());
app.on('will-quit', () => {
  stopLocalRuntime();
});
