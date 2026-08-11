'use strict';

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { materializeRuntime } = require('../runtime-workspace');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pie-runtime-workspace-'));
const source = path.join(root, 'source');
const workspace = path.join(root, 'workspace');

function write(relative, text) {
  const target = path.join(source, ...relative.split('/'));
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, text, 'utf8');
}

function manifest(version, files) {
  const entries = files.map(relative => {
    const target = path.join(source, ...relative.split('/'));
    const bytes = fs.readFileSync(target);
    return { path: relative, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') };
  });
  fs.writeFileSync(path.join(source, 'PIE_RELEASE_MANIFEST.json'), `${JSON.stringify({ schema: 'pie.release.manifest.v1', version, files: entries }, null, 2)}\n`);
}

try {
  fs.mkdirSync(source, { recursive: true });
  write('pie.ps1', 'version one\n');
  write('scripts/tool.ps1', 'tool one\n');
  write('memory/policy.json', '{"mode":"ask"}\n');
  write('runs/legacy/conversation.ndjson', 'legacy state\n');
  manifest('one', ['pie.ps1', 'scripts/tool.ps1', 'memory/policy.json']);
  materializeRuntime({ sourceRoot: source, workspaceRoot: workspace, appVersion: '1.0.0' });
  if (fs.readFileSync(path.join(workspace, 'runs', 'legacy', 'conversation.ndjson'), 'utf8') !== 'legacy state\n') throw new Error('legacy state not migrated');
  if (!fs.existsSync(path.join(workspace, '.pie', 'desktop-migrations', 'legacy-runtime-to-workspace.json'))) throw new Error('legacy migration receipt missing');
  fs.writeFileSync(path.join(workspace, 'memory', 'policy.json'), '{"mode":"off"}\n');
  fs.mkdirSync(path.join(workspace, 'runs', 'session'), { recursive: true });
  fs.writeFileSync(path.join(workspace, 'runs', 'session', 'conversation.ndjson'), 'preserve\n');
  fs.writeFileSync(path.join(workspace, 'scripts', 'stale.ps1'), 'stale\n');

  write('pie.ps1', 'version two\n');
  write('scripts/tool.ps1', 'tool two\n');
  write('memory/policy.json', '{"mode":"auto_accept"}\n');
  manifest('two', ['pie.ps1', 'scripts/tool.ps1', 'memory/policy.json']);
  materializeRuntime({ sourceRoot: source, workspaceRoot: workspace, appVersion: '2.0.0' });
  if (fs.readFileSync(path.join(workspace, 'pie.ps1'), 'utf8') !== 'version two\n') throw new Error('immutable code not updated');
  if (fs.readFileSync(path.join(workspace, 'memory', 'policy.json'), 'utf8') !== '{"mode":"off"}\n') throw new Error('mutable policy overwritten');
  if (fs.readFileSync(path.join(workspace, 'runs', 'session', 'conversation.ndjson'), 'utf8') !== 'preserve\n') throw new Error('session state lost');
  if (fs.existsSync(path.join(workspace, 'scripts', 'stale.ps1'))) throw new Error('stale runtime file retained');

  fs.appendFileSync(path.join(source, 'scripts', 'tool.ps1'), 'tamper\n');
  let tamperRejected = false;
  try { materializeRuntime({ sourceRoot: source, workspaceRoot: workspace, appVersion: '2.0.0' }); }
  catch (error) { tamperRejected = error.message.includes('SOURCE_HASH_MISMATCH'); }
  if (!tamperRejected) throw new Error('tampered source accepted');

  write('scripts/tool.ps1', 'tool two\n');
  const badManifest = { schema: 'pie.release.manifest.v1', version: 'bad', files: [{ path: '../escape', bytes: 0, sha256: '0'.repeat(64) }] };
  fs.writeFileSync(path.join(source, 'PIE_RELEASE_MANIFEST.json'), `${JSON.stringify(badManifest)}\n`);
  let traversalRejected = false;
  try { materializeRuntime({ sourceRoot: source, workspaceRoot: workspace, appVersion: '2.0.0' }); }
  catch (error) { traversalRejected = error.message.includes('MANIFEST_PATH_INVALID'); }
  if (!traversalRejected) throw new Error('manifest traversal accepted');

  manifest('two', ['pie.ps1', 'scripts/tool.ps1', 'memory/policy.json']);
  const linkedWorkspace = path.join(root, 'linked-workspace');
  fs.mkdirSync(linkedWorkspace);
  fs.mkdirSync(path.join(root, 'outside'));
  let linkTested = false;
  try {
    fs.symlinkSync(path.join(root, 'outside'), path.join(linkedWorkspace, 'runs'), 'junction');
    linkTested = true;
  } catch {}
  if (linkTested) {
    let linkRejected = false;
    try { materializeRuntime({ sourceRoot: source, workspaceRoot: linkedWorkspace, appVersion: '2.0.0' }); }
    catch (error) { linkRejected = error.message.includes('MUTABLE_LINK_REJECTED'); }
    if (!linkRejected) throw new Error('mutable link accepted');
  }
  process.stdout.write('PIE_DESKTOP_RUNTIME_WORKSPACE_SELFTEST_OK\n');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
