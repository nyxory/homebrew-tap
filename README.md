# homebrew-nyx

Distribution channel for the [`nyx` CLI](https://github.com/nyxory/cli).

This repo is auto-managed by goreleaser running in
[`nyxory/cli`'s release workflow](https://github.com/nyxory/cli/blob/main/.github/workflows/release.yml).
Every `v*.*.*` tag pushed there fans out to:

- **GitHub Releases on this repo** — four tarballs (`darwin/{amd64,arm64}` + `linux/{amd64,arm64}`) plus a `checksums.txt`.
- **`Formula/nyx.rb`** — the Homebrew formula, rewritten to point at the new release.

## Install

### Homebrew (macOS + Linux)

```sh
brew install nyxory/nyx/nyx
```

`brew upgrade nyxory/nyx/nyx` keeps it current.

### curl-pipe

```sh
curl -fsSL https://raw.githubusercontent.com/nyxory/homebrew-nyx/main/install.sh | bash
```

Auto-detects platform, drops the binary into `/usr/local/bin/nyx`
(or `~/.local/bin/nyx` if the former isn't writable), and verifies
SHA-256 against the goreleaser-published `checksums.txt`. Pin a
version with `bash -s -- --version v0.5.0` or change the destination
with `bash -s -- --dir ~/bin`.

### Manual

Pull the archive matching your platform from the
[Releases tab](https://github.com/nyxory/homebrew-nyx/releases),
extract, drop `nyx` on your `$PATH`.

## What lives where

| | Path | Updated by |
|---|---|---|
| Source code | [`nyxory/cli`](https://github.com/nyxory/cli) (private) | Engineering |
| Release tarballs | [Releases tab](https://github.com/nyxory/homebrew-nyx/releases) | goreleaser, on tag push |
| Brew formula | [`Formula/nyx.rb`](Formula/nyx.rb) | goreleaser, on tag push |
| Installer script | [`install.sh`](install.sh) | mirrored from [`nyxory/cli/release/install.sh`](https://github.com/nyxory/cli/blob/main/release/install.sh) |

Don't edit `Formula/nyx.rb` by hand — it gets clobbered on the next
release. Open a PR against [`nyxory/cli`'s `.goreleaser.yaml`](https://github.com/nyxory/cli/blob/main/.goreleaser.yaml)
instead.

For `install.sh`, edit upstream and re-mirror; the local file is the
served copy but the canonical source is in `nyxory/cli`.
