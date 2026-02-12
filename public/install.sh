#!/bin/bash

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print the QNCH ASCII banner
print_banner() {
    local banner
    banner=$(cat << 'BANNER'
 ██████╗ ███╗   ██╗ ██████╗██╗  ██╗
██╔═══██╗████╗  ██║██╔════╝██║  ██║
██║   ██║██╔██╗ ██║██║     ███████║
██║▄▄ ██║██║╚██╗██║██║     ██╔══██║
╚██████╔╝██║ ╚████║╚██████╗██║  ██║
 ╚══▀▀═╝ ╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝
BANNER
)
    echo ""
    if [ "$GUM_AVAILABLE" = true ]; then
        echo "$banner" | gum style --foreground 212 --bold
        echo ""
        gum style --foreground 99 --bold "         Setup Wizard v$STATION_VERSION"
    else
        echo -e "${PURPLE} ██████╗ ${CYAN}███╗   ██╗${PURPLE} ██████╗${CYAN}██╗  ██╗${NC}"
        echo -e "${PURPLE}██╔═══██╗${CYAN}████╗  ██║${PURPLE}██╔════╝${CYAN}██║  ██║${NC}"
        echo -e "${PURPLE}██║   ██║${CYAN}██╔██╗ ██║${PURPLE}██║     ${CYAN}███████║${NC}"
        echo -e "${PURPLE}██║▄▄ ██║${CYAN}██║╚██╗██║${PURPLE}██║     ${CYAN}██╔══██║${NC}"
        echo -e "${PURPLE}╚██████╔╝${CYAN}██║ ╚████║${PURPLE}╚██████╗${CYAN}██║  ██║${NC}"
        echo -e "${PURPLE} ╚══▀▀═╝ ${CYAN}╚═╝  ╚═══╝${PURPLE} ╚═════╝${CYAN}╚═╝  ╚═╝${NC}"
        echo ""
        echo -e "${BOLD}         Setup Wizard v$STATION_VERSION${NC}"
    fi
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
        gum style --foreground 39 "→ $1"
    else
        echo -e "${BLUE}→${NC} $1"
    fi
}

print_success() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground 82 "✓ $1"
    else
        echo -e "${GREEN}✓${NC} $1"
    fi
}

print_error() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground 196 "✗ $1"
    else
        echo -e "${RED}✗${NC} $1"
    fi
}

print_warning() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground 214 "⚠ $1"
    else
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

print_info() {
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground 39 "ℹ $1"
    else
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

# Gum availability flag
GUM_AVAILABLE=false

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

    case "$OS" in
        ubuntu|debian)
            # Add Charm repository
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list
            apt-get update -qq && apt-get install -y -qq gum
            ;;
        fedora|rhel|centos)
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' > /etc/yum.repos.d/charm.repo
            dnf install -y gum 2>/dev/null || yum install -y gum
            ;;
        *)
            # Try go install as fallback
            if command -v go &> /dev/null; then
                go install github.com/charmbracelet/gum@latest
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
        gum spin --spinner dot --title "$title" -- "$@"
    else
        echo "$title"
        "$@"
    fi
}

# Styled box for important messages
gum_box() {
    local text="$1"
    local border="${2:-rounded}"
    local color="${3:-212}"
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
        gum style --foreground 212 --bold --border double --border-foreground 99 --padding "0 2" "$title"
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
      - ACME_PRODUCTION=${ACME_PRODUCTION:-false}

    networks:
      - station-network

    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
        reservations:
          cpus: '0.1'
          memory: 64M

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Station Artist Node - P2P Music Streaming Backend
  station:
    image: ghcr.io/gotnoshoeson/station:STATION_VERSION
    container_name: station-node
    restart: unless-stopped

    ports:
      - "4001:4001"         # libp2p swarm TCP
      - "4002:4002/udp"     # libp2p swarm QUIC

    volumes:
      - ./data:/data
      - ./config:/config
      - ./music:/music:ro

    environment:
      - STATION_LOG_LEVEL=${STATION_LOG_LEVEL:-info}
      - STATION_DATA_DIR=/data
      - STATION_CONFIG=/config/station.yml
      - STATION_MUSIC_DIR=/music
      - STATION_BOOTSTRAP_PEERS=${STATION_BOOTSTRAP_PEERS:-/dns4/theramble.duckdns.org/tcp/4001/p2p/12D3KooWACcJjwyRZfz9hSXDTANF4uQXZaNaeuDZmCKUReK8dw8F}
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

    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M

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

networks:
  station-network:
    name: station-network
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
COMPOSE_EOF

    # Replace version placeholder
    sed -i "s|STATION_VERSION|$STATION_VERSION|g" docker-compose.yml

    # Add Watchtower service if enabled
    if [ "$ENABLE_WATCHTOWER" = true ]; then
        cat >> docker-compose.yml << 'WATCHTOWER_EOF'

  # Watchtower - Automatic Docker Image Updates
  watchtower:
    image: containrrr/watchtower:latest
    container_name: station-watchtower
    restart: unless-stopped

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

    environment:
      - WATCHTOWER_SCOPE=station
      - WATCHTOWER_POLL_INTERVAL=21600
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_NO_RESTART=false

    labels:
      - "com.centurylinklabs.watchtower.scope=station"

    networks:
      - station-network

    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 128M

    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "2"
WATCHTOWER_EOF
        print_success "Added Watchtower service to docker-compose.yml"
    fi

    print_success "Created docker-compose.yml"
    echo ""
}

# Use current working directory for all operations
PROJECT_ROOT="$(pwd)"

# Station version - fetched dynamically from qnch.network
VERSION_URL="https://qnch.network/version.json"
FALLBACK_VERSION="0.1.0-beta.52"

fetch_latest_version() {
    local version=""

    # Try python3 + curl first
    if command -v python3 &> /dev/null; then
        version=$(curl -sf "$VERSION_URL" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" 2>/dev/null)
    fi

    # Try jq + curl as fallback
    if [ -z "$version" ] && command -v jq &> /dev/null; then
        version=$(curl -sf "$VERSION_URL" 2>/dev/null | jq -r '.version' 2>/dev/null)
    fi

    # Return fetched version or fallback
    if [ -n "$version" ] && [ "$version" != "null" ]; then
        echo "$version"
    else
        echo "$FALLBACK_VERSION"
    fi
}

STATION_VERSION=$(fetch_latest_version)

print_banner

# Setup gum for pretty prompts (installs if needed)
setup_gum

# Show welcome message with prerequisites
if [ "$GUM_AVAILABLE" = true ]; then
    gum style --border rounded --border-foreground 99 --padding "1 2" --margin "1 0" \
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

# Check if already configured
if [ -f "$PROJECT_ROOT/.env" ]; then
    print_warning "Found existing .env file"
    if ! gum_confirm "Do you want to reconfigure?" "no"; then
        print_info "Exiting. To start services, run: docker compose -f docker-compose.yml up -d"
        exit 0
    fi
fi

# ============================================================================
# Step 1: Check and Install Prerequisites
# ============================================================================

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

    if gum_confirm "Install Docker automatically?" "yes"; then
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

if [ ${#PORTS_IN_USE[@]} -gt 0 ]; then
    print_warning "Ports in use: ${PORTS_IN_USE[*]}"
    echo ""
    echo "The following ports must be available: 80, 443"
    echo "Currently in use: ${PORTS_IN_USE[*]}"
    echo ""
    echo "Services using these ports:"
    timeout 5 ss -tulnp 2>/dev/null | grep -E ":(${PORTS_IN_USE[*]}) " || \
    timeout 5 netstat -tulnp 2>/dev/null | grep -E ":(${PORTS_IN_USE[*]}) " || \
    echo "  (could not determine)"
    echo ""
    if ! gum_confirm "Stop these services and continue?" "no"; then
        exit 1
    fi
else
    print_success "Ports 80 and 443 are available"
fi

echo ""

# ============================================================================
# Step 2: Domain Configuration
# ============================================================================

print_step "Domain Configuration"
echo ""

domain_choice=$(gum_choose "How would you like to configure your domain?" "Own domain (mymusic.example.com)" "DuckDNS (free dynamic DNS)")

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
    if [ "$GUM_AVAILABLE" = true ]; then
        SERVER_IP=$(gum spin --spinner dot --title "Detecting server's public IP..." -- bash -c 'curl -s https://api.ipify.org || curl -s https://ifconfig.me')
    else
        print_step "Detecting server's public IP address..."
        SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
    fi

    if [ -z "$SERVER_IP" ]; then
        print_warning "Could not auto-detect public IP"
        SERVER_IP=$(gum_input "Enter this server's public IP address:" "192.168.1.1")
    else
        print_success "Server IP: $SERVER_IP"
    fi
    echo ""

    while true; do
        STATION_DOMAIN=$(gum_input "Enter your domain:" "mymusic.example.com")

        # Validate domain format
        if [[ ! "$STATION_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid domain format"
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
                gum style --border rounded --border-foreground 214 --padding "1 2" \
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
            if ! gum_confirm "Try again after configuring DNS?" "yes"; then
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
            if ! gum_confirm "Continue anyway? (not recommended)" "no"; then
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

    if ! gum_confirm "Have you created a DuckDNS account and subdomain?" "no"; then
        echo ""
        print_info "Please visit https://www.duckdns.org/ to create a free account."
        print_info "Then run this script again."
        exit 1
    fi

    echo ""
    DUCKDNS_SUBDOMAIN=$(gum_input "Enter your DuckDNS subdomain:" "myband")

    # Remove .duckdns.org if user included it
    DUCKDNS_SUBDOMAIN=${DUCKDNS_SUBDOMAIN%.duckdns.org}

    DUCKDNS_TOKEN=$(gum_input "Enter your DuckDNS token:" "your-token-here")

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

ACME_EMAIL=$(gum_input "Enter email address:" "your@email.com")

if [ -z "$ACME_EMAIL" ] || [ "$ACME_EMAIL" = "your@email.com" ]; then
    ACME_EMAIL="admin@${STATION_DOMAIN}"
    print_warning "Using placeholder email: $ACME_EMAIL"
    print_info "You can update this in .env later"
fi

echo ""

# ============================================================================
# Step 4: ACME Environment
# ============================================================================

print_step "Certificate Generation Mode"
echo ""
if [ "$GUM_AVAILABLE" = true ]; then
    cat << 'CERT_INFO' | gum format
Let's Encrypt has two modes:

**STAGING** _(recommended for first-time setup)_
* No rate limits (test freely)
* Self-signed certificates (browser warnings)
* Perfect for testing configuration

**PRODUCTION** _(for live use)_
* Trusted certificates (no warnings)
* Rate limited: 5 duplicate certs per week
* Use after testing in staging mode

> Recommendation: Start with STAGING, switch to PRODUCTION once working.
CERT_INFO
else
    echo "Let's Encrypt has two modes:"
    echo ""
    echo "  STAGING (recommended for first-time setup):"
    echo "    • No rate limits (test freely)"
    echo "    • Self-signed certificates (browser warnings)"
    echo "    • Perfect for testing configuration"
    echo ""
    echo "  PRODUCTION (for live use):"
    echo "    • Trusted certificates (no warnings)"
    echo "    • Rate limited: 5 duplicate certs per week"
    echo "    • Use after testing in staging mode"
    echo ""
    echo "Recommendation: Start with STAGING, switch to PRODUCTION once working."
fi
echo ""

if gum_confirm "Use STAGING mode? (recommended for first-time setup)" "yes"; then
    ACME_PRODUCTION="false"
    print_info "Using STAGING mode (certificate warnings are normal)"
else
    ACME_PRODUCTION="true"
    print_warning "Using PRODUCTION mode"
    print_info "Let's Encrypt limits you to 5 duplicate certificates per week."
    print_info "If something goes wrong, you may need to wait before retrying."
fi

echo ""

# ============================================================================
# Step 5: Automatic Updates (Watchtower)
# ============================================================================

print_step "Automatic Updates"
echo ""

if [ "$GUM_AVAILABLE" = true ]; then
    cat << 'WATCHTOWER_INFO' | gum format
**Watchtower** can automatically update your Station node when new versions are released.

* Checks for new Docker images every 6 hours
* Pulls and restarts the Station container automatically
* Only updates the Station container (not Traefik)
* Can be disabled later via the dashboard
WATCHTOWER_INFO
else
    echo "Watchtower can automatically update your Station node when new versions are released."
    echo ""
    echo "  - Checks for new Docker images every 6 hours"
    echo "  - Pulls and restarts the Station container automatically"
    echo "  - Only updates the Station container (not Traefik)"
    echo "  - Can be disabled later via the dashboard"
fi
echo ""

ENABLE_WATCHTOWER=false
if gum_confirm "Enable automatic updates via Watchtower?" "yes"; then
    ENABLE_WATCHTOWER=true
    print_success "Watchtower will be enabled"
else
    print_info "Watchtower will not be installed. You can update manually via the dashboard."
fi
echo ""

# ============================================================================
# Step 6: Create Directory Structure
# ============================================================================

print_step "Setting up directories..."

cd "$PROJECT_ROOT"

mkdir -p data
mkdir -p config
mkdir -p music
mkdir -p traefik
mkdir -p logs

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

# Generate .env file
cat > .env << EOF
# Station Domain Configuration
STATION_DOMAIN=$STATION_DOMAIN

# Let's Encrypt Email
ACME_EMAIL=$ACME_EMAIL

# Certificate Mode (true=production, false=staging)
ACME_PRODUCTION=$ACME_PRODUCTION

# Station Configuration
STATION_LOG_LEVEL=info
STATION_DATA_DIR=/data
STATION_CONFIG=/config/station.yml
STATION_MUSIC_DIR=/music

# Bootstrap peers (comma-separated multiaddrs)
# Default: Official Station bootstrap node
STATION_BOOTSTRAP_PEERS=/dns4/theramble.duckdns.org/tcp/4001/p2p/12D3KooWACcJjwyRZfz9hSXDTANF4uQXZaNaeuDZmCKUReK8dw8F

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

# Generate traefik.yml with dynamic CA server based on mode
if [ "$ACME_PRODUCTION" = "true" ]; then
    CA_SERVER="https://acme-v02.api.letsencrypt.org/directory"
else
    CA_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
fi

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
    gum style --border rounded --border-foreground 99 --padding "1 2" \
        "Domain:           $STATION_DOMAIN" \
        "Email:            $ACME_EMAIL" \
        "Certificate:      $([ "$ACME_PRODUCTION" = "true" ] && echo "Production" || echo "Staging")" \
        "Domain Type:      $DOMAIN_TYPE"
else
    echo "  Domain:              $STATION_DOMAIN"
    echo "  Email:               $ACME_EMAIL"
    echo "  Certificate Mode:    $([ "$ACME_PRODUCTION" = "true" ] && echo "Production" || echo "Staging")"
    echo "  Domain Type:         $DOMAIN_TYPE"
fi
echo ""

# ============================================================================
# Step 10: Start Services
# ============================================================================

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
fi

echo ""
echo ""
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

print_step "Retrieving setup PIN from Station..."

# Give Station a moment to generate and log the PIN
sleep 3

# Extract PIN from logs - look for the PIN pattern (XXX-XXX)
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

if [ -z "$SETUP_PIN" ]; then
    print_warning "Could not automatically retrieve PIN"
    SETUP_PIN="(check logs - see troubleshooting below)"
else
    print_success "PIN retrieved successfully"
fi

echo ""

# ============================================================================
# Step 13: Final Status and Next Steps
# ============================================================================

echo ""
if [ "$GUM_AVAILABLE" = true ]; then
    gum style --foreground 82 --bold "✓ Setup completed successfully!"
else
    print_success "Setup completed successfully!"
fi
echo ""

if [ "$ACME_PRODUCTION" = "false" ]; then
    if [ "$GUM_AVAILABLE" = true ]; then
        gum style --foreground 214 --italic \
            "Note: Using staging certificates (browser warnings expected)." \
            "Run 'bash switch-to-production.sh' later for trusted certificates."
    else
        echo "Note: Using staging certificates (browser warnings expected)."
        echo "Run 'bash switch-to-production.sh' later to get trusted certificates."
    fi
    echo ""
fi

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
if [ "$GUM_AVAILABLE" = true ]; then
    gum style --border double --border-foreground 212 --padding "1 3" --margin "1 0" --bold \
        "NEXT STEPS" \
        "" \
        "1. Open:  https://$STATION_DOMAIN/setup" \
        "" \
        "2. Enter PIN:  $SETUP_PIN" \
        "" \
        "3. Upload your music!" \
        "" \
        "4. Share your namespace with listeners"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  NEXT STEPS:"
    echo ""
    echo "  1. Open:  https://$STATION_DOMAIN/setup"
    echo ""
    echo "  2. Enter PIN:  $SETUP_PIN"
    echo ""
    echo "  3. Use the dashboard to upload your music"
    echo ""
    echo "  4. Share your 'namespace' with listeners"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
echo ""
