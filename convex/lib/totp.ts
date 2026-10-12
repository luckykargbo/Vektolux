// convex/lib/totp.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Pure RFC 6238 TOTP Engine & AES-256-GCM Secret Encryption
// Zero external dependencies; built entirely on standard WebCrypto API.
// ═══════════════════════════════════════════════════════════════════════

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

// ─── Base32 Utilities ────────────────────────────────────────────────

export function base32Encode(buffer: Uint8Array): string {
  let bits = 0;
  let value = 0;
  let output = "";

  for (let i = 0; i < buffer.length; i++) {
    value = (value << 8) | buffer[i];
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }

  if (bits > 0) {
    output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }

  return output;
}

export function base32Decode(base32: string): Uint8Array {
  const sanitized = base32.toUpperCase().replace(/=+$/, "").replace(/[\s-]/g, "");
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];

  for (let i = 0; i < sanitized.length; i++) {
    const val = BASE32_ALPHABET.indexOf(sanitized[i]);
    if (val === -1) {
      throw new Error("Invalid base32 character in secret");
    }
    value = (value << 5) | val;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }

  return new Uint8Array(bytes);
}

// ─── Cryptographic Random Secret Generation ──────────────────────────

/** Generates a cryptographically secure 20-byte (160-bit) base32 secret. */
export function generateTotpSecret(): string {
  const bytes = new Uint8Array(20);
  crypto.getRandomValues(bytes);
  return base32Encode(bytes);
}

/** Generates an otpauth:// URL for Google Authenticator / 1Password / Authy */
export function generateOtpauthUrl(accountEmail: string, secret: string, issuer = "Vektolux"): string {
  const encodedIssuer = encodeURIComponent(issuer);
  const encodedAccount = encodeURIComponent(accountEmail);
  return `otpauth://totp/${encodedIssuer}:${encodedAccount}?secret=${secret}&issuer=${encodedIssuer}&algorithm=SHA1&digits=6&period=30`;
}

// ─── RFC 6238 TOTP Generation & Verification ────────────────────────

/** Generates a 6-digit TOTP code for a specific counter step. */
async function generateTotpCode(secretBytes: Uint8Array, timeStep: number): Promise<string> {
  const counterBuffer = new ArrayBuffer(8);
  const view = new DataView(counterBuffer);
  // Big-endian 64-bit integer
  view.setUint32(0, Math.floor(timeStep / 0x100000000));
  view.setUint32(4, timeStep & 0xffffffff);

  const key = await crypto.subtle.importKey(
    "raw",
    secretBytes as unknown as BufferSource,
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("HMAC", key, counterBuffer);
  const hmac = new Uint8Array(signature);

  // Dynamic truncation
  const offset = hmac[hmac.length - 1] & 0x0f;
  const binary =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);

  const otp = binary % 1000000;
  return otp.toString().padStart(6, "0");
}

/**
 * Verifies a 6-digit TOTP code with ±1 step (±30 seconds) tolerance.
 */
export async function verifyTotpCode(
  secretBase32: string,
  userCode: string,
  nowMs = Date.now()
): Promise<boolean> {
  const cleanCode = userCode.trim().replace(/[\s-]/g, "");
  if (!/^\d{6}$/.test(cleanCode)) return false;

  const secretBytes = base32Decode(secretBase32);
  const currentStep = Math.floor(nowMs / 1000 / 30);

  // Window of -1, 0, +1 time steps (90 seconds total window for clock drift)
  for (const stepOffset of [0, -1, 1]) {
    const expected = await generateTotpCode(secretBytes, currentStep + stepOffset);
    if (constantTimeCompare(cleanCode, expected)) {
      return true;
    }
  }

  return false;
}

function constantTimeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// ─── AES-256-GCM Secret Encryption at Rest ───────────────────────────

/** Minimum length of TOTP_ENCRYPTION_KEY. It is hashed with SHA-256, so it must carry real entropy. */
export const MIN_TOTP_ENCRYPTION_KEY_LENGTH = 32;
/** The key that older builds silently fell back to. It is public (in git), so it is refused outright. */
const REVOKED_DEFAULT_KEY = "vektolux-totp-default-secure-rest-key-2026";

/**
 * The AES key for TOTP secrets. Fails CLOSED: there is no development or production fallback.
 * A correctly configured key derives the same AES key as before (SHA-256 of the configured value),
 * so secrets encrypted under it keep decrypting. No key is ever rotated or rewritten here.
 */
async function getEncryptionKey(): Promise<CryptoKey> {
  const rawKey = (process.env.TOTP_ENCRYPTION_KEY ?? "").trim();
  if (!rawKey) {
    throw new Error("TOTP_ENCRYPTION_KEY is not configured; two-factor secrets cannot be encrypted or decrypted.");
  }
  if (rawKey === REVOKED_DEFAULT_KEY || rawKey.length < MIN_TOTP_ENCRYPTION_KEY_LENGTH) {
    throw new Error(
      `TOTP_ENCRYPTION_KEY is invalid: it must be a unique secret of at least ${MIN_TOTP_ENCRYPTION_KEY_LENGTH} characters.`
    );
  }
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(rawKey));

  return crypto.subtle.importKey(
    "raw",
    digest as unknown as BufferSource,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"]
  );
}

/** Encrypts a plaintext TOTP secret into iv:ciphertext:tag string. */
export async function encryptTotpSecret(plainSecret: string): Promise<string> {
  const key = await getEncryptionKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plainSecret);

  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    encoded as unknown as BufferSource
  );

  const ivHex = Array.from(iv).map((b) => b.toString(16).padStart(2, "0")).join("");
  const cipherHex = Array.from(new Uint8Array(ciphertext))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return `${ivHex}:${cipherHex}`;
}

/** Decrypts an encrypted TOTP secret from iv:ciphertext:tag string. */
export async function decryptTotpSecret(encryptedString: string): Promise<string> {
  const parts = encryptedString.split(":");
  if (parts.length !== 2) throw new Error("Invalid encrypted TOTP secret payload");

  const [ivHex, cipherHex] = parts;
  const ivMatches = ivHex.match(/.{1,2}/g);
  const cipherMatches = cipherHex.match(/.{1,2}/g);

  if (!ivMatches || !cipherMatches) throw new Error("Malformed encrypted TOTP payload hex");

  const iv = new Uint8Array(ivMatches.map((b) => parseInt(b, 16)));
  const ciphertext = new Uint8Array(cipherMatches.map((b) => parseInt(b, 16)));

  const key = await getEncryptionKey();
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    key,
    ciphertext as unknown as BufferSource
  );

  return new TextDecoder().decode(decrypted);
}

// ─── Emergency Backup Codes ──────────────────────────────────────────

/** Generates 10 cryptographically random 8-character backup codes. */
export function generateBackupCodes(): string[] {
  const codes: string[] = [];
  for (let i = 0; i < 10; i++) {
    const bytes = new Uint8Array(4);
    crypto.getRandomValues(bytes);
    // Format: "xxxx-xxxx"
    const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
    codes.push(`${hex.slice(0, 4)}-${hex.slice(4, 8)}`);
  }
  return codes;
}

/** Hashes a backup code using SHA-256 for secure storage. */
export async function hashBackupCode(code: string): Promise<string> {
  const clean = code.trim().toLowerCase().replace(/[-\s]/g, "");
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`vx-bkp:${clean}`));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
