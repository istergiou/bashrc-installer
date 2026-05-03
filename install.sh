#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_URL="https://raw.githubusercontent.com/istergiou/bashrc-installer/main/bashrc-installer.sh"
SCRIPT_NAME="bashrc-installer"

die() { echo "Error: $*" >&2; exit 1; }
log() { echo "$*"; }

usage() {
    cat <<EOF
Usage: install.sh [-i|--install-dir <dir>]

Downloads and installs bashrc-installer into the specified directory.

OPTIONS:
  -i, --install-dir <dir>   Install directory (default: \$HOME/.local/bin)
  -h, --help                Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--install-dir)
            [[ $# -lt 2 ]] && die "--install-dir requires a directory argument"
            INSTALL_DIR="$2"; shift 2 ;;
        --install-dir=*)
            INSTALL_DIR="${1#*=}"; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            die "Unknown option: $1. Run with --help for usage." ;;
    esac
done

if [[ ! -d "$INSTALL_DIR" ]]; then
    mkdir -p "$INSTALL_DIR" || die "Cannot create directory: $INSTALL_DIR"
    log "Created $INSTALL_DIR"
fi

[[ -w "$INSTALL_DIR" ]] || die "Directory is not writable: $INSTALL_DIR"

TARGET="${INSTALL_DIR}/${SCRIPT_NAME}"

log "Downloading ${SCRIPT_NAME}..."
if command -v curl &>/dev/null; then
    curl -fsSL "$SCRIPT_URL" -o "$TARGET"
elif command -v wget &>/dev/null; then
    wget -qO "$TARGET" "$SCRIPT_URL"
else
    die "Neither curl nor wget is available."
fi

chmod +x "$TARGET"
log "Installed ${SCRIPT_NAME} → ${TARGET}"

case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        log ""
        log "Note: ${INSTALL_DIR} is not in your PATH."
        log "Add it to your shell profile: export PATH=\"${INSTALL_DIR}:\$PATH\""
        ;;
esac
