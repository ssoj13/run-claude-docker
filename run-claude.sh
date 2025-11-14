#!/bin/bash

# Claude Code Docker Runner Script
# Usage: ./run-claude.sh [options] [command]
#
# MIT License - Copyright (c) 2025 Jonas
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -e

# Check for required tools
check_required_tools() {
  local missing_tools=()
  local required_tools=(
    "docker"
    "jq"
    "sha256sum"
    "whoami"
    "awk"
    "sed"
    "cut"
    "wc"
    "grep"
    "git"
  )

  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      missing_tools+=("$tool")
    fi
  done

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    echo -e "${RED}Error: The following required tools are missing:${NC}" >&2
    for tool in "${missing_tools[@]}"; do
      echo -e "  - ${YELLOW}$tool${NC}" >&2
    done
    echo >&2
    echo -e "${YELLOW}Please install the missing tools and try again.${NC}" >&2
    exit 1
  fi
}

# Version and default values
VERSION="1.0.0"
USERNAME="$(whoami)"
IMAGE_NAME="claude-code-${USERNAME}:latest"
WORKSPACE_PATH="$(pwd)"

# Generate container name based on workspace path
# Take last two path components and create hash
WORKSPACE_TWO_PARTS=$(echo "$WORKSPACE_PATH" | awk -F'/' '{if(NF>=2) print $(NF-1)"/"$NF; else print $NF}')
WORKSPACE_SANITIZED=$(echo "$WORKSPACE_TWO_PARTS" | sed 's/[^a-zA-Z0-9_-]/-/g')
WORKSPACE_HASH=$(echo "$WORKSPACE_PATH" | sha256sum | cut -c1-12)
CONTAINER_NAME="claude-code-$WORKSPACE_SANITIZED-$WORKSPACE_HASH"
CLAUDE_CONFIG_PATH="$HOME/.claude"
INTERACTIVE=true
REMOVE_CONTAINER=false
PRIVILEGED=true
DANGEROUS_MODE=true
BUILD_ONLY=false
FORCE_REBUILD=false
FORCE_PULL=false
RECREATE_CONTAINER=true
VERBOSE=false
REMOVE_CONTAINERS=false
FORCE_REMOVE_ALL_CONTAINERS=false
EXPORT_DOCKERFILE=""
PUSH_TO_REPO=""
ENABLE_GPG=true
DRY_RUN=false
EXTRA_PACKAGES=()
PASSTHROUGH_ARGS=()
EXTRA_VOLUMES=()

# List of environment variables to forward to the container
FORWARDED_VARIABLES=(
  "ANTHROPIC_API_KEY"
  "OPENAI_API_KEY"
  "NUGET_API_KEY"
  "UNSPLASH_ACCESS_KEY"
  "ANTHROPIC_MODEL"
  "TERM"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BRIGHT_CYAN='\033[1;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Check for required tools before proceeding
check_required_tools

# Generate -e flags for forwarded environment variables
generate_forwarded_variables() {
  local env_flags=""
  local seen_vars=""

  # Process all forwarded variables (avoiding duplicates)
  for var in "${FORWARDED_VARIABLES[@]}"; do
    if [[ -n "${!var}" && "$seen_vars" != *"|$var|"* ]]; then
      env_flags="$env_flags -e $var=${!var}"
      seen_vars="$seen_vars|$var|"
    fi
  done

  echo "$env_flags"
}

# Format Docker command for pretty verbose output
format_docker_command() {
  local cmd="$1"

  # First normalize the command: remove existing backslashes and tabs, then add proper breaks
  local normalized_cmd=$(echo "$cmd" | tr -d '\\\n\t' | sed 's/  */ /g')

  # Add line breaks before flags AND before image name, then process each line
  # Use a more targeted approach to separate image:tag from any trailing arguments
  local all_lines=$(echo "$normalized_cmd" | sed -E '
		s/ (-[a-z]|--[a-z-]+)/ \\\n  \1/g
		s/ ([a-z0-9-]+:[a-z0-9.-]+)/ \\\n\1/g
	' | sed -E 's/^([a-z0-9-]+:[a-z0-9.-]+) (.+)$/\1\n\2/')

  local line_count=$(echo "$all_lines" | wc -l)
  local current_line=0

  echo "$all_lines" | while IFS= read -r line; do
    current_line=$((current_line + 1))
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Remove any trailing backslashes for cleaner output
    line=$(echo "$line" | sed 's/ \\$//')

    # Color the first line (docker run command)
    if [[ "$line" =~ ^docker\ run ]]; then
      printf "${WHITE}%s${NC}\n" "$line"
    # Color environment and volume flags specially
    elif [[ "$line" =~ ^[[:space:]]*(-[ev])[[:space:]]+(.+)$ ]]; then
      flag="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # Special handling for -v flags to colorize name:value parts
      if [[ "$flag" == "-v" && "$value" =~ ^([^:]+):(.+)$ ]]; then
        name="${BASH_REMATCH[1]}"
        dest="${BASH_REMATCH[2]}"
        printf "    ${YELLOW}%s${NC} ${MAGENTA}%s${NC}:${BRIGHT_CYAN}%s${NC}\n" "$flag" "$name" "$dest"
      # Special handling for -e flags to colorize name=value parts
      elif [[ "$flag" == "-e" && "$value" =~ ^([^=]+)=(.+)$ ]]; then
        name="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        printf "    ${YELLOW}%s${NC} ${MAGENTA}%s${NC}=${BRIGHT_CYAN}%s${NC}\n" "$flag" "$name" "$val"
      else
        printf "    ${YELLOW}%s${NC} ${BRIGHT_CYAN}%s${NC}\n" "$flag" "$value"
      fi
    # Color other flags with special handling for --label and --name
    elif [[ "$line" =~ ^[[:space:]]*(-[a-z]|--[a-z-]+) ]]; then
      # Special handling for --label flags to colorize name=value parts
      if [[ "$line" =~ ^([[:space:]]*--label[[:space:]]+)([^=]+)=(.+)$ ]]; then
        flag_part="${BASH_REMATCH[1]}"
        name="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]}"
        printf "${BLUE}%s${MAGENTA}%s${NC}=${BRIGHT_CYAN}%s${NC}\n" "$flag_part" "$name" "$value"
      # Special handling for --name flags to colorize the name value
      elif [[ "$line" =~ ^([[:space:]]*--name[[:space:]]+)(.+)$ ]]; then
        flag_part="${BASH_REMATCH[1]}"
        name_value="${BASH_REMATCH[2]}"
        printf "${BLUE}%s${BRIGHT_CYAN}%s${NC}\n" "$flag_part" "$name_value"
      else
        printf "${BLUE}%s${NC}\n" "$line"
      fi
    # Everything else (like image name and command arguments)
    else
      # Add proper indentation for image name and arguments
      # Don't add backslash to the very last line
      if [[ $current_line -eq $line_count ]]; then
        printf "  ${BRIGHT_CYAN}%s${NC}\n" "$line"
      else
        printf "  ${BRIGHT_CYAN}%s${NC} \\\\\n" "$line"
      fi
    fi
  done
}

# Generate shell completions
generate_completions() {
  local shell="$1"

  if [[ -z "$shell" ]]; then
    echo -e "${RED}Error: Shell type required. Use 'bash' or 'zsh'${NC}" >&2
    exit 1
  fi

  case "$shell" in
  bash)
    cat <<'EOF'
_run_claude_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    opts="-w --workspace -c --claude-config -n --name -i --image --rm --no-interactive --no-privileged --safe --no-gpg --gpg --build --rebuild --recreate --verbose --remove-containers --force-remove-all-containers --export-dockerfile --push-to --generate-completions --username --extra-package -E --forward-variable --aws -h --help"
    
    case "${prev}" in
        -w|--workspace)
            COMPREPLY=( $(compgen -d -- ${cur}) )
            return 0
            ;;
        -c|--claude-config)
            COMPREPLY=( $(compgen -d -- ${cur}) )
            return 0
            ;;
        -n|--name)
            COMPREPLY=( $(compgen -W "claude-code" -- ${cur}) )
            return 0
            ;;
        -i|--image)
            COMPREPLY=( $(compgen -W "claude-code:latest" -- ${cur}) )
            return 0
            ;;
        --export-dockerfile)
            COMPREPLY=( $(compgen -f -- ${cur}) )
            return 0
            ;;
        --push-to)
            COMPREPLY=( $(compgen -W "docker.io/username/repo:tag" -- ${cur}) )
            return 0
            ;;
        --generate-completions)
            COMPREPLY=( $(compgen -W "bash zsh" -- ${cur}) )
            return 0
            ;;
        --username)
            COMPREPLY=( $(compgen -W "$(whoami)" -- ${cur}) )
            return 0
            ;;
        --extra-package)
            COMPREPLY=( $(compgen -W "curl wget tmux htop nano emacs" -- ${cur}) )
            return 0
            ;;
        -E|--forward-variable)
            COMPREPLY=( $(compgen -W "AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY GITHUB_TOKEN" -- ${cur}) )
            return 0
            ;;
        *)
            ;;
    esac
    
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
}
complete -F _run_claude_completion run-claude.sh
EOF
    ;;
  zsh)
    cat <<'EOF'
_run_claude_zsh_completion() {
    local -a options
    options=(
        '-w[Set workspace path]:workspace:_files -/'
        '--workspace[Set workspace path]:workspace:_files -/'
        '-c[Set Claude config path]:config:_files -/'
        '--claude-config[Set Claude config path]:config:_files -/'
        '-n[Set container name]:name:'
        '--name[Set container name]:name:'
        '-i[Set image name]:image:'
        '--image[Set image name]:image:'
        '--rm[Remove container after exit]'
        '--no-interactive[Run in non-interactive mode]'
        '--no-privileged[Run without privileged mode]'
        '--safe[Disable dangerous permissions]'
        '--no-gpg[Disable GPG agent forwarding]'
        '--gpg[Enable GPG agent forwarding]'
        '--build[Build the Docker image and exit]'
        '--rebuild[Force rebuild the Docker image and continue]'
        '--recreate[Remove existing container and create new one]'
        '--verbose[Show detailed output including Docker commands]'
        '--remove-containers[Remove stopped Claude Code containers and exit]'
        '--force-remove-all-containers[Remove ALL Claude Code containers and exit]'
        '--export-dockerfile[Export the embedded Dockerfile]:file:_files'
        '--push-to[Tag and push image to repository]:repository:'
        '--generate-completions[Generate shell completions]:shell:(bash zsh)'
        '--username[Set container username]:username:($(whoami))'
        '--extra-package[Add extra Ubuntu package]:package:(curl wget tmux htop nano emacs)'
        '-E[Forward environment variable]:variable:(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY GITHUB_TOKEN)'
        '--forward-variable[Forward environment variable]:variable:(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY GITHUB_TOKEN)'
        '--aws[Enable AWS integration: forward AWS vars and mount ~/.aws]'
        '(-h --help)'{-h,--help}'[Show help]'
    )
    _arguments -s -S $options
}
compdef _run_claude_zsh_completion run-claude.sh
EOF
    ;;
  *)
    echo -e "${RED}Error: Unsupported shell '$shell'. Use 'bash' or 'zsh'${NC}" >&2
    exit 1
    ;;
  esac
}

usage() {
  echo "Usage: $(basename $0) [OPTIONS] [COMMAND]"
  echo ""
  echo "OPTIONS:"
  echo "  -w, --workspace PATH    Set workspace path (default: current directory)"
  echo "  -c, --claude-config PATH Set Claude config path (default: ~/.claude)"
  echo "  -n, --name NAME         Set container name"
  echo "  -i, --image NAME        Set image name (default: claude-code:latest)"
  echo "  --rm                    Remove container after exit (default: persistent)"
  echo "  --no-interactive        Run in non-interactive mode"
  echo "  --no-privileged         Run without privileged mode"
  echo "  --safe                  Disable dangerous permissions"
  echo "  --no-gpg                Disable GPG agent forwarding"
  echo "  --gpg                   Enable GPG agent forwarding (overrides RUN_CLAUDE_NO_GPG)"
  echo "  --build                 Build the Docker image and exit"
  echo "  --pull                  Pull latest image from registry"
  echo "  --rebuild               Force rebuild the Docker image and continue"
  echo "  --recreate              Remove existing container and create new one"
  echo "  --verbose               Show detailed output including Docker commands"
  echo "  --dry-run               Show what would be executed without actually running"
  echo "  --remove-containers     Remove stopped Claude Code containers and exit"
  echo "  --force-remove-all-containers"
  echo "                          Remove ALL Claude Code containers (including active ones) and exit"
  echo "  --export-dockerfile FILE"
  echo "                          Export the embedded Dockerfile to specified file and exit"
  echo "  --push-to REPO          Tag and push image to repository (e.g., docker.io/user/repo:tag)"
  echo "  --generate-completions SHELL"
  echo "                          Generate shell completions (bash|zsh) and exit"
  echo "  --username NAME         Set container username (default: current user)"
  echo "  --extra-package PACKAGE Add extra Ubuntu package to container (can be used multiple times)"
  echo "                          Only works with --build, --rebuild, or --export-dockerfile"
  echo "  -E, --forward-variable VAR"
  echo "                          Forward additional environment variable to container (can be used multiple times)"
  echo "                          Use -E !VAR to exclude a variable from the default forwarded list"
  echo "  --aws                   Enable AWS integration: forward common AWS environment variables"
  echo "                          and mount ~/.aws directory to container (readonly)"
  echo "  --                      Pass remaining arguments directly to docker run/exec"
  echo "  -h, --help              Show this help"
  echo ""
  echo "EXAMPLES:"
  echo "  # Interactive shell"
  echo "  $(basename $0)"
  echo ""
  echo "  # Run specific command"
  echo "  $(basename $0) claude --dangerously-skip-permissions 'help me with this project'"
  echo ""
  echo "  # Custom workspace"
  echo "  $(basename $0) -w /path/to/project"
  echo ""
  echo "  # One-shot command with cleanup"
  echo "  $(basename $0) --rm --no-interactive claude auth status"
  echo ""
  echo "  # Build image only"
  echo "  $(basename $0) --build"
  echo ""
  echo "  # Force rebuild image and run"
  echo "  $(basename $0) --rebuild"
  echo ""
  echo "  # Push to Docker Hub"
  echo "  $(basename $0) --push-to docker.io/username/claude-code:latest"
  echo ""
  echo "  # Add extra packages during build"
  echo "  $(basename $0) --extra-package tmux --extra-package curl --build"
  echo ""
  echo "  # Use environment variable for extra packages"
  echo "  RUN_CLAUDE_EXTRA_PACKAGES=\"tmux curl\" $(basename $0) --extra-package gpg --build"
  echo ""
  echo "  # Forward additional environment variables"
  echo "  $(basename $0) -E AWS_ACCESS_KEY_ID -E AWS_SECRET_ACCESS_KEY"
  echo ""
  echo "  # Exclude a default variable from being forwarded"
  echo "  $(basename $0) -E !TERM -E AWS_ACCESS_KEY_ID"
  echo ""
  echo "  # Use environment variable for extra variables"
  echo "  RUN_CLAUDE_EXTRA_VARIABLES=\"AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY\" $(basename $0)"
  echo ""
  echo "  # Pass Docker arguments directly"
  echo "  $(basename $0) -- --env MY_VAR=value --volume /host:/container"
  echo ""
  echo "  # Install shell completions"
  echo "  # For bash:"
  echo "  echo 'eval \"\$($(basename $0) --generate-completions bash)\"' >> ~/.bashrc"
  echo ""
  echo "  # For zsh:"
  echo "  echo 'eval \"\$($(basename $0) --generate-completions zsh)\"' >> ~/.zshrc"
  echo ""
  echo "ENVIRONMENT VARIABLES:"
  echo "  CLAUDE_CODE_IMAGE_NAME  Override the default Docker Hub image (default: icanhasjonas/claude-code)"
  echo "                          Note: :latest tag is automatically appended"
  echo ""
  echo "  RUN_CLAUDE_EXTRA_PACKAGES  Space-separated list of extra Ubuntu packages to install"
  echo "                             Combined with --extra-package options during build"
  echo ""
  echo "  RUN_CLAUDE_EXTRA_VARIABLES Space-separated list of extra environment variables to forward"
  echo "                             Combined with -E/--forward-variable options. Use !VAR to exclude variables"
  echo ""
  echo "  # Use custom image:"
  echo "  CLAUDE_CODE_IMAGE_NAME=myregistry/my-claude-code $(basename $0)"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -w | --workspace)
    WORKSPACE_PATH="$2"
    shift 2
    ;;
  -c | --claude-config)
    CLAUDE_CONFIG_PATH="$2"
    shift 2
    ;;
  -n | --name)
    CONTAINER_NAME="$2"
    shift 2
    ;;
  -i | --image)
    IMAGE_NAME="$2"
    shift 2
    ;;
  --rm)
    REMOVE_CONTAINER=true
    shift
    ;;
  --no-interactive)
    INTERACTIVE=false
    shift
    ;;
  --no-privileged)
    PRIVILEGED=false
    shift
    ;;
  --safe)
    DANGEROUS_MODE=false
    ENABLE_GPG=false
    shift
    ;;
  --no-gpg)
    ENABLE_GPG=false
    shift
    ;;
  --gpg)
    ENABLE_GPG=true
    shift
    ;;
  --build)
    BUILD_ONLY=true
    shift
    ;;
  --pull)
    FORCE_PULL=true
    shift
    ;;
  --rebuild)
    FORCE_REBUILD=true
    shift
    ;;
  --recreate)
    RECREATE_CONTAINER=true
    shift
    ;;
  --verbose)
    VERBOSE=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --remove-containers)
    REMOVE_CONTAINERS=true
    shift
    ;;
  --force-remove-all-containers)
    FORCE_REMOVE_ALL_CONTAINERS=true
    shift
    ;;
  --export-dockerfile)
    EXPORT_DOCKERFILE="$2"
    shift 2
    ;;
  --push-to)
    PUSH_TO_REPO="$2"
    shift 2
    ;;
  --generate-completions)
    generate_completions "$2"
    exit 0
    ;;
  --username)
    USERNAME="$2"
    shift 2
    ;;
  --extra-package)
    EXTRA_PACKAGES+=("$2")
    shift 2
    ;;
  -E | --forward-variable)
    var="$2"
    if [[ "$var" =~ ^!(.+)$ ]]; then
      # Remove variable from forwarded list
      var_to_remove="${BASH_REMATCH[1]}"
      new_array=()
      for existing_var in "${FORWARDED_VARIABLES[@]}"; do
        if [[ "$existing_var" != "$var_to_remove" ]]; then
          new_array+=("$existing_var")
        fi
      done
      FORWARDED_VARIABLES=("${new_array[@]}")
    else
      # Add variable to forwarded list
      FORWARDED_VARIABLES+=("$var")
    fi
    shift 2
    ;;
  --aws)
    # Add default AWS environment variables
    AWS_VARS=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN" "AWS_REGION" "AWS_DEFAULT_REGION" "AWS_PROFILE" "AWS_ROLE_ARN" "AWS_WEB_IDENTITY_TOKEN_FILE" "AWS_ROLE_SESSION_NAME")
    for aws_var in "${AWS_VARS[@]}"; do
      FORWARDED_VARIABLES+=("$aws_var")
    done
    # Mount ~/.aws directory if it exists
    if [[ -d "$HOME/.aws" ]]; then
      EXTRA_VOLUMES+=(-v "$HOME/.aws:/home/$USERNAME/.aws:ro")
    fi
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    # Everything after -- is passed to docker
    shift
    PASSTHROUGH_ARGS=("$@")
    break
    ;;
  --*)
    # Unknown long option
    echo -e "${RED}Error: Unknown option '$1'${NC}"
    echo ""
    usage
    exit 1
    ;;
  -*)
    # Unknown short option
    echo -e "${RED}Error: Unknown option '$1'${NC}"
    echo ""
    usage
    exit 1
    ;;
  *)
    # Remaining arguments are the command to run
    break
    ;;
  esac
done

# Handle GPG environment variable override
if [[ "$RUN_CLAUDE_NO_GPG" == "1" && "$ENABLE_GPG" == "true" ]]; then
  ENABLE_GPG=false
fi

# Handle extra packages from environment variable
if [[ -n "$RUN_CLAUDE_EXTRA_PACKAGES" ]]; then
  # Convert space-separated string to array and append to EXTRA_PACKAGES
  IFS=' ' read -ra ENV_PACKAGES <<<"$RUN_CLAUDE_EXTRA_PACKAGES"
  EXTRA_PACKAGES+=("${ENV_PACKAGES[@]}")
fi

# Handle extra variables from environment variable
if [[ -n "$RUN_CLAUDE_EXTRA_VARIABLES" ]]; then
  # Convert space-separated string to array and process each variable
  IFS=' ' read -ra ENV_VARIABLES <<<"$RUN_CLAUDE_EXTRA_VARIABLES"
  for var in "${ENV_VARIABLES[@]}"; do
    if [[ "$var" =~ ^!(.+)$ ]]; then
      # Remove variable from forwarded list
      var_to_remove="${BASH_REMATCH[1]}"
      new_array=()
      for existing_var in "${FORWARDED_VARIABLES[@]}"; do
        if [[ "$existing_var" != "$var_to_remove" ]]; then
          new_array+=("$existing_var")
        fi
      done
      FORWARDED_VARIABLES=("${new_array[@]}")
    else
      # Add variable to forwarded list
      FORWARDED_VARIABLES+=("$var")
    fi
  done
fi

# Validate conflicting options
if [[ "$FORCE_PULL" == "true" && "$BUILD_ONLY" == "true" ]]; then
  echo -e "${RED}Error: Cannot use --pull and --build together${NC}"
  echo -e "${YELLOW}Choose one: --pull (to pull latest image) or --build (to build locally)${NC}"
  exit 1
fi

# Validate that --extra-package is only used with appropriate commands
if [[ ${#EXTRA_PACKAGES[@]} -gt 0 ]]; then
  if [[ "$BUILD_ONLY" != "true" && "$FORCE_REBUILD" != "true" && -z "$EXPORT_DOCKERFILE" ]]; then
    echo -e "${RED}Error: --extra-package can only be used with --build, --rebuild, or --export-dockerfile${NC}"
    echo -e "${YELLOW}Extra packages are only applied during image building operations${NC}"
    exit 1
  fi
fi

# Validate paths
if [[ ! -d "$WORKSPACE_PATH" ]]; then
  echo -e "${RED}Error: Workspace path does not exist: $WORKSPACE_PATH${NC}"
  exit 1
fi

if [[ ! -d "$CLAUDE_CONFIG_PATH" ]]; then
  echo -e "${YELLOW}Warning: Claude config path does not exist: $CLAUDE_CONFIG_PATH${NC}"
  echo -e "${YELLOW}You may need to run 'claude auth' first${NC}"
fi

# Build docker run command
DOCKER_CMD="docker run"

if [[ "$REMOVE_CONTAINER" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD --rm"
fi

if [[ "$INTERACTIVE" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD -it"
fi

if [[ "$PRIVILEGED" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD --privileged"
fi

DOCKER_CMD="$DOCKER_CMD --name $CONTAINER_NAME"

# Use host network to allow access to localhost services
DOCKER_CMD="$DOCKER_CMD --network host"

# Add labels for container identification
DOCKER_CMD="$DOCKER_CMD --label run-claude.managed=true"
DOCKER_CMD="$DOCKER_CMD --label run-claude.workspace=$WORKSPACE_PATH"
DOCKER_CMD="$DOCKER_CMD --label run-claude.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DOCKER_CMD="$DOCKER_CMD --label run-claude.version=$VERSION"
DOCKER_CMD="$DOCKER_CMD --label run-claude.username=$USERNAME"

# Get basename of workspace for container mapping
WORKSPACE_BASENAME=$(basename "$WORKSPACE_PATH")

# Add environment variables
DOCKER_CMD="$DOCKER_CMD \
	-e NODE_OPTIONS=--max-old-space-size=8192 \
	-e WORKSPACE_PATH=/home/$USERNAME/$WORKSPACE_BASENAME \
	-e CLAUDE_CONFIG_PATH=/home/$USERNAME/.claude \
	-e CONTAINER_USER=$USERNAME"

# Forward dangerous mode flags
if [[ "$DANGEROUS_MODE" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD \
	-e CLAUDE_DANGEROUS_MODE=1 \
	-e ANTHROPIC_DANGEROUS_MODE=1"
fi

# Forward verbose mode to container
if [[ "$VERBOSE" == "true" ]]; then
  DOCKER_CMD="$DOCKER_CMD \
	-e RUN_CLAUDE_VERBOSE=1"
fi

# Forward environment variables from the FORWARDED_VARIABLES list
FORWARDED_ENV_FLAGS=$(generate_forwarded_variables)
if [[ -n "$FORWARDED_ENV_FLAGS" ]]; then
  DOCKER_CMD="$DOCKER_CMD$FORWARDED_ENV_FLAGS"
fi

# Add conditional bind-mount for host Claude config if it exists
if [[ -f "$HOME/.claude.json" ]]; then
  DOCKER_CMD="$DOCKER_CMD \
	-v $HOME/.claude.json:/home/$USERNAME/.claude.host.json:ro"
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${MAGENTA}Host Claude config detected and will be mounted for merging${NC}"
  fi
fi

# Add volume mounts
DOCKER_CMD="$DOCKER_CMD \
	-v $CLAUDE_CONFIG_PATH:/home/$USERNAME/.claude \
	-v $WORKSPACE_PATH:/home/$USERNAME/$WORKSPACE_BASENAME"

# Add optional read-only mounts if they exist
if [[ -d "$HOME/.ssh" ]]; then
  DOCKER_CMD="$DOCKER_CMD \
	-v $HOME/.ssh:/home/$USERNAME/.ssh:ro"
fi

if [[ -f "$HOME/.gitconfig" ]]; then
  DOCKER_CMD="$DOCKER_CMD \
	-v $HOME/.gitconfig:/home/$USERNAME/.gitconfig:ro"
fi

# Forward SSH agent if available
if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]]; then
  SSH_AGENT_PATH=$(readlink -f "$SSH_AUTH_SOCK")
  DOCKER_CMD="$DOCKER_CMD \
	-v $SSH_AGENT_PATH:/ssh-agent \
	-e SSH_AUTH_SOCK=/ssh-agent"
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${MAGENTA}SSH agent socket detected and will be forwarded to container${NC}"
  fi
fi

# Forward GPG directory and agent if available
if [[ "$ENABLE_GPG" == "true" && -d "$HOME/.gnupg" ]]; then
  # Mount GPG directory (read-write for agent communication)
  DOCKER_CMD="$DOCKER_CMD \
	-v $HOME/.gnupg:/home/$USERNAME/.gnupg"

  # Forward GPG agent extra socket if available
  GPG_EXTRA_SOCKET=$(gpgconf --list-dirs agent-extra-socket 2>/dev/null)
  if [[ -S "$GPG_EXTRA_SOCKET" ]]; then
    DOCKER_CMD="$DOCKER_CMD \
	-v $GPG_EXTRA_SOCKET:/gpg-agent-extra"
    if [[ "$VERBOSE" == "true" ]]; then
      echo -e "${MAGENTA}GPG agent socket detected and will be forwarded to container${NC}"
    fi
  fi

  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${MAGENTA}GPG directory detected and will be mounted to container${NC}"
  fi
fi

# Add extra volumes if any were specified
if [[ ${#EXTRA_VOLUMES[@]} -gt 0 ]]; then
  for volume in "${EXTRA_VOLUMES[@]}"; do
    DOCKER_CMD="$DOCKER_CMD $volume"
  done
fi

# Add image name
DOCKER_CMD="$DOCKER_CMD $IMAGE_NAME"

# Add passthrough arguments if provided (after image name)
if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
  for arg in "${PASSTHROUGH_ARGS[@]}"; do
    DOCKER_CMD="$DOCKER_CMD $arg"
  done
fi

# Add command if provided (only if no passthrough args, since passthrough includes the command)
if [[ $# -gt 0 && ${#PASSTHROUGH_ARGS[@]} -eq 0 ]]; then
  DOCKER_CMD="$DOCKER_CMD $*"
fi

# Print what we're about to run
if [[ "$VERBOSE" == "true" ]]; then
  echo -e "${MAGENTA}Running Claude Code container...${NC}"
  echo -e "${MAGENTA}Container name: ${BRIGHT_CYAN}$CONTAINER_NAME${NC}"
  echo -e "${MAGENTA}Workspace: ${BRIGHT_CYAN}$WORKSPACE_PATH${NC}"
  echo -e "${MAGENTA}Command:${NC}"
  format_docker_command "$DOCKER_CMD"
  echo ""
fi

# Function to build Docker image
build_image() {
  echo -e "${MAGENTA}Building Docker image ${BRIGHT_CYAN}$IMAGE_NAME${MAGENTA}...${NC}"

  # Create temporary directory for Dockerfile
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf $TEMP_DIR" EXIT

  # Generate Dockerfile using shared function
  generate_dockerfile_content >"$TEMP_DIR/Dockerfile"

  # Build the image
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${MAGENTA}Would execute: ${BRIGHT_CYAN}docker build --build-arg USERNAME=\"$USERNAME\" -t \"$IMAGE_NAME\" \"$TEMP_DIR\"${NC}"
    echo -e "${GREEN}Dry run complete - would have built Docker image.${NC}"
    return 0
  fi

  if docker build --build-arg USERNAME="$USERNAME" -t "$IMAGE_NAME" "$TEMP_DIR"; then
    echo -e "${MAGENTA}Successfully built ${BRIGHT_CYAN}$IMAGE_NAME${NC}"
  else
    echo -e "${RED}Failed to build Docker image${NC}"
    exit 1
  fi
}

# Function to pull and tag remote image
pull_remote_image() {
  local REMOTE_IMAGE="${CLAUDE_CODE_IMAGE_NAME:-icanhasjonas/claude-code}:latest"

  echo -e "${MAGENTA}Pulling remote image ${BRIGHT_CYAN}$REMOTE_IMAGE${MAGENTA}...${NC}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${MAGENTA}Would execute: ${BRIGHT_CYAN}docker pull \"$REMOTE_IMAGE\"${NC}"
    echo -e "${MAGENTA}Would execute: ${BRIGHT_CYAN}docker tag \"$REMOTE_IMAGE\" \"$IMAGE_NAME\"${NC}"
    echo -e "${GREEN}Dry run complete - would have pulled and tagged remote image.${NC}"
    return 0
  fi

  if docker pull "$REMOTE_IMAGE"; then
    echo -e "${MAGENTA}Successfully pulled ${BRIGHT_CYAN}$REMOTE_IMAGE${NC}"
    echo -e "${MAGENTA}Tagging as ${BRIGHT_CYAN}$IMAGE_NAME${MAGENTA}...${NC}"
    if docker tag "$REMOTE_IMAGE" "$IMAGE_NAME"; then
      echo -e "${MAGENTA}Successfully tagged as ${BRIGHT_CYAN}$IMAGE_NAME${NC}"
    else
      echo -e "${RED}Failed to tag remote image${NC}"
      echo -e "${YELLOW}Falling back to building from source...${NC}"
      build_image
    fi
  else
    echo -e "${YELLOW}Failed to pull remote image. Building from source...${NC}"
    build_image
  fi
}

# Function to check if image exists and build if necessary
build_image_if_missing() {
  if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Docker image $IMAGE_NAME not found.${NC}"
    echo -e "${YELLOW}Building image locally...${NC}"
    build_image
  fi
}

# Function to remove stopped Claude Code containers using labels
remove_stopped_containers() {
  echo -e "${GREEN}Searching for Claude Code containers...${NC}"

  # Find all containers with our label
  ALL_CONTAINERS=$(docker ps -aq --filter "label=run-claude.managed=true" 2>/dev/null || true)

  if [[ -z "$ALL_CONTAINERS" ]]; then
    echo -e "${YELLOW}No Claude Code containers found.${NC}"
    return 0
  fi

  # Find running containers with our label
  RUNNING_CONTAINERS=$(docker ps -q --filter "label=run-claude.managed=true" 2>/dev/null || true)

  # Find stopped containers (all - running)
  STOPPED_CONTAINERS=""
  for container in $ALL_CONTAINERS; do
    if ! echo "$RUNNING_CONTAINERS" | grep -q "$container"; then
      STOPPED_CONTAINERS="$STOPPED_CONTAINERS $container"
    fi
  done

  # Display all containers with status
  echo -e "${YELLOW}Found the following Claude Code containers:${NC}"
  docker ps -a --filter "label=run-claude.managed=true" --format "table {{.Names}}\t{{.Status}}\t{{.Label \"run-claude.workspace\"}}" 2>/dev/null || true
  echo ""

  # Handle running containers
  if [[ -n "$RUNNING_CONTAINERS" ]]; then
    echo -e "${YELLOW}Active containers (not removed):${NC}"
    for container in $RUNNING_CONTAINERS; do
      CONTAINER_NAME=$(docker inspect --format '{{.Name}}' "$container" | sed 's|^/||')
      echo -e "${YELLOW}  - $CONTAINER_NAME (running)${NC}"
      echo -e "    ${GREEN}To force remove:${NC}"
      echo -e "      \033[2mdocker stop \033[1m$CONTAINER_NAME\033[0m\033[2m && docker rm \033[1m$CONTAINER_NAME\033[0m"
    done
    echo ""
  fi

  # Remove stopped containers
  if [[ -n "$(echo $STOPPED_CONTAINERS | xargs)" ]]; then
    echo -e "${GREEN}Removing stopped containers...${NC}"
    docker rm $(echo $STOPPED_CONTAINERS | xargs) >/dev/null 2>&1 || true
    echo -e "${GREEN}Stopped Claude Code containers have been removed.${NC}"
  else
    echo -e "${YELLOW}No stopped containers to remove.${NC}"
  fi
}

# Function to force remove ALL Claude Code containers with warning
force_remove_all_containers() {
  echo -e "${RED}⚠️  WARNING: Force removing ALL Claude Code containers!${NC}"
  echo -e "${RED}This will STOP and DELETE all containers, including active ones.${NC}"
  echo -e "${RED}Any unsaved work in running containers will be LOST!${NC}"
  echo ""

  # Find all containers with our label
  ALL_CONTAINERS=$(docker ps -aq --filter "label=run-claude.managed=true" 2>/dev/null || true)

  if [[ -z "$ALL_CONTAINERS" ]]; then
    echo -e "${YELLOW}No Claude Code containers found.${NC}"
    return 0
  fi

  # Display all containers with status
  echo -e "${YELLOW}Found the following Claude Code containers:${NC}"
  docker ps -a --filter "label=run-claude.managed=true" --format "table {{.Names}}\t{{.Status}}\t{{.Label \"run-claude.workspace\"}}" 2>/dev/null || true
  echo ""

  # Ask for confirmation
  echo -e "${RED}Are you sure you want to force remove ALL containers? [y/N]:${NC} "
  read -r CONFIRM

  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    return 0
  fi

  echo ""
  echo -e "${GREEN}Force stopping all containers...${NC}"
  docker stop $ALL_CONTAINERS >/dev/null 2>&1 || true

  echo -e "${GREEN}Removing all containers...${NC}"
  docker rm $ALL_CONTAINERS >/dev/null 2>&1 || true

  echo -e "${GREEN}All Claude Code containers have been force removed.${NC}"
}

# Function to generate Dockerfile content
generate_dockerfile_content() {
  # Build the base package list
  local base_packages=(
    "build-essential"
    "ca-certificates"
    "curl"
    "wget"
    "git"
    "python3"
    "unzip"
    "sudo"
    "fzf"
    "zsh"
    "gh"
    "vim"
    "htop"
    "jq"
    "tree"
    "ripgrep"
    "fd-find"
    "gpg"
    "git-delta"
  )

  # Add extra packages to the list
  local all_packages=("${base_packages[@]}")
  if [[ ${#EXTRA_PACKAGES[@]} -gt 0 ]]; then
    all_packages+=("${EXTRA_PACKAGES[@]}")
  fi

  # Generate the package installation lines
  local package_lines=""
  for ((i = 0; i < ${#all_packages[@]}; i++)); do
    if [[ $i -eq $((${#all_packages[@]} - 1)) ]]; then
      # Last package, no backslash since we're ending the RUN instruction
      package_lines+=$'\t'"${all_packages[i]}"
    else
      # Not last package, add backslash and newline
      package_lines+=$'\t'"${all_packages[i]}"$' \\\n'
    fi
  done

  cat <<'DOCKERFILE_EOF'
# vim: set ft=dockerfile:

# ============================================================================
# Stage 1: Base tools and development environment
# ============================================================================
FROM ubuntu:25.04 AS base-tools

# Install system dependencies including zsh and tools
RUN apt-get update && apt-get install -y \
DOCKERFILE_EOF

  # Insert the dynamic package list
  echo -e "$package_lines"

  cat <<'DOCKERFILE_EOF'

# Clean up apt cache
RUN rm -rf /var/lib/apt/lists/*

# Install Go
RUN ARCH=$(dpkg --print-architecture) && \
	if [ "$ARCH" = "amd64" ]; then GOARCH="amd64"; else GOARCH="arm64"; fi && \
	wget -O go.tar.gz "https://go.dev/dl/go1.21.5.linux-${GOARCH}.tar.gz" \
	&& tar -C /usr/local -xzf go.tar.gz \
	&& rm go.tar.gz
ENV PATH=/usr/local/go/bin:$PATH
ENV CGO_ENABLED=0

# Install uv (fast Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH=/root/.cargo/bin:$PATH

# Install latest Neovim from GitHub releases
RUN ARCH=$(dpkg --print-architecture) && \
	if [ "$ARCH" = "amd64" ]; then NVIM_ARCH="x86_64"; else NVIM_ARCH="arm64"; fi && \
	NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/') && \
	wget -O nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz" && \
	tar -C /usr/local -xzf nvim.tar.gz && \
	ln -s /usr/local/nvim-linux-${NVIM_ARCH}/bin/nvim /usr/local/bin/nvim && \
	rm nvim.tar.gz

# Create user with UID=1000 to match typical host user
# First remove the default 'ubuntu' user if it exists
ARG USERNAME=claude-user
RUN (userdel -r ubuntu 2>/dev/null || true) && \
	useradd -m -s /bin/zsh -u 1000 ${USERNAME} \
	&& echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} \
	&& chmod 0440 /etc/sudoers.d/${USERNAME}

# Build and install Unsplash MCP server
WORKDIR /tmp
RUN git config --global url."https://github.com/".insteadOf git@github.com: \
	&& git clone https://github.com/douglarek/unsplash-mcp-server.git \
	&& cd unsplash-mcp-server \
	&& go build -o /usr/local/bin/unsplash-mcp-server ./cmd/server \
	&& git config --global --unset url."https://github.com/".insteadOf

# ============================================================================
# Stage 2: User environment setup (zsh, fnm, node)
# ============================================================================
FROM base-tools AS user-env

# Switch to user and setup zsh with oh-my-zsh
USER $USERNAME
WORKDIR /home/$USERNAME

# Set up oh-my-zsh and plugins
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
	&& git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
	&& git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Setup fnm for user
RUN curl -o- https://fnm.vercel.app/install | bash
ENV PATH="/home/$USERNAME/.local/share/fnm:$PATH"
SHELL ["/bin/bash", "-c"]
RUN eval "$(fnm env)" && fnm install 22 && fnm default 22 && fnm use 22

# Install uv for user
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/$USERNAME/.cargo/bin:$PATH"


# Install LazyVim
RUN git clone https://github.com/LazyVim/starter ~/.config/nvim \
	&& rm -rf ~/.config/nvim/.git

RUN nvim --headless "+Lazy! sync" +qa

# ============================================================================
# Stage 3: Claude and MCP servers
# ============================================================================
FROM user-env AS claude-mcp

# Install Claude CLI
RUN eval "$(fnm env)" && curl -fsSL https://claude.ai/install.sh | bash
ENV PATH=/home/$USERNAME/.local/bin:$PATH

# Install Playwright MCP via npm
RUN eval "$(fnm env)" && npm install -g @playwright/mcp@latest

# Setup MCP servers using claude mcp add
RUN eval "$(fnm env)" && claude mcp add unsplash \
	--scope user \
	/usr/local/bin/unsplash-mcp-server

RUN eval "$(fnm env)" && claude mcp add context7 \
	--scope user \
  --transport http \
	https://mcp.context7.com/mcp

RUN eval "$(fnm env)" && claude mcp add playwright \
	--scope user -- \
	npx @playwright/mcp@latest

RUN eval "$(fnm env)" && claude mcp add sequential-thinking \
	--scope user -- \
	npx -y @modelcontextprotocol/server-sequential-thinking

RUN eval "$(fnm env)" && claude mcp add filesystem \
	--scope user -- \
	npx -y @modelcontextprotocol/server-filesystem /home/${USERNAME}

RUN eval "$(fnm env)" && claude mcp add fetch \
	--scope user -- \
	npx -y @kazuph/mcp-fetch

RUN eval "$(fnm env)" && claude mcp add exa \
	--scope user -- \
	npx -y exa-mcp-server

RUN eval "$(fnm env)" && claude mcp add zen \
	--scope user -- \
	uvx --from git+https://github.com/BeehiveInnovations/zen-mcp-server.git zen-mcp-server

# ============================================================================
# Stage 4: Final runtime image
# ============================================================================
FROM claude-mcp AS final

# Create entrypoint script that handles workspace directory change (as root)
USER root
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/sh

# Merge Claude config from host file if available
if [ -f "$HOME/.claude.host.json" ]; then
  CONFIG_KEYS="oauthAccount hasSeenTasksHint userID hasCompletedOnboarding lastOnboardingVersion subscriptionNoticeCount hasAvailableSubscription s1mAccessCache"
  
  # Build jq expression for extraction
  JQ_EXPR=""
  for key in $CONFIG_KEYS; do
    if [ -n "$JQ_EXPR" ]; then JQ_EXPR="$JQ_EXPR, "; fi
    JQ_EXPR="$JQ_EXPR\"$key\": .$key"
  done
  
  # Extract config data and add bypass permissions
  HOST_CONFIG=$(jq -c "{$JQ_EXPR, \"bypassPermissionsModeAccepted\": true}" "$HOME/.claude.host.json" 2>/dev/null || echo "")
  
  if [ -n "$HOST_CONFIG" ] && [ "$HOST_CONFIG" != "null" ] && [ "$HOST_CONFIG" != "{}" ]; then
    if [ -f "$HOME/.claude.json" ]; then
      # Merge with existing container file
      jq ". * $HOST_CONFIG" "$HOME/.claude.json" > "$HOME/.claude.json.tmp" && mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
    else
      # Create new container file with host config
      echo "$HOST_CONFIG" | jq . > "$HOME/.claude.json"
    fi
    if [ "$RUN_CLAUDE_VERBOSE" = "1" ]; then
      echo "Claude config merged from host file"
    fi
  else
    if [ "$RUN_CLAUDE_VERBOSE" = "1" ]; then
      echo "No valid config found in host file"
    fi
  fi
else
  if [ "$RUN_CLAUDE_VERBOSE" = "1" ]; then
    echo "No host Claude config file mounted"
  fi
fi

# Link GPG agent socket if forwarded
if [ -S "/gpg-agent-extra" ]; then
  # Detect expected socket location dynamically
  EXPECTED_SOCKET=$(gpgconf --list-dirs agent-socket 2>/dev/null)
  
  if [ -n "$EXPECTED_SOCKET" ]; then
    # Create directory structure for expected socket location
    mkdir -p "$(dirname "$EXPECTED_SOCKET")"
    chmod 700 "$(dirname "$EXPECTED_SOCKET")"
    
    # Link forwarded socket to expected location
    ln -sf /gpg-agent-extra "$EXPECTED_SOCKET"
    if [ "$RUN_CLAUDE_VERBOSE" = "1" ]; then
      echo "GPG agent socket linked at $EXPECTED_SOCKET"
    fi
  else
    # Fallback to traditional ~/.gnupg location
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg
    ln -sf /gpg-agent-extra ~/.gnupg/S.gpg-agent
    if [ "$RUN_CLAUDE_VERBOSE" = "1" ]; then
      echo "GPG agent socket linked at ~/.gnupg/S.gpg-agent (fallback)"
    fi
  fi
fi

# Change to workspace directory if provided
if [ -n "$WORKSPACE_PATH" ] && [ -d "$WORKSPACE_PATH" ]; then
  cd "$WORKSPACE_PATH"
fi

exec "$@"
EOF
RUN chmod +x /entrypoint.sh

# Create claude-exec wrapper script for proper environment setup in docker exec
RUN cat > /usr/local/bin/claude-exec << 'EOF'
#!/bin/zsh

# Change to workspace directory if available, fallback to home
if [[ -n "$WORKSPACE_PATH" && -d "$WORKSPACE_PATH" ]]; then
	cd "$WORKSPACE_PATH"
else
	cd ~
fi

# Execute the requested command or start interactive zsh
if [[ $# -gt 0 ]]; then
	# Source zsh environment files for command execution
	[[ -f ~/.zshenv ]] && source ~/.zshenv
	[[ -f ~/.zshrc ]] && source ~/.zshrc
	exec "$@"
else
	# Let zsh handle its own sourcing for interactive shells
	exec /bin/zsh
fi
EOF
RUN chmod +x /usr/local/bin/claude-exec

# Set working directory for user sessions
USER $USERNAME
WORKDIR /home/$USERNAME

# Configure zsh with theme, plugins, and aliases
RUN cat > ~/.zshrc << 'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# Colorful prompt prefix
export PS1="%F{red}[%F{yellow}r%F{green}u%F{cyan}n%F{blue}-%F{magenta}c%F{red}l%F{yellow}a%F{green}u%F{cyan}d%F{blue}e%F{magenta}]%f $PS1"

# History configuration
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000

# Node version manager
eval "$(fnm env --use-on-cd --shell zsh)"

# Claude aliases - conditional based on dangerous mode
if [ "$CLAUDE_DANGEROUS_MODE" = "1" ] || [ "$ANTHROPIC_DANGEROUS_MODE" = "1" ]; then
	alias claude="claude --dangerously-skip-permissions"
fi
alias claude-safe="command claude"

# General aliases
alias ll="ls -la"
alias vim="nvim"
alias vi="nvim"

# Git SSH configuration
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
EOF

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/zsh"]
DOCKERFILE_EOF
}

# Function to export Dockerfile
export_dockerfile() {
  local OUTPUT_FILE="$1"

  if [[ -z "$OUTPUT_FILE" ]]; then
    echo -e "${RED}Error: No output file specified${NC}"
    exit 1
  fi

  echo -e "${MAGENTA}Exporting Dockerfile to: ${BRIGHT_CYAN}$OUTPUT_FILE${NC}"

  # Use the shared function to generate content
  generate_dockerfile_content >"$OUTPUT_FILE"

  echo -e "${MAGENTA}Dockerfile exported successfully!${NC}"
  echo -e "${YELLOW}To build: docker build --build-arg USERNAME=claude-user -t your-image-name .${NC}"
}

# Function to push image to repository
push_to_repository() {
  local REPO="$1"

  if [[ -z "$REPO" ]]; then
    echo -e "${RED}Error: No repository specified${NC}"
    exit 1
  fi

  echo -e "${MAGENTA}Pushing image to repository: ${BRIGHT_CYAN}$REPO${NC}"

  # Check if local image exists
  if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Local image $IMAGE_NAME not found. Getting it first...${NC}"
    pull_remote_image
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${MAGENTA}Would execute: ${BRIGHT_CYAN}docker tag \"$IMAGE_NAME\" \"$REPO\"${NC}"
    echo -e "${MAGENTA}Would execute: ${BRIGHT_CYAN}docker push \"$REPO\"${NC}"
    echo -e "${GREEN}Dry run complete - would have tagged and pushed image.${NC}"
    return 0
  fi

  # Tag the image for the target repository
  echo -e "${MAGENTA}Tagging image ${BRIGHT_CYAN}$IMAGE_NAME${MAGENTA} as ${BRIGHT_CYAN}$REPO${MAGENTA}...${NC}"
  if ! docker tag "$IMAGE_NAME" "$REPO"; then
    echo -e "${RED}Failed to tag image${NC}"
    exit 1
  fi

  # Push the image
  echo -e "${MAGENTA}Pushing ${BRIGHT_CYAN}$REPO${MAGENTA} to registry...${NC}"
  if docker push "$REPO"; then
    echo -e "${MAGENTA}Successfully pushed ${BRIGHT_CYAN}$REPO${NC}"
    echo -e "${MAGENTA}Image is now available at: ${BRIGHT_CYAN}$REPO${NC}"
  else
    echo -e "${RED}Failed to push image${NC}"
    echo -e "${YELLOW}Make sure you are logged in: docker login${NC}"
    exit 1
  fi
}

# Handle special commands
if [[ -n "$EXPORT_DOCKERFILE" ]]; then
  export_dockerfile "$EXPORT_DOCKERFILE"
  exit 0
fi

if [[ -n "$PUSH_TO_REPO" ]]; then
  push_to_repository "$PUSH_TO_REPO"
  exit 0
fi

if [[ "$REMOVE_CONTAINERS" == "true" ]]; then
  remove_stopped_containers
  exit 0
fi

if [[ "$FORCE_REMOVE_ALL_CONTAINERS" == "true" ]]; then
  force_remove_all_containers
  exit 0
fi

if [[ "$BUILD_ONLY" == "true" ]]; then
  build_image
  echo -e "${MAGENTA}Build complete. Exiting.${NC}"
  exit 0
fi

if [[ "$FORCE_PULL" == "true" ]]; then
  echo -e "${YELLOW}Force pull requested - pulling latest image...${NC}"
  pull_remote_image
elif [[ "$FORCE_REBUILD" == "true" ]]; then
  echo -e "${YELLOW}Force rebuild requested - cleaning up first...${NC}"

  # Remove containers first to avoid conflicts
  echo -e "${GREEN}Removing existing containers...${NC}"
  remove_stopped_containers

  # Remove the image
  if docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Removing existing image $IMAGE_NAME...${NC}"
    docker rmi "$IMAGE_NAME"
  fi
  build_image
else
  # Check if image exists and build if necessary
  build_image_if_missing
fi

# Function to handle existing container
handle_existing_container() {
  if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${MAGENTA}Container ${BRIGHT_CYAN}$CONTAINER_NAME${MAGENTA} already exists.${NC}"

    # Check version compatibility
    CONTAINER_VERSION=$(docker inspect --format '{{index .Config.Labels "run-claude.version"}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
    if [[ "$CONTAINER_VERSION" != "$VERSION" ]]; then
      echo -e "${YELLOW}⚠️  Version mismatch detected!${NC}"
      echo -e "${YELLOW}   Container version: ${BRIGHT_CYAN}$CONTAINER_VERSION${NC}"
      echo -e "${YELLOW}   Script version:    ${BRIGHT_CYAN}$VERSION${NC}"
      echo -e "${YELLOW}   This may cause authentication or compatibility issues.${NC}"
      echo ""
      echo -e "${YELLOW}To upgrade the container:${NC}"
      echo -e "${BRIGHT_CYAN}   $(basename $0) --remove-containers && $(basename $0) --build${NC}"
      echo ""
    fi

    # Check if container is running
    if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
      echo -e "${MAGENTA}Container ${BRIGHT_CYAN}$CONTAINER_NAME${MAGENTA} is already running. Executing command in existing container...${NC}"
      # Build docker exec command with passthrough args and environment variables
      EXEC_CMD="docker exec"
      if [[ "$INTERACTIVE" == "true" ]]; then
        EXEC_CMD="$EXEC_CMD -it"
      fi
      if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
        for arg in "${PASSTHROUGH_ARGS[@]}"; do
          EXEC_CMD="$EXEC_CMD $arg"
        done
      fi

      # Add forwarded environment variables
      FORWARDED_ENV_FLAGS=$(generate_forwarded_variables)
      if [[ -n "$FORWARDED_ENV_FLAGS" ]]; then
        EXEC_CMD="$EXEC_CMD$FORWARDED_ENV_FLAGS"
      fi

      EXEC_CMD="$EXEC_CMD $CONTAINER_NAME /usr/local/bin/claude-exec"

      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${MAGENTA}Would execute: ${BRIGHT_CYAN}$EXEC_CMD${NC}"
        if [[ $# -gt 0 ]]; then
          echo -e "${MAGENTA}With args: ${BRIGHT_CYAN}$*${NC}"
        fi
        echo -e "${GREEN}Dry run complete - would have executed docker exec.${NC}"
        exit 0
      fi

      if [[ $# -gt 0 ]]; then
        exec $EXEC_CMD "$@"
      else
        exec $EXEC_CMD
      fi
    else
      echo -e "${MAGENTA}Container ${BRIGHT_CYAN}$CONTAINER_NAME${MAGENTA} exists but is not running. Starting it...${NC}"

      if [[ "$DRY_RUN" == "true" ]]; then
        if [[ $# -gt 0 ]]; then
          echo -e "${MAGENTA}Would execute: ${BRIGHT_CYAN}docker start $CONTAINER_NAME${NC}"
          EXEC_CMD="docker exec"
          if [[ "$INTERACTIVE" == "true" ]]; then
            EXEC_CMD="$EXEC_CMD -it"
          fi
          if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
            for arg in "${PASSTHROUGH_ARGS[@]}"; do
              EXEC_CMD="$EXEC_CMD $arg"
            done
          fi

          # Add forwarded environment variables
          FORWARDED_ENV_FLAGS=$(generate_forwarded_variables)
          if [[ -n "$FORWARDED_ENV_FLAGS" ]]; then
            EXEC_CMD="$EXEC_CMD$FORWARDED_ENV_FLAGS"
          fi

          EXEC_CMD="$EXEC_CMD $CONTAINER_NAME /usr/local/bin/claude-exec"
          echo -e "${MAGENTA}Then execute: ${BRIGHT_CYAN}$EXEC_CMD${NC}"
          echo -e "${MAGENTA}With args: ${BRIGHT_CYAN}$*${NC}"
        else
          echo -e "${MAGENTA}Would execute: ${BRIGHT_CYAN}docker start -i $CONTAINER_NAME${NC}"
        fi
        echo -e "${GREEN}Dry run complete - would have started and executed commands.${NC}"
        exit 0
      fi

      if [[ $# -gt 0 ]]; then
        # Start container and then execute command in it
        # Use timeout + stdin redirect to prevent WSL2 Docker hang on mount errors
        # Disable errexit temporarily to capture exit code
        set +e
        START_OUTPUT=$(timeout 10 docker start "$CONTAINER_NAME" </dev/null 2>&1)
        START_EXIT_CODE=$?
        set -e

        # Check if start failed due to mount/bind-mount issues (WSL2 problem)
        if [[ $START_EXIT_CODE -ne 0 ]]; then
          if [[ "$START_OUTPUT" =~ mount|bind-mounts ]]; then
            echo -e "${YELLOW}Container failed to start due to stale mount paths (WSL2 issue).${NC}"
            echo -e "${YELLOW}Removing stale container and will create a fresh one...${NC}"
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
            # Return to let the script create a new container
            return 1
          else
            echo -e "${RED}Failed to start container:${NC}"
            echo "$START_OUTPUT"
            exit 1
          fi
        fi

        # Build docker exec command with passthrough args and environment variables
        EXEC_CMD="docker exec"
        if [[ "$INTERACTIVE" == "true" ]]; then
          EXEC_CMD="$EXEC_CMD -it"
        fi
        if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
          for arg in "${PASSTHROUGH_ARGS[@]}"; do
            EXEC_CMD="$EXEC_CMD $arg"
          done
        fi

        # Add forwarded environment variables
        FORWARDED_ENV_FLAGS=$(generate_forwarded_variables)
        if [[ -n "$FORWARDED_ENV_FLAGS" ]]; then
          EXEC_CMD="$EXEC_CMD$FORWARDED_ENV_FLAGS"
        fi

        EXEC_CMD="$EXEC_CMD $CONTAINER_NAME /usr/local/bin/claude-exec"
        exec $EXEC_CMD "$@"
      else
        # Start container interactively
        # Use timeout + stdin redirect to prevent WSL2 Docker hang on mount errors
        # Disable errexit temporarily to capture exit code
        set +e
        START_OUTPUT=$(timeout 10 docker start -i "$CONTAINER_NAME" </dev/null 2>&1)
        START_EXIT_CODE=$?
        set -e

        # Check if start failed due to mount/bind-mount issues (WSL2 problem)
        if [[ $START_EXIT_CODE -ne 0 ]]; then
          if [[ "$START_OUTPUT" =~ mount|bind-mounts ]]; then
            echo -e "${YELLOW}Container failed to start due to stale mount paths (WSL2 issue).${NC}"
            echo -e "${YELLOW}Removing stale container and will create a fresh one...${NC}"
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
            # Return to let the script create a new container
            return 1
          else
            # Other error - show it and exit
            echo -e "${RED}Failed to start container:${NC}"
            echo "$START_OUTPUT"
            exit $START_EXIT_CODE
          fi
        else
          # Success - container ran and exited normally
          exit 0
        fi
      fi
    fi
  fi
}

# Handle existing container removal if recreate is requested
if [[ "$RECREATE_CONTAINER" == "true" ]]; then
  if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${MAGENTA}Removing existing container ${BRIGHT_CYAN}$CONTAINER_NAME${MAGENTA}...${NC}"
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null
  fi
fi

# Handle existing container unless we want to remove it
if [[ "$REMOVE_CONTAINER" == "false" && "$RECREATE_CONTAINER" == "false" ]]; then
  handle_existing_container "$@"
elif [[ "$REMOVE_CONTAINER" == "true" ]]; then
  # Check if container exists when using --rm
  if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}Error: Container ${BRIGHT_CYAN}$CONTAINER_NAME${RED} already exists!${NC}"
    echo -e "${YELLOW}The --rm flag creates temporary containers, but a persistent container with this name already exists.${NC}"
    echo ""
    echo -e "${YELLOW}Choose one of these options:${NC}"
    echo -e "${BRIGHT_CYAN}  # Use the existing container (recommended):${NC}"
    echo -e "  $(basename $0) $*"
    echo ""
    echo -e "${BRIGHT_CYAN}  # Remove the existing container first:${NC}"
    echo -e "  $(basename $0) --recreate --rm $*"
    echo ""
    echo -e "${BRIGHT_CYAN}  # Remove all stopped containers:${NC}"
    echo -e "  $(basename $0) --remove-containers"
    echo ""
    exit 1
  fi
fi

# Execute the command (for new containers or when --rm is used)
if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${GREEN}Dry run complete - would have executed the above Docker command.${NC}"
  exit 0
fi

if ! exec $DOCKER_CMD; then
  echo -e "${RED}Failed to run Docker container.${NC}"
  echo -e "${YELLOW}If this failed due to architecture issues (e.g., Apple Silicon/arm64), try:${NC}"
  echo -e "${BRIGHT_CYAN}  $(basename $0) --build${NC}"
  echo -e "${YELLOW}This will build a local image compatible with your architecture.${NC}"
  exit 1
fi
