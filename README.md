<p align="center">
  <img src="assets/nyxory-logo.png" alt="nyxory" width="340">
</p>

<h3 align="center">Distribution channel for the <code>nyx</code> CLI</h3>

<p align="center">
  <a href="https://github.com/nyxory/homebrew-tap/releases/latest"><img src="https://img.shields.io/github/v/release/nyxory/homebrew-tap?color=CCFF00&labelColor=000&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-CCFF00?labelColor=000" alt="Platforms">
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-CCFF00?labelColor=000" alt="Architectures">
  <a href="https://nyxory.com"><img src="https://img.shields.io/badge/nyxory-.com-CCFF00?labelColor=000" alt="nyxory.com"></a>
</p>

---

`nyx` is the command-line client for the [nyxory](https://nyxory.com)
deployment platform — drive a deploy end-to-end from your terminal, or
hand it to an LLM agent. This repo is the **public distribution
channel**: it hosts the release binaries, the Homebrew formula, and the
`curl`-pipe installer. The source lives in
[`nyxory/cli`](https://github.com/nyxory/cli).

## Install

### Homebrew (macOS + Linux)

```sh
brew install nyxory/tap/nyx
```

Keep it current with `brew upgrade nyxory/tap/nyx`.

### curl-pipe

```sh
curl -fsSL https://raw.githubusercontent.com/nyxory/homebrew-tap/main/install.sh | bash
```

Auto-detects your platform, verifies the download against the
goreleaser-published `checksums.txt`, and installs to `/usr/local/bin`
(when writable without `sudo`) or `~/.local/bin` otherwise.

| Want to… | Append |
|---|---|
| Pin a version | `bash -s -- --version v0.8.0` |
| Choose the install dir | `bash -s -- --dir ~/bin` |
| …or via env (handy for pipes) | `… \| NYX_INSTALL_DIR=~/bin bash` |
| Skip the banner animation | `… \| NYX_NO_ANIM=1 bash` |

### Manual

Grab the archive for your platform from the
[Releases tab](https://github.com/nyxory/homebrew-tap/releases),
extract, and drop `nyx` on your `$PATH`.

## Quickstart

`nyx` ships with two pre-seeded contexts — **`prod`** (active by
default) and **`dev`** — so signing in needs no URLs:

```sh
nyx login                # browser sign-in to prod (or: --context dev)
nyx claude install       # wire Claude Code / your AI agent to the nyxory MCP
nyx project add widget   # create a project
nyx app list             # see what's running
```

Deploys run through your **AI agent**: once the MCP is wired up, ask
Claude Code (or Cursor / Codex) to deploy your repo — it drives the
`nyx_*` tools for you. Every command also takes `--json` for scripting
and CI. Full docs in [`nyxory/cli`](https://github.com/nyxory/cli#readme).

## What lives where

| | Path | Updated by |
|---|---|---|
| Source code | [`nyxory/cli`](https://github.com/nyxory/cli) *(private)* | Engineering |
| Release tarballs | [Releases tab](https://github.com/nyxory/homebrew-tap/releases) | goreleaser, on `v*.*.*` tag |
| Brew formula | [`nyx.rb`](nyx.rb) | goreleaser, on `v*.*.*` tag |
| Installer script | [`install.sh`](install.sh) | mirrored from [`nyxory/cli`](https://github.com/nyxory/cli/blob/main/release/install.sh) on every change |

> [!NOTE]
> Everything in this repo is generated or mirrored — **don't edit it by
> hand.** `nyx.rb` is rewritten by goreleaser on every release, and
> `install.sh` is auto-mirrored from `nyxory/cli/release/install.sh`.
> Open your PR against [`nyxory/cli`](https://github.com/nyxory/cli)
> instead.
