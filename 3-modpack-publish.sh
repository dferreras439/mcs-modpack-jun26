#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
PACK_DIR="${PACK_DIR:-$ROOT_DIR/publish}"
RCLONE="${RCLONE:-$ROOT_DIR/bin/rclone}"
RCLONE_REMOTE="${RCLONE_REMOTE:-r2}"
R2_PREFIX="${R2_PREFIX:-}"

# shellcheck source=scripts/load-env.sh
source "$ROOT_DIR/scripts/load-env.sh"
load_env_file "$ENV_FILE"

PACK_DIR="${PACK_DIR:-$ROOT_DIR/publish}"
RCLONE="${RCLONE:-$ROOT_DIR/bin/rclone}"
RCLONE_REMOTE="${RCLONE_REMOTE:-r2}"
R2_PREFIX="${R2_PREFIX:-}"

if [ ! -x "$RCLONE" ]; then
    if command -v rclone >/dev/null 2>&1; then
        RCLONE="$(command -v rclone)"
    else
        echo "Error: rclone not found. Install rclone or set RCLONE=/path/to/rclone." >&2
        exit 1
    fi
fi

if [ ! -d "$PACK_DIR" ]; then
    echo "Error: pack directory not found: $PACK_DIR" >&2
    exit 1
fi

if [ ! -f "$PACK_DIR/pack.toml" ] || [ ! -f "$PACK_DIR/index.toml" ]; then
    echo "Error: pack.toml and index.toml must exist before publishing." >&2
    echo "Run ./2-modpack-finalize.sh first." >&2
    exit 1
fi

if [ -n "${RCLONE_DEST:-}" ]; then
    DEST="$RCLONE_DEST"
else
    if [ -z "${R2_BUCKET:-}" ]; then
        echo "Error: set R2_BUCKET or RCLONE_DEST" >&2
        exit 1
    fi
    DEST="${RCLONE_REMOTE}:${R2_BUCKET}"
    if [ -n "$R2_PREFIX" ]; then
        DEST="${DEST%/}/${R2_PREFIX#/}"
    fi
fi

remote_env_prefix="RCLONE_CONFIG_${RCLONE_REMOTE^^}"

set_rclone_env_default() {
    local name="$1"
    local default_value="$2"
    local current_value="${!name:-}"
    if [ -z "$current_value" ]; then
        current_value="$default_value"
    fi
    export "${name}=${current_value}"
}

if [ -n "${R2_ACCOUNT_ID:-}" ]; then
    set_rclone_env_default "${remote_env_prefix}_TYPE" "s3"
    set_rclone_env_default "${remote_env_prefix}_PROVIDER" "Cloudflare"
    set_rclone_env_default "${remote_env_prefix}_ENDPOINT" "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
fi

if [ -n "${R2_ACCESS_KEY_ID:-}" ]; then
    export "${remote_env_prefix}_ACCESS_KEY_ID=${R2_ACCESS_KEY_ID}"
fi
if [ -n "${R2_SECRET_ACCESS_KEY:-}" ]; then
    export "${remote_env_prefix}_SECRET_ACCESS_KEY=${R2_SECRET_ACCESS_KEY}"
fi

common_flags=(--fast-list --transfers "${RCLONE_TRANSFERS:-16}" --checkers "${RCLONE_CHECKERS:-32}")

if [ "${PUBLISH_DRY_RUN:-false}" = "true" ]; then
    common_flags+=(--dry-run)
fi

echo "Wiping destination before publish: $DEST"
"$RCLONE" delete "$DEST" --rmdirs "${common_flags[@]}"

echo "Uploading $PACK_DIR to $DEST"
"$RCLONE" sync "$PACK_DIR" "$DEST" --delete-before "${common_flags[@]}"

echo "Publish complete: $DEST"
