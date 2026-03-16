#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_ROOT="${LANREADER_CODEX_ROOT:-$REPO_ROOT/.codex}"
LANREADER_USE_LOCAL_XCODE_ENV="${LANREADER_USE_LOCAL_XCODE_ENV:-0}"

export REPO_ROOT
export CODEX_ROOT
export LANREADER_USE_LOCAL_XCODE_ENV

if [[ "$LANREADER_USE_LOCAL_XCODE_ENV" == "1" ]]; then
  export HOME="${LANREADER_XCODE_HOME:-$CODEX_ROOT/xcode-home}"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$CODEX_ROOT/xdg-cache}"
  export TMPDIR="${TMPDIR:-$CODEX_ROOT/tmp/}"
  export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$CODEX_ROOT/module-cache/clang}"
  export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CODEX_ROOT/module-cache/swiftpm}"
  LANREADER_DERIVED_DATA_PATH="${LANREADER_DERIVED_DATA_PATH:-$CODEX_ROOT/DerivedData}"
  LANREADER_SOURCE_PACKAGES_DIR="${LANREADER_SOURCE_PACKAGES_DIR:-$CODEX_ROOT/SourcePackages}"
else
  LANREADER_DERIVED_DATA_PATH="${LANREADER_DERIVED_DATA_PATH:-}"
  LANREADER_SOURCE_PACKAGES_DIR="${LANREADER_SOURCE_PACKAGES_DIR:-}"
fi

LANREADER_BUILD_DIR="${LANREADER_BUILD_DIR:-$REPO_ROOT/build}"
LANREADER_RESULTS_DIR="${LANREADER_RESULTS_DIR:-$LANREADER_BUILD_DIR/results}"

export LANREADER_DERIVED_DATA_PATH
export LANREADER_SOURCE_PACKAGES_DIR
export LANREADER_RESULTS_DIR
export LANREADER_BUILD_DIR

prepare_xcode_environment() {
  local dirs=(
    "$HOME/Library/Caches/org.swift.swiftpm/manifests"
    "$HOME/Library/org.swift.swiftpm/security"
    "$LANREADER_RESULTS_DIR"
    "$LANREADER_BUILD_DIR"
  )

  if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    dirs+=("$XDG_CACHE_HOME")
  fi
  if [[ -n "${TMPDIR:-}" ]]; then
    dirs+=("$TMPDIR")
  fi
  if [[ -n "${CLANG_MODULE_CACHE_PATH:-}" ]]; then
    dirs+=("$CLANG_MODULE_CACHE_PATH")
  fi
  if [[ -n "${SWIFTPM_MODULECACHE_OVERRIDE:-}" ]]; then
    dirs+=("$SWIFTPM_MODULECACHE_OVERRIDE")
  fi
  if [[ -n "$LANREADER_DERIVED_DATA_PATH" ]]; then
    dirs+=("$LANREADER_DERIVED_DATA_PATH")
  fi
  if [[ -n "$LANREADER_SOURCE_PACKAGES_DIR" ]]; then
    dirs+=("$LANREADER_SOURCE_PACKAGES_DIR")
  fi

  mkdir -p "${dirs[@]}"
}

trust_swift_macros() {
  prepare_xcode_environment
  cp "$REPO_ROOT/ci_scripts/macros.json" "$HOME/Library/org.swift.swiftpm/security/macros.json"
}
