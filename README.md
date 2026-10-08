# kickstart

One command to set up a Mac from my dotfiles:

```sh
/bin/bash -c "$(curl -fsSL https://kickstart.ccheng.us)"
```

On a new Mac: finish Setup Assistant with an admin account, open Terminal,
paste the command. It asks a few questions first, each with a default
(Enter keeps it), and shows a summary before changing anything:

```
  Computer name  [Chengs-MacBook-Pro]: ccheng-mbp-m6-home
  Git name       [Cheng Cheng]:
  Git email      [ccheng@ccheng.us]:

==> GitHub access ... logged in as cchengleo

  dotfiles-local branch for ccheng-mbp-m6-home:
    1) default            (minimal, shared)
    2) new: Darwin/ccheng-mbp-m6-home  (from default, pushed)
    3) existing branch...
  Choice [1]: 2
```

Then it installs Homebrew if needed (enter your Mac password once), logs in
to GitHub (approve the one-time code in the browser that opens, or on any
other device), sets the computer name and hostname, clones the private
`cchengleo/dotfiles` and `cchengleo/dotfiles-local` repos, and deploys both.
If `Darwin/<name>` already exists it is used without asking. Running it
again updates and redeploys.

On an Apple-managed Mac, install Apple's internal Homebrew first; kickstart
stops and says so rather than installing the public one.

Each variable replaces its question. With no terminal, or with
`KICKSTART_YES=1`, nothing is asked and the defaults are used.

| Variable | Effect |
|----------|--------|
| `KICKSTART_NAME` | computer name and hostname (default: current hostname) |
| `KICKSTART_BRANCH` | dotfiles-local branch, or `new` to create `Darwin/<name>` from `default` |
| `KICKSTART_GIT_NAME`, `KICKSTART_GIT_EMAIL` | git author for both repos |
| `DOTFILES_CONFLICT` | what bootstrap does with existing files: `backup` (default), `skip`, `overwrite` |
| `KICKSTART_DOTFILES_URL`, `KICKSTART_DOTFILES_LOCAL_URL` | clone these instead of GitHub and skip the login (for tests) |

```sh
KICKSTART_BRANCH=Darwin/ccheng-macserver /bin/bash -c "$(curl -fsSL https://kickstart.ccheng.us)"
```

This repo is public and must stay free of secrets: anything that can change
what `kickstart.ccheng.us` serves can run code on a new Mac. Keep 2FA on the
GitHub account and on the `ccheng.us` registrar/DNS account.

## Testing

`~/.dotfiles/test/tart/run.sh --kickstart install.sh --host <name>` runs this
script in a fresh macOS VM against local snapshots of both repos and checks
the result; add `--answers 'name\n\n\n2\nY\n'` to drive the questions.
`--e2e` runs the published one-liner against GitHub instead (see
`test/tart/README.md` in dotfiles).

## Hosting setup (one time)

`.github/workflows/pages.yml` publishes `install.sh` as the site's index on
every push to `main`. To serve it at `kickstart.ccheng.us`:

1. **Verify the domain** (prevents someone else from claiming
   `*.ccheng.us` on GitHub Pages): GitHub → your avatar → Settings → Pages →
   **Add a domain** → `ccheng.us`. GitHub shows a TXT record like
   `_github-pages-challenge-cchengleo.ccheng.us` with a value; add it in the
   `ccheng.us` DNS, then click **Verify**.
2. **DNS**: in the `ccheng.us` DNS, add

   | Type | Name | Value | TTL |
   |------|------|-------|-----|
   | `CNAME` | `kickstart` | `cchengleo.github.io` | default / auto |

   Some providers want the value with a trailing dot (`cchengleo.github.io.`).
   On Cloudflare, set the record to **DNS only** (grey cloud) so GitHub can
   issue the HTTPS certificate. Check it with
   `dig +short kickstart.ccheng.us CNAME` → `cchengleo.github.io.`
3. **Pages source**: this repo → Settings → Pages → Build and deployment →
   Source: **GitHub Actions**. Push to `main` (or run the workflow by hand
   from the Actions tab) to publish.
4. **Custom domain**: same page → Custom domain → `kickstart.ccheng.us` →
   Save. Wait for the DNS check to pass and the certificate to be issued
   (minutes, occasionally hours), then tick **Enforce HTTPS**.
5. **Check**: `curl -fsSL https://kickstart.ccheng.us | head -3` should print
   the start of `install.sh`.
