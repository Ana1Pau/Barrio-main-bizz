export function normalizeClabeInput(value) {
  return typeof value === 'string' ? value.replace(/[\s-]/g, '') : '';
}

export function isValidClabe(value) {
  return /^\d{18}$/.test(value);
}
