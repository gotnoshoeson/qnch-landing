#!/bin/bash

set -e  # Exit on error

# Colours: the artist dashboard's palette (web/artist-portal/src/theme.js).
# gum takes the hex values; plain output uses true colour when the terminal
# says it has it, else the nearest of the 256 standard colours.
COL_MINT="#ADEBB3"
COL_AQUA="#ADEBD2"
COL_LIME="#C6EBAD"
COL_MUTED="#A1A1AA"
COL_WARN="#F5C08A"
COL_ERROR="#F28B82"
ansi_fg() { # ansi_fg "#RRGGBB" 256-colour-index
    case "${COLORTERM:-}" in
        truecolor|24bit) printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}" ;;
        *) printf '\033[38;5;%dm' "$2" ;;
    esac
}
GREEN=$(ansi_fg "$COL_MINT" 151)
CYAN=$(ansi_fg "$COL_AQUA" 158)
LIME=$(ansi_fg "$COL_LIME" 193)
MUTED=$(ansi_fg "$COL_MUTED" 248)
YELLOW=$(ansi_fg "$COL_WARN" 222)
RED=$(ansi_fg "$COL_ERROR" 210)
BLUE="$GREEN"
BOLD='\033[1m'
NC='\033[0m' # No Color

# gum's own prompts, buttons and spinners in the same palette.
export GUM_SPIN_SPINNER_FOREGROUND="$COL_MINT"
export GUM_CONFIRM_PROMPT_FOREGROUND="$COL_MINT"
export GUM_CONFIRM_SELECTED_BACKGROUND="$COL_MINT"
export GUM_CONFIRM_SELECTED_FOREGROUND="#09090B"
export GUM_CONFIRM_UNSELECTED_BACKGROUND="#27272A"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="$COL_MUTED"
export GUM_INPUT_PROMPT_FOREGROUND="$COL_MINT"
export GUM_INPUT_CURSOR_FOREGROUND="$COL_MINT"
export GUM_INPUT_PLACEHOLDER_FOREGROUND="#71717A"
export GUM_CHOOSE_CURSOR_FOREGROUND="$COL_MINT"
export GUM_CHOOSE_SELECTED_FOREGROUND="$COL_MINT"
export GUM_CHOOSE_HEADER_FOREGROUND="$COL_MINT"
# gum format (Markdown) in the same palette: a small theme file, removed on exit.
STATION_GUM_THEME=$(mktemp 2>/dev/null || echo "/tmp/station-gum-theme.$$.json")
cat > "$STATION_GUM_THEME" << 'GUM_THEME'
{"document":{"block_prefix":"\n","block_suffix":"\n","margin":2},"heading":{"block_suffix":"\n","color":"#ADEBB3","bold":true},"h1":{"prefix":""},"h2":{"prefix":""},"h3":{"prefix":""},"paragraph":{},"list":{"level_indent":2},"item":{"block_prefix":"• "},"strong":{"bold":true},"emph":{"italic":true,"color":"#A1A1AA"},"code":{"color":"#ADEBD2"},"code_block":{"color":"#E4E4E7","margin":2}}
GUM_THEME
export GUM_FORMAT_THEME="$STATION_GUM_THEME"

# Temporary files removed on exit: the theme above and, with --tui, the
# downloaded installer app.
TUI_TMPDIR=""
cleanup_tmp() {
    rm -f "$STATION_GUM_THEME"
    if [ -n "$TUI_TMPDIR" ]; then rm -rf "$TUI_TMPDIR"; fi
}
trap cleanup_tmp EXIT

# ----------------------------------------------------------------------------
# Environment target (deploy-time choice): which P2P directory this node
# joins. Artists run the bare script and get production (mainnet directory,
# "/station"); testnet deploys pass --network testnet ("/station/testnet");
# local dev uses --network local ("/station/local"). The choice is baked into
# the generated .env here, so the operator never hand-edits it.
#
# STATION_CHAIN is a separate, optional axis: which EVM chain the artist's
# contracts live on (polkadot-hub | kusama-hub | paseo | local | local-dummy).
# On a real node this is picked from the artist dashboard after first login —
# leave --chain unset. Only pass --chain for automation/scripted setups (CI,
# local multi-node testing) that need to skip the picker.
# ----------------------------------------------------------------------------
NETWORK="production"
CHAIN=""
# --answers <file>: the answers the station-installer terminal app collected
# (KEY='value' lines). With it, every question below is answered from the
# file instead of asked; without it, nothing changes.
ANSWERS_FILE=""
# The questions are asked by the station-installer terminal app by default
# (founder, 2026-10-25); --classic uses the wizard below instead. --tui is
# kept so older commands still work. --tui-binary <path> uses a local build
# instead of the release download (testing).
USE_TUI=true
TUI_BINARY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --network=*)
            NETWORK="${1#*=}"
            shift
            ;;
        --network)
            shift
            NETWORK="${1:-}"
            [ $# -eq 0 ] || shift
            ;;
        --chain=*)
            CHAIN="${1#*=}"
            shift
            ;;
        --chain)
            shift
            CHAIN="${1:-}"
            [ $# -eq 0 ] || shift
            ;;
        --answers=*)
            ANSWERS_FILE="${1#*=}"
            shift
            ;;
        --answers)
            shift
            ANSWERS_FILE="${1:-}"
            [ $# -eq 0 ] || shift
            ;;
        --tui)
            USE_TUI=true
            shift
            ;;
        --classic)
            USE_TUI=false
            shift
            ;;
        --tui-binary)
            shift
            USE_TUI=true
            TUI_BINARY="${1:-}"
            [ $# -eq 0 ] || shift
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--network production|testnet|local] [--chain polkadot-hub|kusama-hub|paseo|local|local-dummy] [--classic] [--answers <file>]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done
case "$NETWORK" in
    production|testnet|local) ;;
    *)
        echo "Invalid --network '$NETWORK' (expected: production, testnet, local)" >&2
        exit 1
        ;;
esac
case "$CHAIN" in
    ""|polkadot-hub|kusama-hub|paseo|local|local-dummy) ;;
    *)
        echo "Invalid --chain '$CHAIN' (expected: polkadot-hub, kusama-hub, paseo, local, local-dummy)" >&2
        exit 1
        ;;
esac

# ----------------------------------------------------------------------------
# Terminal app (--tui). The app asks the questions and runs this script again
# with --answers, so everything after the questions is unchanged. Anything
# that stops it (no download, a bad checksum, no terminal, not root) falls
# back to the wizard below. The app is published beside install.sh on
# qnch.network by release.yml, which also fills in STATION_RELEASE_TAG; a copy
# of this script that was not published (empty tag) does not download it.
# ----------------------------------------------------------------------------
STATION_RELEASE_TAG="v0.1.0-rc.22"
STATION_INSTALLER_URL="https://qnch.network/installer"

fetch_tui() {
    local arch dir base want got
    case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) return 1 ;;
    esac
    [ -n "$STATION_RELEASE_TAG" ] || return 1
    command -v curl >/dev/null && command -v sha256sum >/dev/null || return 1
    dir=$(mktemp -d) || return 1
    TUI_TMPDIR="$dir"
    base="$STATION_INSTALLER_URL/station-installer-linux-$arch"
    curl -fsSL --max-time 120 -o "$dir/station-installer" "$base" || return 1
    curl -fsSL --max-time 30 -o "$dir/station-installer.sha256" "$base.sha256" || return 1
    want=$(awk '{print $1; exit}' "$dir/station-installer.sha256")
    got=$(sha256sum "$dir/station-installer" | awk '{print $1}')
    [ -n "$want" ] && [ "$want" = "$got" ] || return 1
    chmod 700 "$dir/station-installer"
    TUI_BINARY="$dir/station-installer"
}

# Not root: skip the app quietly; the wizard below says how to run as root.
if [ "$USE_TUI" = true ] && [ -z "$ANSWERS_FILE" ] && [ "$EUID" -eq 0 ]; then
    tui_note=""
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        tui_note="the new installer needs an interactive terminal"
    elif [ -z "$TUI_BINARY" ] && ! fetch_tui; then
        tui_note="the new installer could not be downloaded or checked"
    fi
    if [ -z "$tui_note" ]; then
        tui_rc=0
        tui_args=(--preview=false --script "$(readlink -f "${BASH_SOURCE[0]}")" --network "$NETWORK")
        [ -n "$CHAIN" ] && tui_args+=(--chain "$CHAIN")
        "$TUI_BINARY" "${tui_args[@]}" || tui_rc=$?
        # 3: the app could not run here. Anything else is the install's own
        # result (the app ran this script), or the artist cancelled (130).
        [ "$tui_rc" -eq 3 ] || exit "$tui_rc"
        tui_note="the new installer could not start here"
    fi
    echo "Note: $tui_note. Using the classic setup wizard."
    echo ""
fi

# Print the STATION banner: the same letters and lime-to-aqua fade as the
# station-installer terminal app (internal/installer/splash.go).
print_banner() {
    local g1 g2
    g1=$(ansi_fg "#B9EBB0" 157)
    g2=$(ansi_fg "#ADEBC2" 158)
    echo ""
    echo -e "${LIME}███████ ████████  █████  ████████ ██  ██████  ███    ██${NC}"
    echo -e "${g1}██         ██    ██   ██    ██    ██ ██    ██ ████   ██${NC}"
    echo -e "${GREEN}███████    ██    ███████    ██    ██ ██    ██ ██ ██  ██${NC}"
    echo -e "${g2}     ██    ██    ██   ██    ██    ██ ██    ██ ██  ██ ██${NC}"
    echo -e "${CYAN}███████    ██    ██   ██    ██    ██  ██████  ██   ████${NC}"
    echo ""
    echo -e "Part of the ${GREEN}${BOLD}QNCH${NC} Network  ${MUTED}·  setup wizard${NC}"
    echo ""
}

# Helper functions (enhanced with gum when available)
print_header() {
    # Use gum_header if gum is available, otherwise fallback
    if [ "$GUM_AVAILABLE" = true ]; then
        gum_header "$1"
    else
        echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC} $1"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    fi
}

print_step() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground "$COL_MINT" "→ $1"
    else
        echo -e "${BLUE}→${NC} $1"
    fi
}

print_success() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground "$COL_MINT" "✓ $1"
    else
        echo -e "${GREEN}✓${NC} $1"
    fi
}

print_error() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground "$COL_ERROR" "✗ $1"
    else
        echo -e "${RED}✗${NC} $1"
    fi
}

print_warning() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground "$COL_WARN" "⚠ $1"
    else
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

print_info() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground "$COL_AQUA" "ℹ $1"
    else
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

# Gum availability flag
GUM_AVAILABLE=false

# Progress for the station-installer terminal app. It sets STATION_TUI=1 when
# it runs this script (always with --answers) and turns these lines into its
# checklist and final card; without it they print nothing.
tui_stage() { if [ "${STATION_TUI:-}" = 1 ]; then echo "::stage::$1"; fi; }
tui_result() { if [ "${STATION_TUI:-}" = 1 ]; then echo "::result::$1"; fi; }

# Check if gum is installed and install if needed
setup_gum() {
    if command -v gum &> /dev/null; then
        GUM_AVAILABLE=true
        return 0
    fi

    # Try to install gum
    print_step "Installing gum for better interactive prompts..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi

    # NOTE: every branch below ends with `|| true`. gum is optional (there's
    # a full non-gum prompt fallback after this case statement), but under
    # `set -e`, the LAST command of an && / || chain is NOT exempt from -e
    # even though earlier commands in the same chain are — so e.g. a bare
    # `apt-get update -qq && apt-get install -y -qq gum` would abort the
    # ENTIRE installer if just the install step failed, skipping the
    # intended "Could not install gum, using basic prompts" fallback below.
    # `|| true` neutralizes that so failures here always fall through.
    case "$OS" in
        ubuntu|debian)
            # Add Charm repository
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list
            apt-get update -qq && apt-get install -y -qq gum || true
            ;;
        fedora|rhel|centos)
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' > /etc/yum.repos.d/charm.repo
            dnf install -y gum 2>/dev/null || yum install -y gum || true
            ;;
        *)
            # Try go install as fallback
            if command -v go &> /dev/null; then
                go install github.com/charmbracelet/gum@latest || true
            fi
            ;;
    esac

    if command -v gum &> /dev/null; then
        GUM_AVAILABLE=true
        print_success "Gum installed successfully"
    else
        print_warning "Could not install gum, using basic prompts"
        GUM_AVAILABLE=false
    fi
}

# Gum-enhanced prompt functions with fallbacks

# Spinner for long-running commands
gum_spin() {
    local title="$1"
    shift
    if [ "$GUM_AVAILABLE" = true ]; then
        # --show-error: by default `gum spin` swallows the wrapped command's
        # stdout/stderr entirely (success or failure), so a failing apt-get,
        # curl, or systemctl call here would abort the script (set -e) with
        # no diagnostic at all. Surface output only when the command fails,
        # keeping the quiet spinner on the success path.
        gum spin --spinner dot --title "$title" --show-error -- "$@"
    else
        echo "$title"
        "$@"
    fi
}

# Styled box for important messages
gum_box() {
    local text="$1"
    local border="${2:-rounded}"
    local color="${3:-$COL_MINT}"
    if [ "$GUM_AVAILABLE" = true ]; then
        echo "$text" | gum style --border "$border" --border-foreground "$color" --padding "1 2" --margin "1 0"
    else
        echo ""
        echo "┌────────────────────────────────────────────────────────────────┐"
        echo "$text" | while IFS= read -r line; do
            printf "│ %-66s │\n" "$line"
        done
        echo "└────────────────────────────────────────────────────────────────┘"
        echo ""
    fi
}

# Format markdown text
gum_markdown() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum format
    else
        cat
    fi
}

# Log with level (info, warn, error, debug)
gum_log() {
    local level="$1"
    local message="$2"
    if [ "$GUM_AVAILABLE" = true ]; then
        gum log --level "$level" "$message"
    else
        case "$level" in
            info)  echo -e "${BLUE}INFO${NC}  $message" ;;
            warn)  echo -e "${YELLOW}WARN${NC}  $message" ;;
            error) echo -e "${RED}ERROR${NC} $message" ;;
            debug) echo -e "${CYAN}DEBUG${NC} $message" ;;
            *)     echo "$message" ;;
        esac
    fi
}

# Styled section header
gum_header() {
    local title="$1"
    if [ "$GUM_AVAILABLE" = true ]; then
        echo ""
        gum style --foreground "$COL_MINT" --bold --border double --border-foreground "$COL_MINT" --padding "0 2" "$title"
        echo ""
    else
        print_header "$title"
    fi
}

gum_confirm() {
    local prompt="$1"
    local default="${2:-yes}"  # yes or no

    if [ "$GUM_AVAILABLE" = true ]; then
        if [ "$default" = "yes" ]; then
            gum confirm --default=yes "$prompt"
        else
            gum confirm --default=no "$prompt"
        fi
    else
        # Fallback to basic prompt
        if [ "$default" = "yes" ]; then
            read -p "$prompt [Y/n] " response
            [[ -z "$response" || "$response" =~ ^[Yy] ]]
        else
            read -p "$prompt [y/N] " response
            [[ "$response" =~ ^[Yy] ]]
        fi
    fi
}

gum_input() {
    local prompt="$1"
    local placeholder="${2:-}"
    local default="${3:-}"

    if [ "$GUM_AVAILABLE" = true ]; then
        gum input --prompt "$prompt " --placeholder "$placeholder" --value "$default"
    else
        # Fallback to basic prompt
        if [ -n "$default" ]; then
            read -p "$prompt [$default] " response
            echo "${response:-$default}"
        else
            read -p "$prompt " response
            echo "$response"
        fi
    fi
}

gum_choose() {
    local prompt="$1"
    shift
    local options=("$@")

    if [ "$GUM_AVAILABLE" = true ]; then
        echo "$prompt" >&2
        printf '%s\n' "${options[@]}" | gum choose
    else
        # Fallback to numbered selection
        echo "$prompt"
        local i=1
        for opt in "${options[@]}"; do
            echo "  $i) $opt"
            ((i++))
        done
        read -p "Enter number: " choice
        echo "${options[$((choice-1))]}"
    fi
}

# ----------------------------------------------------------------------------
# Answers file (--answers). Read line by line, never sourced: only the keys
# below are accepted, each as KEY='value' with '\'' for a quote inside, which
# is exactly what station-installer writes. Values land in ANS_<KEY>.
# ----------------------------------------------------------------------------
ANSWERS_MODE=false
ANSWER_KEYS="ANSWERS_VERSION NETWORK CHAIN RECONFIGURE INSTALL_DOCKER STOP_PORT_SERVICES DOMAIN_TYPE SERVER_IP STATION_DOMAIN DUCKDNS_SUBDOMAIN DUCKDNS_TOKEN DNS_MISMATCH_OK ACME_EMAIL ENABLE_ETHRPC KEEP_SAVED_BOOTNODE BOOTSTRAP_PEERS_VALUE"

answers_fail() {
    print_error "Answers file: $1"
    exit 1
}

load_answers() {
    local file="$1" line key value n=0
    [ -f "$file" ] || answers_fail "$file not found"
    for key in $ANSWER_KEYS; do printf -v "ANS_$key" '%s' ""; done
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        [ -z "$line" ] && continue
        if [[ ! "$line" =~ ^([A-Z_]+)=\'(.*)\'$ ]]; then
            answers_fail "line $n is not KEY='value'"
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        [[ " $ANSWER_KEYS " == *" $key "* ]] || answers_fail "unknown key $key on line $n"
        value="${value//\'\\\'\'/\'}"
        printf -v "ANS_$key" '%s' "$value"
    done < "$file"
    [ "$ANS_ANSWERS_VERSION" = "1" ] || answers_fail "version '$ANS_ANSWERS_VERSION' is not supported by this installer"
    [ "$ANS_NETWORK" = "$NETWORK" ] || answers_fail "written for network '$ANS_NETWORK', but this run is --network $NETWORK"
    [ "$ANS_CHAIN" = "$CHAIN" ] || answers_fail "written for chain '$ANS_CHAIN', but this run has --chain '$CHAIN'"
    ANSWERS_MODE=true
}

# answer_bool KEY: succeeds when ANS_KEY is "true".
answer_bool() {
    local v="ANS_$1"
    [ "${!v}" = "true" ]
}

# Docker installation function for Ubuntu/Debian
install_docker_ubuntu() {
    print_step "Installing Docker..."
    echo ""

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_CODENAME=$VERSION_CODENAME
    else
        print_error "Cannot detect OS version"
        return 1
    fi

    # Only support Ubuntu/Debian
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_error "Automatic installation only supports Ubuntu and Debian"
        echo "Detected OS: $OS"
        echo ""
        echo "Please install Docker manually:"
        echo "  https://docs.docker.com/engine/install/"
        return 1
    fi

    print_info "Installing for: $PRETTY_NAME"
    echo ""

    # Update package index
    gum_spin "Updating package index..." apt-get update -qq

    # Install dependencies
    gum_spin "Installing dependencies..." apt-get install -y -qq ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    gum_spin "Adding Docker GPG key..." bash -c '
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/'"$OS"'/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        chmod a+r /etc/apt/keyrings/docker.gpg
    '

    # Add Docker repository
    print_step "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/$OS \
      $VERSION_CODENAME stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index again
    gum_spin "Updating package index..." apt-get update -qq

    # Install Docker
    gum_spin "Installing Docker packages..." apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # Start Docker service
    gum_spin "Starting Docker service..." bash -c 'systemctl start docker && systemctl enable docker'

    # Add current user to docker group (if not root)
    if [ "$EUID" -ne 0 ] && [ -n "$SUDO_USER" ]; then
        print_step "Adding user to docker group..."
        usermod -aG docker $SUDO_USER
        print_warning "You may need to log out and back in for group membership to take effect"
    fi

    print_success "Docker installed successfully!"
    echo ""

    return 0
}

# Station node image: single source for both the generated compose file and the
# bootnode lookup in the "Joining the network" step.
STATION_IMAGE="ghcr.io/gotnoshoeson/station:edge"

# Docker Compose configuration generation
generate_docker_compose() {
    print_step "Generating docker-compose.yml..."

    cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

# Station with Traefik Reverse Proxy
# =============================================================================
# Production configuration using Traefik for automatic HTTPS.
# Generated by Station setup script.
# =============================================================================

services:
  # Traefik Reverse Proxy - HTTPS/TLS Termination
  traefik:
    image: traefik:latest
    container_name: station-traefik
    restart: unless-stopped

    security_opt:
      - no-new-privileges:true

    ports:
      - "80:80"     # HTTP - ACME challenge + redirect to HTTPS
      - "443:443"   # HTTPS - TLS termination

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro
      - ./traefik/acme.json:/acme.json:rw

    environment:
      - ACME_EMAIL=${ACME_EMAIL}
      - ACME_PRODUCTION=${ACME_PRODUCTION:-true}

    networks:
      - station-network

    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Station Artist Node - P2P Music Streaming Backend
  station:
    image: __STATION_IMAGE__
    container_name: station-node
    restart: unless-stopped

    # The binary is flag+env configured (Go stdlib `flag`; see
    # cmd/station/main.go) — there is no --config flag and nothing reads a
    # YAML config file. --data-dir is NOT optional: without it the process
    # falls back to $HOME/.station inside the container instead of the /data
    # volume below, so identity key / catalog / SQLite state would silently
    # fail to persist across container recreates. This mirrors the image's
    # own default CMD (Dockerfile) so it works even against an older image
    # tag whose baked-in CMD predates this fix.
    command: ["station", "start", "--data-dir", "/data", "--port", "8080"]

    ports:
      - "4001:4001"         # libp2p swarm TCP
      - "4002:4002/udp"     # libp2p swarm QUIC

    volumes:
      - ./data:/data

    environment:
      # NOTE: not read by the binary today (no STATION_LOG_LEVEL consumer in
      # cmd/station or pkg/) — left in place as a documented, currently-inert
      # knob rather than silently dropped. Data dir is set via the `command:`
      # flag above, not an env var — main.go has no STATION_DATA_DIR reader.
      - STATION_LOG_LEVEL=${STATION_LOG_LEVEL:-info}
      # Environment: which P2P directory this node joins (production | testnet | local).
      - STATION_NETWORK=${STATION_NETWORK:-production}
      # Chain override (optional): polkadot-hub | kusama-hub | paseo | local | local-dummy.
      # Leave unset to pick the chain from the artist dashboard instead.
      - STATION_CHAIN=${STATION_CHAIN:-}
      # Local eth-rpc sidecar: where Station writes the backend it wants the
      # sidecar running on, and reads the sidecar's answer back. Empty unless
      # the wizard provisioned a sidecar, and empty makes the whole subsystem
      # inert — the node behaves exactly as it did before.
      - STATION_ETHRPC_CONTROL_DIR=${STATION_ETHRPC_CONTROL_DIR:-}
      # Update trigger: where Station asks Watchtower to update, and the bearer
      # token it presents. Watchtower is reachable only on station-network.
      - STATION_WATCHTOWER_URL=http://watchtower:8080
      - STATION_WATCHTOWER_TOKEN=${WATCHTOWER_HTTP_API_TOKEN:-}
      - STATION_BOOTSTRAP_PEERS=${STATION_BOOTSTRAP_PEERS}
      - STATION_ANNOUNCE_ADDRS=${STATION_ANNOUNCE_ADDRS}
      - TZ=${TZ:-UTC}

    networks:
      - station-network

    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.station.rule=Host(`${STATION_DOMAIN}`)"
      - "traefik.http.routers.station.entrypoints=websecure"
      - "traefik.http.routers.station.tls=true"
      - "traefik.http.routers.station.tls.certresolver=letsencrypt"
      - "traefik.http.routers.station.service=station"
      - "traefik.http.services.station.loadbalancer.server.port=8080"
      - "traefik.http.services.station.loadbalancer.passhostheader=true"
      - "traefik.http.services.station.loadbalancer.server.scheme=http"
      - "traefik.http.middlewares.station-headers.headers.sslredirect=true"
      - "traefik.http.middlewares.station-headers.headers.stsSeconds=31536000"
      - "traefik.http.middlewares.station-headers.headers.stsIncludeSubdomains=true"
      - "traefik.http.middlewares.station-headers.headers.stsPreload=true"
      - "traefik.http.middlewares.station-headers.headers.forceSTSHeader=true"
      - "traefik.http.middlewares.station-headers.headers.contentTypeNosniff=true"
      - "traefik.http.middlewares.station-headers.headers.browserXssFilter=true"
      - "traefik.http.middlewares.station-headers.headers.referrerPolicy=strict-origin-when-cross-origin"
      - "traefik.http.middlewares.station-headers.headers.frameDeny=true"
      - "traefik.http.routers.station.middlewares=station-headers"
      # WebSocket router for libp2p browser connections (port 9095)
      # Uses header-based routing (Upgrade: websocket) with HTTP/2 disabled
      # Browser multiaddr: /dns4/domain/tcp/443/wss/p2p/...
      - "traefik.http.routers.station-ws.rule=Host(`${STATION_DOMAIN}`) && HeaderRegexp(`Upgrade`, `(?i)websocket`)"
      - "traefik.http.routers.station-ws.entrypoints=websecure"
      - "traefik.http.routers.station-ws.tls=true"
      - "traefik.http.routers.station-ws.tls.certresolver=letsencrypt"
      - "traefik.http.routers.station-ws.tls.options=forcehttp11@file"
      - "traefik.http.routers.station-ws.priority=100"
      - "traefik.http.routers.station-ws.service=station-ws"
      - "traefik.http.services.station-ws.loadbalancer.server.port=9095"
      - "traefik.http.services.station-ws.loadbalancer.server.scheme=http"
      # Watchtower scope label - only update Station, not Traefik
      - "com.centurylinklabs.watchtower.scope=station"

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

    healthcheck:
      disable: true

    depends_on:
      traefik:
        condition: service_healthy
COMPOSE_EOF

    # The heredoc above is quoted, so fill in the image reference afterwards.
    sed -i "s|__STATION_IMAGE__|${STATION_IMAGE}|" docker-compose.yml

    # Add the Watchtower service (always installed; idle until Station asks)
    cat >> docker-compose.yml << 'WATCHTOWER_EOF'

  # Watchtower - Docker Image Updates, on request only
  # Runs in HTTP API update mode: it never polls on its own and updates only
  # when Station calls POST /v1/update with the bearer token. Which updates
  # happen is decided by the update preference in the dashboard. No ports are
  # published: the API is reachable only on station-network.
  # nickfedor/watchtower is the maintained fork; containrrr is archived (2025) and
  # its last image (2023) speaks a Docker API too old for Engine v29+ (client 1.25 < min 1.40).
  watchtower:
    image: nickfedor/watchtower:1.19.0
    container_name: station-watchtower
    restart: unless-stopped

    # NOT :ro — unlike Traefik's docker.sock mount (which only reads
    # container metadata for routing), Watchtower has to stop/recreate
    # containers and pull images, which needs a writable socket. The
    # official containrrr docs mount it read-write; :ro is a documented
    # source of "Restarting" crash-loops for this image.
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

    environment:
      - WATCHTOWER_SCOPE=station
      - WATCHTOWER_HTTP_API_UPDATE=true
      # Required: Watchtower refuses to start with an empty token.
      - WATCHTOWER_HTTP_API_TOKEN=${WATCHTOWER_HTTP_API_TOKEN:?run setup-station.sh to generate the Watchtower token}
      # Explicitly off, so an API-mode Watchtower never updates by itself.
      - WATCHTOWER_HTTP_API_PERIODIC_POLLS=false
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_NO_RESTART=false

    labels:
      - "com.centurylinklabs.watchtower.scope=station"

    networks:
      - station-network

    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "2"
WATCHTOWER_EOF
    print_success "Added Watchtower service to docker-compose.yml"

    # Add the local eth-rpc sidecar if enabled
    if [ "$ENABLE_ETHRPC" = true ]; then
        cat >> docker-compose.yml << 'ETHRPC_EOF'

  # eth-rpc - the artist's own blockchain indexer.
  #
  # This is Station's wrapper image: the pinned upstream eth-rpc binary plus a
  # small supervisor that owns the process. eth-rpc's --node-rpc-url is read
  # once at process start, so changing which Substrate provider it reads from
  # means restarting it — and nothing in Station may talk to the Docker socket.
  # The supervisor watches /control/backend.json and does the restart from
  # inside the container instead. See docs/ETHRPC_ENDPOINT_ARCHITECTURE.md § 7d.
  #
  # No `profiles:` gating and no --node-rpc-url here on purpose: the supervisor
  # idles happily until Station writes a backend, which happens once the artist
  # picks a chain in the dashboard. So this starts with everything else and
  # waits, rather than needing a second `docker compose up` later.
  eth-rpc:
    image: ghcr.io/gotnoshoeson/station:ethrpc-edge
    container_name: station-eth-rpc
    restart: unless-stopped

    # NO ports: — deliberately unpublished. The station container reaches this
    # over the internal bridge as http://eth-rpc:8545, exactly like station's
    # own 8080. Nothing outside the project can reach it, which is also what
    # makes the supervisor's --rpc-cors=all safe (that flag gates Host-header
    # validation, not just browser origins — without it cross-container calls
    # are refused). If a host port is ever published here, revisit that flag.
    volumes:
      - ./data/eth-rpc/db:/data          # eth-rpc.db (+ -wal/-shm)
      - ./data/eth-rpc/control:/control  # backend.json in, backend.status.json out

    # Measured steady state is ~22-45MB RSS and ~0.85% of one core, so these are
    # a blast-radius bound rather than a tight fit.
    mem_limit: 256m
    cpus: 0.5

    # Kept in Watchtower's scope, same as the station container. The two halves
    # share a versioned file contract, so letting them update on the same cycle
    # keeps them in step; pinning one and not the other is what would let them
    # drift apart. A restart is safe by construction — eth-rpc resumes from its
    # sync_state checkpoint and fills exactly the gap.
    labels:
      - "com.centurylinklabs.watchtower.scope=station"

    networks:
      - station-network

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
ETHRPC_EOF
        print_success "Added eth-rpc service to docker-compose.yml"
    fi

    # Top-level networks block MUST be appended last: it has to come after
    # every service (including the Watchtower service above), or
    # whatever service block was last in the file ends up nested under
    # networks: instead of services: (invalid compose, services silently
    # fail to start). See docker-compose.yml networks.watchtower bug.
    cat >> docker-compose.yml << 'NETWORKS_EOF'

networks:
  station-network:
    name: station-network
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
NETWORKS_EOF

    print_success "Created docker-compose.yml"
    echo ""
}

# Use current working directory for all operations
PROJECT_ROOT="$(pwd)"

# With --answers the terminal app has already shown its splash.
[ -n "$ANSWERS_FILE" ] || print_banner

# Setup gum for pretty prompts (installs if needed). Under the terminal app
# the output goes to its log panel, so plain text is used instead.
if [ "${STATION_TUI:-}" = 1 ]; then
    GUM_AVAILABLE=false
else
    setup_gum
fi

if [ -n "$ANSWERS_FILE" ]; then
    load_answers "$ANSWERS_FILE"
    print_info "Using the answers from $ANSWERS_FILE"
fi

# Show welcome message with prerequisites (the terminal app already checked them)
if [ -n "$ANSWERS_FILE" ]; then
    :
elif [ "$GUM_AVAILABLE" = true ]; then
    gum style --border rounded --border-foreground "$COL_MINT" --padding "1 2" --margin "1 0" \
        "This script will set up your QNCH node with HTTPS support." \
        "It requires an internet connection."
    echo ""
    cat << 'PREREQ' | gum format
## Prerequisites

* Ubuntu 20.04/22.04 or Debian 11/12 VPS
* Root or sudo access
* Ports **80**, **443**, **4001**, **4002** accessible from internet
* Domain name pointing to this server (or DuckDNS account)
PREREQ
else
    echo "This script will set up your QNCH node with HTTPS support using Traefik."
    echo "It requires an internet connection."
    echo ""
    echo "Prerequisites:"
    echo "  • Ubuntu 20.04/22.04 or Debian 11/12 VPS"
    echo "  • Root or sudo access"
    echo "  • Ports 80, 443, 4001, 4002 accessible from internet"
    echo "  • Domain name pointing to this server (or DuckDNS account)"
fi
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root or with sudo"
    echo "Please run: sudo $0"
    exit 1
fi

# ============================================================================
# Architecture gate (local eth-rpc)
# ============================================================================
# Runs before any prompt, including the reconfigure check below, so an arm64
# host is told why up front instead of hitting a confusing platform-mismatch
# error deep inside `docker compose up` after the whole wizard has run.
#
# This does NOT abort the install: Station itself is architecture-independent.
# It only decides whether the local eth-rpc option is offered at all, because
# the upstream parity/eth-rpc image is amd64-only across every published tag.
ETHRPC_ARCH_SUPPORTED=true
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64|amd64) ;;
    *)
        ETHRPC_ARCH_SUPPORTED=false
        ;;
esac

# Check if already configured
if [ -f "$PROJECT_ROOT/.env" ]; then
    print_warning "Found existing .env file"
    if [ "$ANSWERS_MODE" = true ]; then
        reconfigure_ok=false; answer_bool RECONFIGURE && reconfigure_ok=true
    elif gum_confirm "Do you want to reconfigure?" "no"; then
        reconfigure_ok=true
    else
        reconfigure_ok=false
    fi
    if [ "$reconfigure_ok" != true ]; then
        print_info "Exiting. To start services, run: docker compose -f docker-compose.yml up -d"
        exit 0
    fi
fi

# ============================================================================
# Step 1: Check and Install Prerequisites
# ============================================================================
tui_stage server

print_step "Checking prerequisites..."
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    print_warning "Docker is not installed"
    echo ""
    if [ "$GUM_AVAILABLE" = true ]; then
        cat << 'DOCKER_INFO' | gum format
This script can install Docker automatically for **Ubuntu/Debian** systems.

Installation will:
* Add Docker's official repository
* Install Docker Engine, CLI, and Compose
* Start Docker service
* Configure automatic startup
DOCKER_INFO
    else
        echo "This script can install Docker automatically for Ubuntu/Debian systems."
        echo ""
        echo "Installation will:"
        echo "  • Add Docker's official repository"
        echo "  • Install Docker Engine, CLI, and Compose"
        echo "  • Start Docker service"
        echo "  • Configure automatic startup"
    fi
    echo ""

    if { [ "$ANSWERS_MODE" = true ] && answer_bool INSTALL_DOCKER; } || \
       { [ "$ANSWERS_MODE" != true ] && gum_confirm "Install Docker automatically?" "yes"; }; then
        if ! install_docker_ubuntu; then
            print_error "Docker installation failed"
            echo ""
            echo "Please install Docker manually and run this script again:"
            echo "  https://docs.docker.com/engine/install/"
            exit 1
        fi
    else
        print_error "Docker is required to continue"
        echo ""
        echo "Install Docker manually:"
        echo "  Ubuntu: https://docs.docker.com/engine/install/ubuntu/"
        echo "  Debian: https://docs.docker.com/engine/install/debian/"
        exit 1
    fi
fi
print_success "Docker installed"

# Check docker compose (plugin version)
if ! docker compose version &> /dev/null; then
    print_error "Docker Compose plugin is not installed"
    echo "This should have been installed with Docker."
    echo ""
    echo "Try: apt-get install docker-compose-plugin"
    exit 1
fi
print_success "Docker Compose installed"

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running"
    echo ""
    echo "Try: systemctl start docker"
    exit 1
fi
print_success "Docker daemon is running"

# Check required commands
for cmd in curl dig; do
    if ! command -v $cmd &> /dev/null; then
        print_warning "$cmd not found, installing..."
        apt-get install -y -qq dnsutils curl
    fi
done

# Check ports
print_info "Checking if required ports are available..."
PORTS_IN_USE=()

for port in 80 443; do
    if timeout 5 ss -tuln 2>/dev/null | grep -q ":$port " || \
       timeout 5 netstat -tuln 2>/dev/null | grep -q ":$port "; then
        PORTS_IN_USE+=($port)
    fi
done

# On a re-run the ports are usually held by this install's own Traefik. That
# is not a conflict: the install replaces that container.
STATION_OWNS_PORTS=false
if [ ${#PORTS_IN_USE[@]} -gt 0 ] && [ -f "$PROJECT_ROOT/.env" ] && \
   [ -n "$(docker ps -q --filter name='^station-traefik$' 2>/dev/null)" ]; then
    STATION_OWNS_PORTS=true
fi

if [ "$STATION_OWNS_PORTS" = true ]; then
    print_success "Ports 80 and 443 are used by your current Station, which this install restarts"
elif [ ${#PORTS_IN_USE[@]} -gt 0 ]; then
    if [ ${#PORTS_IN_USE[@]} -eq 1 ]; then
        print_warning "Another program is using port ${PORTS_IN_USE[0]}"
    else
        print_warning "Another program is using ports ${PORTS_IN_USE[0]} and ${PORTS_IN_USE[1]}"
    fi
    echo ""
    echo "Station needs ports 80 and 443 for HTTPS. This is what is using them:"
    # ERE alternation needs ports joined with "|" (e.g. "80|443"). ${arr[*]}
    # joins with a plain space by default, producing ":(80 443) " — a
    # pattern that greps for the literal substring "80 443" and therefore
    # never matches real ss/netstat output, always falling through to
    # "(could not determine)".
    PORTS_REGEX=$(IFS='|'; echo "${PORTS_IN_USE[*]}")
    timeout 5 ss -tulnp 2>/dev/null | grep -E ":(${PORTS_REGEX}) " || \
    timeout 5 netstat -tulnp 2>/dev/null | grep -E ":(${PORTS_REGEX}) " || \
    echo "  (could not determine)"
    echo ""
    echo "Stop that program, then continue."
    echo ""
    if [ "$ANSWERS_MODE" = true ]; then
        answer_bool STOP_PORT_SERVICES || exit 1
    elif ! gum_confirm "Continue now?" "no"; then
        exit 1
    fi
    # Nothing here stops the program; check whether it was stopped.
    for port in "${PORTS_IN_USE[@]}"; do
        if timeout 5 ss -tuln 2>/dev/null | grep -q ":$port " || \
           timeout 5 netstat -tuln 2>/dev/null | grep -q ":$port "; then
            print_warning "Port $port is still in use; Station will not be able to start until it is free"
        fi
    done
else
    print_success "Ports 80 and 443 are available"
fi

echo ""

# ============================================================================
# Step 2: Domain Configuration
# ============================================================================
tui_stage network

print_step "Domain Configuration"
echo ""

if [ "$ANSWERS_MODE" = true ]; then
    case "$ANS_DOMAIN_TYPE" in
        custom) domain_choice="Own domain" ;;
        duckdns) domain_choice="DuckDNS" ;;
        *) answers_fail "DOMAIN_TYPE must be custom or duckdns" ;;
    esac
else
    domain_choice=$(gum_choose "How would you like to configure your domain?" "Own domain (mymusic.example.com)" "DuckDNS (free dynamic DNS)")
fi

if [[ "$domain_choice" == "Own domain"* ]]; then
    domain_option="1"
else
    domain_option="2"
fi

echo ""

if [ "$domain_option" = "1" ]; then
    # Custom domain
    print_info "Using custom domain"
    echo ""
    if [ "$GUM_AVAILABLE" = true ]; then
        cat << 'DOMAIN_REQ' | gum format
Your domain must:
* Have an **A record** pointing to this server's IP
* Be accessible from the internet
* DNS propagation must be complete _(can take 5-60 minutes)_
DOMAIN_REQ
    else
        echo "Your domain must:"
        echo "  • Have an A record pointing to this server's IP address"
        echo "  • Be accessible from the internet"
        echo "  • DNS propagation must be complete (can take 5-60 minutes)"
    fi
    echo ""

    # Get this server's public IP
    # Trailing `|| true` in both branches: if BOTH IP-echo services are
    # unreachable, the last command in the `||` chain fails and, under
    # set -e, `SERVER_IP=$(...)` failing would abort the whole script —
    # skipping the manual-entry fallback right below this. `|| true` makes
    # the substitution always "succeed" (with an empty SERVER_IP), which is
    # exactly what that fallback already expects and handles.
    if [ "$GUM_AVAILABLE" = true ]; then
        SERVER_IP=$(gum spin --spinner dot --title "Detecting server's public IP..." -- bash -c 'curl -s https://api.ipify.org || curl -s https://ifconfig.me || true')
    else
        print_step "Detecting server's public IP address..."
        SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || true)
    fi

    if [ -z "$SERVER_IP" ]; then
        print_warning "Could not auto-detect public IP"
        if [ "$ANSWERS_MODE" = true ]; then
            [ -n "$ANS_SERVER_IP" ] || answers_fail "this server's public IP could not be detected and none was given"
            SERVER_IP="$ANS_SERVER_IP"
        else
            SERVER_IP=$(gum_input "Enter this server's public IP address:" "192.168.1.1")
        fi
    else
        print_success "Server IP: $SERVER_IP"
    fi
    echo ""

    while true; do
        if [ "$ANSWERS_MODE" = true ]; then
            STATION_DOMAIN="$ANS_STATION_DOMAIN"
        else
            STATION_DOMAIN=$(gum_input "Enter your domain:" "mymusic.example.com")
        fi

        # Validate domain format
        if [[ ! "$STATION_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid domain format"
            [ "$ANSWERS_MODE" = true ] && exit 1
            continue
        fi

        # Check DNS resolution
        print_info "Checking DNS resolution for $STATION_DOMAIN..."
        DOMAIN_IP=$(dig +short "$STATION_DOMAIN" A | tail -n1)

        if [ -z "$DOMAIN_IP" ]; then
            print_error "Domain does not resolve to any IP address"
            echo "Please configure your DNS A record and wait for propagation."
            echo ""
            if [ "$GUM_AVAILABLE" = true ]; then
                gum style --border rounded --border-foreground "$COL_WARN" --padding "1 2" \
                    "DNS Configuration" \
                    "" \
                    "Type:   A" \
                    "Name:   $STATION_DOMAIN" \
                    "Value:  $SERVER_IP" \
                    "TTL:    300 (5 minutes)"
            else
                echo "DNS Configuration:"
                echo "  Type: A"
                echo "  Name: $STATION_DOMAIN"
                echo "  Value: $SERVER_IP"
                echo "  TTL: 300 (5 minutes)"
            fi
            echo ""
            if [ "$ANSWERS_MODE" = true ] || ! gum_confirm "Try again after configuring DNS?" "yes"; then
                exit 1
            fi
            continue
        fi

        if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
            print_error "DNS mismatch!"
            echo "  Domain $STATION_DOMAIN points to: $DOMAIN_IP"
            echo "  This server's IP is: $SERVER_IP"
            echo ""
            echo "Please update your DNS A record to point to $SERVER_IP"
            echo "and wait 5-15 minutes for propagation."
            echo ""
            if [ "$ANSWERS_MODE" = true ]; then
                answer_bool DNS_MISMATCH_OK || exit 1
            elif ! gum_confirm "Continue anyway? (not recommended)" "no"; then
                continue
            fi
        else
            print_success "DNS correctly configured: $STATION_DOMAIN → $SERVER_IP"
        fi

        break
    done

    DOMAIN_TYPE="custom"

else
    # DuckDNS
    print_info "Using DuckDNS"
    echo ""
    echo "DuckDNS Setup:"
    echo "  1. Visit https://www.duckdns.org/"
    echo "  2. Sign in (Twitter, GitHub, Google, etc.)"
    echo "  3. Create a subdomain (e.g., 'myband')"
    echo "  4. Copy your token from the top of the page"
    echo ""

    if [ "$ANSWERS_MODE" != true ] && ! gum_confirm "Have you created a DuckDNS account and subdomain?" "no"; then
        echo ""
        print_info "Please visit https://www.duckdns.org/ to create a free account."
        print_info "Then run this script again."
        exit 1
    fi

    echo ""
    if [ "$ANSWERS_MODE" = true ]; then
        DUCKDNS_SUBDOMAIN="$ANS_DUCKDNS_SUBDOMAIN"
    else
        DUCKDNS_SUBDOMAIN=$(gum_input "Enter your DuckDNS subdomain:" "myband")
    fi

    # Remove .duckdns.org if user included it
    DUCKDNS_SUBDOMAIN=${DUCKDNS_SUBDOMAIN%.duckdns.org}

    if [ "$ANSWERS_MODE" = true ]; then
        DUCKDNS_TOKEN="$ANS_DUCKDNS_TOKEN"
    else
        DUCKDNS_TOKEN=$(gum_input "Enter your DuckDNS token:" "your-token-here")
    fi

    STATION_DOMAIN="${DUCKDNS_SUBDOMAIN}.duckdns.org"

    # Update DuckDNS with current IP
    print_step "Updating DuckDNS IP address..."
    DUCKDNS_RESPONSE=$(curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=")

    if [ "$DUCKDNS_RESPONSE" = "OK" ]; then
        print_success "DuckDNS updated successfully"

        # Wait a moment and verify
        sleep 2
        DOMAIN_IP=$(dig +short "$STATION_DOMAIN" A | tail -n1)
        if [ -n "$DOMAIN_IP" ]; then
            print_success "DuckDNS domain resolves to: $DOMAIN_IP"
        fi
    else
        print_error "Failed to update DuckDNS (response: $DUCKDNS_RESPONSE)"
        echo "Please check your subdomain and token."
        exit 1
    fi

    DOMAIN_TYPE="duckdns"
fi

echo ""

# ============================================================================
# Step 3: Email Configuration
# ============================================================================

print_step "Email Configuration"
echo ""
echo "Let's Encrypt will send certificate expiration notices to this email."
echo "This is optional but recommended in case auto-renewal fails."
echo ""

if [ "$ANSWERS_MODE" = true ]; then
    ACME_EMAIL="$ANS_ACME_EMAIL"
else
    ACME_EMAIL=$(gum_input "Enter email address:" "your@email.com")
fi

if [ -z "$ACME_EMAIL" ] || [ "$ACME_EMAIL" = "your@email.com" ]; then
    ACME_EMAIL="admin@${STATION_DOMAIN}"
    print_warning "Using placeholder email: $ACME_EMAIL"
    print_info "You can update this in .env later"
fi

echo ""

# ============================================================================
# Step 4: ACME Environment
# ============================================================================

print_step "Certificate Generation"
echo ""

# Always use Let's Encrypt production certificates. Staging certs are signed by
# a CA browsers reject, so the listener app can't reach a staging node.
ACME_PRODUCTION="true"
print_info "Using Let's Encrypt production certificates (trusted, no browser warnings)."
print_info "Let's Encrypt limits you to 5 duplicate certificates per week."

echo ""

# ============================================================================
# Step 5b: Local eth-rpc adapter
# ============================================================================
ENABLE_ETHRPC=false
if [ "$ETHRPC_ARCH_SUPPORTED" = true ]; then
    print_step "Your own blockchain indexer"
    echo ""
    if [ "$GUM_AVAILABLE" = true ]; then
        cat << 'ETHRPC_INFO' | gum format
Station can run its own **blockchain indexer** alongside your node, so the
record of your sales lives on your own server instead of depending entirely on
someone else's.

* Uses about 45MB of memory and well under 1% of a CPU core
* Reads from free public providers — no account, no API key, nothing to pay for
* If one provider goes down, your node moves to the next one on its own
* Falls back to public indexers automatically if you skip this
ETHRPC_INFO
    else
        echo "Station can run its own blockchain indexer, so the record of your"
        echo "sales lives on your own server rather than someone else's."
        echo ""
        echo "  - About 45MB of memory, well under 1% of a CPU core"
        echo "  - Reads from free public providers (no account or API key)"
        echo "  - Moves to another provider on its own if one goes down"
        echo "  - Falls back to public indexers automatically if you skip this"
    fi
    echo ""
    if { [ "$ANSWERS_MODE" = true ] && answer_bool ENABLE_ETHRPC; } || \
       { [ "$ANSWERS_MODE" != true ] && gum_confirm "Run your own blockchain indexer?" "yes"; }; then
        ENABLE_ETHRPC=true
        print_success "Your node will run its own indexer"
    else
        print_info "Skipping. Your node will use public indexers."
    fi
else
    print_info "Skipping the local blockchain indexer: it is only published for x86_64, and this machine is $HOST_ARCH."
    print_info "Station itself runs fine here — your node will use public indexers instead."
fi
echo ""

# ============================================================================
# Step 5c: Joining the network (entry node)
# ============================================================================
# Is this a plausible libp2p peer ID? Checked locally: base58 alphabet only,
# and the exact length of an Ed25519 ID (12D3KooW... = 52 chars) or a legacy
# SHA-256 ID (Qm... = 46 chars). Catches typos and truncated or padded IDs;
# it cannot tell a made-up ID of the right shape from a real one (the node
# image's own check, below, can).
valid_peer_id_shape() {
    local id="$1"
    [[ "$id" =~ ^[1-9A-HJ-NP-Za-km-z]+$ ]] || return 1
    if [[ "$id" == 12D3KooW* ]]; then
        [ "${#id}" -eq 52 ]
    elif [[ "$id" == Qm* ]]; then
        [ "${#id}" -eq 46 ]
    else
        return 1
    fi
}

# Validate and tidy a comma-separated list of libp2p multiaddrs. Prints the
# cleaned list (whitespace trimmed, empty entries dropped, joined by ",") and
# returns 0 when every entry passes the local check; returns 1 otherwise.
# Local check: starts with "/", ends in /p2p/<peer ID> where the ID passes
# valid_peer_id_shape, and contains "/tcp/" or "/udp/". The authoritative
# check is the node image's (check_node_addr_with_image).
normalize_node_addrs() {
    local raw="$1" part out=""
    local -a parts
    IFS=',' read -r -a parts <<< "$raw"
    for part in "${parts[@]}"; do
        # Trim leading/trailing whitespace
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [ -z "$part" ] && continue
        [[ "$part" == /* ]] || return 1
        [[ "$part" =~ /p2p/([A-Za-z0-9]+)$ ]] || return 1
        valid_peer_id_shape "${BASH_REMATCH[1]}" || return 1
        [[ "$part" == */tcp/* || "$part" == */udp/* ]] || return 1
        out="${out:+$out,}$part"
    done
    echo "$out"
}

# ---- Node image address check ------------------------------------------------
# The Station image validates an address properly (multiaddr parse, real peer
# ID decode). ONE-LINE CHANGE POINT: if the subcommand is renamed, edit this.
NODE_ADDR_CHECK_CMD="station check-addr"

# Run the image's check on one address. Returns 0 = valid, 1 = invalid (reason
# in NODE_ADDR_REASON), 2 = could not check (no image, old image, timeout,
# unexpected output) so the caller relies on the local check alone. An old
# image without the subcommand would START A NODE, hence the timeout and fixed
# name; a rejection only counts if it is a single line of output.
NODE_ADDR_REASON=""
NODE_ADDR_IMAGE_READY=""
check_node_addr_with_image() {
    local addr="$1" out rc
    NODE_ADDR_REASON=""
    if [ -z "$NODE_ADDR_IMAGE_READY" ]; then
        if docker image inspect "$STATION_IMAGE" >/dev/null 2>&1 || docker pull -q "$STATION_IMAGE" >/dev/null 2>&1; then
            NODE_ADDR_IMAGE_READY=yes
        else
            NODE_ADDR_IMAGE_READY=no
        fi
    fi
    [ "$NODE_ADDR_IMAGE_READY" = yes ] || return 2
    # $NODE_ADDR_CHECK_CMD is deliberately unquoted (command plus subcommand).
    # shellcheck disable=SC2086
    rc=0
    out=$(timeout 20 docker run --rm --name station-addr-check "$STATION_IMAGE" $NODE_ADDR_CHECK_CMD "$addr" 2>&1) || rc=$?
    docker rm -f station-addr-check >/dev/null 2>&1 || true
    case "$rc" in
        0) return 0 ;;
        1)
            out="${out%$'\r'}"
            if [ -n "$out" ] && [[ "$out" != *$'\n'* ]]; then
                NODE_ADDR_REASON="$out"
                return 1
            fi
            return 2
            ;;
        *) return 2 ;;
    esac
}

# Validate a comma-separated address list: local shape check first (fast, no
# Docker), then the image's check on each entry. Sets NODE_ADDR_VALUE (cleaned
# list, empty = none) and, on failure, NODE_ADDR_REASON. Call directly, not in
# $(...), so the globals survive. Returns 0 valid, 1 invalid.
NODE_ADDR_VALUE=""
validate_node_addrs() {
    local raw="$1" cleaned addr rc
    local -a addrs
    NODE_ADDR_VALUE=""
    NODE_ADDR_REASON=""
    if ! cleaned=$(normalize_node_addrs "$raw"); then
        return 1
    fi
    if [ -n "$cleaned" ]; then
        IFS=',' read -r -a addrs <<< "$cleaned"
        for addr in "${addrs[@]}"; do
            rc=0
            check_node_addr_with_image "$addr" || rc=$?
            if [ "$rc" -eq 1 ]; then
                return 1
            fi
        done
    fi
    NODE_ADDR_VALUE="$cleaned"
    return 0
}

# Ask for a node address until it is valid or left empty (Enter = none).
# Sets BOOTSTRAP_PEERS_VALUE (empty = none).
prompt_node_address() {
    local node_addr_input
    if [ "$ANSWERS_MODE" = true ]; then
        if validate_node_addrs "$ANS_BOOTSTRAP_PEERS_VALUE"; then
            BOOTSTRAP_PEERS_VALUE="$NODE_ADDR_VALUE"
            return 0
        fi
        answers_fail "BOOTSTRAP_PEERS_VALUE is not a valid node address${NODE_ADDR_REASON:+: $NODE_ADDR_REASON}"
    fi
    while true; do
        node_addr_input=$(gum_input "Node address:" "/dns4/artist.example.com/tcp/443/wss/p2p/12D3KooW...")
        if validate_node_addrs "$node_addr_input"; then
            BOOTSTRAP_PEERS_VALUE="$NODE_ADDR_VALUE"
            return 0
        fi
        print_error "That doesn't look like a node address. It should look like: /dns4/artist.example.com/tcp/443/wss/p2p/12D3KooW..."
        if [ -n "$NODE_ADDR_REASON" ]; then print_info "$NODE_ADDR_REASON"; fi
    done
}

# Accept the output of `station bootstrap-peers` only if every non-empty line
# looks like a multiaddr ("/" first, contains "/p2p/"). Prints the non-empty
# lines and returns 0 (an empty list is valid: prints nothing, returns 0);
# returns 1 for anything else, e.g. the log lines a starting node would print.
parse_bootnode_list() {
    local line
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == /* && "$line" == */p2p/* ]] || return 1
        echo "$line"
    done <<< "$1"
    return 0
}

# Is one bootnode address reachable?
#  /dns4|dns|dns6/<host>/tcp/443/wss/p2p/<id>: GET https://<host>/api/v1/node/info
#     (8s timeout, one retry); reachable only if the body contains that peer ID.
#  Any other shape with a /tcp/ port: plain TCP connect to host:port (5s).
#  Anything else (e.g. UDP-only) cannot be tested here and counts as unreachable.
bootnode_addr_reachable() {
    local addr="$1" host port id body attempt
    if [[ "$addr" =~ ^/(dns4|dns6|dns)/([^/]+)/tcp/443/wss/p2p/([A-Za-z0-9]+)$ ]]; then
        host="${BASH_REMATCH[2]}"
        id="${BASH_REMATCH[3]}"
        for attempt in 1 2; do
            body=$(curl -fsS -m 8 "https://${host}/api/v1/node/info" 2>/dev/null || true)
            if [ -n "$body" ] && grep -qF -- "$id" <<< "$body"; then
                return 0
            fi
        done
        return 1
    fi
    if [[ "$addr" =~ ^/(ip4|ip6|dns4|dns6|dns)/([^/]+)/tcp/([0-9]+) ]]; then
        host="${BASH_REMATCH[2]}"
        port="${BASH_REMATCH[3]}"
        timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" >/dev/null 2>&1
        return $?
    fi
    return 1
}

# The bootnode counts as reachable if ANY address in the (newline-separated)
# list passes.
bootnodes_reachable() {
    local addr
    while IFS= read -r addr; do
        [ -z "$addr" ] && continue
        if bootnode_addr_reachable "$addr"; then
            return 0
        fi
    done <<< "$1"
    return 1
}

# Ask the Station image which bootnodes this network has built in. Sets
# BUILTIN_BOOTNODES (newline-separated, possibly empty) and returns 0, or
# returns 1 for "could not determine" (pull failed, timeout, nonzero exit, or
# output that isn't a list). An image older than the `bootstrap-peers`
# subcommand would ignore it and START A NODE, hence the timeout, the probe
# container's fixed name (so it can be removed), and the strict output check.
BUILTIN_BOOTNODES=""
fetch_builtin_bootnodes() {
    local out
    BUILTIN_BOOTNODES=""
    gum_spin "Fetching Station..." docker pull -q "$STATION_IMAGE" || return 1
    if ! out=$(timeout 20 docker run --rm --name station-bootnode-probe \
            -e STATION_NETWORK="$NETWORK" "$STATION_IMAGE" station bootstrap-peers 2>/dev/null); then
        docker rm -f station-bootnode-probe >/dev/null 2>&1 || true
        return 1
    fi
    BUILTIN_BOOTNODES=$(parse_bootnode_list "$out") || return 1
}

# BOOTSTRAP_PEERS_VALUE stays empty (STATION_BOOTSTRAP_PEERS unset, node uses
# its built-in list) unless an address is saved or entered below.
BOOTSTRAP_PEERS_VALUE=""
ENTRY_NODE_SUMMARY="built-in"

EXISTING_BOOTSTRAP=""
if [ -f "$PROJECT_ROOT/.env" ]; then
    EXISTING_BOOTSTRAP=$(grep -E '^STATION_BOOTSTRAP_PEERS=.+' "$PROJECT_ROOT/.env" | head -n1 | cut -d= -f2- || true)
fi

print_step "Joining the network"
echo ""
if [ -n "$EXISTING_BOOTSTRAP" ]; then
    # Re-run over an existing install with a saved entry node. A saved "none"
    # (bootstrap disabled) is a valid value; anything else is re-checked.
    # (No saved line at all means the built-in list: that path is below.)
    SAVED_OK=true
    if [ "$EXISTING_BOOTSTRAP" != "none" ]; then
        if ! validate_node_addrs "$EXISTING_BOOTSTRAP"; then
            SAVED_OK=false
        fi
    fi
    if [ "$SAVED_OK" = true ]; then
        print_info "Your saved entry node is: $EXISTING_BOOTSTRAP"
        KEEP_PROMPT="Keep this entry node?"
        KEEP_DEFAULT=yes
    else
        print_warning "Your saved entry node doesn't look like a valid node address: $EXISTING_BOOTSTRAP"
        if [ -n "$NODE_ADDR_REASON" ]; then print_info "$NODE_ADDR_REASON"; fi
        KEEP_PROMPT="Keep it anyway?"
        KEEP_DEFAULT=no
    fi
    if { [ "$ANSWERS_MODE" = true ] && answer_bool KEEP_SAVED_BOOTNODE; } || \
       { [ "$ANSWERS_MODE" != true ] && gum_confirm "$KEEP_PROMPT" "$KEEP_DEFAULT"; }; then
        BOOTSTRAP_PEERS_VALUE="$EXISTING_BOOTSTRAP"
        ENTRY_NODE_SUMMARY="$EXISTING_BOOTSTRAP"
        print_info "Keeping your saved entry node: $EXISTING_BOOTSTRAP"
    else
        # No address means the network's built-in bootnode list (founder,
        # 2026-10-25): the saved line is dropped and the node uses that list.
        HAS_BUILTIN=false
        if fetch_builtin_bootnodes && [ -n "$BUILTIN_BOOTNODES" ]; then
            HAS_BUILTIN=true
            echo "Paste a node address from another Station node's dashboard (Settings), or press Enter to use Station's built-in bootnode."
        else
            echo "Paste a node address from another Station node's dashboard (Settings), or press Enter to continue without one."
        fi
        echo ""
        prompt_node_address
        if [ -n "$BOOTSTRAP_PEERS_VALUE" ]; then
            ENTRY_NODE_SUMMARY="$BOOTSTRAP_PEERS_VALUE"
            print_success "Your node will join the network through: $BOOTSTRAP_PEERS_VALUE"
        elif [ "$HAS_BUILTIN" = true ]; then
            ENTRY_NODE_SUMMARY="built-in"
            print_info "Your node will join the network through Station's built-in bootnode."
        else
            ENTRY_NODE_SUMMARY="none yet"
            print_warning "Your node will start, but it won't be on the network until you add a node address. To add one later, run this installer again."
        fi
    fi
elif fetch_builtin_bootnodes; then
    BOOTNODE_LIST_EMPTY=false
    [ -z "$BUILTIN_BOOTNODES" ] && BOOTNODE_LIST_EMPTY=true

    if [ "$BOOTNODE_LIST_EMPTY" = false ] && bootnodes_reachable "$BUILTIN_BOOTNODES"; then
        print_success "Station's bootnode is reachable."
    else
        if [ "$BOOTNODE_LIST_EMPTY" = true ]; then
            echo "This network has no built-in bootnode yet."
        else
            echo "Station's original bootnode cannot be reached, but you can still join the network."
        fi
        echo "Your node can join through any other Station node instead. Ask an artist who runs one to open their dashboard, go to Settings, and copy their Node address."
        echo "Paste it here, or press Enter to continue without one and add it later."
        echo ""
        prompt_node_address
        if [ -n "$BOOTSTRAP_PEERS_VALUE" ]; then
            ENTRY_NODE_SUMMARY="$BOOTSTRAP_PEERS_VALUE"
            print_success "Your node will join the network through: $BOOTSTRAP_PEERS_VALUE"
        else
            ENTRY_NODE_SUMMARY="none yet"
            if [ "$BOOTNODE_LIST_EMPTY" = true ]; then
                print_warning "Your node will start, but it won't be on the network until you add a node address. To add one later, run this installer again."
            else
                print_warning "Your node will start, but it won't be on the network until the original bootnode is back or you add a node address. To add one later, run this installer again."
            fi
        fi
    fi
fi
echo ""

# ============================================================================
# Step 6: Create Directory Structure
# ============================================================================
tui_stage config

print_step "Setting up directories..."

cd "$PROJECT_ROOT"

mkdir -p data
mkdir -p traefik
mkdir -p logs

# Local eth-rpc sidecar directories, created before the chown below so the
# existing recursive `chown -R 1000:1000 data` covers them with no extra step.
# The wrapper image deliberately runs as UID 1000 (not the upstream image's
# 1001) precisely so both containers share these at ordinary permissions.
if [ "$ENABLE_ETHRPC" = true ]; then
    mkdir -p data/eth-rpc/db
    mkdir -p data/eth-rpc/control
fi

# The station container runs as a non-root user, UID:GID 1000:1000 (see
# Dockerfile: `addgroup -g 1000 station && adduser -u 1000 -G station`).
# ./data is bind-mounted over the image's own /data, which shadows whatever
# ownership the image set internally — the HOST directory's ownership is what
# actually governs write access at runtime. Without this, station's identity
# key / catalog / SQLite writes fail with a permission error (this directory
# is created by this script running as root, so it defaults to root:root).
chown -R 1000:1000 data

# Initialize acme.json with correct permissions
touch traefik/acme.json
chmod 600 traefik/acme.json

print_success "Created directory structure"
echo ""

# ============================================================================
# Step 7: Generate Docker Compose Configuration
# ============================================================================

generate_docker_compose

# ============================================================================
# Step 8: Generate Traefik and .env Configuration Files
# ============================================================================

print_step "Generating configuration files..."

print_info "Target environment: $NETWORK"
if [ -n "$CHAIN" ]; then
    print_info "Chain override: $CHAIN"
else
    print_info "Chain: not set — pick your chain from the artist dashboard after first login"
fi

# Chain override line: written live only when --chain was passed, otherwise
# left commented out (discoverable, but the dashboard picker stays in charge).
if [ -n "$CHAIN" ]; then
    CHAIN_LINE="STATION_CHAIN=$CHAIN"
else
    CHAIN_LINE="# STATION_CHAIN="
fi

# Generate .env file
# Only point Station at a control directory when a sidecar actually exists.
if [ "$ENABLE_ETHRPC" = true ]; then
    ETHRPC_CONTROL_LINE="/data/eth-rpc/control"
else
    ETHRPC_CONTROL_LINE=""
fi

# Watchtower HTTP API token: Station presents it to ask Watchtower for an
# update. Keep the existing one when re-running over an old .env so an
# installed node is not rotated out from under its running containers.
WATCHTOWER_TOKEN=""
if [ -f .env ]; then
    WATCHTOWER_TOKEN=$(grep -E '^WATCHTOWER_HTTP_API_TOKEN=.+' .env | head -n1 | cut -d= -f2-)
fi
if [ -z "$WATCHTOWER_TOKEN" ]; then
    if command -v openssl &> /dev/null; then
        WATCHTOWER_TOKEN=$(openssl rand -hex 32)
    else
        WATCHTOWER_TOKEN=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
fi

# Only written (uncommented) when the wizard saved or kept an entry node;
# otherwise the line stays commented and the node uses its built-in list.
BOOTSTRAP_PEERS_LINE=""
if [ -n "$BOOTSTRAP_PEERS_VALUE" ]; then
    BOOTSTRAP_PEERS_LINE=$'\n'"STATION_BOOTSTRAP_PEERS=$BOOTSTRAP_PEERS_VALUE"
fi

cat > .env << EOF
# Station Domain Configuration
STATION_DOMAIN=$STATION_DOMAIN

# Let's Encrypt Email
ACME_EMAIL=$ACME_EMAIL

# Certificate Mode (always production; Let's Encrypt trusted certs)
ACME_PRODUCTION=$ACME_PRODUCTION

# Station Configuration
# NOTE: not read by the binary today (no consumer in cmd/station or pkg/) —
# left in place as a documented, currently-inert knob rather than silently
# dropped. The data directory is fixed to /data via docker-compose.yml's
# station service command (--data-dir flag), not an env var here.
STATION_LOG_LEVEL=info

# Environment: production (mainnet directory) | testnet | local
# Set by setup-station.sh --network; selects the P2P directory this node
# joins (/station, /station/testnet, or /station/local). Does NOT select
# the chain — see STATION_CHAIN below.
STATION_NETWORK=$NETWORK

# Chain override (optional): polkadot-hub | kusama-hub | paseo | local | local-dummy
# Set by setup-station.sh --chain. Leave unset (commented out) to pick your
# chain from the artist dashboard on first login — that's the normal path.
# Only automation/scripted setups (CI, local multi-node testing) should set
# this directly. A chain that doesn't belong to STATION_NETWORK's environment
# is silently ignored by the node (falls back to chain-less).
$CHAIN_LINE

# Local eth-rpc sidecar control directory (inside the station container).
# Set only when the wizard provisioned the sidecar. Empty or unset makes the
# whole local-indexer subsystem inert, which is the correct state for a node
# that uses public indexers.
STATION_ETHRPC_CONTROL_DIR=$ETHRPC_CONTROL_LINE

# Watchtower HTTP API token. Station sends it as a bearer token to ask
# Watchtower for an update; Watchtower only listens on the internal Docker
# network and never updates on its own timer. Treat it like a password.
WATCHTOWER_HTTP_API_TOKEN=$WATCHTOWER_TOKEN

# Bootstrap peers (comma-separated multiaddrs) — OVERRIDE ONLY.
# Leave unset to use the network's built-in seeds (from the committed profile).
# Set this to point at a custom seed, or to "none" to disable bootstrap
# (the first bootnode of a network runs with no seeds — it IS the seed).
# STATION_BOOTSTRAP_PEERS=$BOOTSTRAP_PEERS_LINE

# Public announce address for DHT (derived from domain)
# This tells other peers how to reach this node through Traefik
STATION_ANNOUNCE_ADDRS=/dns4/$STATION_DOMAIN/tcp/443/wss

# Timezone
TZ=UTC
EOF

# Add DuckDNS config if used
if [ "$DOMAIN_TYPE" = "duckdns" ]; then
    cat >> .env << EOF

# DuckDNS Configuration
DUCKDNS_SUBDOMAIN=$DUCKDNS_SUBDOMAIN
DUCKDNS_TOKEN=$DUCKDNS_TOKEN
EOF
fi

print_success "Created .env"

# Generate traefik.yml with Let's Encrypt production CA server
CA_SERVER="https://acme-v02.api.letsencrypt.org/directory"

cat > traefik/traefik.yml << EOF
# Traefik Static Configuration
# Generated by Station setup script

global:
  checkNewVersion: true
  sendAnonymousUsage: false

# API and Dashboard (disabled for security)
api:
  dashboard: false
  debug: false

# Logging - use Docker's log driver instead of files
log:
  level: INFO
  format: json

accessLog:
  format: json

# Entry Points
entryPoints:
  # HTTP - port 80 (redirects to HTTPS)
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  # HTTPS - port 443
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
        # Use forcehttp11 TLS option to disable HTTP/2 for WebSocket compatibility
        # Must use @file suffix because TLS options are loaded from dynamic config
        options: forcehttp11@file

# Ping endpoint for health checks
ping:
  entryPoint: web

# Docker provider for auto-discovery
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: station-network
    watch: true
  # File provider for dynamic TLS options
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

# Certificate Resolver - Let's Encrypt
certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL}
      storage: /acme.json
      caServer: $CA_SERVER
      httpChallenge:
        entryPoint: web

EOF

print_success "Created traefik/traefik.yml"

# Create dynamic.yml for TLS options
# TLS options with alpnProtocols MUST be in dynamic configuration, not static
cat > traefik/dynamic.yml << 'EOF'
# Traefik Dynamic Configuration - TLS Options
# Force HTTP/1.1 via ALPN to ensure WebSocket Upgrade headers work correctly
# HTTP/2 uses RFC 8441 Extended CONNECT instead of Upgrade headers,
# which breaks header-based WebSocket routing rules

tls:
  options:
    forcehttp11:
      alpnProtocols:
        - http/1.1
EOF

print_success "Created traefik/dynamic.yml"
echo ""

# ============================================================================
# Step 9: Display Configuration Summary
# ============================================================================

print_step "Configuration Summary"
echo ""
if [ "$GUM_AVAILABLE" = true ]; then
    gum style --border rounded --border-foreground "$COL_MINT" --padding "1 2" \
        "Domain:           $STATION_DOMAIN" \
        "Email:            $ACME_EMAIL" \
        "Certificate:      Production" \
        "Domain Type:      $DOMAIN_TYPE" \
        "Entry node:       $ENTRY_NODE_SUMMARY"
else
    echo "  Domain:              $STATION_DOMAIN"
    echo "  Email:               $ACME_EMAIL"
    echo "  Certificate Mode:    Production"
    echo "  Domain Type:         $DOMAIN_TYPE"
    echo "  Entry Node:          $ENTRY_NODE_SUMMARY"
fi
echo ""

# ============================================================================
# Step 10: Start Services
# ============================================================================
tui_stage containers

print_step "Starting Station and Traefik..."
echo ""

if [ "$GUM_AVAILABLE" = true ]; then
    cat << 'STARTUP' | gum format
## Starting services...

1. Pull Docker images (if needed)
2. Start Traefik reverse proxy
3. Start Station node
4. Request SSL certificate
STARTUP
else
    echo "This will:"
    echo "  1. Pull Docker images (if needed)"
    echo "  2. Start Traefik reverse proxy"
    echo "  3. Start Station node"
    echo "  4. Request SSL certificate from Let's Encrypt"
fi
echo ""

# Start services using production config (without override)
# The -f flag ensures we ONLY use docker-compose.yml (not the local dev override)
gum_spin "Starting Docker services..." docker compose -f docker-compose.yml up -d

echo ""
print_info "Waiting for Traefik to be ready..."

# Wait for Traefik to be ready (max 30 seconds)
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if docker exec station-traefik traefik healthcheck --ping &> /dev/null; then
        print_success "Traefik is ready"
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
    echo -n "."
done

if [ $attempt -eq $max_attempts ]; then
    print_warning "Traefik health check timed out (but may still be working)"
    echo "Check logs: docker compose -f docker-compose.yml logs traefik"
fi

echo ""
echo ""
tui_stage certificate
print_info "Waiting for certificate provisioning..."
echo "This can take 30-90 seconds while Let's Encrypt validates your domain..."
echo ""

# Wait for certificate (max 2 minutes)
max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if grep -q "\"$STATION_DOMAIN\"" traefik/acme.json 2>/dev/null; then
        print_success "Certificate provisioned successfully!"
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
    if [ $((attempt % 10)) -eq 0 ]; then
        echo -n "."
    fi
done

echo ""

if [ $attempt -eq $max_attempts ]; then
    print_warning "Certificate provisioning is taking longer than expected"
    echo ""
    echo "This can happen if:"
    echo "  • DNS propagation is still in progress"
    echo "  • Port 80 is not accessible from internet"
    echo "  • Domain doesn't point to this server"
    echo ""
    echo "Check logs: docker compose -f docker-compose.yml logs traefik"
else
    echo ""
fi

# ============================================================================
# Step 11: Wait for Station to be Ready
# ============================================================================
tui_stage node

print_info "Waiting for Station to start..."

max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    # Check if Station container is running
    if docker compose -f docker-compose.yml ps station 2>/dev/null | grep -q "Up"; then
        # Try to access the health endpoint through Traefik
        if curl -sf -k "https://$STATION_DOMAIN/health" > /dev/null 2>&1; then
            print_success "Station is ready"
            break
        fi
    fi
    attempt=$((attempt + 1))
    sleep 1
    if [ $((attempt % 5)) -eq 0 ]; then
        echo -n "."
    fi
done

echo ""

if [ $attempt -eq $max_attempts ]; then
    print_warning "Station is taking longer than expected to start"
    echo "You can check status with: docker compose -f docker-compose.yml logs station"
    echo ""
fi

# ============================================================================
# Step 12: Extract Setup PIN from Station Logs
# ============================================================================
tui_stage login

print_step "Retrieving setup PIN from Station..."

# Give Station a moment to generate and log the PIN
sleep 3

# A node only has a setup PIN until its login exists. On a re-run over an
# install that already has one, say so instead of looking for a PIN.
SETUP_DONE=false
AUTH_STATUS=""
for _ in 1 2 3 4 5; do
    AUTH_STATUS=$(docker compose -f docker-compose.yml exec -T station \
        wget -qO- http://127.0.0.1:8080/api/auth/status 2>/dev/null || true)
    [ -n "$AUTH_STATUS" ] && break
    sleep 2
done
if [[ "$AUTH_STATUS" == *'"setup_complete":true'* ]]; then
    SETUP_DONE=true
fi

# Extract PIN from logs - look for the PIN pattern (XXX-XXX)
if [ "$SETUP_DONE" = true ]; then
    SETUP_PIN=""
else
SETUP_PIN=$(docker compose -f docker-compose.yml logs station 2>&1 | \
    grep -E "^\s*[0-9]{3}-[0-9]{3}\s*$" | \
    tr -d ' ' | \
    tail -n 1)

if [ -z "$SETUP_PIN" ]; then
    # Try alternative pattern - look for line after "Enter this PIN:"
    # Use grep -o to extract only the PIN, not the container prefix
    SETUP_PIN=$(docker compose -f docker-compose.yml logs station 2>&1 | \
        grep -A 1 "Enter this PIN" | \
        grep -oE "[0-9]{3}-[0-9]{3}" | \
        tail -n 1)
fi

fi

if [ "$SETUP_DONE" = true ]; then
    print_success "Your login is already set up"
elif [ -z "$SETUP_PIN" ]; then
    print_warning "Could not automatically retrieve PIN"
    SETUP_PIN="(check logs - see troubleshooting below)"
else
    print_success "PIN retrieved successfully"
fi

echo ""

# ============================================================================
# Step 13: Final Status and Next Steps
# ============================================================================
tui_result "domain=$STATION_DOMAIN"
if [ "$SETUP_DONE" = true ]; then
    tui_result "login=existing"
elif [[ "$SETUP_PIN" =~ ^[0-9]{3}-[0-9]{3}$ ]]; then
    tui_result "pin=$SETUP_PIN"
else
    tui_result "login=unknown"
fi
tui_stage done

echo ""
if [ "$GUM_AVAILABLE" = true ]; then
    gum style --foreground "$COL_MINT" --bold "✓ Setup completed successfully!"
else
    print_success "Setup completed successfully!"
fi
echo ""


if [ "$GUM_AVAILABLE" = true ]; then
    cat << COMMANDS | gum format
## Useful Commands

\`\`\`bash
# View logs
docker compose -f docker-compose.yml logs -f

# Check status
docker compose -f docker-compose.yml ps

# Get new PIN (if expired)
docker compose -f docker-compose.yml restart station
docker compose -f docker-compose.yml logs station | grep -oE '[0-9]{3}-[0-9]{3}' | tail -1
\`\`\`
COMMANDS
else
    echo "Useful commands:  docker compose -f docker-compose.yml logs -f"
    echo "                  docker compose -f docker-compose.yml ps"
    echo ""
    echo "PIN expired? Run: docker compose -f docker-compose.yml restart station"
    echo "             Then: docker compose -f docker-compose.yml logs station | grep -oE '[0-9]{3}-[0-9]{3}' | tail -1"
fi

echo ""

# Display final next steps in a beautiful box
if [ "$SETUP_DONE" = true ]; then
    NEXT_OPEN="1. Open:  https://$STATION_DOMAIN/login"
    NEXT_LOGIN="2. Sign in with your email and password"
else
    NEXT_OPEN="1. Open:  https://$STATION_DOMAIN/setup"
    NEXT_LOGIN="2. Enter PIN:  $SETUP_PIN"
fi
if [ "$GUM_AVAILABLE" = true ]; then
    gum style --border double --border-foreground "$COL_MINT" --padding "1 3" --margin "1 0" --bold \
        "NEXT STEPS" \
        "" \
        "$NEXT_OPEN" \
        "" \
        "$NEXT_LOGIN" \
        "" \
        "3. Upload your music!" \
        "" \
        "4. Share your namespace with listeners"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  NEXT STEPS:"
    echo ""
    echo "  $NEXT_OPEN"
    echo ""
    echo "  $NEXT_LOGIN"
    echo ""
    echo "  3. Use the dashboard to upload your music"
    echo ""
    echo "  4. Share your 'namespace' with listeners"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
echo ""
