# Vendored: ink-studio

This folder is a copy of **@shapeshift-labs/ink-studio**, the tool every splat asset is authored with.

| | |
|---|---|
| Source | https://github.com/siliconjungle/shapeshift-labs-ink-studio (public) |
| Commit | `d58ddc92416769e1289307dd65d9be6acb07e565` (2026-11-18) |
| Version | 0.1.0 |
| Licence | MIT, see `LICENSE` (Shapeshift Labs) |
| Vendored | 2026-11-18, replacing the earlier pin `b86f00a` |

## Why it is copied here

This library depends on a pinned copy, not on the project. ink-studio is version 0.1 and moves fast: 175 commits in the two days between the two pins. Assets must rebuild on any machine, whatever happens upstream. Only `../build.js` and `../snap.js` call it, at build time; the `.bytes` files they write are a game's only interface to it.

## What is in the copy

Every file the commit tracks (409), from `git archive`, with upstream's line endings (LF). This file is the only addition. `dist/` (the bundle `load()` compiles on first use) and `studio/` (its command line's outputs) are generated and ignored.

## Local changes

None. Do not edit files in this folder: what we add goes in our own layer, beside it. If a change here ever becomes necessary, list it in this section with what, why and which files.

## Updating from upstream

Deliberate, never automatic.

1. In each game, run `build.js --check` and `snap.js --check`: both must pass before the swap.
2. Replace this folder's contents with the new commit's tracked files (`git archive`, with `core.autocrlf=false`), keep this file, and update the commit above.
3. Run both checks again in each game. No difference: the upgrade is free. Any difference they report is the review: look at the pictures and accept or reject the upgrade.

Measured on 2026-11-18 for this pin: all 63 assets of the game it was checked against rebuilt byte for byte identical to the ones built with `b86f00a`, and all its reference snapshots matched.
