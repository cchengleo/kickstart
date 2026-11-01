# kickstart

Sets up a Mac from my dotfiles in one command. Open Terminal and run:

```sh
/bin/bash -c "$(curl -fsSL https://kickstart.ccheng.us)"
```

It asks how to get access, installs Homebrew if needed (enter your Mac
password when asked), clones the dotfiles to `~/.dotfiles`, and hands over to
their own setup script. That asks a few more questions (computer name, whether
to install Karabiner-Elements, ...), each with a default that Enter keeps, and
shows a summary before changing anything. Running the command again updates
everything.

On a Mac managed by an organization, install the organization's Homebrew
first; kickstart stops and says so rather than installing the public one.

## My Macs

Choose **1) GitHub login**. It installs the GitHub CLI and shows a one-time
code; approve it at https://github.com/login/device, in a browser on this Mac
or on any other device.

## A friend's Mac

You need a key from me: a 1Password link. Then:

1. Run the command above and choose **2) a deploy key you were given**.
2. Open the link, copy the **private key**, and paste it at the
   `Deploy key [paste, then Enter]` prompt (it isn't shown).

kickstart saves it as `~/.ssh/cchengleo-dotfiles`, checks that it works, and
clones a read-only copy of my dotfiles that I keep for friends. Their setup
offers you a `~/.dotfiles-local` of your own, for your changes; its README
explains it. The same command, run again, updates your Mac to my latest
dotfiles.

## Options

| Variable | Effect |
|----------|--------|
| `KICKSTART_DEPLOY_KEY` | use this private key file instead of asking |
| `KICKSTART_GITHUB_USER` | owner of the dotfiles repos (default `cchengleo`) |
| `KICKSTART_DOTFILES_URL` | clone this instead of GitHub (for tests) |

The rest of the setup has its own options; see `script/kickstart` in the
dotfiles.

## About this repo

It is public and holds no secrets: `install.sh` only gets you read access to
the private dotfiles repo and runs the setup from there. Anything that can
change what `kickstart.ccheng.us` serves can run code on a new Mac, so 2FA
stays on for the GitHub account and the `ccheng.us` DNS account.

`.github/workflows/pages.yml` publishes `install.sh` to GitHub Pages on every
push to `main`, at `kickstart.ccheng.us` (Settings → Pages: source GitHub
Actions, custom domain `kickstart.ccheng.us`, Enforce HTTPS; DNS: a `CNAME`
record `kickstart` → `cchengleo.github.io`).

The dotfiles' Tart tests run this script in a macOS VM:
`test/tart/run.sh --kickstart <path to install.sh> [--friend]`, and `--e2e` for
the published version.
