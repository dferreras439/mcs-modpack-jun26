#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$ROOT_DIR/bin}"
TOOLS_DIR="${TOOLS_DIR:-$ROOT_DIR/.tools}"
MC_IMAGE_HELPER_VERSION="${MC_IMAGE_HELPER_VERSION:-1.61.1}"
MC_IMAGE_HELPER_URL="${MC_IMAGE_HELPER_URL:-https://github.com/itzg/mc-image-helper/releases/download/${MC_IMAGE_HELPER_VERSION}/mc-image-helper-${MC_IMAGE_HELPER_VERSION}.tgz}"
PACKWIZ_PACKAGE="${PACKWIZ_PACKAGE:-github.com/packwiz/packwiz@latest}"

mkdir -p "$BIN_DIR"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command not found: $cmd" >&2
        exit 1
    fi
}

install_packwiz() {
    require_cmd go

    echo "Installing packwiz from $PACKWIZ_PACKAGE..."
    GOBIN="$BIN_DIR" go install "$PACKWIZ_PACKAGE"

    if [ ! -x "$BIN_DIR/packwiz" ]; then
        echo "Error: failed to install packwiz into $BIN_DIR" >&2
        exit 1
    fi

    "$BIN_DIR/packwiz" --help >/dev/null
}

install_mc_image_helper() {
    require_cmd curl
    require_cmd tar

    echo "Installing mc-image-helper $MC_IMAGE_HELPER_VERSION..."
    local tmp_dir helper dist_dir install_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"; trap - RETURN' RETURN

    curl -fsSL "$MC_IMAGE_HELPER_URL" | tar -C "$tmp_dir" -zxf -

    helper="$(find "$tmp_dir" -path '*/bin/mc-image-helper' -type f | head -n 1)"
    if [ -z "$helper" ]; then
        echo "Error: mc-image-helper binary was not found in downloaded archive" >&2
        exit 1
    fi

    # mc-image-helper is a Gradle application distribution. Its bin launcher
    # depends on the sibling ../lib directory, so do not copy the launcher by
    # itself into ./bin.
    dist_dir="$(cd "$(dirname "$helper")/.." && pwd)"
    install_dir="$TOOLS_DIR/mc-image-helper-$MC_IMAGE_HELPER_VERSION"

    rm -rf "$install_dir"
    mkdir -p "$TOOLS_DIR"
    cp -R "$dist_dir" "$install_dir"
    chmod +x "$install_dir/bin/mc-image-helper"

    cat > "$BIN_DIR/mc-image-helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$install_dir/bin/mc-image-helper" "\$@"
EOF
    chmod +x "$BIN_DIR/mc-image-helper"

    "$BIN_DIR/mc-image-helper" --help >/dev/null
}

install_rclone_shim_if_available() {
    if command -v rclone >/dev/null 2>&1; then
        echo "Linking existing rclone into $BIN_DIR..."
        ln -sf "$(command -v rclone)" "$BIN_DIR/rclone"
    else
        echo "rclone was not found on PATH. Install rclone before running ./3-modpack-publish.sh." >&2
        echo "The publish script will also use RCLONE=... if you keep rclone outside ./bin." >&2
    fi
}

install_packwiz
install_mc_image_helper
install_rclone_shim_if_available

echo
echo "Bootstrap complete."
echo "Installed tools:"
echo "  packwiz:         $BIN_DIR/packwiz"
echo "  mc-image-helper: $BIN_DIR/mc-image-helper"
if [ -e "$BIN_DIR/rclone" ]; then
    echo "  rclone:          $BIN_DIR/rclone"
fi
