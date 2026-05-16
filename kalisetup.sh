#!/usr/bin/env bash
set -euo pipefail

# fresh_kali_setup.sh
# Fresh Kali setup for OSCP prep.
#
# - Updates Kali
# - Installs Go only if missing
# - Downloads only oscp_prep.sh from your GitHub repo
# - Runs oscp_prep.sh
# - Removes old ProjectDiscovery tools
# - Reinstalls ProjectDiscovery tools with PDTM
# - Updates nuclei templates

# =========================
# Config
# =========================

OSCP_SCRIPT_URL="https://raw.githubusercontent.com/0xdbyx/oscp_prep/main/oscp_prep.sh"
SCRIPT_DIR="$HOME/Desktop/scripts"
OSCP_SCRIPT_PATH="$SCRIPT_DIR/oscp_prep.sh"

PROJECTDISCOVERY_TOOLS=(
  subfinder
  httpx
  naabu
  nuclei
  katana
  dnsx
)

# =========================
# Helpers
# =========================

log() {
  echo -e "\n[+] $*"
}

warn() {
  echo -e "\n[!] $*"
}

die() {
  echo -e "\n[-] $*" >&2
  exit 1
}

require_sudo() {
  if ! sudo -v; then
    die "sudo access is required."
  fi
}

add_path_line() {
  local line="$1"
  local file="$2"

  touch "$file"

  if ! grep -qxF "$line" "$file"; then
    echo "$line" >> "$file"
  fi
}

remove_binary_everywhere() {
  local bin="$1"

  log "Removing old $bin binaries if present"

  rm -f "$HOME/go/bin/$bin" 2>/dev/null || true
  rm -f "$HOME/.pdtm/go/bin/$bin" 2>/dev/null || true
  rm -f "$HOME/.local/bin/$bin" 2>/dev/null || true

  sudo rm -f "/usr/local/bin/$bin" 2>/dev/null || true
  sudo rm -f "/usr/bin/$bin" 2>/dev/null || true
  sudo rm -f "/bin/$bin" 2>/dev/null || true
}

verify_bin() {
  local bin="$1"

  if command -v "$bin" >/dev/null 2>&1; then
    echo "[OK] $bin -> $(command -v "$bin")"
  else
    echo "[MISSING] $bin"
  fi
}

# =========================
# Start
# =========================

log "Starting fresh Kali setup"
require_sudo

log "Creating working folders"
mkdir -p "$SCRIPT_DIR" "$HOME/.local/bin"

# =========================
# Update Kali
# =========================

log "Updating Kali packages"
sudo apt update
sudo apt full-upgrade -y

# =========================
# Check curl and install Go
# =========================

log "Checking curl"

if ! command -v curl >/dev/null 2>&1; then
  die "curl is not installed. Install it with: sudo apt install -y curl"
fi

log "Checking Go"

if ! command -v go >/dev/null 2>&1; then
  log "Go not found. Installing Go."
  sudo apt install -y golang
else
  log "Go already installed: $(go version)"
fi

# =========================
# Set Go paths
# =========================

log "Setting Go environment paths"

export GOPATH="$HOME/go"
export GOBIN="$HOME/go/bin"
export PATH="$PATH:$GOBIN:$HOME/.pdtm/go/bin:$HOME/.local/bin"

add_path_line 'export GOPATH="$HOME/go"' "$HOME/.bashrc"
add_path_line 'export GOBIN="$HOME/go/bin"' "$HOME/.bashrc"
add_path_line 'export PATH="$PATH:$HOME/go/bin:$HOME/.pdtm/go/bin:$HOME/.local/bin"' "$HOME/.bashrc"

mkdir -p "$GOBIN"

log "Go version"
go version || die "Go install failed."

# =========================
# Download and run oscp_prep.sh only
# =========================

log "Downloading only oscp_prep.sh from GitHub"

curl -fsSL "$OSCP_SCRIPT_URL" -o "$OSCP_SCRIPT_PATH"

chmod +x "$OSCP_SCRIPT_PATH"

log "Checking oscp_prep.sh syntax"
bash -n "$OSCP_SCRIPT_PATH"

log "Running oscp_prep.sh"
bash "$OSCP_SCRIPT_PATH"

# =========================
# Remove old ProjectDiscovery tools
# =========================

log "Removing old ProjectDiscovery tools and PDTM"

for tool in "${PROJECTDISCOVERY_TOOLS[@]}"; do
  remove_binary_everywhere "$tool"
done

remove_binary_everywhere pdtm

log "Removing old PDTM directories"
rm -rf "$HOME/.pdtm" 2>/dev/null || true
rm -rf "$HOME/.config/pdtm" 2>/dev/null || true

log "Removing old nuclei templates"
rm -rf "$HOME/nuclei-templates" 2>/dev/null || true
rm -rf "$HOME/.local/nuclei-templates" 2>/dev/null || true
rm -rf "$HOME/.config/nuclei/templates" 2>/dev/null || true

# =========================
# Install PDTM
# =========================

log "Installing PDTM"
go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest

if ! command -v pdtm >/dev/null 2>&1; then
  die "pdtm was installed but is not in PATH. Try: source ~/.bashrc"
fi

log "PDTM version"
pdtm -version || true

# =========================
# Install ProjectDiscovery tools
# =========================

log "Installing ProjectDiscovery tools with PDTM"

PD_INSTALL_LIST="$(IFS=,; echo "${PROJECTDISCOVERY_TOOLS[*]}")"

pdtm -install "$PD_INSTALL_LIST" -ip -igp

log "Updating ProjectDiscovery tools"
pdtm -update "$PD_INSTALL_LIST" || true

# =========================
# Install nuclei templates
# =========================

log "Installing nuclei templates"

if command -v nuclei >/dev/null 2>&1; then
  nuclei -update-templates || nuclei -ut || warn "Nuclei template update failed"
else
  warn "nuclei not found, skipping template update"
fi

# =========================
# Symlink tools into ~/.local/bin
# =========================

log "Linking tools into ~/.local/bin"

for tool in "${PROJECTDISCOVERY_TOOLS[@]}" pdtm; do
  if [[ -x "$HOME/.pdtm/go/bin/$tool" ]]; then
    ln -sf "$HOME/.pdtm/go/bin/$tool" "$HOME/.local/bin/$tool"
  elif [[ -x "$HOME/go/bin/$tool" ]]; then
    ln -sf "$HOME/go/bin/$tool" "$HOME/.local/bin/$tool"
  fi
done

# =========================
# Verify
# =========================

log "Verifying installed tools"

for tool in "${PROJECTDISCOVERY_TOOLS[@]}" pdtm; do
  verify_bin "$tool"
done

log "Versions"

subfinder -version 2>/dev/null || true
httpx -version 2>/dev/null || true
naabu -version 2>/dev/null || true
nuclei -version 2>/dev/null || true
katana -version 2>/dev/null || true
dnsx -version 2>/dev/null || true

# =========================
# Done
# =========================

log "Setup complete"

echo
echo "Run this now so your current terminal gets the new PATH:"
echo
echo "  source ~/.bashrc"
echo
echo "Downloaded oscp_prep.sh here:"
echo "  $OSCP_SCRIPT_PATH"
echo
echo "ProjectDiscovery tools are installed here:"
echo "  $HOME/.pdtm/go/bin"
echo
echo "Go tools are installed here:"
echo "  $HOME/go/bin"
echo
echo "Check installed tools:"
echo
echo "  which subfinder httpx naabu nuclei katana dnsx pdtm"
echo
echo "Optional reboot after full-upgrade:"
echo "  sudo reboot"
