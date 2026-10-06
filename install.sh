#!/bin/bash
#
# kickstart: set up a Mac from cchengleo/dotfiles and cchengleo/dotfiles-local
#
#   /bin/bash -c "$(curl -fsSL https://kickstart.ccheng.us)"
#
# 1. Homebrew. On an Apple-managed Mac, install Apple's Homebrew first.
# 2. GitHub CLI, and a one-time browser login so git can read the private repos
# 3. ~/.dotfiles: clone or update, then script/bootstrap and script/install
# 4. ~/.dotfiles-local: branch Darwin/<hostname -s> if there is one, otherwise
#    default; then its script/bootstrap and script/install
#
# Re-running it updates both repos and deploys again.
#
# Environment:
#   KICKSTART_BRANCH     dotfiles-local branch to use instead of the automatic choice
#   DOTFILES_CONFLICT    what bootstrap does with existing files: backup (default),
#                        skip or overwrite
#   KICKSTART_DOTFILES_URL, KICKSTART_DOTFILES_LOCAL_URL
#                        clone these instead of the GitHub repos and skip the GitHub
#                        login (used by the dotfiles Tart tests)
#
# This file is public and has no secrets; everything else comes from the
# private repos after you log in.

# Everything runs from main(), called on the last line, so a partial download
# runs nothing.

GITHUB_USER=cchengleo
DOTFILES_DIR="$HOME/.dotfiles"
DOTFILES_LOCAL_DIR="$HOME/.dotfiles-local"
GIT_NAME="Cheng Cheng"
GIT_EMAIL="ccheng@ccheng.us"

info()  { printf '\033[34m==>\033[0m \033[1m%s\033[0m\n' "$1"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$1"; }
die()   { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

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

apple_managed() {
  [[ -x /usr/local/bin/appleconnect ]] || command -v appleconnect >/dev/null 2>&1
}

setup_homebrew() {
  info "Homebrew"
  if load_brew; then
    ok "$(brew --prefix)"
    return
  fi
  if apple_managed; then
    die "This is an Apple-managed Mac without Homebrew. Install Apple's internal Homebrew (github.pie.apple.com/homebrew/brew) first, then run kickstart again."
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
    ok "logged in as $(gh api user --jq .login 2>/dev/null || echo "$GITHUB_USER")"
  else
    # Prints a one-time code; open the URL on any device to approve
    gh auth login --hostname github.com --git-protocol https --web
  fi
  # Let git use gh's login for https://github.com
  gh auth setup-git --hostname github.com
  ok "git can read the private repos"
}

# clone_or_update URL DIR
clone_or_update() {
  local url=$1 dir=$2
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --quiet --prune origin
    ok "$dir: fetched"
  else
    git clone --quiet "$url" "$dir"
    ok "$dir: cloned"
  fi
  if [[ -z "$(git -C "$dir" config user.email || true)" ]]; then
    git -C "$dir" config user.name "$GIT_NAME"
    git -C "$dir" config user.email "$GIT_EMAIL"
  fi
}

# fast_forward DIR: update the checked-out branch from origin, if it tracks one
fast_forward() {
  local dir=$1
  if git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git -C "$dir" merge --quiet --ff-only '@{u}' \
      || die "Can't fast-forward $dir to origin (local commits or changes in the way); update it by hand, then run kickstart again"
  fi
}

deploy() {
  local dir=$1
  DOTFILES_CONFLICT="${DOTFILES_CONFLICT:-backup}" "$dir/script/bootstrap"
  "$dir/script/install"
}

main() {
  set -euo pipefail

  [[ "$(uname -s)" == Darwin ]] || die "kickstart only supports macOS"

  local dotfiles_url="${KICKSTART_DOTFILES_URL:-}"
  local local_url="${KICKSTART_DOTFILES_LOCAL_URL:-}"

  setup_homebrew
  if [[ -z "$dotfiles_url" || -z "$local_url" ]]; then
    setup_github
    dotfiles_url="${dotfiles_url:-https://github.com/$GITHUB_USER/dotfiles.git}"
    local_url="${local_url:-https://github.com/$GITHUB_USER/dotfiles-local.git}"
  fi

  info "dotfiles"
  clone_or_update "$dotfiles_url" "$DOTFILES_DIR"
  fast_forward "$DOTFILES_DIR"
  deploy "$DOTFILES_DIR"

  info "dotfiles-local"
  clone_or_update "$local_url" "$DOTFILES_LOCAL_DIR"
  local host_branch branch
  host_branch="$(uname -s)/$(hostname -s)"
  if [[ -n "${KICKSTART_BRANCH:-}" ]]; then
    branch="$KICKSTART_BRANCH"
  elif git -C "$DOTFILES_LOCAL_DIR" ls-remote --exit-code --heads origin "$host_branch" >/dev/null 2>&1; then
    branch="$host_branch"
  else
    branch=default
  fi
  git -C "$DOTFILES_LOCAL_DIR" checkout --quiet "$branch" \
    || die "Could not check out $branch in $DOTFILES_LOCAL_DIR (local changes?)"
  fast_forward "$DOTFILES_LOCAL_DIR"
  ok "branch $branch"
  deploy "$DOTFILES_LOCAL_DIR"

  info "Done"
  if [[ "$branch" == default ]]; then
    echo "  This Mac uses the default dotfiles-local branch. To customize it:"
    echo "    cd ~/.dotfiles-local && git checkout -b $host_branch && git push -u origin $host_branch"
  fi
  echo "  Open a new terminal to load the shell configuration."
}

main "$@"
