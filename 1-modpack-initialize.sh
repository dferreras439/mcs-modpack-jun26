#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
PACK_DIR="${PACK_DIR:-$ROOT_DIR/publish}"
PACKWIZ="${PACKWIZ:-$ROOT_DIR/bin/packwiz}"
MC_IMAGE_HELPER="${MC_IMAGE_HELPER:-$ROOT_DIR/bin/mc-image-helper}"
CACHE_DIR="${CACHE_DIR:-$ROOT_DIR/.cache/modpack-source}"
WIPE_PACK_DIR="${WIPE_PACK_DIR:-true}"
MODPACK_SOURCE="${MODPACK_SOURCE:-curseforge}"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

PACK_DIR="${PACK_DIR:-$ROOT_DIR/publish}"
PACKWIZ="${PACKWIZ:-$ROOT_DIR/bin/packwiz}"
MC_IMAGE_HELPER="${MC_IMAGE_HELPER:-$ROOT_DIR/bin/mc-image-helper}"
CACHE_DIR="${CACHE_DIR:-$ROOT_DIR/.cache/modpack-source}"
WIPE_PACK_DIR="${WIPE_PACK_DIR:-true}"
MODPACK_SOURCE="${MODPACK_SOURCE:-curseforge}"

if [ ! -x "$PACKWIZ" ]; then
    echo "Error: packwiz not found at $PACKWIZ" >&2
    echo "Run ./0-bootstrap.sh first." >&2
    exit 1
fi

if [ ! -x "$MC_IMAGE_HELPER" ]; then
    echo "Error: mc-image-helper not found at $MC_IMAGE_HELPER" >&2
    echo "Run ./0-bootstrap.sh first." >&2
    exit 1
fi

run_packwiz() {
    (
        cd "$PACK_DIR"
        "$PACKWIZ" "$@"
    )
}

run_mc_image_helper() {
    "$MC_IMAGE_HELPER" "$@"
}

truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

require_value() {
    local name="$1"
    local value="${!name:-}"
    if [ -z "$value" ]; then
        echo "Error: $name is required for MODPACK_SOURCE=$MODPACK_SOURCE" >&2
        exit 1
    fi
}

extract_manifest_defaults() {
    local manifest_path="$1"
    if [ ! -f "$manifest_path" ]; then
        return 0
    fi

    local parsed
    parsed="$({ python3 - "$manifest_path" <<'PY'
import json
import re
import shlex
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
mc = (data.get("minecraft") or {})
loaders = mc.get("modLoaders") or []
primary = next((loader for loader in loaders if loader.get("primary")), loaders[0] if loaders else {})
loader_id = primary.get("id", "")
loader = ""
loader_version = ""
if loader_id:
    # CurseForge IDs are commonly forge-47.4.0, fabric-0.15.3, neoforge-21.1.233, quilt-0.23.1.
    match = re.match(r"^([A-Za-z]+)-(.+)$", loader_id)
    if match:
        loader = match.group(1).lower()
        loader_version = match.group(2)

values = {
    "PACK_NAME_DEFAULT": data.get("name", ""),
    "PACK_VERSION_DEFAULT": data.get("version", ""),
    "MC_VERSION_DEFAULT": mc.get("version", ""),
    "MODLOADER_DEFAULT": loader,
    "MODLOADER_VERSION_DEFAULT": loader_version,
}
for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
    } 2>/dev/null || true)"

    if [ -n "$parsed" ]; then
        eval "$parsed"
        PACK_NAME="${PACK_NAME:-${PACK_NAME_DEFAULT:-}}"
        PACK_VERSION="${PACK_VERSION:-${PACK_VERSION_DEFAULT:-}}"
        MC_VERSION="${MC_VERSION:-${MC_VERSION_DEFAULT:-}}"
        MODLOADER="${MODLOADER:-${MODLOADER_DEFAULT:-}}"
        MODLOADER_VERSION="${MODLOADER_VERSION:-${MODLOADER_VERSION_DEFAULT:-}}"
    fi
}

prepare_pack_dir() {
    if truthy "$WIPE_PACK_DIR" && [ "$MODPACK_SOURCE" != "local" ]; then
        echo "Resetting $PACK_DIR..."
        rm -rf "$PACK_DIR"
    fi
    mkdir -p "$PACK_DIR" "$CACHE_DIR"
}

install_curseforge() {
    local manifest_for_defaults=""
    local downloaded_zip=""

    local -a args
    args=(install-curseforge --output-directory "$PACK_DIR" --force-synchronize)

    if [ -n "${MODPACK_ZIP_URL:-}" ]; then
        downloaded_zip="$CACHE_DIR/curseforge-modpack.zip"
        echo "Downloading CurseForge modpack ZIP with mc-image-helper..."
        run_mc_image_helper get "$MODPACK_ZIP_URL" -o "$downloaded_zip"
        CF_MODPACK_ZIP="$downloaded_zip"
    fi

    if [ -n "${CF_MODPACK_ZIP:-}" ]; then
        args+=(--modpack-zip "$CF_MODPACK_ZIP")
        if command -v unzip >/dev/null 2>&1 && unzip -p "$CF_MODPACK_ZIP" manifest.json > "$CACHE_DIR/curseforge-manifest.json" 2>/dev/null; then
            manifest_for_defaults="$CACHE_DIR/curseforge-manifest.json"
        fi
    fi

    if [ -n "${CF_MODPACK_MANIFEST:-}" ]; then
        args+=(--modpack-manifest "$CF_MODPACK_MANIFEST")
        if [[ "$CF_MODPACK_MANIFEST" != http://* && "$CF_MODPACK_MANIFEST" != https://* ]]; then
            manifest_for_defaults="$CF_MODPACK_MANIFEST"
        fi
    fi

    if [ -n "${CF_PAGE_URL:-}" ]; then
        args+=(--modpack-page-url "$CF_PAGE_URL")
    fi
    if [ -n "${CF_SLUG:-}" ]; then
        args+=(--slug "$CF_SLUG")
    fi
    if [ -n "${CF_FILE_ID:-}" ]; then
        args+=(--file-id "$CF_FILE_ID")
    fi
    if [ -n "${CF_FILENAME_MATCHER:-}" ]; then
        args+=(--filename-matcher "$CF_FILENAME_MATCHER")
    fi
    if [ -n "${CF_DOWNLOADS_REPO:-}" ]; then
        args+=(--downloads-repo "$CF_DOWNLOADS_REPO")
    fi
    if [ -n "${CF_MOD_LOADER_VERSION:-}" ]; then
        args+=(--mod-loader-version "$CF_MOD_LOADER_VERSION")
    fi
    if [ -n "${CF_EXCLUDE_INCLUDE_FILE:-}" ]; then
        args+=(--exclude-include-file "$CF_EXCLUDE_INCLUDE_FILE")
    fi
    if [ -n "${CF_EXCLUDE_MODS:-}" ]; then
        args+=(--excludes "$CF_EXCLUDE_MODS")
    fi
    if [ -n "${CF_FORCE_INCLUDE_MODS:-}" ]; then
        args+=(--force-includes "$CF_FORCE_INCLUDE_MODS")
    fi
    if truthy "${CF_EXCLUDE_ALL_MODS:-false}"; then
        args+=(--exclude-all-mods)
    fi
    if [ -n "${CF_OVERRIDES_EXCLUSIONS:-}" ]; then
        args+=(--overrides-exclusions "$CF_OVERRIDES_EXCLUSIONS")
    fi
    if [ -n "${CF_IGNORE_MISSING_FILES:-}" ]; then
        args+=(--ignore-missing-files "$CF_IGNORE_MISSING_FILES")
    fi

    if [ -z "${CF_MODPACK_ZIP:-}" ] && [ -z "${CF_MODPACK_MANIFEST:-}" ] && [ -z "${CF_PAGE_URL:-}" ] && [ -z "${CF_SLUG:-}" ]; then
        echo "Error: provide one of CF_PAGE_URL, CF_SLUG, CF_MODPACK_ZIP, CF_MODPACK_MANIFEST, or legacy MODPACK_ZIP_URL" >&2
        exit 1
    fi

    if [ -n "$manifest_for_defaults" ]; then
        extract_manifest_defaults "$manifest_for_defaults"
    fi

    echo "Installing CurseForge modpack with mc-image-helper..."
    run_mc_image_helper "${args[@]}"
}

install_modrinth() {
    require_value MODRINTH_PROJECT

    local -a args
    args=(install-modrinth-modpack --output-directory "$PACK_DIR" --project "$MODRINTH_PROJECT" --force-synchronize)

    if [ -n "${MODRINTH_VERSION:-}" ]; then
        args+=(--version "$MODRINTH_VERSION")
    fi
    if [ -n "${MODRINTH_GAME_VERSION:-}" ]; then
        args+=(--game-version "$MODRINTH_GAME_VERSION")
        MC_VERSION="${MC_VERSION:-$MODRINTH_GAME_VERSION}"
    fi
    if [ -n "${MODRINTH_LOADER:-}" ]; then
        args+=(--loader "$MODRINTH_LOADER")
        MODLOADER="${MODLOADER:-$MODRINTH_LOADER}"
    fi
    if [ -n "${MODRINTH_EXCLUDE_FILES:-}" ]; then
        args+=(--exclude-files "$MODRINTH_EXCLUDE_FILES")
    fi
    if [ -n "${MODRINTH_FORCE_INCLUDE_FILES:-}" ]; then
        args+=(--force-include-files "$MODRINTH_FORCE_INCLUDE_FILES")
    fi
    if [ -n "${MODRINTH_IGNORE_MISSING_FILES:-}" ]; then
        args+=(--ignore-missing-files "$MODRINTH_IGNORE_MISSING_FILES")
    fi
    if [ -n "${MODRINTH_OVERRIDES_EXCLUSIONS:-}" ]; then
        args+=(--overrides-exclusions "$MODRINTH_OVERRIDES_EXCLUSIONS")
    fi

    echo "Installing Modrinth modpack with mc-image-helper..."
    run_mc_image_helper "${args[@]}"
}

write_packwiz_ignore() {
    cat > "$PACK_DIR/.packwizignore" <<'PACKWIZIGNORE'
.git/**
.packwizignore
.cache/**
packwiz-cache/**
logs/**
crash-reports/**
saves/**
screenshots/**
backups/**
server/**
libraries/**
versions/**
world/**
eula.txt
run.sh
run.bat
server.properties
user_jvm_args.txt
*.log
*.tmp
*.bak
PACKWIZIGNORE
}

initialize_packwiz_metadata() {
    PACK_NAME="${PACK_NAME:-Minecraft Modpack}"
    PACK_VERSION="${PACK_VERSION:-0.1.0}"
    require_value MC_VERSION

    local -a args
    args=(init --reinit --yes --name "$PACK_NAME" --version "$PACK_VERSION" --mc-version "$MC_VERSION")

    case "${MODLOADER:-}" in
        ""|none|NONE|vanilla|VANILLA)
            ;;
        fabric|Fabric)
            args+=(--modloader fabric)
            if [ "${MODLOADER_VERSION:-}" = "latest" ] || [ -z "${MODLOADER_VERSION:-}" ]; then
                args+=(--fabric-latest)
            else
                args+=(--fabric-version "$MODLOADER_VERSION")
            fi
            ;;
        forge|Forge)
            args+=(--modloader forge)
            if [ "${MODLOADER_VERSION:-}" = "latest" ] || [ -z "${MODLOADER_VERSION:-}" ]; then
                args+=(--forge-latest)
            else
                args+=(--forge-version "$MODLOADER_VERSION")
            fi
            ;;
        neoforge|NeoForge|NEOFORGE)
            args+=(--modloader neoforge)
            if [ "${MODLOADER_VERSION:-}" = "latest" ] || [ -z "${MODLOADER_VERSION:-}" ]; then
                args+=(--neoforge-latest)
            else
                args+=(--neoforge-version "$MODLOADER_VERSION")
            fi
            ;;
        quilt|Quilt)
            args+=(--modloader quilt)
            if [ "${MODLOADER_VERSION:-}" = "latest" ] || [ -z "${MODLOADER_VERSION:-}" ]; then
                args+=(--quilt-latest)
            else
                args+=(--quilt-version "$MODLOADER_VERSION")
            fi
            ;;
        liteloader|LiteLoader)
            args+=(--modloader liteloader)
            if [ "${MODLOADER_VERSION:-}" = "latest" ] || [ -z "${MODLOADER_VERSION:-}" ]; then
                args+=(--liteloader-latest)
            else
                args+=(--liteloader-version "$MODLOADER_VERSION")
            fi
            ;;
        *)
            echo "Error: unsupported MODLOADER '${MODLOADER}'" >&2
            echo "Use fabric, forge, neoforge, quilt, liteloader, or none." >&2
            exit 1
            ;;
    esac

    write_packwiz_ignore
    echo "Generating packwiz metadata..."
    run_packwiz "${args[@]}"
}

prepare_pack_dir
case "$MODPACK_SOURCE" in
    curseforge|cf)
        install_curseforge
        ;;
    modrinth|mr)
        install_modrinth
        ;;
    empty|none)
        echo "Starting from an empty pack directory."
        ;;
    local)
        echo "Using existing local files in $PACK_DIR."
        ;;
    *)
        echo "Error: unsupported MODPACK_SOURCE '$MODPACK_SOURCE'" >&2
        echo "Use curseforge, modrinth, empty, or local." >&2
        exit 1
        ;;
esac

initialize_packwiz_metadata

echo
echo "Initialization complete."
echo "Pack directory: $PACK_DIR"
echo "Next: run ./2-modpack-finalize.sh"
