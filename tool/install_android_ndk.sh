#!/usr/bin/env bash
# Install the Android NDK used by app/build.gradle into the SDK used by CI.
set -euo pipefail

ndk_version="28.2.13676358"
sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$sdk_root" || ! -d "$sdk_root" ]]; then
  echo 'ANDROID_SDK_ROOT or ANDROID_HOME must name an existing Android SDK.' >&2
  exit 1
fi
sdk_root="$(cd "$sdk_root" && pwd -P)"
if [[ -n "${ANDROID_HOME:-}" ]]; then
  if [[ ! -d "$ANDROID_HOME" || "$(cd "$ANDROID_HOME" && pwd -P)" != "$sdk_root" ]]; then
    echo 'ANDROID_SDK_ROOT and ANDROID_HOME disagree; select one Android SDK.' >&2
    exit 1
  fi
fi
ndk_build="$sdk_root/ndk/$ndk_version/ndk-build"
if [[ ! -x "$ndk_build" ]]; then
  sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
  if [[ ! -x "$sdkmanager" ]]; then
    sdkmanager="$(command -v sdkmanager || true)"
  fi
  if [[ -z "$sdkmanager" ]]; then
    echo 'Android sdkmanager not found; cannot install the declared NDK.' >&2
    exit 1
  fi
  "$sdkmanager" --sdk_root="$sdk_root" "ndk;$ndk_version"
fi
if [[ ! -x "$ndk_build" ]]; then
  echo "NDK installation did not provide an executable: $ndk_build" >&2
  exit 1
fi
printf 'Android NDK %s is available at %s\n' "$ndk_version" "$sdk_root/ndk/$ndk_version"
