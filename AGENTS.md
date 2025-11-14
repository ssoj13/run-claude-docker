# Repository Guidelines

## Project Structure & Module Organization
This repo is intentionally small: `run-claude.sh` in the root is both the entry point and the source of the embedded Dockerfile generated via `generate_dockerfile_content()`. Align helper functions with the feature they support (validation near `check_required_tools()`, container lifecycle near `manage_container()`), and update the usage banner whenever you add or rename a flag.

## Build, Test, and Development Commands
- `./run-claude.sh --build` — Builds the `claude-code` image only; run after Dockerfile edits.
- `./run-claude.sh --rebuild` — Forces a rebuild and starts the container to verify runtime behavior.
- `./run-claude.sh --export-dockerfile debug.dockerfile` — Dumps the generated Dockerfile for diffing or linting.
- `./run-claude.sh --help` — Ensure this output mirrors any new flags or defaults you introduce.

## Coding Style & Naming Conventions
Everything is Bash, so retain `#!/bin/bash` and `set -e`. Use two-space indentation, snake_case for functions (`prepare_workspace()`), and uppercase snake_case for environment names and CLI flags. Prefer double quotes, `local` variables inside functions, and short comments only when the intent is not obvious (e.g., why YOLO mode overrides `--safe`). When editing the embedded Dockerfile, keep instructions version-pinned and match the heredoc formatting produced by `generate_dockerfile_content()`.

## Testing Guidelines
With no dedicated CI, contributors must self-certify. Run `shellcheck run-claude.sh` plus `./run-claude.sh --build` whenever you touch Docker layers or dependencies, and follow with `./run-claude.sh --rebuild --safe "claude auth status"` to prove container launch, CLI wiring, and safe-mode execution. Document MCP verification steps (Unsplash, Context7, Playwright) in your PR so reviewers can repeat them.

## Commit & Pull Request Guidelines
History follows emoji-prefixed Conventional Commits (`✨ feat:`, `♻️ refactor:`); follow that casing and tense to keep automation happy. PRs should explain the motivation, reference any linked issue, and note the commands you ran (build, rebuild, export, shellcheck). Include screenshots or log excerpts whenever the change affects runtime output, permissions, or environment expectations, and call out any new secrets or env vars that adopters must set.

## Security & Configuration Tips
This script can run privileged containers, so default new behavior to `--safe` and require explicit confirmation for YOLO paths. Never commit credentials; instead, document required `UNSPLASH_*`, `CONTEXT7_*`, or Claude tokens in the README and remind reviewers to scrub their terminals before sharing logs. If you modify mounts, privilege flags, or environment pass-through, highlight the resulting host-safety implications in your PR summary.
