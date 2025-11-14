# GEMINI.md

This document provides a comprehensive overview of the `run-claude-docker` project, designed to give context to an AI assistant.

## Project Overview

This project consists of a single, powerful shell script: `run-claude.sh`. Its primary purpose is to provide a secure, isolated, and pre-configured Docker environment for running the `claude` command-line tool.

The script is self-contained and includes an embedded, multi-stage Dockerfile. It automates the entire setup process, including:
- Building the Docker image (or pulling a pre-built one from Docker Hub).
- Managing a persistent Docker container to speed up subsequent runs.
- Intelligently mounting essential host files and directories (e.g., `~/.claude`, `~/.ssh`, `~/.gitconfig`, and the current project workspace).
- Forwarding necessary environment variables like API keys.
- Pre-configuring several MCP servers (Unsplash, Context7, Playwright) inside the container.

The container environment is based on Ubuntu and comes with a rich set of development tools, including Go, Node.js, Python, Zsh, and Neovim (LazyVim).

## Building and Running

The script is designed for ease of use. No manual building is required for the initial run.

### Prerequisites

- Docker must be installed and running.
- The `claude` CLI should be authenticated on the host machine (`claude auth`).

### Key Commands

- **Interactive Shell:** To start an interactive shell inside the managed container. All subsequent commands can be run from within this shell.
  ```bash
  ./run-claude.sh
  ```

- **Executing a `claude` Command:** To run a one-off `claude` command directly. The script handles starting the container, executing the command, and stopping it.
  ```bash
  ./run-claude.sh claude --dangerously-skip-permissions "analyze this codebase"
  ```

- **Building the Image Locally:** If the pre-built Docker Hub image fails or if you need a custom build for your architecture (e.g., Apple Silicon), you can build it locally.
  ```bash
  ./run-claude.sh --build
  ```

- **Forcing a Rebuild:** To discard the existing image and build a new one from the embedded Dockerfile. This is useful after modifying the script.
  ```bash
  ./run-claude.sh --rebuild
  ```

- **Specifying a Workspace:** To run the container in the context of a different project directory.
  ```bash
  ./run-claude.sh -w /path/to/your/project
  ```

## Development Conventions

- **Self-Contained Script:** The entire logic, including the Dockerfile, is contained within `run-claude.sh`. This is a core design principle.
- **Dockerfile Modifications:** To change the container environment, edit the `generate_dockerfile_content()` function inside the `run-claude.sh` script.
- **Testing Changes:** After modifying the script (especially the embedded Dockerfile), use `./run-claude.sh --rebuild` to create and test a new image and container.
- **Shell Scripting:** The script is written in `bash` and aims for POSIX compliance where possible, though it uses some bash-specific features. It includes robust argument parsing and error handling.
- **No Dependencies (besides Docker):** The script is designed to be a single file that can be dropped into any project, with Docker being the only external dependency.
