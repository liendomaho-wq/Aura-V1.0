"""Provenance/source invariants only; actual Keystore tests run on Android."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "third_party/flutter_secure_storage"
JAVA = VENDOR / "android/src/main/java/com/it_nomads/fluttersecurestorage"


def test_pinned_upstream_runtime_and_every_changed_file_are_explicit():
    manifest = json.loads((VENDOR / "UPSTREAM.json").read_text())
    assert manifest["commit"] == "692a374a5071c0b60939f624ede58d666b6b645c"
    assert manifest["tag"] == "v10.3.4"
    changed = []
    formatting = []
    for entry in manifest["files"]:
        data = (VENDOR / entry["path"]).read_bytes()
        expected = entry.get("local_sha256", entry["upstream_sha256"])
        assert hashlib.sha256(data).hexdigest() == expected, entry["path"]
        if "local_sha256" in entry:
            (formatting if entry.get("whitespace_only") else changed).append(entry["path"])
            assert entry["change"]
    assert len(manifest["files"]) == 42
    assert len(changed) == 3
    assert len(formatting) == 3
    assert all(path.startswith("android/") for path in changed)
    assert "Copyright" in (VENDOR / "LICENSE").read_text()


def test_application_uses_the_pinned_path_not_an_unpatched_hosted_runtime():
    pubspec = (ROOT / "pubspec.yaml").read_text()
    override = pubspec.split("dependency_overrides:", 1)[1]
    assert "flutter_secure_storage:\n    path: third_party/flutter_secure_storage" in override
    assert "version: 10.3.4" in (VENDOR / "pubspec.yaml").read_text()
    assert 'source: path\n    version: "10.3.4"' in (ROOT / "pubspec.lock").read_text()


def test_original_real_migration_tests_and_active_model_are_not_rewritten():
    original = ROOT / "android/app/src/androidTest/java/com/ciberdefensa/aura/SecureStorageMigrationTest.java"
    assert hashlib.sha256(original.read_bytes()).hexdigest() == "049bcdd4a140d1b2d05e30c0501d9821e55a4ab592fcf9fe5662d7c907b807be"
    model = ROOT / "assets/model/aura_brain_model.json"
    assert hashlib.sha256(model.read_bytes()).hexdigest() == "d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2"


def test_markerless_fast_path_cannot_skip_existing_esp_ciphertext():
    source = (JAVA / "FlutterSecureStorage.java").read_text()
    probe = source.split("private boolean canSkipMarkerlessMigration()", 1)[1].split("private boolean hasAnyEncryptedData", 1)[0]
    assert probe.index("hasPendingLegacyEspData(dataPrefs)") < probe.index("if (sample == null)")
    initialization = source.split("private void initializeStorageCipher(", 1)[1].split("private boolean canMigrateEspIntoCurrentStore", 1)[0]
    assert initialization.index("canMigrateEspIntoCurrentStore(dataPrefs)") < initialization.index("canSkipMarkerlessMigration()")
    assert "Conflicting legacy/current secret; both retained" in source
    assert "Legacy ESP migration failed; data and backups retained" in source


def test_migration_is_one_commit_and_key_persistence_is_checked():
    crypto = (JAVA / "crypto/EncryptedSharedPreferences.java").read_text()
    atomic = crypto.split("public boolean commitMigration(", 1)[1].split("public String getString(", 1)[0]
    assert atomic.count("editor.commit()") == 1
    assert "editor.putString(entry.getKey(), entry.getValue())" in atomic
    assert "editor.remove(encryptKey(entry.getKey()))" in atomic
    assert ".apply()" not in atomic
    gcm = (JAVA / "ciphers/StorageCipherImplementationGCM.java").read_text()
    constructor = gcm.split("@Override", 1)[0]
    assert "if (!editor.commit())" in constructor
    assert "Could not persist wrapped AES key before data migration" in constructor
    assert ".apply()" not in constructor
