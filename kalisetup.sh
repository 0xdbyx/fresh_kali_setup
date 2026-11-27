#!/usr/bin/env bash
set -euo pipefail

# Fresh Kali bootstrap.
#
# - Fully updates a fresh Kali install
# - Installs Go and build/runtime dependencies
# - Installs the current PDTM to a known Go path
# - Installs/updates selected ProjectDiscovery tools through that exact PDTM binary
# - Updates Nuclei templates without deleting custom template directories
# - Installs oscp_prep as a Git clone and exposes it as `oscp_prep`
# - Supports both Kali's default Zsh and Bash

OSCP_REPO_URL="https://github.com/0xdbyx/oscp_prep.git"
OSCP_INSTALL_DIR="$HOME/.local/share/oscp_prep"
LOCAL_BIN="$HOME/.local/bin"

APT_PACKAGES=(
  git
  curl
  python3
  golang
  libpcap-dev
)

PROJECTDISCOVERY_TOOLS=(
  subfinder
  httpx
  naabu
  nuclei
  katana
  dnsx
)

log()  { echo -e "\n[+] $*"; }
warn() { echo -e "\n[!] $*"; }
die()  { echo -e "\n[-] $*" >&2; exit 1; }

require_sudo() {
  sudo -v || die "sudo access is required."
}

add_line_once() {
  local line="$1"
  local file="$2"
  touch "$file"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

configure_shell_paths() {
  local path_line='export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.pdtm/go/bin:$PATH"'
  local gopath_line='export GOPATH="$HOME/go"'
  local gobin_line='export GOBIN="$HOME/go/bin"'
  local rc_files=()

  # Kali desktop installs normally use Zsh, but keep Bash compatible too.
  [[ -f "$HOME/.zshrc" || "${SHELL:-}" == */zsh ]] && rc_files+=("$HOME/.zshrc")
  [[ -f "$HOME/.bashrc" || "${SHELL:-}" == */bash ]] && rc_files+=("$HOME/.bashrc")

  # If neither exists, create the file matching the current shell.
  if [[ ${#rc_files[@]} -eq 0 ]]; then
    if [[ "${SHELL:-}" == */zsh ]]; then
      rc_files+=("$HOME/.zshrc")
    else
      rc_files+=("$HOME/.bashrc")
    fi
  fi

  for rc in "${rc_files[@]}"; do
    add_line_once "$gopath_line" "$rc"
    add_line_once "$gobin_line" "$rc"
    add_line_once "$path_line" "$rc"
  done
}

safe_link() {
  local src="$1"
  local dst="$2"

  if [[ ! -e "$src" ]]; then
    warn "Cannot link missing file: $src"
    return 1
  fi

  # ~/.local/bin is managed by this bootstrap for these commands.
  ln -sfn "$src" "$dst"
}

verify_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    printf '[OK] %-12s -> %s\n' "$name" "$(command -v "$name")"
  else
    printf '[MISSING] %s\n' "$name"
  fi
}

log "Starting fresh Kali setup"
require_sudo

mkdir -p "$LOCAL_BIN" "$HOME/.local/share" "$HOME/go/bin"

log "Updating Kali"
sudo apt update
sudo apt full-upgrade -y

log "Installing bootstrap dependencies"
sudo apt install -y "${APT_PACKAGES[@]}"

command -v git >/dev/null 2>&1 || die "git install failed."
command -v curl >/dev/null 2>&1 || die "curl install failed."
command -v go >/dev/null 2>&1 || die "Go install failed."

go version

log "Configuring Go and shell paths"
export GOPATH="$HOME/go"
export GOBIN="$HOME/go/bin"
export PATH="$LOCAL_BIN:$GOBIN:$HOME/.pdtm/go/bin:$PATH"
configure_shell_paths

log "Installing/updating PDTM to the canonical Go path"
GOBIN="$GOBIN" go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest
PDTM_BIN="$GOBIN/pdtm"
[[ -x "$PDTM_BIN" ]] || die "PDTM was not installed at $PDTM_BIN"

safe_link "$PDTM_BIN" "$LOCAL_BIN/pdtm"

log "PDTM version"
"$PDTM_BIN" -version || true

log "Installing/updating ProjectDiscovery tools"
PD_INSTALL_LIST="$(IFS=,; echo "${PROJECTDISCOVERY_TOOLS[*]}")"

# Install ensures missing tools are present; update refreshes existing tools.
"$PDTM_BIN" -install "$PD_INSTALL_LIST" || true
"$PDTM_BIN" -update "$PD_INSTALL_LIST" || warn "One or more ProjectDiscovery updates failed"

for tool in "${PROJECTDISCOVERY_TOOLS[@]}"; do
  pd_bin="$HOME/.pdtm/go/bin/$tool"
  if [[ -x "$pd_bin" ]]; then
    safe_link "$pd_bin" "$LOCAL_BIN/$tool"
  else
    warn "$tool was not found at the PDTM-managed path: $pd_bin"
  fi
done

hash -r

log "Updating Nuclei templates"
NUCLEI_BIN="$HOME/.pdtm/go/bin/nuclei"
if [[ -x "$NUCLEI_BIN" ]]; then
  "$NUCLEI_BIN" -update-templates || "$NUCLEI_BIN" -ut || warn "Nuclei template update failed"
else
  warn "Nuclei is missing; skipping template update"
fi

log "Installing/updating oscp_prep"
if [[ -d "$OSCP_INSTALL_DIR/.git" ]]; then
  if git -C "$OSCP_INSTALL_DIR" diff --quiet && git -C "$OSCP_INSTALL_DIR" diff --cached --quiet; then
    git -C "$OSCP_INSTALL_DIR" fetch origin main
    git -C "$OSCP_INSTALL_DIR" pull --ff-only origin main || warn "oscp_prep has diverged; leaving the local checkout unchanged"
  else
    warn "Local changes exist in $OSCP_INSTALL_DIR; skipping automatic git pull"
  fi
elif [[ -e "$OSCP_INSTALL_DIR" ]]; then
  die "$OSCP_INSTALL_DIR exists but is not a Git checkout. Move/remove it and rerun."
else
  git clone "$OSCP_REPO_URL" "$OSCP_INSTALL_DIR"
fi

chmod +x "$OSCP_INSTALL_DIR/oscp_prep.sh"
safe_link "$OSCP_INSTALL_DIR/oscp_prep.sh" "$LOCAL_BIN/oscp_prep"

log "Running oscp_prep"
"$OSCP_INSTALL_DIR/oscp_prep.sh" --skip-self-update

log "Verifying ProjectDiscovery commands"
hash -r
for tool in "${PROJECTDISCOVERY_TOOLS[@]}" pdtm; do
  verify_command "$tool"
done

log "Active PDTM"
echo "Canonical : $PDTM_BIN"
echo "PATH uses : $(command -v pdtm 2>/dev/null || echo missing)"
echo
if command -v type >/dev/null 2>&1; then
  type -a pdtm 2>/dev/null || true
fi

log "Setup complete"
echo "Run 'oscp_prep' at any time to update/repair the OSCP tool collection."
echo "Open a new terminal for shell PATH changes to be picked up automatically."
echo "Optional reboot after the full Kali upgrade: sudo reboot"
