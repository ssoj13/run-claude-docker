# Repository Guidelines

## Project Structure & Modules
- Core logic lives in `run-claude.sh`; keep it self‑contained (no extra Dockerfile or helper scripts).
- Documentation: `README.md`, `CHANGELOG.md`, `LICENSE`, and this `AGENTS.md` live in the repo root.
- Container configuration is embedded in `run-claude.sh` (see `generate_dockerfile_content()`).

## Build, Run, and Development
- Build image only: `./run-claude.sh --build`
- Rebuild and run for local testing: `./run-claude.sh --rebuild`
- Run Claude in the current workspace: `./run-claude.sh` or `./run-claude.sh -w /path/to/project`
- Export Dockerfile for inspection: `./run-claude.sh --export-dockerfile debug.dockerfile`

## Coding Style & Naming
- Shell: POSIX-ish Bash, 2‑space indentation, no tabs.
- Functions: `lower_snake_case` (e.g., `check_required_tools`, `format_docker_command`).
- Variables: `UPPER_SNAKE` for constants, `lower_snake_case` for locals.
- Prefer small, composable functions over large blocks; avoid sourcing other files to preserve the single‑file design.

## Testing Guidelines
- After changes, at minimum run:
  - `./run-claude.sh --build` to verify the image builds.
  - `./run-claude.sh --rebuild` and execute a simple command, e.g. `./run-claude.sh claude --help`.
- When editing Docker content, also test `--export-dockerfile` and inspect the output.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subject line, e.g. `add verbose docker logging` or `fix workspace hash generation`.
- Group related changes in a single commit; avoid mixing refactors with behavior changes.
- PRs should include: short summary, motivation, testing notes (commands run), and any security‑relevant changes (privileged flags, mounts).

## Agent-Specific Instructions
- Modify only files needed for the task; keep `run-claude.sh` focused and linear.
- Do not introduce external dependencies or new top‑level scripts unless strictly required.
- Preserve existing behavior and flags; when changing defaults, document them in `README.md` and update examples.
