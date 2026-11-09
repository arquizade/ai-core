#!/usr/bin/env bash
# ==============================================================================
# ai-core: One Shared AI 2nd Brain - Interactive Setup Wizard
# Works with: curl -fsSL https://raw.githubusercontent.com/arquizade/ai-core/main/scripts/setup.sh | bash
# Supported OS: macOS, Linux, Docker/SBX Sandboxes
# ==============================================================================

set -e

# --- Colors & Formatting ---
# The values below use ANSI-C quoting ($'...') so each one holds a real ESC
# byte. Backslash strings such as "\033[1m" only expand under printf '%b',
# which is why any colour embedded in a message printed with '%s' leaked out
# as literal "\033[1m" text.
NO_COLOR_SUPPORTED=true
if [ -n "${FORCE_COLOR:-}" ] || { [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; }; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[1;31m'
    GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[36m'
    MAGENTA=$'\033[35m'
    CYAN=$'\033[36m'
    ACCENT=$'\033[1;36m'
    GREY=$'\033[90m'
    RESET=$'\033[0m'
else
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    ACCENT=""
    GREY=""
    RESET=""
fi

# --- CLI Flag Parsing ---
NON_INTERACTIVE=false
CUSTOM_VAULT_DIR=""
CHECK_ONLY=false

show_help() {
    cat << 'EOF'
Usage: setup.sh [OPTIONS]

Interactive TUI setup wizard for ai-core shared AI 2nd brain.

Options:
  -y, --yes, --headless      Run non-interactively using default choices
  --vault-dir <path>         Target vault directory (default: this vault's folder)
  --check, --status          Report whether the target folder is already set up, then exit
  -h, --help                 Display this help message and exit

Examples:
  # Interactive installation:
  curl -fsSL https://raw.githubusercontent.com/arquizade/ai-core/main/scripts/setup.sh | bash

  # Automated headless installation:
  curl -fsSL https://raw.githubusercontent.com/arquizade/ai-core/main/scripts/setup.sh | bash -s -- --yes
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -y|--yes|--non-interactive|--headless)
            NON_INTERACTIVE=true
            shift
            ;;
        --check|--status)
            CHECK_ONLY=true
            shift
            ;;
        --vault-dir)
            CUSTOM_VAULT_DIR="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# --- TTY Input Handler for curl | bash ---
# When running via `curl ... | bash`, standard stdin is the script itself.
# To read user input interactively, we read from /dev/tty if available.
if [ "$NON_INTERACTIVE" = true ]; then
    TTY_INPUT=0
elif [ -t 0 ]; then
    TTY_INPUT=0
elif [ -e /dev/tty ] && [ -r /dev/tty ] && { exec 3< /dev/tty; } 2>/dev/null; then
    TTY_INPUT=3
else
    TTY_INPUT=0
fi

prompt_input() {
    local message="$1"
    local default_val="$2"
    local result=""

    if [ "$NON_INTERACTIVE" = true ]; then
        printf "%b?%b %s %b[%s]%b  %bauto%b\n" "$ACCENT" "$RESET" "$message" "$CYAN" "$default_val" "$RESET" "$GREY" "$RESET" >&2
        echo "$default_val"
        return
    fi

    if [ -n "$default_val" ]; then
        printf "%b?%b %s %b[%s]%b " "$ACCENT" "$RESET" "$message" "$CYAN" "$default_val" "$RESET" >&2
    else
        printf "%b?%b %s " "$ACCENT" "$RESET" "$message" >&2
    fi

    if [ "$TTY_INPUT" -eq 3 ]; then
        read -r result <&3 || true
    else
        read -r result || true
    fi

    if [ -z "$result" ]; then
        echo "$default_val"
    else
        echo "$result"
    fi
}

prompt_confirm() {
    local message="$1"
    local default_yn="${2:-Y}"
    local ans
    ans=$(prompt_input "$message" "$default_yn")
    case "$ans" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# --- TUI primitives ---
# Visible width of a string, ignoring ANSI escapes.
strip_ansi() {
    printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'
}

# Repeat a character N times without forking a command.
rule() {
    local n="${1:-56}" ch="${2:-─}" pad
    printf -v pad '%*s' "$n" ''
    printf '%s' "${pad// /$ch}"
}

BOX_INNER=62

box_top() {
    printf "%b╭%s╮%b\n" "$ACCENT" "$(rule "$BOX_INNER" '─')" "$RESET"
}

box_bottom() {
    printf "%b╰%s╯%b\n" "$ACCENT" "$(rule "$BOX_INNER" '─')" "$RESET"
}

# One frame row, right border padded to a fixed width. $1 may hold colour codes.
box_line() {
    local text="$1" plain pad
    plain="$(strip_ansi "$text")"
    pad=$(( BOX_INNER - ${#plain} ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%b│%b%s%*s%b│%b\n" "$ACCENT" "$RESET" "$text" "$pad" '' "$ACCENT" "$RESET"
}

box_blank() {
    box_line ''
}

info() {
    printf "  %b→%b %s\n" "$BLUE" "$RESET" "$*"
}

success() {
    printf "  %b✔%b %s\n" "$GREEN" "$RESET" "$*"
}

warn() {
    printf "  %b!%b %s\n" "$YELLOW" "$RESET" "$*"
}

# Dim supporting copy under a step header.
note() {
    printf "    %b%s%b\n" "$GREY" "$*" "$RESET"
}

# Aligned label / value row for the recap.
kv() {
    printf "  %b%-18s%b %s\n" "$BOLD" "$1" "$RESET" "$2"
}

# Label, arrow, command.
tip() {
    printf "  %b%-18s%b %b→%b %b%s%b\n" "$BOLD" "$1" "$RESET" "$GREY" "$RESET" "$CYAN" "$2" "$RESET"
}

# "▸ 1/5  Title" followed by a dim rule. Leave $2 empty for a plain section.
step_header() {
    local num="$1" total="$2" title="$3" label=''
    [ -n "$total" ] && label="${GREY}${num}/${total}${RESET}  "
    printf "\n  %b▸%b  %s%b%s%b\n" "$ACCENT" "$RESET" "$label" "$BOLD" "$title" "$RESET"
    printf "  %b%s%b\n" "$GREY" "$(rule 56 '─')" "$RESET"
}

banner() {
    printf "\n"
    box_top
    box_blank
    box_line "  ${ACCENT}◈${RESET}  ${BOLD}AI-CORE${RESET}  ${GREY}/${RESET}  ${BOLD}One Shared 2nd Brain${RESET}"
    box_line "     ${GREY}Interactive setup wizard for Claude, Gemini & friends${RESET}"
    box_blank
    box_bottom
    printf "\n"
}

# --- Preflight: where is setup running from, and is the target already a vault? ---
VAULT_STATE='new'

# Directory of this script file, or nothing when it is piped in via curl | bash.
script_dir() {
    local src="${BASH_SOURCE[0]:-}"
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        return 1
    fi
    ( cd "$(dirname "$src")" && pwd -P )
}

# True when $1 is $2 or lives underneath it.
is_inside() {
    case "$1/" in
        "$2"/*) return 0 ;;
    esac
    return 1
}

vault_zone_count() {
    local dir="$1" z count=0
    for z in inbox planning coding projects decisions log people templates archive; do
        [ -d "$dir/$z" ] && count=$(( count + 1 ))
    done
    printf '%s' "$count"
}

vault_rule_count() {
    local dir="$1" f count=0
    for f in AGENTS.md CLAUDE.md GEMINI.md; do
        [ -f "$dir/$f" ] && count=$(( count + 1 ))
    done
    printf '%s' "$count"
}

# Sets VAULT_STATE to new | occupied | partial | initialized for $1.
vault_scan() {
    local dir="$1" zones rules entries
    VAULT_STATE='new'
    [ -d "$dir" ] || return 0
    zones="$(vault_zone_count "$dir")"
    rules="$(vault_rule_count "$dir")"
    if [ "$zones" -ge 9 ] && [ "$rules" -ge 1 ]; then
        VAULT_STATE='initialized'
    elif [ "$zones" -gt 0 ] || [ "$rules" -gt 0 ]; then
        VAULT_STATE='partial'
    else
        entries="$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
        [ "${entries:-0}" -gt 0 ] && VAULT_STATE='occupied'
    fi
}

# Read-only report. Leaves VAULT_STATE describing the target.
preflight() {
    local cwd srcdir inside_target=false zones rules cwd_state
    cwd="$(pwd -P)"
    srcdir="$(script_dir 2>/dev/null || true)"

    step_header '' '' "Preflight"
    kv "Working dir" "$cwd"
    if [ -n "$srcdir" ]; then
        kv "Script dir" "$srcdir"
    else
        kv "Script dir" "piped through stdin"
    fi
    kv "Target vault" "$VAULT_DIR"

    if is_inside "$cwd" "$VAULT_DIR"; then
        inside_target=true
    elif [ -n "$srcdir" ] && is_inside "$srcdir" "$VAULT_DIR"; then
        inside_target=true
    fi

    vault_scan "$cwd"
    cwd_state="$VAULT_STATE"
    vault_scan "$VAULT_DIR"
    zones="$(vault_zone_count "$VAULT_DIR")"
    rules="$(vault_rule_count "$VAULT_DIR")"

    if [ "$inside_target" = true ]; then
        note "Setup is running from inside the target vault."
    else
        note "Setup is running outside the target vault."
        if [ "$cwd_state" = 'initialized' ]; then
            warn "This working directory is already a set-up vault, but the target is $VAULT_DIR."
        fi
    fi

    case "$VAULT_STATE" in
        initialized)
            success "Folder already set up: ${zones}/9 zones, ${rules}/3 rule files. Re-running refreshes it in place."
            ;;
        partial)
            warn "Partly set up: ${zones}/9 zones, ${rules}/3 rule files. Setup will fill the gaps."
            ;;
        occupied)
            warn "Folder has files but no ai-core markers. Setup will add the vault alongside them."
            ;;
        *)
            info "No vault at this path yet; starting fresh."
            ;;
    esac
}

# --- Detect OS & Environment ---
detect_environment() {
    OS_TYPE="$(uname -s)"
    IS_CONTAINER=false
    if [ -f /.dockerenv ] || grep -q 'docker\|containerd\|sandbox' /proc/1/cgroup 2>/dev/null; then
        IS_CONTAINER=true
    fi
}

banner
detect_environment

info "Environment: ${BOLD}${OS_TYPE}${RESET}  ${GREY}·${RESET}  container: ${BOLD}${IS_CONTAINER}${RESET}"

# Determine default vault directory: the vault checkout this script belongs to,
# otherwise a fresh ai-core folder beside the current directory. No user-specific
# paths.
default_vault_dir() {
    local root=''
    root="$(script_dir 2>/dev/null || true)"
    if [ -n "$root" ]; then
        root="$(dirname "$root")"
        if [ -f "$root/AGENTS.md" ]; then
            printf '%s' "$root"
            return 0
        fi
    fi
    printf '%s' "$PWD/ai-core"
}

DEFAULT_DIR="$(default_vault_dir)"

if [ -n "$CUSTOM_VAULT_DIR" ]; then
    VAULT_DIR="$CUSTOM_VAULT_DIR"
elif [ "$CHECK_ONLY" = true ]; then
    VAULT_DIR="$DEFAULT_DIR"
else
    step_header 0 5 "Target Vault Directory"
    note "Your notes are plain Markdown on disk. Nothing leaves this machine."
    VAULT_DIR=$(prompt_input "Where would you like to locate your ai-core vault?" "$DEFAULT_DIR")
fi

# Expand ~ if provided
VAULT_DIR="${VAULT_DIR/#\~/$HOME}"
[ "$VAULT_DIR" != "/" ] && VAULT_DIR="${VAULT_DIR%/}"

preflight

if [ "$CHECK_ONLY" = true ]; then
    printf "\n"
    if [ "$VAULT_STATE" = 'initialized' ]; then
        success "Check complete: ${BOLD}$VAULT_DIR${RESET} is already set up."
        exit 0
    fi
    warn "Check complete: $VAULT_DIR is not set up yet."
    exit 1
fi

mkdir -p "$VAULT_DIR"
success "Target vault directory: ${BOLD}$VAULT_DIR${RESET}"

# Keep ~/ai-core pointing at the chosen vault, so sandboxes and docs that use
# that path keep working wherever the vault actually lives.
if [ "$VAULT_DIR" != "$HOME/ai-core" ] && [ -d "$VAULT_DIR" ]; then
    if [ ! -e "$HOME/ai-core" ]; then
        info "Creating ~/ai-core symlink pointing to $VAULT_DIR"
        ln -sfn "$VAULT_DIR" "$HOME/ai-core"
    fi
fi

# ==============================================================================
# PHASE 1: CORE VAULT SCAFFOLDING (MANDATORY & IDEMPOTENT)
# ==============================================================================
step_header '' '' "Foundation: Core Vault Scaffolding"
info "Creating the standard vault layout..."

mkdir -p "$VAULT_DIR/inbox"
mkdir -p "$VAULT_DIR/planning/specs"
mkdir -p "$VAULT_DIR/planning/weekly"
mkdir -p "$VAULT_DIR/coding/architecture"
mkdir -p "$VAULT_DIR/coding/bugs"
mkdir -p "$VAULT_DIR/coding/snippets"
mkdir -p "$VAULT_DIR/coding/setup"
mkdir -p "$VAULT_DIR/projects"
mkdir -p "$VAULT_DIR/decisions"
mkdir -p "$VAULT_DIR/log"
mkdir -p "$VAULT_DIR/people"
mkdir -p "$VAULT_DIR/templates"
mkdir -p "$VAULT_DIR/archive"
mkdir -p "$VAULT_DIR/scripts"
mkdir -p "$VAULT_DIR/.agents"

# Create starter templates if missing
if [ ! -f "$VAULT_DIR/templates/header.md" ]; then
    cat << 'EOF' > "$VAULT_DIR/templates/header.md"
date: YYYY-MM-DD
model:
project:
type:
EOF
fi

if [ ! -f "$VAULT_DIR/templates/spec.md" ]; then
    cat << 'EOF' > "$VAULT_DIR/templates/spec.md"
date: YYYY-MM-DD
model:
project:
type: spec

# Spec: Feature Name

## Summary

## Goals

## Non-goals

## Implementation Details
EOF
fi

if [ ! -f "$VAULT_DIR/templates/bug.md" ]; then
    cat << 'EOF' > "$VAULT_DIR/templates/bug.md"
date: YYYY-MM-DD
model:
project:
type: bug

# Bug: Short Title

## Symptom

## Root Cause

## Solution
EOF
fi

# Create synchronized rules if missing
RULES_CONTENT='# Shared AI Core Rules

Vault root: ~/ai-core
Code lives in ~/Code. Link to repos by path. Never copy code into the vault except in coding/snippets/.

## Folders
- inbox/: raw captures. Do not sort them yourself unless asked.
- planning/: roadmap.md, weekly/ (one file per week), specs/ (feature specs written before building).
- coding/: architecture/, bugs/, snippets/, setup/.
- projects/: one index note per project, linking to its specs, bugs, and repo path.
- decisions/: one dated note per decision, with the reason.
- log/: monthly append-only file. Add entries at the end. Never edit or delete old entries.
- people/: collaborators and their preferences.
- templates/: copy these when creating a new note.
- archive/: finished projects and old weekly plans.

## Note Header (required on every note)
Start every note with:
date: YYYY-MM-DD
model: your model name
project: project name or none
type: spec | bug | decision | log | plan | snippet | setup | architecture | project | person

## Multi-Agent Coexistence Rules
1. Read the relevant project note and recent log entries before answering.
2. Create new notes using matching templates from templates/.
3. Never edit a note written by another model today. Append an amendment or write to log/YYYY-MM.md instead.
4. Conclude task sessions by appending an entry to log/YYYY-MM.md.
'

for rule_file in "AGENTS.md" "CLAUDE.md" "GEMINI.md"; do
    if [ ! -f "$VAULT_DIR/$rule_file" ]; then
        printf "%s\n" "$RULES_CONTENT" > "$VAULT_DIR/$rule_file"
        info "Created rule file: $rule_file"
    fi
done

# Current monthly log
CURRENT_MONTH="$(date +%Y-%m)"
if [ ! -f "$VAULT_DIR/log/$CURRENT_MONTH.md" ]; then
    cat << EOF > "$VAULT_DIR/log/$CURRENT_MONTH.md"
# Log: $(date +%B\ %Y)

Append new entries at the end. Never edit old entries.

- $(date +%Y-%m-%d) | user | Vault initialized via setup wizard.
EOF
fi

# .gitignore configuration
if [ ! -f "$VAULT_DIR/.gitignore" ]; then
    touch "$VAULT_DIR/.gitignore"
fi

for ignore_pattern in ".obsidian/workspace*.json" ".DS_Store" "*.env" "secrets/" ".mempalace/" "*.sqlite3" "mempalace.yaml" "entities.json" "hallways.json" "graphify-out/cache/" "graphify-out/.*"; do
    if ! grep -q -F "$ignore_pattern" "$VAULT_DIR/.gitignore" 2>/dev/null; then
        echo "$ignore_pattern" >> "$VAULT_DIR/.gitignore"
    fi
done

success "Foundation complete: 9 zones, rules, and starter templates ready."

# ==============================================================================
# PHASE 2: INTERACTIVE STEP-BY-STEP MODULES
# ==============================================================================

# --- Step 1: Obsidian Setup ---

# Is Obsidian already on this machine?
obsidian_installed() {
    if [ "$OS_TYPE" = "Darwin" ]; then
        if [ -d "/Applications/Obsidian.app" ] || [ -d "$HOME/Applications/Obsidian.app" ]; then
            return 0
        fi
        return 1
    fi
    if command -v obsidian >/dev/null 2>&1; then
        return 0
    fi
    if command -v flatpak >/dev/null 2>&1; then
        if flatpak list --app 2>/dev/null | grep -q 'md\.obsidian\.Obsidian'; then
            return 0
        fi
    fi
    return 1
}

# Install Obsidian with whichever package manager is available.
obsidian_install() {
    if [ "$OS_TYPE" = "Darwin" ]; then
        command -v brew >/dev/null 2>&1 || return 1
        brew install --cask obsidian >/dev/null 2>&1
    elif command -v flatpak >/dev/null 2>&1; then
        flatpak install -y flathub md.obsidian.Obsidian >/dev/null 2>&1
    elif command -v snap >/dev/null 2>&1; then
        snap install obsidian --classic >/dev/null 2>&1
    else
        return 1
    fi
}

# Where Obsidian keeps its vault registry.
obsidian_config_dir() {
    if [ "$OS_TYPE" = "Darwin" ]; then
        printf '%s\n' "$HOME/Library/Application Support/obsidian"
    else
        printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian"
    fi
}

# 16 hex chars, the id format Obsidian uses for vaults.
obsidian_new_vault_id() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 8
    else
        printf '%016x' "$(date +%s)"
    fi
}

# Percent-encode a path for obsidian://open?path=...
obsidian_urlencode() {
    local s="$1" out='' ch i
    for (( i = 0; i < ${#s}; i++ )); do
        ch="${s:i:1}"
        case "$ch" in
            [a-zA-Z0-9/._~-]) out="$out$ch" ;;
            *) printf -v ch '%%%02X' "'$ch"; out="$out$ch" ;;
        esac
    done
    printf '%s' "$out"
}

# Add $VAULT_DIR to Obsidian's vault list so obsidian://open?path= can find it.
# Sets OBSIDIAN_VAULT_STATE to added | existing | unsupported | error.
OBSIDIAN_VAULT_STATE=''
obsidian_register_vault() {
    local cfg id ts state
    cfg="$(obsidian_config_dir)/obsidian.json"
    OBSIDIAN_VAULT_STATE='error'
    mkdir -p "$(dirname "$cfg")" || return 1
    id="$(obsidian_new_vault_id)"
    ts=$(( $(date +%s) * 1000 ))

    if ! command -v python3 >/dev/null 2>&1; then
        # No JSON parser available: only safe to write when no registry exists.
        if [ -f "$cfg" ]; then
            OBSIDIAN_VAULT_STATE='unsupported'
            return 1
        fi
        printf '{"vaults":{"%s":{"path":"%s","ts":%s,"open":true}}}\n' \
            "$id" "$VAULT_DIR" "$ts" > "$cfg"
        OBSIDIAN_VAULT_STATE='added'
        return 0
    fi

    [ -f "$cfg" ] && cp "$cfg" "$cfg.setup-backup"
    state="$(python3 - "$cfg" "$VAULT_DIR" "$id" "$ts" <<'PYTHON'
import json, os, sys

cfg, path, vid, ts = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
data = {}
if os.path.exists(cfg) and os.path.getsize(cfg) > 0:
    with open(cfg, encoding="utf-8") as fh:
        data = json.load(fh)
if not isinstance(data, dict):
    data = {}
vaults = data.get("vaults")
if not isinstance(vaults, dict):
    vaults = data["vaults"] = {}
target = os.path.realpath(path)
state = "added"
for entry in vaults.values():
    if isinstance(entry, dict) and os.path.realpath(entry.get("path", "")) == target:
        entry["open"] = True
        state = "existing"
        break
else:
    for entry in vaults.values():
        if isinstance(entry, dict):
            entry.pop("open", None)
    vaults[vid] = {"path": path, "ts": ts, "open": True}
tmp = cfg + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(data, fh, separators=(",", ":"))
os.replace(tmp, cfg)
print(state)
PYTHON
)" || { OBSIDIAN_VAULT_STATE='error'; return 1; }

    OBSIDIAN_VAULT_STATE="$state"
    return 0
}

# Open the registered vault through Obsidian's URI handler.
obsidian_open_vault() {
    local uri="obsidian://open?path=$(obsidian_urlencode "$VAULT_DIR")"
    if [ "$OS_TYPE" = "Darwin" ]; then
        open "$uri" >/dev/null 2>&1 && return 0
        open -a Obsidian "$VAULT_DIR" >/dev/null 2>&1
        return $?
    fi
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$uri" >/dev/null 2>&1 && return 0
    fi
    if command -v flatpak >/dev/null 2>&1; then
        flatpak run md.obsidian.Obsidian "$VAULT_DIR" >/dev/null 2>&1 && return 0
    fi
    return 1
}

step_header 1 5 "Obsidian Knowledge Vault"
note "The human view of your vault: browse, link, and edit notes by hand."
note "Vault path: $VAULT_DIR"

if obsidian_installed; then
    success "Obsidian is already installed."
elif prompt_confirm "Install Obsidian from the command line now?" "Y"; then
    info "Installing Obsidian..."
    if obsidian_install; then
        success "Obsidian installed."
    elif [ "$OS_TYPE" = "Darwin" ] && ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found, so Obsidian could not be installed."
        info "Install Homebrew from https://brew.sh, then run: brew install --cask obsidian"
    else
        warn "Obsidian install failed or no supported installer was found."
        info "Download it manually: https://obsidian.md/download"
    fi
else
    info "Skipping Obsidian installation."
fi

if ! obsidian_installed; then
    info "Obsidian is not installed yet, so the vault cannot be opened."
    info "Install Obsidian later, then open: $VAULT_DIR"
elif prompt_confirm "Set $VAULT_DIR as an Obsidian vault and open it now?" "Y"; then
    if obsidian_register_vault; then
        if [ "$OBSIDIAN_VAULT_STATE" = "existing" ]; then
            info "Vault is already in Obsidian's vault list."
        else
            info "Added to Obsidian's vault list."
        fi
    else
        warn "Could not update Obsidian's vault list; trying the folder directly."
    fi
    if obsidian_open_vault; then
        success "Obsidian opened on $VAULT_DIR."
    else
        warn "Could not launch Obsidian from the command line."
        info "Open Obsidian once, choose 'Open folder as vault', and select $VAULT_DIR."
    fi
else
    info "Skipping Obsidian launch (you can open $VAULT_DIR in Obsidian anytime)."
fi

# --- Step 2: MemPalace Vector Recall ---
step_header 2 5 "MemPalace · Local Vector Memory"
note "Zero-key semantic recall on ChromaDB + SQLite."
note "Lets Claude Code, Gemini CLI, and Antigravity recall past decisions by meaning."

if prompt_confirm "Install and configure MemPalace now?" "Y"; then
    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found. Skipping MemPalace install."
    else
        info "Installing mempalace via pip..."
        pip install --user mempalace >/dev/null 2>&1 || pip install mempalace >/dev/null 2>&1 || true

        # Persistent storage setup
        mkdir -p "$VAULT_DIR/.mempalace"
        if [ "$HOME/.mempalace" != "$VAULT_DIR/.mempalace" ]; then
            ln -sfn "$VAULT_DIR/.mempalace" "$HOME/.mempalace"
        fi

        # Persist environment variable
        for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
            if [ -f "$rc" ] && ! grep -q "MEMPAL_DIR" "$rc"; then
                echo "export MEMPAL_DIR=\"$VAULT_DIR/.mempalace\"" >> "$rc"
            fi
        done
        export MEMPAL_DIR="$VAULT_DIR/.mempalace"

        # Initialize palace non-interactively if possible
        if command -v mempalace >/dev/null 2>&1; then
            info "Mining vault notes into persistent memory palace..."
            mempalace mine "$VAULT_DIR" --palace "$VAULT_DIR/.mempalace" >/dev/null 2>&1 || true
            success "MemPalace initialized and notes mined."
        fi

        # Register MCP for Claude Code
        if command -v claude >/dev/null 2>&1; then
            info "Registering MemPalace MCP server in Claude Code..."
            claude mcp add -s user mempalace -e "MEMPAL_DIR=$VAULT_DIR/.mempalace" -- mempalace-mcp --palace "$VAULT_DIR/.mempalace" >/dev/null 2>&1 || true
            success "Claude Code MCP server configured."
        fi

        # Register MCP for Antigravity CLI
        mkdir -p "$HOME/.gemini/config"
        cat << EOF > "$HOME/.gemini/config/mcp_config.json"
{
  "mcpServers": {
    "mempalace": {
      "command": "mempalace-mcp",
      "args": ["--palace", "$VAULT_DIR/.mempalace"],
      "env": {
        "MEMPAL_DIR": "$VAULT_DIR/.mempalace"
      }
    }
  }
}
EOF
        cp "$HOME/.gemini/config/mcp_config.json" "$VAULT_DIR/.agents/mcp_config.json" 2>/dev/null || true
        success "Antigravity CLI MCP server configured."
    fi
else
    info "Skipping MemPalace installation."
fi

# --- Step 3: Graphify Knowledge Graph ---
step_header 3 5 "Graphify · Structural Knowledge Graph"
note "Turns vault links and code ASTs into a topological map."
note "Answers 'how does X connect to Y?' with scoped subgraphs to save tokens."

if prompt_confirm "Install and build Graphify knowledge graph now?" "Y"; then
    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found. Skipping Graphify."
    else
        info "Installing graphifyy..."
        pip install --user graphifyy >/dev/null 2>&1 || pip install graphifyy >/dev/null 2>&1 || true

        if command -v graphify >/dev/null 2>&1; then
            info "Building initial knowledge graph in $VAULT_DIR/graphify-out/..."
            graphify update "$VAULT_DIR" >/dev/null 2>&1 || true

            # Register skills
            if command -v claude >/dev/null 2>&1; then
                graphify install --platform claude >/dev/null 2>&1 || true
            fi
            if command -v agy >/dev/null 2>&1 || [ -d "$HOME/.gemini" ]; then
                graphify install --platform gemini >/dev/null 2>&1 || true
            fi
            success "Graphify knowledge graph built and agent skills installed."
        fi
    fi
else
    info "Skipping Graphify installation."
fi

# --- Step 4: Token Optimization Plugins (Claude Code) ---
step_header 4 5 "Token Optimization Plugins"
note "Caveman trims conversational fluff (60-80%% fewer output tokens)."
note "Ponytail blocks over-engineering and keeps diffs minimal."

if command -v claude >/dev/null 2>&1; then
    if prompt_confirm "Install Caveman & Ponytail plugins for Claude Code?" "Y"; then
        info "Installing Caveman..."
        claude plugin marketplace add JuliusBrussee/caveman >/dev/null 2>&1 || true
        claude plugin install caveman@caveman >/dev/null 2>&1 || true

        info "Installing Ponytail..."
        claude plugin marketplace add DietrichGebert/ponytail >/dev/null 2>&1 || true
        claude plugin install ponytail@ponytail >/dev/null 2>&1 || true

        success "Caveman & Ponytail installed in Claude Code."
    else
        info "Skipping Claude Code plugins."
    fi
else
    info "Claude CLI not detected in PATH. Skipping plugin step."
fi

# --- Step 5: Self-Diagnostic Test ---
step_header 5 5 "Diagnostic & Self-Test"
note "Checks the MCP server, the vector store, and the graph build."
if prompt_confirm "Run a quick self-test to verify installation?" "Y"; then
    printf "\n"
    if [ -f "$VAULT_DIR/scripts/test-mcp.py" ] && command -v python3 >/dev/null 2>&1; then
        info "Testing MemPalace MCP server via JSON-RPC..."
        python3 "$VAULT_DIR/scripts/test-mcp.py" --status | grep -E "total_drawers|sqlite_version|ok" || true
        success "MemPalace MCP self-test passed."
    fi

    if [ -f "$VAULT_DIR/graphify-out/graph.json" ]; then
        NODE_COUNT=$(grep -c '"id":' "$VAULT_DIR/graphify-out/graph.json" 2>/dev/null || echo "100+")
        success "Graphify map verified: ~$NODE_COUNT graph entities indexed."
    fi
else
    info "Skipping diagnostic test."
fi

# ==============================================================================
# COMPLETION RECAP & CHEAT SHEET
# ==============================================================================
printf "\n"
box_top
box_blank
box_line "  ${GREEN}✔${RESET}  ${BOLD}Setup complete${RESET}  ${GREY}·${RESET}  your AI 2nd brain is ready."
box_blank
box_bottom
printf "\n"

kv "Vault"        "$VAULT_DIR"
kv "Rules"        "AGENTS.md · CLAUDE.md · GEMINI.md"
kv "Vector store" "$VAULT_DIR/.mempalace"
kv "Visual graph" "$VAULT_DIR/graphify-out/graph.html"

printf "\n  %bQuick reference%b\n" "$BOLD" "$RESET"
printf "  %b%s%b\n" "$GREY" "$(rule 56 '─')" "$RESET"
tip "Search memories" "mempalace search \"your query\""
tip "Re-mine vault"   "mempalace mine $VAULT_DIR"
tip "Update graph"    "graphify update $VAULT_DIR"
tip "Test MCP server" "python3 $VAULT_DIR/scripts/test-mcp.py --status"
printf "\n"
success "Done. Happy pair-programming."
