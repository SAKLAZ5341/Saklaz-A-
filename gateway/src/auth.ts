import { createHash, timingSafeEqual } from 'node:crypto';

export function sha256Hex(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

/**
 * `Authorization: Bearer <token>` başlığını doğrular. Token'ın SHA-256 özeti
 * izin listesindeki özetlerle sabit zamanlı karşılaştırılır.
 * Başarılıysa cihazın özetini (kimlik olarak) döner.
 */
export function authenticate(header: string | undefined, allowedHashes: readonly string[]): string | null {
  if (!header) return null;
  const m = /^Bearer\s+(\S{16,256})$/i.exec(header.trim());
  if (!m || !m[1]) return null;
  const candidate = Buffer.from(sha256Hex(m[1]), 'hex');
  let match: string | null = null;
  for (const h of allowedHashes) {
    const allowed = Buffer.from(h, 'hex');
    // Kısa devre yapmadan tüm listeyi dolaş (zamanlama sızıntısını azaltır).
    if (allowed.length === candidate.length && timingSafeEqual(allowed, candidate)) match = h;
  }
  return match;
}
