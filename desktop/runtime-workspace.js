'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const mutableRoots = new Set(['memory', 'runs', '.pie']);

function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  const handle = fs.openSync(filePath, 'r');
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  try {
    let bytesRead = 0;
    do {
      bytesRead = fs.readSync(handle, buffer, 0, buffer.length, null);
      if (bytesRead) hash.update(buffer.subarray(0, bytesRead));
    } while (bytesRead);
  } finally {
    fs.closeSync(handle);
  }
  return hash.digest('hex');
}

function safeRelative(value) {
  if (typeof value !== 'string' || !value || value.includes('\\')) throw new Error('PIE_DESKTOP_RUNTIME_MANIFEST_PATH_INVALID');
  const normalized = path.posix.normalize(value);
  if (normalized !== value || normalized.startsWith('../') || path.posix.isAbsolute(normalized)) {
    throw new Error(`PIE_DESKTOP_RUNTIME_MANIFEST_PATH_INVALID: ${value}`);
  }
  return normalized;
}

function isMutable(relative) {
  return mutableRoots.has(relative.split('/')[0]);
}

function ensureOrdinaryParents(root, destination) {
  let current = path.dirname(destination);
  const pending = [];
  while (current !== root) {
    if (!current.startsWith(`${root}${path.sep}`)) throw new Error('PIE_DESKTOP_RUNTIME_DESTINATION_ESCAPE');
    pending.push(current);
    current = path.dirname(current);
  }
  for (const directory of pending.reverse()) {
    if (fs.existsSync(directory)) {
      if (!fs.lstatSync(directory).isDirectory() || fs.lstatSync(directory).isSymbolicLink()) {
        throw new Error(`PIE_DESKTOP_RUNTIME_DESTINATION_LINK_REJECTED: ${directory}`);
      }
    } else fs.mkdirSync(directory);
  }
}

function atomicCopy(source, destination, root) {
  ensureOrdinaryParents(root, destination);
  if (fs.existsSync(destination) && fs.lstatSync(destination).isSymbolicLink()) {
    throw new Error(`PIE_DESKTOP_RUNTIME_DESTINATION_LINK_REJECTED: ${destination}`);
  }
  const temporary = `${destination}.pie-tmp-${crypto.randomUUID()}`;
  fs.copyFileSync(source, temporary, fs.constants.COPYFILE_EXCL);
  fs.renameSync(temporary, destination);
}

function validateMutableTree(target) {
  if (!fs.existsSync(target)) return;
  const stat = fs.lstatSync(target);
  if (stat.isSymbolicLink()) throw new Error(`PIE_DESKTOP_RUNTIME_MUTABLE_LINK_REJECTED: ${target}`);
  if (!stat.isDirectory()) throw new Error(`PIE_DESKTOP_RUNTIME_MUTABLE_ROOT_INVALID: ${target}`);
  for (const entry of fs.readdirSync(target, { withFileTypes: true })) {
    const child = path.join(target, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`PIE_DESKTOP_RUNTIME_MUTABLE_LINK_REJECTED: ${child}`);
    if (entry.isDirectory()) validateMutableTree(child);
  }
}

function copyMutableTree(source, destination, records, relativeRoot) {
  const stat = fs.lstatSync(source);
  if (stat.isSymbolicLink()) throw new Error(`PIE_DESKTOP_RUNTIME_MUTABLE_LINK_REJECTED: ${source}`);
  if (stat.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    for (const name of fs.readdirSync(source)) {
      copyMutableTree(path.join(source, name), path.join(destination, name), records, `${relativeRoot}/${name}`);
    }
    return;
  }
  if (!stat.isFile()) throw new Error(`PIE_DESKTOP_RUNTIME_MUTABLE_ENTRY_INVALID: ${source}`);
  fs.copyFileSync(source, destination, fs.constants.COPYFILE_EXCL);
  records.push({ path: relativeRoot, bytes: stat.size, sha256: sha256File(destination) });
}

function removeStaleImmutable(directory, root, expected) {
  if (!fs.existsSync(directory)) return;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (directory === root && mutableRoots.has(entry.name)) {
      validateMutableTree(fullPath);
      continue;
    }
    if (entry.isSymbolicLink()) throw new Error(`PIE_DESKTOP_RUNTIME_WORKSPACE_LINK_REJECTED: ${fullPath}`);
    if (entry.isDirectory()) {
      removeStaleImmutable(fullPath, root, expected);
      if (!fs.readdirSync(fullPath).length) fs.rmdirSync(fullPath);
      continue;
    }
    const relative = path.relative(root, fullPath).split(path.sep).join('/');
    if (!expected.has(relative) && relative !== 'PIE_RELEASE_MANIFEST.json' && relative !== 'runtime-state.json') fs.unlinkSync(fullPath);
  }
}

function materializeRuntime({ sourceRoot, workspaceRoot, appVersion }) {
  const source = path.resolve(sourceRoot);
  const workspace = path.resolve(workspaceRoot);
  const manifestPath = path.join(source, 'PIE_RELEASE_MANIFEST.json');
  if (!fs.existsSync(manifestPath)) throw new Error('PIE_DESKTOP_RUNTIME_MANIFEST_MISSING');
  const manifestBytes = fs.readFileSync(manifestPath);
  let manifest;
  try { manifest = JSON.parse(manifestBytes.toString('utf8')); }
  catch (error) { throw new Error(`PIE_DESKTOP_RUNTIME_MANIFEST_INVALID: ${error.message}`); }
  if (manifest.schema !== 'pie.release.manifest.v1' || !Array.isArray(manifest.files)) {
    throw new Error('PIE_DESKTOP_RUNTIME_MANIFEST_SCHEMA_BAD');
  }

  const entries = manifest.files.map(item => {
    const relative = safeRelative(item.path);
    if (!/^[0-9a-f]{64}$/.test(item.sha256) || !Number.isSafeInteger(item.bytes) || item.bytes < 0) {
      throw new Error(`PIE_DESKTOP_RUNTIME_MANIFEST_ENTRY_INVALID: ${relative}`);
    }
    const sourcePath = path.resolve(source, ...relative.split('/'));
    if (!sourcePath.startsWith(`${source}${path.sep}`) || !fs.existsSync(sourcePath) || !fs.lstatSync(sourcePath).isFile() || fs.lstatSync(sourcePath).isSymbolicLink()) {
      throw new Error(`PIE_DESKTOP_RUNTIME_SOURCE_INVALID: ${relative}`);
    }
    const stat = fs.statSync(sourcePath);
    if (stat.size !== item.bytes || sha256File(sourcePath) !== item.sha256) {
      throw new Error(`PIE_DESKTOP_RUNTIME_SOURCE_HASH_MISMATCH: ${relative}`);
    }
    return { relative, sourcePath, bytes: item.bytes, sha256: item.sha256 };
  });
  if (new Set(entries.map(item => item.relative)).size !== entries.length) throw new Error('PIE_DESKTOP_RUNTIME_MANIFEST_DUPLICATE_PATH');

  fs.mkdirSync(workspace, { recursive: true });
  if (fs.lstatSync(workspace).isSymbolicLink()) throw new Error('PIE_DESKTOP_RUNTIME_WORKSPACE_LINK_REJECTED');
  const migrated = [];
  for (const rootName of mutableRoots) {
    const legacyRoot = path.join(source, rootName);
    const destinationRoot = path.join(workspace, rootName);
    if (fs.existsSync(legacyRoot) && !fs.existsSync(destinationRoot)) {
      validateMutableTree(legacyRoot);
      copyMutableTree(legacyRoot, destinationRoot, migrated, rootName);
    }
  }
  if (migrated.length) {
    const receiptRoot = path.join(workspace, '.pie', 'desktop-migrations');
    fs.mkdirSync(receiptRoot, { recursive: true });
    const receipt = {
      schema: 'pie.desktop.legacy-migration.v1',
      source,
      destination: workspace,
      files: migrated.sort((left, right) => left.path.localeCompare(right.path)),
      migrated_utc: new Date().toISOString(),
    };
    fs.writeFileSync(path.join(receiptRoot, 'legacy-runtime-to-workspace.json'), `${JSON.stringify(receipt, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' });
  }
  const expected = new Set(entries.map(item => item.relative));
  removeStaleImmutable(workspace, workspace, expected);

  for (const entry of entries) {
    const destination = path.join(workspace, ...entry.relative.split('/'));
    if (isMutable(entry.relative) && fs.existsSync(destination)) continue;
    if (!fs.existsSync(destination) || fs.statSync(destination).size !== entry.bytes || sha256File(destination) !== entry.sha256) {
      atomicCopy(entry.sourcePath, destination, workspace);
    }
  }
  atomicCopy(manifestPath, path.join(workspace, 'PIE_RELEASE_MANIFEST.json'), workspace);
  const state = {
    schema: 'pie.desktop.runtime-state.v1',
    app_version: appVersion,
    source_manifest_sha256: crypto.createHash('sha256').update(manifestBytes).digest('hex'),
    mutable_roots: Array.from(mutableRoots).sort(),
    synchronized_utc: new Date().toISOString(),
  };
  const statePath = path.join(workspace, 'runtime-state.json');
  const temporaryState = `${statePath}.pie-tmp-${crypto.randomUUID()}`;
  fs.writeFileSync(temporaryState, `${JSON.stringify(state, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' });
  fs.renameSync(temporaryState, statePath);
  return { workspace, manifestSha256: state.source_manifest_sha256, fileCount: entries.length };
}

module.exports = { materializeRuntime, sha256File };
