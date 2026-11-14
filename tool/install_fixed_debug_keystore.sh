#!/usr/bin/env bash
# Optional stable debug keystore. Source this file; it is a no-op when unset.
# Never prints passwords or keystore bytes.
install_fixed_debug_keystore() {
    if [[ -z "${AURA_DEBUG_KEYSTORE_BASE64:-}" && -z "${AURA_DEBUG_KEYSTORE_PATH:-}" ]]; then
        return 0
    fi
    if [[ -n "${AURA_DEBUG_KEYSTORE_BASE64:-}" ]]; then
        local dest
        dest="${AURA_DEBUG_KEYSTORE_PATH:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/aura-debug.keystore}"
        mkdir -p "$(dirname "$dest")"
        if ! printf '%s' "$AURA_DEBUG_KEYSTORE_BASE64" | base64 --decode > "$dest" 2>/dev/null \
            && ! printf '%s' "$AURA_DEBUG_KEYSTORE_BASE64" | base64 -D > "$dest" 2>/dev/null; then
            printf '%s\n' "AURA_DEBUG_KEYSTORE_BASE64 is not valid Base64." >&2
            return 1
        fi
        if [[ ! -s "$dest" ]]; then
            printf '%s\n' "AURA_DEBUG_KEYSTORE_BASE64 decoded to an empty file." >&2
            return 1
        fi
        export AURA_DEBUG_KEYSTORE_PATH="$dest"
    elif [[ ! -f "${AURA_DEBUG_KEYSTORE_PATH}" ]]; then
        printf '%s\n' "AURA_DEBUG_KEYSTORE_PATH does not exist." >&2
        return 1
    fi
    export AURA_DEBUG_STORE_PASSWORD="${AURA_DEBUG_STORE_PASSWORD:-android}"
    export AURA_DEBUG_KEY_ALIAS="${AURA_DEBUG_KEY_ALIAS:-androiddebugkey}"
    export AURA_DEBUG_KEY_PASSWORD="${AURA_DEBUG_KEY_PASSWORD:-$AURA_DEBUG_STORE_PASSWORD}"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        {
            printf 'AURA_DEBUG_KEYSTORE_PATH=%s\n' "$AURA_DEBUG_KEYSTORE_PATH"
            printf 'AURA_DEBUG_STORE_PASSWORD=%s\n' "$AURA_DEBUG_STORE_PASSWORD"
            printf 'AURA_DEBUG_KEY_ALIAS=%s\n' "$AURA_DEBUG_KEY_ALIAS"
            printf 'AURA_DEBUG_KEY_PASSWORD=%s\n' "$AURA_DEBUG_KEY_PASSWORD"
        } >> "$GITHUB_ENV"
    fi
    if [[ -n "${CM_ENV:-}" ]]; then
        {
            printf 'AURA_DEBUG_KEYSTORE_PATH=%s\n' "$AURA_DEBUG_KEYSTORE_PATH"
            printf 'AURA_DEBUG_STORE_PASSWORD=%s\n' "$AURA_DEBUG_STORE_PASSWORD"
            printf 'AURA_DEBUG_KEY_ALIAS=%s\n' "$AURA_DEBUG_KEY_ALIAS"
            printf 'AURA_DEBUG_KEY_PASSWORD=%s\n' "$AURA_DEBUG_KEY_PASSWORD"
        } >> "$CM_ENV"
    fi
}
install_fixed_debug_keystore
