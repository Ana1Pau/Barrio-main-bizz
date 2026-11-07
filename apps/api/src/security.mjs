import { createHmac, randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
const scrypt = promisify(scryptCb);

export async function hashPassword(password) {
  const salt = randomBytes(32);
  const hash = await scrypt(password, salt, 64, { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });
  return { salt, hash };
}

export async function verifyPassword(password, salt, expected) {
  const actual = await scrypt(password, salt, expected.length, { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function issueAccessToken(userId, roles, secret, now = Math.floor(Date.now() / 1000)) {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ sub: userId, roles, iat: now, exp: now + 900, iss: 'barrio-api', aud: 'barrio-app' })).toString('base64url');
  const content = `${header}.${payload}`;
  const signature = createHmac('sha256', secret).update(content).digest('base64url');
  return `${content}.${signature}`;
}

export function verifyAccessToken(token, secret, now = Math.floor(Date.now() / 1000)) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const content = `${parts[0]}.${parts[1]}`;
  const expected = createHmac('sha256', secret).update(content).digest();
  const actual = Buffer.from(parts[2], 'base64url');
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return null;
  try {
    const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    if (header.alg !== 'HS256' || payload.iss !== 'barrio-api' || payload.aud !== 'barrio-app' || payload.exp <= now) return null;
    if (!payload.sub || !Array.isArray(payload.roles)) return null;
    return payload;
  } catch { return null; }
}
