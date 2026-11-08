# Aura: narrowly scoped Android v9 ESP migration fixes

Upstream runtime: **v10.3.4**, commit `692a374a5071c0b60939f624ede58d666b6b645c` of https://github.com/juliansteenbakker/flutter_secure_storage. Original BSD license and embedded notices are preserved. `UPSTREAM.json` records the archive digest, every included upstream file digest and the four functional Android patch digests plus explicitly marked whitespace-only differences; `AURA_PATCHES.json` stores the exact unified patch as JSON text. All production Dart implementation files are unmodified. Example applications, upstream test suites and dev-only analyzer configuration are not copied or represented as executed Aura tests. The published SDK helper imported by its production Dart library is retained byte-for-byte for API compatibility; it is not used to replace Android/Keystore tests.

## Actual defect, not an assertion change

Run `42491355979`, job `128766339515`, executed **both original tests on a real Android 16 emulator** without privileged KVM. The normal migration failed at `SecureStorageMigrationTest.java:74`: expected `v9-real-keystore-secret-preserved`, received `null`; interrupted-backup case passed. The original test file stays byte-for-byte unchanged (SHA-256 `049bcdd4a140d1b2d05e30c0501d9821e55a4ab592fcf9fe5662d7c907b807be`).

In 10.3.4, `migrateWithBackup=true` skips the early ESP migration, while `canSkipMarkerlessMigration()` infers an empty store from absence of plaintext-prefixed keys. ESP **encrypts the key names**. That inference can skip existing secrets, exposing `null` to an application that creates a key on first use.

## Changes

1. Inspect existing ESP metadata/ciphertext before treating a markerless store as empty. Refuse incomplete ESP keyset metadata without regenerating it.
2. Read/authenticate real ESP values before generating a target AES key. Do not try to unwrap a guessed CBC key for an ESP-only store, or for a verified already-current target during recovery.
3. Authenticate every existing current-format target record before taking that recovery path. Backup entries still use the original interrupted-backup flow.
4. Stage all selected new ciphertext; verify round trips; write the target values and remove the corresponding legacy encrypted keys in **one checked, synchronous SharedPreferences transaction on the same file**. No per-record `apply()`/delete gap. Original encrypted source remains until the atomic conversion; no fake backup-status flag.
5. If legacy/current secrets differ, retain both and report an error. If they match, preserve the exact existing current ciphertext. Do not silently choose a root key, overwrite either secret or reset the vault.
6. Check durable wrapped-AES-key storage before committing migrated data. An ESP authentication failure in the general backup flow aborts before backup cleanup.
7. Prevent authenticated initialization from calling success after it already called error.
8. Refuse replacing an existing RSA private key with a new AES key at the same alias. That destructive provider shortcut is not a data-preserving authenticated migration; a distinct alias and verified recovery are required. A real Android regression must show that the original certificate/key and freshly unwrapped secret survive.

## Verification boundaries

`tool/test_secure_storage_vendor.py` verifies provenance and source invariants, not Android. The Android workflow must execute the two original migration cases and five additional real provider/data-integrity cases. Android 16 additionally requires the four real VPN cases. API 29 is additional regression coverage, never a substitute for Android 16 acceptance or the reference phone.

This patch **does not configure the application's vault keys to use biometric CryptoObject protection**, certify all failure/power-loss scenarios, recover already-lost cryptographic material, or prove compatibility with a physical Redmi. Those remain separate acceptance work. Conflicting legacy/current secrets require deliberate recovery; failing closed preserves both rather than inventing a resolution.
