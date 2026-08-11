'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const MAGIC = Buffer.from('PIEBAK2\n', 'ascii');
const TAG_BYTES = 16;
const HEADER_LIMIT = 4096;
const SCRYPT = Object.freeze({ N: 131072, r: 8, p: 1, maxmem: 256 * 1024 * 1024 });

function fail(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}

function readPassphrase() {
  return new Promise((resolve, reject) => {
    const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity, terminal: false });
    let settled = false;
    input.once('line', line => {
      settled = true;
      input.close();
      const normalized = line.normalize('NFKC');
      if (normalized.length < 14 || normalized.length > 1024) reject(new Error('PIE_SESSION_BACKUP_PASSPHRASE_LENGTH_INVALID'));
      else resolve(normalized);
    });
    input.once('close', () => { if (!settled) reject(new Error('PIE_SESSION_BACKUP_PASSPHRASE_REQUIRED')); });
  });
}

function deriveKey(passphrase, salt, parameters) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(passphrase, salt, 32, parameters, (error, key) => error ? reject(error) : resolve(key));
  });
}

function pipeline(source, transform, destination) {
  return new Promise((resolve, reject) => {
    const streams = [source, transform, destination];
    const abort = error => {
      for (const stream of streams) stream.destroy();
      reject(error);
    };
    source.once('error', abort);
    transform.once('error', abort);
    destination.once('error', abort);
    transform.once('end', resolve);
    source.pipe(transform).pipe(destination, { end: false });
  });
}

async function encrypt(inputPath, outputPath, passphrase) {
  const source = path.resolve(inputPath);
  const destination = path.resolve(outputPath);
  if (!fs.statSync(source).isFile()) fail('PIE_SESSION_BACKUP_CRYPTO_INPUT_INVALID');
  if (fs.existsSync(destination)) fail('PIE_SESSION_BACKUP_CRYPTO_OUTPUT_EXISTS');
  const salt = crypto.randomBytes(32);
  const nonce = crypto.randomBytes(12);
  const header = Buffer.from(JSON.stringify({
    schema: 'pie.session.encrypted.v1', cipher: 'aes-256-gcm', tag_bytes: TAG_BYTES,
    kdf: 'scrypt', N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p,
    salt: salt.toString('base64'), nonce: nonce.toString('base64'),
  }), 'utf8');
  if (header.length > HEADER_LIMIT) fail('PIE_SESSION_BACKUP_CRYPTO_HEADER_TOO_LARGE');
  const prefix = Buffer.alloc(MAGIC.length + 4 + header.length);
  MAGIC.copy(prefix, 0);
  prefix.writeUInt32BE(header.length, MAGIC.length);
  header.copy(prefix, MAGIC.length + 4);
  const key = await deriveKey(passphrase, salt, SCRYPT);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce, { authTagLength: TAG_BYTES });
  cipher.setAAD(header);
  const output = fs.createWriteStream(destination, { flags: 'wx', mode: 0o600 });
  try {
    output.write(prefix);
    await pipeline(fs.createReadStream(source), cipher, output);
    output.end(cipher.getAuthTag());
    await new Promise((resolve, reject) => { output.once('close', resolve); output.once('error', reject); });
  } catch (error) {
    output.destroy();
    try { fs.unlinkSync(destination); } catch {}
    throw error;
  } finally {
    key.fill(0);
  }
  return { schema: 'pie.session.encryption.result.v1', status: 'encrypted', bytes: fs.statSync(destination).size };
}

function readEnvelope(source) {
  const descriptor = fs.openSync(source, 'r');
  try {
    const fixed = Buffer.alloc(MAGIC.length + 4);
    if (fs.readSync(descriptor, fixed, 0, fixed.length, 0) !== fixed.length || !fixed.subarray(0, MAGIC.length).equals(MAGIC)) fail('PIE_SESSION_BACKUP_ENCRYPTED_MAGIC_BAD');
    const headerLength = fixed.readUInt32BE(MAGIC.length);
    if (headerLength < 32 || headerLength > HEADER_LIMIT) fail('PIE_SESSION_BACKUP_CRYPTO_HEADER_LENGTH_INVALID');
    const headerBytes = Buffer.alloc(headerLength);
    if (fs.readSync(descriptor, headerBytes, 0, headerLength, fixed.length) !== headerLength) fail('PIE_SESSION_BACKUP_CRYPTO_HEADER_TRUNCATED');
    let header;
    try { header = JSON.parse(headerBytes.toString('utf8')); } catch { fail('PIE_SESSION_BACKUP_CRYPTO_HEADER_INVALID'); }
    if (header.schema !== 'pie.session.encrypted.v1' || header.cipher !== 'aes-256-gcm' || header.tag_bytes !== TAG_BYTES || header.kdf !== 'scrypt' || header.N !== SCRYPT.N || header.r !== SCRYPT.r || header.p !== SCRYPT.p) fail('PIE_SESSION_BACKUP_CRYPTO_PROFILE_REJECTED');
    const salt = Buffer.from(header.salt, 'base64');
    const nonce = Buffer.from(header.nonce, 'base64');
    if (salt.length !== 32 || nonce.length !== 12) fail('PIE_SESSION_BACKUP_CRYPTO_PARAMETER_INVALID');
    const size = fs.fstatSync(descriptor).size;
    const ciphertextStart = fixed.length + headerLength;
    const ciphertextLength = size - ciphertextStart - TAG_BYTES;
    if (ciphertextLength <= 0) fail('PIE_SESSION_BACKUP_CIPHERTEXT_TRUNCATED');
    const tag = Buffer.alloc(TAG_BYTES);
    if (fs.readSync(descriptor, tag, 0, TAG_BYTES, size - TAG_BYTES) !== TAG_BYTES) fail('PIE_SESSION_BACKUP_AUTH_TAG_TRUNCATED');
    return { header, headerBytes, salt, nonce, tag, ciphertextStart, ciphertextLength };
  } finally { fs.closeSync(descriptor); }
}

async function decrypt(inputPath, outputPath, passphrase) {
  const source = path.resolve(inputPath);
  const destination = path.resolve(outputPath);
  if (!fs.statSync(source).isFile()) fail('PIE_SESSION_BACKUP_CRYPTO_INPUT_INVALID');
  if (fs.existsSync(destination)) fail('PIE_SESSION_BACKUP_CRYPTO_OUTPUT_EXISTS');
  const envelope = readEnvelope(source);
  const key = await deriveKey(passphrase, envelope.salt, SCRYPT);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, envelope.nonce, { authTagLength: TAG_BYTES });
  decipher.setAAD(envelope.headerBytes);
  decipher.setAuthTag(envelope.tag);
  const output = fs.createWriteStream(destination, { flags: 'wx', mode: 0o600 });
  try {
    await pipeline(fs.createReadStream(source, { start: envelope.ciphertextStart, end: envelope.ciphertextStart + envelope.ciphertextLength - 1 }), decipher, output);
    output.end();
    await new Promise((resolve, reject) => { output.once('close', resolve); output.once('error', reject); });
  } catch (error) {
    output.destroy();
    try { fs.unlinkSync(destination); } catch {}
    const wrapped = new Error('PIE_SESSION_BACKUP_DECRYPT_AUTH_FAILED');
    wrapped.cause = error;
    throw wrapped;
  } finally {
    key.fill(0);
  }
  return { schema: 'pie.session.encryption.result.v1', status: 'decrypted', bytes: fs.statSync(destination).size };
}

async function main() {
  const [, , action, inputPath, outputPath] = process.argv;
  if (!['encrypt', 'decrypt'].includes(action) || !inputPath || !outputPath) fail('PIE_SESSION_BACKUP_CRYPTO_USAGE');
  const passphrase = await readPassphrase();
  const result = action === 'encrypt'
    ? await encrypt(inputPath, outputPath, passphrase)
    : await decrypt(inputPath, outputPath, passphrase);
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

main().catch(error => {
  process.stderr.write(`${error.code || error.message || 'PIE_SESSION_BACKUP_CRYPTO_FAILED'}\n`);
  process.exitCode = 1;
});
