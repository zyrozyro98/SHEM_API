const crypto = require('crypto');

function normalizePhone(value) {
  const digits = String(value ?? '')
    .replace(/[\u0660-\u0669\u06F0-\u06F9]/g, (character) => {
      const code = character.charCodeAt(0);
      const base = code >= 0x06f0 ? 0x06f0 : 0x0660;
      return String.fromCharCode(0x30 + code - base);
    })
    .replace(/\D/g, '');
  return digits.startsWith('00') ? digits.slice(2) : digits;
}

function normalizeYemenPhoneKey(value) {
  let digits = normalizePhone(value);
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0') && digits.length === 10) {
    digits = `967${digits.slice(1)}`;
  } else if (digits.length === 9) {
    digits = `967${digits}`;
  }
  return /^967[0-9]{9}$/.test(digits) ? digits : '';
}

function passwordMatches(expectedHash, password) {
  if (typeof expectedHash !== 'string' || !/^[a-f0-9]{64}$/i.test(expectedHash)) {
    return false;
  }
  const actualHash = crypto.createHash('sha256').update(password.trim()).digest();
  const expected = Buffer.from(expectedHash, 'hex');
  return expected.length === actualHash.length &&
    crypto.timingSafeEqual(expected, actualHash);
}

module.exports = {
  normalizePhone,
  normalizeYemenPhoneKey,
  passwordMatches,
};
