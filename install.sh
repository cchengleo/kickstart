#!/bin/bash
#
# kickstart: set up a Mac from cchengleo/dotfiles and cchengleo/dotfiles-local
#
#   /bin/bash -c "$(curl -fsSL https://kickstart.ccheng.us)"
#
# In a terminal it first asks a few questions (computer name, git identity,
# dotfiles-local branch), each with a default, and shows a summary before
# changing anything. Then:
#
# 1. Homebrew. On an Apple-managed Mac, install Apple's Homebrew first.
# 2. GitHub CLI, and a one-time browser login so git can read the private repos
# 3. Computer name (also the hostname, which picks the dotfiles-local branch)
# 4. ~/.dotfiles: clone or update, then script/bootstrap and script/install
# 5. ~/.dotfiles-local: Darwin/<name> if it exists, otherwise default, a new
#    Darwin/<name> branched from default, or another branch you pick; then
#    its script/bootstrap and script/install
#
# Re-running it updates both repos and deploys again.
#
# Environment (each one replaces its question; with no terminal, or with
# KICKSTART_YES=1, nothing is asked and the defaults are used):
#   KICKSTART_NAME       computer name and hostname (default: current hostname)
#   KICKSTART_BRANCH     dotfiles-local branch, or "new" to create Darwin/<name>
#                        from default (default: Darwin/<name> if it exists,
#                        otherwise default)
#   KICKSTART_GIT_NAME, KICKSTART_GIT_EMAIL
#                        git author for both repos
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

# ask VAR LABEL DEFAULT: prompt with a default; Enter keeps it
ask() {
  local answer
  read -r -p "  $(printf '%-14s' "$2") [$3]: " answer || answer=
  printf -v "$1" '%s' "${answer:-$3}"
}

# Computer names double as the LocalHostName, which allows letters, digits, hyphens
valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
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
    # Prints a one-time code; approve it in a browser on this Mac or any device
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
  git -C "$dir" config user.name "$git_name"
  git -C "$dir" config user.email "$git_email"
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

# choose_branch: sets branch and new_branch from KICKSTART_BRANCH, the remote's
# branches, and (in a terminal) a menu
choose_branch() {
  local heads
  heads="$(git ls-remote --heads "$local_url" | sed 's|.*refs/heads/||')" \
    || die "Can't list the branches of $local_url"
  new_branch=false

  if [[ -n "${KICKSTART_BRANCH:-}" ]]; then
    if [[ "$KICKSTART_BRANCH" == new ]]; then
      branch="$host_branch"; new_branch=true
    else
      branch="$KICKSTART_BRANCH"
    fi
  elif grep -qxF "$host_branch" <<< "$heads"; then
    branch="$host_branch"
  elif [[ "$interactive" == true ]]; then
    echo
    echo "  dotfiles-local branch for $name:"
    echo "    1) default            (minimal, shared)"
    echo "    2) new: $host_branch  (from default, pushed)"
    echo "    3) existing branch..."
    local choice
    ask choice "Choice" 1
    case "$choice" in
      1) branch=default ;;
      2) branch="$host_branch"; new_branch=true ;;
      3)
        local others=() b i=0 pick
        while IFS= read -r b; do
          [[ "$b" == main ]] || others+=("$b")
        done <<< "$heads"
        for b in "${others[@]}"; do i=$((i + 1)); printf '    %2d) %s\n' "$i" "$b"; done
        ask pick "Branch number" 1
        [[ "$pick" =~ ^[0-9]+$ && "$pick" -ge 1 && "$pick" -le ${#others[@]} ]] || die "No branch number $pick"
        branch="${others[$((pick - 1))]}"
        ;;
      *) die "Choose 1, 2 or 3" ;;
    esac
  else
    branch=default
  fi

  if [[ "$new_branch" == true ]] && grep -qxF "$branch" <<< "$heads"; then
    new_branch=false   # already there; just use it
  fi
  if [[ "$new_branch" == false ]] && ! grep -qxF "$branch" <<< "$heads"; then
    die "dotfiles-local has no branch $branch"
  fi
}

main() {
  set -euo pipefail

  [[ "$(uname -s)" == Darwin ]] || die "kickstart only supports macOS"

  interactive=false
  if [[ -t 0 && -z "${KICKSTART_YES:-}" ]]; then interactive=true; fi

  local current_name
  current_name="$(hostname -s)"
  name="${KICKSTART_NAME:-$current_name}"
  git_name="${KICKSTART_GIT_NAME:-$GIT_NAME}"
  git_email="${KICKSTART_GIT_EMAIL:-$GIT_EMAIL}"

  if [[ "$interactive" == true ]]; then
    info "kickstart"
    echo
    [[ -n "${KICKSTART_NAME:-}" ]] || ask name "Computer name" "$name"
    until valid_name "$name"; do
      echo "  Use letters, digits and hyphens (no spaces), up to 63 characters."
      ask name "Computer name" "$current_name"
    done
    [[ -n "${KICKSTART_GIT_NAME:-}" ]] || ask git_name "Git name" "$git_name"
    [[ -n "${KICKSTART_GIT_EMAIL:-}" ]] || ask git_email "Git email" "$git_email"
    echo
  fi
  valid_name "$name" || die "Invalid computer name: $name"
  host_branch="$(uname -s)/$name"

  dotfiles_url="${KICKSTART_DOTFILES_URL:-}"
  local_url="${KICKSTART_DOTFILES_LOCAL_URL:-}"

  setup_homebrew
  if [[ -z "$dotfiles_url" || -z "$local_url" ]]; then
    setup_github
    dotfiles_url="${dotfiles_url:-https://github.com/$GITHUB_USER/dotfiles.git}"
    local_url="${local_url:-https://github.com/$GITHUB_USER/dotfiles-local.git}"
  fi

  choose_branch

  if [[ "$interactive" == true ]]; then
    echo
    echo "  Ready to set up this Mac:"
    echo "    name    $name$([[ "$name" == "$current_name" ]] || echo "  (was $current_name)")"
    echo "    branch  $branch$([[ "$new_branch" == true ]] && echo "  (new, from default)")"
    echo "    git     $git_name <$git_email>"
    local go
    ask go "Continue? (Y/n)" Y
    [[ "$go" =~ ^[Yy] ]] || { echo "  Stopped. Nothing on this Mac was changed beyond Homebrew and gh."; exit 0; }
    echo
  fi

  if [[ "$name" != "$current_name" ]]; then
    info "Computer name"
    sudo scutil --set ComputerName "$name"
    sudo scutil --set LocalHostName "$name"
    sudo scutil --set HostName "$name"
    ok "$name"
  fi

  info "dotfiles"
  clone_or_update "$dotfiles_url" "$DOTFILES_DIR"
  fast_forward "$DOTFILES_DIR"
  deploy "$DOTFILES_DIR"

  info "dotfiles-local"
  clone_or_update "$local_url" "$DOTFILES_LOCAL_DIR"
  if [[ "$new_branch" == true ]]; then
    git -C "$DOTFILES_LOCAL_DIR" checkout --quiet -b "$branch" origin/default \
      || die "Could not create $branch in $DOTFILES_LOCAL_DIR (local changes?)"
    git -C "$DOTFILES_LOCAL_DIR" push --quiet -u origin "$branch"
    ok "created and pushed $branch"
  else
    git -C "$DOTFILES_LOCAL_DIR" checkout --quiet "$branch" \
      || die "Could not check out $branch in $DOTFILES_LOCAL_DIR (local changes?)"
    fast_forward "$DOTFILES_LOCAL_DIR"
    ok "branch $branch"
  fi
  deploy "$DOTFILES_LOCAL_DIR"

  info "Done"
  if [[ "$branch" == default ]]; then
    echo "  This Mac uses the default dotfiles-local branch. To customize it, run"
    echo "  kickstart again and choose a new branch, or:"
    echo "    cd ~/.dotfiles-local && git checkout -b $host_branch && git push -u origin $host_branch"
  fi
  echo "  Open a new terminal to load the shell configuration."
}

main "$@"
