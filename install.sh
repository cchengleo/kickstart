#!/bin/bash
#
# kickstart: set up a Mac from cchengleo/dotfiles in one command
#
#   /bin/bash -c "$(curl -fsSL https://kickstart.ccheng.us)"
#
# 1. Asks how to get read access to the private dotfiles repo:
#    - GitHub login, on the repo owner's Macs: installs the GitHub CLI and logs
#      in with a one-time code you approve in a browser
#    - a deploy key you were given, on a friend's Mac: paste the private key;
#      it is saved as ~/.ssh/damaris-x-dotfiles, used for updates too, and
#      reads the copy of the dotfiles kept for friends (damaris-x/dotfiles)
# 2. Installs Homebrew if it's missing (it brings git). On a Mac managed by an
#    organization (MDM), install the organization's Homebrew first.
# 3. Clones the repo to ~/.dotfiles and runs ~/.dotfiles/script/kickstart,
#    which asks a few more questions, shows a summary, and sets up the rest.
#
# Running it again reuses the clone and the key, and updates.
#
# Environment:
#   KICKSTART_DEPLOY_KEY    private key file to use, instead of asking
#   KICKSTART_GITHUB_USER   owner of the dotfiles repo (default: cchengleo)
#   KICKSTART_FRIENDS_REPO  the friends' copy (default: damaris-x/dotfiles)
#   KICKSTART_DOTFILES_URL  clone this instead of GitHub, without an access
#                           check (used by the dotfiles Tart tests)
#   The rest pass through to script/kickstart (see the top of that file).
#
# This file is public and holds no secrets; everything else comes from the
# private repo. Everything runs from main(), called on the last line, so a
# partial download runs nothing.

GITHUB_USER="${KICKSTART_GITHUB_USER:-cchengleo}"
FRIENDS_REPO="${KICKSTART_FRIENDS_REPO:-damaris-x/dotfiles}"
DOTFILES_DIR="$HOME/.dotfiles"
KEY_NAME="${FRIENDS_REPO//\//-}"
KEY_FILE="$HOME/.ssh/$KEY_NAME"
# As stored in the clone's core.sshCommand; git runs it through the shell
SSH_COMMAND="ssh -i ~/.ssh/$KEY_NAME -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

info()  { printf '\033[34m==>\033[0m \033[1m%s\033[0m\n' "$1"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$1"; }
die()   { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

# ask VAR LABEL DEFAULT: prompt with a default; Enter keeps it
ask() {
  local answer
  read -r -p "  $(printf '%-14s' "$2") [$3]: " answer || answer=
  printf -v "$1" '%s' "${answer:-$3}"
}

load_brew() {
  local brew
  for brew in /opt/homebrew/bin/brew /usr/local/bin/brew /opt/brew/bin/brew; do
    if [[ -x "$brew" ]]; then
      eval "$("$brew" shellenv)"
      return 0
    fi
  done
  command -v brew >/dev/null 2>&1
}

# Enrolled in an organization's device management, like most work Macs
managed_mac() {
  /usr/bin/profiles status -type enrollment 2>/dev/null | grep -q '^MDM enrollment: Yes'
}

setup_homebrew() {
  info "Homebrew"
  if load_brew; then
    ok "$(brew --prefix)"
    return
  fi
  if managed_mac; then
    die "This Mac is managed by an organization and has no Homebrew. Install Homebrew the way the organization provides it, then run kickstart again."
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew || die "Homebrew installed, but brew is not on the expected paths"
  ok "installed at $(brew --prefix)"
}

setup_github() {
  info "GitHub access"
  if ! command -v gh >/dev/null 2>&1; then
    brew install gh
  fi
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    ok "logged in to GitHub"
  else
    # Prints a one-time code; approve it in a browser on this Mac or any device
    gh auth login --hostname github.com --git-protocol https --web
  fi
  gh auth setup-git --hostname github.com
}

# read_pasted_key FILE: read a pasted private key into FILE, through its END
# line. Echo is off from before the prompt, so no part of a fast paste shows.
read_pasted_key() {
  local out=$1 line started=false
  saved_tty="$(stty -g)"
  stty -echo
  printf '  %-14s [paste, then Enter]: ' "Deploy key"
  while IFS= read -r line; do
    # Copies from web pages can carry CRs and stray spaces
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ "$started" == false ]]; then
      [[ -n "$line" ]] || continue
      [[ "$line" == "-----BEGIN "*"PRIVATE KEY-----" ]] \
        || die "That isn't a private key; it starts with -----BEGIN ... PRIVATE KEY-----"
      started=true
    fi
    printf '%s\n' "$line" >> "$out"
    if [[ "$line" == "-----END "*"PRIVATE KEY-----" ]]; then
      stty "$saved_tty"
      saved_tty=
      echo
      return 0
    fi
  done
  die "The key ended before its -----END ... PRIVATE KEY----- line"
}

# install_key SRC: check a private key (a file, or "paste") and save it as KEY_FILE
install_key() {
  local src=$1
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  key_tmp="$(mktemp "$HOME/.ssh/.kickstart-key.XXXXXX")"
  if [[ "$src" == paste ]]; then
    read_pasted_key "$key_tmp"
  else
    [[ -f "$src" ]] || die "KICKSTART_DEPLOY_KEY: no such file: $src"
    tr -d '\r' < "$src" > "$key_tmp"
  fi
  chmod 600 "$key_tmp"
  /usr/bin/ssh-keygen -y -f "$key_tmp" >/dev/null 2>&1 \
    || die "ssh can't read that key. Ask $GITHUB_USER for it again (RSA, or OpenSSH format)."
  mv "$key_tmp" "$KEY_FILE"
  key_tmp=
  ok "key saved as ~/.ssh/$KEY_NAME"
}

main() {
  set -euo pipefail
  [[ "$(uname -s)" == Darwin ]] || die "kickstart only supports macOS"

  interactive=false
  if [[ -t 0 && -z "${KICKSTART_YES:-}" ]]; then interactive=true; fi
  # A half-read key never stays behind, and echo always comes back
  key_tmp=
  saved_tty=
  trap '[[ -z "$saved_tty" ]] || stty "$saved_tty"; [[ -z "$key_tmp" ]] || rm -f "$key_tmp"' EXIT

  # How to read the repo: key_src is a key file, "paste", "saved", or empty
  # for a GitHub login
  key_src=
  if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    if [[ -n "${KICKSTART_DEPLOY_KEY:-}" ]]; then
      key_src="${KICKSTART_DEPLOY_KEY/#\~/$HOME}"
    elif [[ -f "$KEY_FILE" ]]; then
      key_src=saved
    elif [[ "$interactive" == true ]]; then
      info "Access to $GITHUB_USER/dotfiles"
      echo "    1) GitHub login ($GITHUB_USER's own Macs)"
      echo "    2) a deploy key you were given"
      local access
      ask access "Choice" 1
      case "$access" in
        1) ;;
        2) key_src=paste ;;
        *) die "Choose 1 or 2" ;;
      esac
    fi
  fi

  setup_homebrew

  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    info "dotfiles"
    ok "~/.dotfiles is there; kickstart updates it"
  elif [[ -n "$key_src" ]]; then
    info "Deploy key"
    [[ "$key_src" == saved ]] || install_key "$key_src"
    local url="${KICKSTART_DOTFILES_URL:-git@github.com:$FRIENDS_REPO.git}"
    if [[ -z "${KICKSTART_DOTFILES_URL:-}" ]]; then
      GIT_SSH_COMMAND="$SSH_COMMAND" git ls-remote "$url" HEAD >/dev/null 2>&1 \
        || die "The key can't read $FRIENDS_REPO yet. Once $GITHUB_USER has added it there as a deploy key, run this again."
      ok "the key can read $FRIENDS_REPO"
    fi
    info "dotfiles"
    git clone --quiet -c core.sshCommand="$SSH_COMMAND" "$url" "$DOTFILES_DIR"
    ok "cloned to ~/.dotfiles, read-only with the key"
  else
    if [[ -z "${KICKSTART_DOTFILES_URL:-}" ]]; then
      setup_github
      info "dotfiles"
      gh repo clone "$GITHUB_USER/dotfiles" "$DOTFILES_DIR" -- --quiet
    else
      info "dotfiles"
      git clone --quiet "$KICKSTART_DOTFILES_URL" "$DOTFILES_DIR"
    fi
    ok "cloned to ~/.dotfiles"
  fi

  [[ -x "$DOTFILES_DIR/script/kickstart" ]] || die "~/.dotfiles has no script/kickstart"
  exec "$DOTFILES_DIR/script/kickstart"
}

main "$@"
