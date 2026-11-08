import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeClabeInput, isValidClabe } from '../public/formats.mjs';

test('formatted CLABE paste is normalized before validation', () => {
  const formatted = '123 456 7890 1234 5678';
  const normalized = normalizeClabeInput(formatted);
  assert.equal(normalized, '123456789012345678');
  assert.equal(isValidClabe(normalized), true);
  assert.equal(isValidClabe('12345678901234567'), false);
  assert.equal(isValidClabe('1234567890123456789'), false);
});

test('CLABE normalization removes common spaces and hyphens only', () => {
  assert.equal(normalizeClabeInput('123-456 7890-1234 5678'), '123456789012345678');
  assert.equal(normalizeClabeInput(null), '');
});
