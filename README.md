# bashrc-installer

Installs shell scripts into `~/.bashrc.d` so they are automatically sourced by bash.
Supports **GitHub**, **GitLab**, and **Gitea/Forgejo** (self-hosted with basepaths included).

## Requirements

- `bash` 4+
- `git` (for `install` and `install-all`)
- `curl` or `wget` (for `list`)

## Installation

Run `install.sh` to download `bashrc-installer` into `~/.local/bin`:

```bash
# curl
curl -fsSL https://raw.githubusercontent.com/istergiou/bashrc-installer/main/install.sh | bash

# wget
wget -qO- https://raw.githubusercontent.com/istergiou/bashrc-installer/main/install.sh | bash
```

To install into a custom directory:

```bash
# curl
curl -fsSL https://raw.githubusercontent.com/istergiou/bashrc-installer/main/install.sh | bash -s -- --install-dir /usr/local/bin

# wget
wget -qO- https://raw.githubusercontent.com/istergiou/bashrc-installer/main/install.sh | bash -s -- --install-dir /usr/local/bin
```

## Quick start

```bash
bashrc-installer prepare          # create ~/.bashrc.d and wire it into ~/.bashrc
bashrc-installer install-all github.com/istergiou
source ~/.bashrc
```

## Usage

```
bashrc-installer [OPTIONS] COMMAND [ARGS]
```

### Options

| Flag | Description |
|------|-------------|
| `-h`, `--help` | Show help and exit |
| `-v`, `--version` | Show version and exit |
| `-i`, `--install-dir <dir>` | Install directory (default: `$HOME/.bashrc.d`) |
| `-f`, `--force` | Overwrite existing files without prompting |

### Commands

#### `prepare`

Creates `~/.bashrc.d` and appends a sourcing snippet to `~/.bashrc` (idempotent):

```bash
bashrc-installer prepare
```

This adds the following to `~/.bashrc` if not already present:

```bash
for file in ${HOME}/.bashrc.d/*.sh; do
[ -r "$file" ] && source "$file"
done
```

#### `list`

List repos for a user whose name starts with `bashrc-` or `bashrc_`. Uses `curl` or `wget` for the API call; does not check whether the repos contain scripts.

```bash
bashrc-installer list github.com/istergiou
bashrc-installer list gitlab.com/istergiou
bashrc-installer list gitea.example.com/istergiou
bashrc-installer list mygitserver.com/basepath/user
```

#### `install`

Install all `*.sh` files (set executable) and all `*.md`/`*.txt` files from a single repository into `~/.bashrc.d` via `git clone`. Works with any repo name — no `bashrc-` prefix required:

```bash
bashrc-installer install github.com/istergiou/bashrc-kubeconfig
bashrc-installer install gitlab.com/istergiou/bashrc-kubeconfig
bashrc-installer install mygitserver.com/basepath/user/bashrc-repo
bashrc-installer install mygitserver.com/basepath/user/bashrc
bashrc-installer install mygitserver.com/basepath/user/somerepo
```

#### `install-all`

Install all `*.sh`, `*.md`, and `*.txt` files from every repo with a `bashrc-` or `bashrc_` prefix for a given user. Each repo is cloned via `git`:

```bash
bashrc-installer install-all github.com/istergiou
bashrc-installer install-all mygitserver.com/basepath/user
```

Force overwrite without prompting:

```bash
bashrc-installer -f install-all github.com/istergiou
```

#### `uninstall`

Remove an installed script from `~/.bashrc.d`:

```bash
bashrc-installer uninstall kubeconfig
```

### Authentication and API rate limits

```bash
# GitHub (60 req/hr unauthenticated → 5000/hr authenticated)
export GITHUB_TOKEN=ghp_your_token_here

# GitLab or Gitea/Forgejo
export GIT_TOKEN=your_token_here
```

`GIT_TOKEN` is the universal token. `GITHUB_TOKEN` is an alias that applies on `github.com` only.
Both tokens are used for `git clone` authentication (via `oauth2:<token>@host`) as well as API calls.

For private repositories use the command:

```bash
GITHUB_TOKEN=ghp_your_token_here bashrc-installer install github.com/istergiou/bashrc-private
```

---

## For script developers

To make your repository installable via `bashrc-installer`, follow these conventions.

### Repository naming

The repository name must start with `bashrc-` or `bashrc_` to be discovered by `list` and `install-all`.
Any repository can be installed directly with `install` regardless of its name.

### File conventions

The installer copies the following files from the **root of the repository** into `~/.bashrc.d`:

| File type | Action |
|-----------|--------|
| `*.sh` | Copied and made executable |
| `*.md` | Copied as-is |
| `*.txt` | Copied as-is |

Files in subdirectories are not installed.

### Checklist

- [ ] Repository name starts with `bashrc-` or `bashrc_`
- [ ] Shell scripts are at the repo root with a `.sh` extension
- [ ] Scripts are designed to be **sourced** (set env vars, aliases, functions) rather than executed
- [ ] Scripts are valid bash
- [ ] Default branch is `main` or `master`
- [ ] Scripts are self-contained or document their dependencies clearly
