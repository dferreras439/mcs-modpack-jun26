#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
PACK_DIR="${PACK_DIR:-$ROOT_DIR/publish}"
PACKWIZ="${PACKWIZ:-$ROOT_DIR/bin/packwiz}"

# shellcheck source=scripts/load-env.sh
source "$ROOT_DIR/scripts/load-env.sh"
load_env_file "$ENV_FILE"

PACK_DIR="${PACK_DIR:-$ROOT_DIR/publish}"
PACKWIZ="${PACKWIZ:-$ROOT_DIR/bin/packwiz}"

if [ ! -x "$PACKWIZ" ]; then
    echo "Error: packwiz not found at $PACKWIZ" >&2
    echo "Run ./0-bootstrap.sh first." >&2
    exit 1
fi

if [ ! -f "$PACK_DIR/pack.toml" ]; then
    echo "Error: $PACK_DIR/pack.toml not found" >&2
    echo "Run ./1-modpack-initialize.sh first." >&2
    exit 1
fi

echo "Refreshing packwiz index..."
(
    cd "$PACK_DIR"
    "$PACKWIZ" refresh
)

echo "Finalize complete."
echo "Packwiz pack file: $PACK_DIR/pack.toml"
