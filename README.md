# kickstart

One command to set up a Mac from my dotfiles:

```sh
/bin/bash -c "$(curl -fsSL https://kickstart.ccheng.us)"
```

It installs Homebrew if needed, logs in to GitHub once (browser or one-time
code), clones the private `cchengleo/dotfiles` and `cchengleo/dotfiles-local`
repos, and deploys both. dotfiles-local uses the `Darwin/<hostname -s>` branch
if it exists, otherwise `default`. Running it again updates and redeploys.

On an Apple-managed Mac, install Apple's internal Homebrew first; kickstart
stops and says so rather than installing the public one.

| Variable | Effect |
|----------|--------|
| `KICKSTART_BRANCH` | dotfiles-local branch to use instead of the automatic choice |
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
the result (see `test/tart/README.md` in dotfiles).

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
