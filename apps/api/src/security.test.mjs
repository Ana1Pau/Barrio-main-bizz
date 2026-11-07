import test from 'node:test';
import assert from 'node:assert/strict';
import { hashPassword, verifyPassword, issueAccessToken, verifyAccessToken } from './security.mjs';

test('password hashes verify only the original password', async () => {
  const saved = await hashPassword('correct horse battery staple');
  assert.equal(await verifyPassword('correct horse battery staple', saved.salt, saved.hash), true);
  assert.equal(await verifyPassword('wrong password', saved.salt, saved.hash), false);
});

test('access tokens are signed, expire and reject tampering', () => {
  const secret = 'a'.repeat(48);
  const token = issueAccessToken('user-1', ['Comprador'], secret, 1000);
  assert.deepEqual(verifyAccessToken(token, secret, 1001).roles, ['Comprador']);
  assert.equal(verifyAccessToken(token, secret, 1900), null);
  assert.equal(verifyAccessToken(`${token.slice(0, -1)}x`, secret, 1001), null);
});
