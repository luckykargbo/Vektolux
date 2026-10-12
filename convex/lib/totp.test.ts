/// <reference types="vite/client" />
// TOTP secret encryption must fail closed: no hardcoded / development fallback key.
import { afterEach, describe, expect, test, vi } from "vitest";
import { decryptTotpSecret, encryptTotpSecret, generateTotpSecret } from "./totp";

const GOOD_KEY = "unit-test-totp-key-0123456789-abcdefghij";

afterEach(() => vi.unstubAllEnvs());

describe("TOTP_ENCRYPTION_KEY", () => {
  test("missing key: encryption and decryption both refuse (no fallback)", async () => {
    vi.stubEnv("TOTP_ENCRYPTION_KEY", "");
    await expect(encryptTotpSecret(generateTotpSecret())).rejects.toThrow(/not configured/);
    await expect(decryptTotpSecret("00:00")).rejects.toThrow(/not configured/);
  });

  test("whitespace-only key is treated as missing", async () => {
    vi.stubEnv("TOTP_ENCRYPTION_KEY", "     ");
    await expect(encryptTotpSecret("ABC")).rejects.toThrow(/not configured/);
  });

  test("too-short key is invalid", async () => {
    vi.stubEnv("TOTP_ENCRYPTION_KEY", "short-key");
    await expect(encryptTotpSecret("ABC")).rejects.toThrow(/invalid/);
  });

  test("the old hardcoded default key is rejected even though it is long enough", async () => {
    vi.stubEnv("TOTP_ENCRYPTION_KEY", "vektolux-totp-default-secure-rest-key-2026");
    await expect(encryptTotpSecret("ABC")).rejects.toThrow(/invalid/);
  });

  test("valid key: round trip works and ciphertext is not the plaintext", async () => {
    vi.stubEnv("TOTP_ENCRYPTION_KEY", GOOD_KEY);
    const secret = generateTotpSecret();
    const enc = await encryptTotpSecret(secret);
    expect(enc).not.toContain(secret);
    await expect(decryptTotpSecret(enc)).resolves.toBe(secret);
  });

  test("existing secrets stay readable: key derivation is SHA-256 of the configured value, as before", async () => {
    vi.stubEnv("TOTP_ENCRYPTION_KEY", GOOD_KEY);
    // Encrypt independently with the documented scheme (AES-256-GCM, key = SHA-256(TOTP_ENCRYPTION_KEY)).
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(GOOD_KEY));
    const key = await crypto.subtle.importKey("raw", digest, { name: "AES-GCM" }, false, ["encrypt"]);
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode("JBSWY3DPEHPK3PXP")));
    const hex = (u: Uint8Array) => Array.from(u).map((b) => b.toString(16).padStart(2, "0")).join("");
    await expect(decryptTotpSecret(`${hex(iv)}:${hex(ct)}`)).resolves.toBe("JBSWY3DPEHPK3PXP");
  });

  test("a different key cannot decrypt (no silent fallback to another key)", async () => {
    vi.stubEnv("TOTP_ENCRYPTION_KEY", GOOD_KEY);
    const enc = await encryptTotpSecret("JBSWY3DPEHPK3PXP");
    vi.stubEnv("TOTP_ENCRYPTION_KEY", GOOD_KEY + "-other");
    await expect(decryptTotpSecret(enc)).rejects.toThrow();
  });
});
