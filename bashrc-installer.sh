#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
DEFAULT_INSTALL_DIR="${HOME}/.bashrc.d"
INSTALL_DIR="${DEFAULT_INSTALL_DIR}"
FORCE=false

die() { echo "Error: $*" >&2; exit 1; }
log() { echo "$*"; }

# --- HTTP: used by 'list' for API calls ---

# Authenticated API GET (curl/wget).
# Uses GITHUB_TOKEN as alias for GIT_TOKEN on github.com.
api_get() {
    local host="$1" url="$2"
    local token=""
    case "$host" in
        github.com) token="${GITHUB_TOKEN:-${GIT_TOKEN:-}}" ;;
        *)          token="${GIT_TOKEN:-}" ;;
    esac
    if command -v curl &>/dev/null; then
        local args=(-fsSL)
        [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
        curl "${args[@]}" "$url"
    elif command -v wget &>/dev/null; then
        local args=(-qO-)
        [[ -n "$token" ]] && args+=("--header=Authorization: Bearer $token")
        wget "${args[@]}" "$url"
    else
        die "Neither curl nor wget is available (required for 'list')."
    fi
}

# --- Source parsing ---
# Splits "host/[basepath/]user[/repo]" into three parts:
#   host   = first component
#   parent = everything between host and the last component (may be empty)
#   name   = last component (repo for install, user for list/install-all)
parse_source() {
    local source="$1"
    source="${source#https://}"
    source="${source#http://}"
    local host="${source%%/*}"
    local full_path="${source#*/}"
    local name="${full_path##*/}"
    local parent=""
    [[ "$full_path" == */* ]] && parent="${full_path%/*}"
    printf '%s\t%s\t%s' "$host" "$parent" "$name"
}

# --- JSON parsing: used by 'list' and 'install-all' ---

# Extracts all repo names from a platform API JSON response using grep/awk only.
parse_repo_names() {
    local json="$1" platform="$2"
    case "$platform" in
        github|gitea)
            printf '%s' "$json" | grep '"full_name"' | \
                awk -F'"' '{split($4, a, "/"); print a[length(a)]}'
            ;;
        gitlab)
            printf '%s' "$json" | grep '"path_with_namespace"' | \
                awk -F'"' '{split($4, a, "/"); print a[length(a)]}'
            ;;
    esac
}

list_repos() {
    local host="$1" basepath="$2" user="$3"
    local json
    local base_url="https://${host}${basepath:+/${basepath}}"
    case "$host" in
        github.com)
            json=$(api_get "$host" "https://api.github.com/users/${user}/repos?per_page=100") \
                || die "Failed to fetch repos from github.com/${user}"
            parse_repo_names "$json" "github"
            ;;
        gitlab.com|gitlab.*)
            json=$(api_get "$host" "${base_url}/api/v4/users/${user}/projects?per_page=100") \
                || die "Failed to fetch repos from ${host}/${basepath:+${basepath}/}${user}"
            parse_repo_names "$json" "gitlab"
            ;;
        *)
            json=$(api_get "$host" "${base_url}/api/v1/users/${user}/repos?limit=50") \
                || die "Failed to fetch repos from ${host}/${basepath:+${basepath}/}${user}. Host may not support a compatible API."
            parse_repo_names "$json" "gitea"
            ;;
    esac
}

# --- Git: used by 'install' and 'install-all' ---

# Builds an authenticated HTTPS clone URL.
# Uses oauth2:<token>@host, accepted by GitHub, GitLab, and Gitea.
git_clone_url() {
    local host="$1" path="$2"
    local token=""
    case "$host" in
        github.com) token="${GITHUB_TOKEN:-${GIT_TOKEN:-}}" ;;
        *)          token="${GIT_TOKEN:-}" ;;
    esac
    if [[ -n "$token" ]]; then
        printf 'https://oauth2:%s@%s/%s' "$token" "$host" "$path"
    else
        printf 'https://%s/%s' "$host" "$path"
    fi
}

# Clone a repo and install all *.sh files (executable) and *.md/*.txt files to INSTALL_DIR.
install_repo_files() {
    local host="$1" repo_path="$2" repo_name="$3"
    local url tmpdir
    url=$(git_clone_url "$host" "$repo_path")
    tmpdir=$(mktemp -d)

    if ! GIT_TERMINAL_PROMPT=0 git clone --depth=1 --quiet "$url" "$tmpdir" 2>/dev/null; then
        rm -rf "$tmpdir"
        log "  SKIP ${repo_name}: failed to clone"
        return 0
    fi

    local installed=0 fname target answer

    while IFS= read -r f; do
        fname=$(basename "$f")
        target="${INSTALL_DIR}/${fname}"
        if [[ -f "$target" ]] && [[ "$FORCE" == "false" ]]; then
            read -r -p "${fname} already exists in ${INSTALL_DIR}. Overwrite? [y/N] " answer < /dev/tty
            answer=${answer:-N} # Default to 'N' if no input is provided
            case "$answer" in [yY]*) ;; *) log "  SKIP ${fname}"; continue ;; esac
        fi
        cp "$f" "$target"
        chmod +x "$target"
        log "  INSTALLED ${fname} → ${target}"
        installed=1
    done < <(find "$tmpdir" -maxdepth 1 -name "*.sh" ! -name ".*")

    while IFS= read -r f; do
        fname=$(basename "$f")
        target="${INSTALL_DIR}/${fname}"
        if [[ -f "$target" ]] && [[ "$FORCE" == "false" ]]; then
            read -r -p "${fname} already exists in ${INSTALL_DIR}. Overwrite? [y/N] " answer < /dev/tty
            answer=${answer:-N} # Default to 'N' if no input is provided
            case "$answer" in [yY]*) ;; *) log "  SKIP ${fname}"; continue ;; esac
        fi
        cp "$f" "$target"
        log "  COPIED ${fname} → ${target}"
        installed=1
    done < <(find "$tmpdir" -maxdepth 1 \( -name "*.md" -o -name "*.txt" \) ! -name ".*")

    rm -rf "$tmpdir"

    if [[ $installed -eq 0 ]]; then
        log "  SKIP ${repo_name}: no installable files found"
    fi
}

# --- Utilities ---

ensure_install_dir() {
    if [[ ! -d "${INSTALL_DIR}" ]]; then
        mkdir -p "${INSTALL_DIR}" || die "Cannot create install directory: ${INSTALL_DIR}"
        log "Created install directory: ${INSTALL_DIR}"
    fi
    [[ -w "${INSTALL_DIR}" ]] || die "Install directory is not writable: ${INSTALL_DIR}"
}

# --- Commands ---

cmd_prepare() {
    local bashrc_d="${HOME}/.bashrc.d"
    local bashrc="${HOME}/.bashrc"

    if [[ ! -d "$bashrc_d" ]]; then
        mkdir -p "$bashrc_d" || die "Cannot create ${bashrc_d}"
        log "Created ${bashrc_d}"
    else
        log "${bashrc_d} already exists"
    fi

    if grep -qF '.bashrc.d' "$bashrc" 2>/dev/null; then
        log "${bashrc} already sources ~/.bashrc.d"
    else
        cat >> "$bashrc" <<'EOF'

printf "sourcing:"
for file in ${HOME}/.bashrc.d/*.sh; do
  [ -r "$file" ] && printf " $(basename -s ".sh" "$file")" && source "$file"
done
printf  ".\n"
EOF
        log "Updated ${bashrc} to source ~/.bashrc.d/*.sh"
    fi
}

# List repos with bashrc- or bashrc_ prefix. No URL probing.
cmd_list() {
    local source="${1:-}"
    [[ -z "${source}" ]] && die "Usage: bashrc-installer.sh list <host>/<user>"

    local host parent name
    IFS=$'\t' read -r host parent name <<< "$(parse_source "${source}")"
    local user="$name"

    log "Fetching repos for ${user} on ${host}..."
    local repos
    repos=$(list_repos "$host" "$parent" "$user") || true

    if [[ -z "${repos}" ]]; then
        log "No repos found for ${user} on ${host}."
        return 0
    fi

    local found=()
    while IFS= read -r r; do
        if [[ "$r" == bashrc[-_]* ]]; then
            found+=("$r")
        fi
    done <<< "${repos}"

    if [[ ${#found[@]} -eq 0 ]]; then
        log "No bashrc repos found for ${user} on ${host}."
        return 0
    fi

    log ""
    log "Available bashrc repos:"
    for r in "${found[@]}"; do
        log "  ${r}"
    done
}

# install: single repo via git clone — installs all *.sh, *.md, *.txt files
cmd_install() {
    local source="${1:-}"
    [[ -z "${source}" ]] && die "Usage: bashrc-installer.sh install <host>/<user>/<repo>"

    ensure_install_dir
    command -v git &>/dev/null || die "git is required for install."

    local host parent name
    IFS=$'\t' read -r host parent name <<< "$(parse_source "${source}")"

    [[ -z "${parent}" ]] && die "Specify a repo: bashrc-installer.sh install <host>/<user>/<repo>"
    install_repo_files "$host" "${parent}/${name}" "$name"
}

# install-all: all bashrc[-_] repos for a user via git clone
cmd_install_all() {
    local source="${1:-}"
    [[ -z "${source}" ]] && die "Usage: bashrc-installer.sh install-all <host>/<user>"

    ensure_install_dir
    command -v git &>/dev/null || die "git is required for install-all."

    local host parent name
    IFS=$'\t' read -r host parent name <<< "$(parse_source "${source}")"
    [[ "$name" == "$host" ]] && die "Specify a user: bashrc-installer.sh install-all <host>/<user>"

    local user="$name"
    local user_path="${parent:+${parent}/}${user}"

    log "Fetching repos for ${user} on ${host}..."
    local repos
    repos=$(list_repos "$host" "$parent" "$user") || true

    if [[ -z "${repos}" ]]; then
        log "No repos found for ${user} on ${host}."
        return 0
    fi

    while IFS= read -r r; do
        if [[ "$r" == bashrc[-_]* ]]; then
            log "Installing from ${host}/${user_path}/${r}..."
            install_repo_files "$host" "${user_path}/${r}" "$r"
        fi
    done <<< "${repos}"
}

cmd_uninstall() {
    local name="${1:-}"
    [[ -z "${name}" ]] && die "Usage: bashrc-installer.sh uninstall <name>"

    # Accept name with or without .sh extension
    name="${name%.sh}"
    local target="${INSTALL_DIR}/${name}.sh"

    if [[ ! -f "${target}" ]]; then
        log "Warning: ${name} is not installed in ${INSTALL_DIR}"
        return 0
    fi

    rm -f "${target}"
    log "Uninstalled ${name} from ${INSTALL_DIR}"
}

cmd_help() {
    cat <<EOF
bashrc-installer.sh v${VERSION}

Installs shell scripts into ~/.bashrc.d so they are automatically sourced by bash.
Supports GitHub, GitLab, and Gitea/Forgejo (including self-hosted with a basepath).

USAGE:
  bashrc-installer.sh [OPTIONS] COMMAND [ARGS]

OPTIONS:
  -h, --help                  Show this help message and exit
  -v, --version               Show version and exit
  -i, --install-dir <dir>     Install directory (default: \$HOME/.bashrc.d)
  -f, --force                 Overwrite existing files without prompting

COMMANDS:
  prepare                         Create ~/.bashrc.d and wire it into ~/.bashrc
  list <host>/<user>              List repos with bashrc- or bashrc_ prefix (no script check)
  install <host>/<user>/<repo>    Install all *.sh, *.md, *.txt from a repo via git clone
  install-all <host>/<user>       Install all bashrc[-_] repos for a user via git clone
  uninstall <name>                Remove an installed script

  Self-hosted servers with a basepath are supported:
    install     mygitserver.com/basepath/user/repo
    install-all mygitserver.com/basepath/user

ENVIRONMENT:
  GIT_TOKEN       Personal access token (all platforms)
  GITHUB_TOKEN    Alias for GIT_TOKEN on github.com

  Unauthenticated GitHub API requests: 60/hr. Authenticated: 5000/hr.

EXAMPLES:
  bashrc-installer.sh prepare
  bashrc-installer.sh list github.com/istergiou
  bashrc-installer.sh install github.com/istergiou/bashrc-kubeconfig
  bashrc-installer.sh install mygitserver.com/basepath/user/bashrc-repo
  bashrc-installer.sh install-all github.com/istergiou
  bashrc-installer.sh install-all mygitserver.com/basepath/user
  bashrc-installer.sh --install-dir /usr/local/bin install gitlab.com/istergiou/bashrc-kubeconfig
  bashrc-installer.sh -f install-all gitea.example.com/istergiou
  bashrc-installer.sh uninstall kubeconfig
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cmd_help; exit 0 ;;
            -v|--version)
                log "bashrc-installer.sh v${VERSION}"; exit 0 ;;
            -f|--force)
                FORCE=true; shift ;;
            -i|--install-dir)
                [[ $# -lt 2 ]] && die "--install-dir requires a directory argument"
                INSTALL_DIR="$2"; shift 2 ;;
            --install-dir=*)
                INSTALL_DIR="${1#*=}"; shift ;;
            -*)
                die "Unknown option: $1. Run with --help for usage." ;;
            *)
                break ;;
        esac
    done

    local cmd="${1:-}"
    shift || true

    case "${cmd}" in
        prepare)     cmd_prepare ;;
        list)        cmd_list "$@" ;;
        install)     cmd_install "$@" ;;
        install-all) cmd_install_all "$@" ;;
        uninstall)   cmd_uninstall "$@" ;;
        "")          cmd_help; exit 1 ;;
        *)           die "Unknown command: ${cmd}. Run with --help for usage." ;;
    esac
}

main "$@"
