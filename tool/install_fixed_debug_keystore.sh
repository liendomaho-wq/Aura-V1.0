#!/usr/bin/env bash
# Optional fixed debug keystore. Sourced by tool/compile_aura.sh and run as a
# step in CI. Passwords stay in the current process. They are not written to
# GITHUB_ENV or CM_ENV, because those files leak into later logs and steps.
install_fixed_debug_keystore() {
  if [[ -z "${AURA_DEBUG_KEYSTORE_BASE64:-}" && -z "${AURA_DEBUG_KEYSTORE_PATH:-}" ]]; then
    echo "::warning title=Keystore de prueba fijo ausente::Faltan AURA_DEBUG_KEYSTORE_BASE64 y AURA_DEBUG_KEYSTORE_PATH. El APK puede cambiar de certificado y obligar a desinstalar; eso borra SecureVault. Crea el grupo aura_debug_keystore en CodeMagic y los cuatro secretos del documento de la fase 2."
    return 0
  fi
  if [[ -n "${AURA_DEBUG_KEYSTORE_BASE64:-}" ]]; then
    local destination="${AURA_DEBUG_KEYSTORE_PATH:-$HOME/.android/aura-debug.keystore}"
    mkdir -p "$(dirname "$destination")"
    printf '%s' "$AURA_DEBUG_KEYSTORE_BASE64" | base64 -d > "$destination"
    export AURA_DEBUG_KEYSTORE_PATH="$destination"
  fi
  export AURA_DEBUG_STORE_PASSWORD="${AURA_DEBUG_STORE_PASSWORD:-android}"
  export AURA_DEBUG_KEY_ALIAS="${AURA_DEBUG_KEY_ALIAS:-androiddebugkey}"
  export AURA_DEBUG_KEY_PASSWORD="${AURA_DEBUG_KEY_PASSWORD:-$AURA_DEBUG_STORE_PASSWORD}"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf 'AURA_DEBUG_KEYSTORE_PATH=%s\n' "$AURA_DEBUG_KEYSTORE_PATH" >> "$GITHUB_ENV"
  fi
  if [[ -n "${CM_ENV:-}" ]]; then
    printf 'AURA_DEBUG_KEYSTORE_PATH=%s\n' "$AURA_DEBUG_KEYSTORE_PATH" >> "$CM_ENV"
  fi
}
install_fixed_debug_keystore
