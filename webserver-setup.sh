#!/bin/bash

# ============================================================================
# Universal Web Server Setup Script v3.0
# ============================================================================
# A comprehensive, production-ready tool for setting up web applications with:
# - Apache2 or Nginx (auto-install if missing)
# - Reverse proxy configuration with WebSocket support
# - Static file serving with caching
# - SSL/TLS with Let's Encrypt, self-signed, or existing certificates
#
# Backend support:
# - Node.js (Express, NestJS, Fastify)
# - Python (FastAPI, Django, Flask)
# - PHP (Laravel, WordPress, Symfony)
#
# Frontend support (NEW in v3.0):
# - Next.js (SSR, Static Export, Standalone)
# - Nuxt.js (SSR, Static Generation, SPA)
# - React (Vite, Create React App)
# - Vue.js (Vite, Vue CLI)
# - Angular (Angular CLI)
# - Svelte/SvelteKit (SSR, Static, SPA)
#
# Features:
# - Multiple package managers (npm, pnpm, yarn, bun)
# - Node.js version selection (18, 20, 22 LTS)
# - Optimized caching for hashed assets
# - SPA routing support
# - PM2 or systemd process management
# - UFW firewall configuration
# - Database installation (MySQL/PostgreSQL)
# - Automatic security hardening
#
# Usage:
#   chmod +x webserver-setup.sh
#   sudo ./webserver-setup.sh
#
# ============================================================================

VERSION="3.0.0"

# Exit on error, but handle gracefully
set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Global variables
LOG_FILE="/var/log/webserver-setup.log"
BACKUP_DIR="/var/backups/webserver-setup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ============================================================================
# LOGGING & UTILITY FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_step() {
    echo -e "${MAGENTA}[STEP]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# Error handler
error_handler() {
    local line_no=$1
    local error_code=$2
    log_error "Error occurred in script at line $line_no (exit code: $error_code)"
    log_error "Check log file for details: $LOG_FILE"
    echo ""
    echo -e "${RED}Setup failed. Please check the error above and try again.${NC}"
    exit 1
}

trap 'error_handler ${LINENO} $?' ERR

# Spinner for long operations
spinner() {
    local pid=$1
    local msg=$2
    local spin='-\|/'
    local i=0

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r${BLUE}[INFO]${NC} ${msg} ${spin:$i:1}"
        sleep 0.1
    done
    printf "\r"
}

# Header
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║          Universal Web Server Setup v${VERSION}                        ║"
    echo "║     Apache2 • Nginx • SSL • PM2 • Frontend & Backend Deploy          ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${DIM}Supports: Next.js, Nuxt.js, React, Vue, Angular, Svelte, Node.js, Python, PHP${NC}"
    echo -e "${DIM}Log file: $LOG_FILE${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi

    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    echo "=== Web Server Setup Started at $(date) ===" >> "$LOG_FILE"
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_CODENAME=${VERSION_CODENAME:-$(echo $VERSION | grep -oP '\(\K[^)]+' || echo "unknown")}
    else
        log_error "Cannot detect OS. This script supports Ubuntu/Debian."
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            log_info "Detected OS: $OS $OS_VERSION ($OS_CODENAME)"
            ;;
        *)
            log_warning "This script is optimized for Ubuntu/Debian. Proceeding with caution..."
            ;;
    esac

    log_debug "OS: $OS, Version: $OS_VERSION, Codename: $OS_CODENAME"
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if package is installed (reliable method)
package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Install package with error handling
install_package() {
    local pkg=$1
    local optional=${2:-false}

    if package_installed "$pkg"; then
        log_success "$pkg already installed"
        return 0
    fi

    log_info "Installing $pkg..."
    log_debug "Running: apt-get install -y $pkg"

    if apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1; then
        log_success "$pkg installed"
        return 0
    else
        if [ "$optional" = true ]; then
            log_warning "$pkg failed to install (optional package)"
            return 0
        else
            log_error "$pkg failed to install"
            return 1
        fi
    fi
}

# Backup file or directory
backup_item() {
    local item=$1
    if [ -e "$item" ]; then
        mkdir -p "$BACKUP_DIR/$TIMESTAMP"
        local backup_path="$BACKUP_DIR/$TIMESTAMP/$(basename "$item")"
        cp -r "$item" "$backup_path"
        log_debug "Backed up $item to $backup_path"
    fi
}

# ============================================================================
# MENU FUNCTIONS
# ============================================================================

# Select web server
select_web_server() {
    echo ""
    echo -e "${BOLD}Select Web Server:${NC}"
    echo -e "  1) Apache2  ${DIM}(feature-rich, .htaccess support)${NC}"
    echo -e "  2) Nginx    ${DIM}(high performance, modern)${NC}"
    echo ""

    while true; do
        read -p "Enter choice [1-2]: " choice
        case $choice in
            1) WEB_SERVER="apache2"; break;;
            2) WEB_SERVER="nginx"; break;;
            *) echo "Invalid choice. Please enter 1 or 2.";;
        esac
    done

    log_info "Selected: $WEB_SERVER"
}

# Select app type
select_app_type() {
    echo ""
    echo -e "${BOLD}Select Application Type:${NC}"
    echo -e "  ${CYAN}── Backend ──${NC}"
    echo -e "  1) Node.js  ${DIM}(Express, NestJS, Fastify, etc.)${NC}"
    echo -e "  2) Python   ${DIM}(FastAPI, Django, Flask)${NC}"
    echo -e "  3) PHP      ${DIM}(Laravel, WordPress, Symfony)${NC}"
    echo -e "  ${CYAN}── Frontend ──${NC}"
    echo -e "  4) Next.js  ${DIM}(React SSR/SSG framework)${NC}"
    echo -e "  5) Nuxt.js  ${DIM}(Vue SSR/SSG framework)${NC}"
    echo -e "  6) React    ${DIM}(SPA - Vite, CRA)${NC}"
    echo -e "  7) Vue.js   ${DIM}(SPA - Vite, Vue CLI)${NC}"
    echo -e "  8) Angular  ${DIM}(SPA - Angular CLI)${NC}"
    echo -e "  9) Svelte   ${DIM}(SPA/SSR - SvelteKit)${NC}"
    echo -e "  ${CYAN}── Other ──${NC}"
    echo -e "  10) Static  ${DIM}(pre-built HTML, CSS, JS)${NC}"
    echo -e "  11) Proxy   ${DIM}(reverse proxy to existing app)${NC}"
    echo ""

    while true; do
        read -p "Enter choice [1-11]: " choice
        case $choice in
            1) APP_TYPE="nodejs"; break;;
            2) APP_TYPE="python"; break;;
            3) APP_TYPE="php"; break;;
            4) APP_TYPE="nextjs"; break;;
            5) APP_TYPE="nuxtjs"; break;;
            6) APP_TYPE="react"; break;;
            7) APP_TYPE="vue"; break;;
            8) APP_TYPE="angular"; break;;
            9) APP_TYPE="svelte"; break;;
            10) APP_TYPE="static"; break;;
            11) APP_TYPE="proxy"; break;;
            *) echo "Invalid choice. Please enter 1-11.";;
        esac
    done

    log_info "Selected app type: $APP_TYPE"

    # Get frontend-specific configuration
    if [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|react|vue|angular|svelte)$ ]]; then
        get_frontend_config
    fi
}

# Get frontend-specific configuration
get_frontend_config() {
    echo ""
    echo -e "${BOLD}Frontend Configuration:${NC}"

    # Deployment mode based on framework
    case $APP_TYPE in
        nextjs)
            echo ""
            echo -e "${BOLD}Next.js Deployment Mode:${NC}"
            echo -e "  1) SSR       ${DIM}(Server-Side Rendering - needs Node.js server)${NC}"
            echo -e "  2) Static    ${DIM}(Static Export - output: 'export' in next.config.js)${NC}"
            echo -e "  3) Standalone${DIM}(Self-contained server - output: 'standalone')${NC}"
            echo ""
            while true; do
                read -p "Enter choice [1-3] [1]: " mode_choice
                mode_choice=${mode_choice:-1}
                case $mode_choice in
                    1) FRONTEND_MODE="ssr"; break;;
                    2) FRONTEND_MODE="static"; break;;
                    3) FRONTEND_MODE="standalone"; break;;
                    *) echo "Invalid choice.";;
                esac
            done
            FRONTEND_BUILD_DIR=".next"
            FRONTEND_STATIC_DIR="out"
            FRONTEND_BUILD_CMD="npm run build"
            FRONTEND_START_CMD="npm start"
            ;;
        nuxtjs)
            echo ""
            echo -e "${BOLD}Nuxt.js Deployment Mode:${NC}"
            echo -e "  1) SSR       ${DIM}(Server-Side Rendering - universal mode)${NC}"
            echo -e "  2) Static    ${DIM}(Static Generation - nuxt generate)${NC}"
            echo -e "  3) SPA       ${DIM}(Single Page Application - ssr: false)${NC}"
            echo ""
            while true; do
                read -p "Enter choice [1-3] [1]: " mode_choice
                mode_choice=${mode_choice:-1}
                case $mode_choice in
                    1) FRONTEND_MODE="ssr"; break;;
                    2) FRONTEND_MODE="static"; break;;
                    3) FRONTEND_MODE="spa"; break;;
                    *) echo "Invalid choice.";;
                esac
            done
            FRONTEND_BUILD_DIR=".output"
            FRONTEND_STATIC_DIR=".output/public"
            if [ "$FRONTEND_MODE" == "static" ]; then
                FRONTEND_BUILD_CMD="npm run generate"
                FRONTEND_STATIC_DIR="dist"
            else
                FRONTEND_BUILD_CMD="npm run build"
            fi
            FRONTEND_START_CMD="node .output/server/index.mjs"
            ;;
        react)
            FRONTEND_MODE="spa"
            echo ""
            echo -e "${BOLD}React Build Tool:${NC}"
            echo -e "  1) Vite      ${DIM}(recommended, fast builds)${NC}"
            echo -e "  2) CRA       ${DIM}(Create React App)${NC}"
            echo ""
            while true; do
                read -p "Enter choice [1-2] [1]: " tool_choice
                tool_choice=${tool_choice:-1}
                case $tool_choice in
                    1) FRONTEND_TOOL="vite"; FRONTEND_STATIC_DIR="dist"; break;;
                    2) FRONTEND_TOOL="cra"; FRONTEND_STATIC_DIR="build"; break;;
                    *) echo "Invalid choice.";;
                esac
            done
            FRONTEND_BUILD_CMD="npm run build"
            ;;
        vue)
            FRONTEND_MODE="spa"
            echo ""
            echo -e "${BOLD}Vue Build Tool:${NC}"
            echo -e "  1) Vite      ${DIM}(recommended, fast builds)${NC}"
            echo -e "  2) Vue CLI   ${DIM}(legacy)${NC}"
            echo ""
            while true; do
                read -p "Enter choice [1-2] [1]: " tool_choice
                tool_choice=${tool_choice:-1}
                case $tool_choice in
                    1) FRONTEND_TOOL="vite"; FRONTEND_STATIC_DIR="dist"; break;;
                    2) FRONTEND_TOOL="cli"; FRONTEND_STATIC_DIR="dist"; break;;
                    *) echo "Invalid choice.";;
                esac
            done
            FRONTEND_BUILD_CMD="npm run build"
            ;;
        angular)
            FRONTEND_MODE="spa"
            FRONTEND_TOOL="angular-cli"
            FRONTEND_BUILD_CMD="npm run build -- --configuration production"
            echo ""
            read -p "Enter Angular project name (for build output path) [app]: " ANGULAR_PROJECT
            ANGULAR_PROJECT=${ANGULAR_PROJECT:-app}
            FRONTEND_STATIC_DIR="dist/$ANGULAR_PROJECT/browser"
            ;;
        svelte)
            echo ""
            echo -e "${BOLD}Svelte Deployment Mode:${NC}"
            echo -e "  1) SvelteKit SSR  ${DIM}(Server-Side Rendering)${NC}"
            echo -e "  2) SvelteKit Static ${DIM}(adapter-static)${NC}"
            echo -e "  3) Svelte SPA     ${DIM}(Vite only, no SvelteKit)${NC}"
            echo ""
            while true; do
                read -p "Enter choice [1-3] [1]: " mode_choice
                mode_choice=${mode_choice:-1}
                case $mode_choice in
                    1) FRONTEND_MODE="ssr"; break;;
                    2) FRONTEND_MODE="static"; break;;
                    3) FRONTEND_MODE="spa"; break;;
                    *) echo "Invalid choice.";;
                esac
            done
            FRONTEND_BUILD_DIR="build"
            FRONTEND_STATIC_DIR="build"
            FRONTEND_BUILD_CMD="npm run build"
            FRONTEND_START_CMD="node build/index.js"
            ;;
    esac

    log_info "Frontend mode: $FRONTEND_MODE"

    # Node.js version selection
    echo ""
    echo -e "${BOLD}Node.js Version:${NC}"
    echo -e "  1) Node.js 20 LTS ${DIM}(recommended)${NC}"
    echo -e "  2) Node.js 22 LTS ${DIM}(latest LTS)${NC}"
    echo -e "  3) Node.js 18 LTS ${DIM}(older LTS)${NC}"
    echo ""
    while true; do
        read -p "Enter choice [1-3] [1]: " node_choice
        node_choice=${node_choice:-1}
        case $node_choice in
            1) NODE_VERSION="20"; break;;
            2) NODE_VERSION="22"; break;;
            3) NODE_VERSION="18"; break;;
            *) echo "Invalid choice.";;
        esac
    done
    log_info "Node.js version: $NODE_VERSION"

    # Package manager selection
    echo ""
    echo -e "${BOLD}Package Manager:${NC}"
    echo -e "  1) npm   ${DIM}(default)${NC}"
    echo -e "  2) pnpm  ${DIM}(fast, efficient)${NC}"
    echo -e "  3) yarn  ${DIM}(classic)${NC}"
    echo -e "  4) bun   ${DIM}(fastest, all-in-one)${NC}"
    echo ""
    while true; do
        read -p "Enter choice [1-4] [1]: " pkg_choice
        pkg_choice=${pkg_choice:-1}
        case $pkg_choice in
            1) PKG_MANAGER="npm"; break;;
            2) PKG_MANAGER="pnpm"; break;;
            3) PKG_MANAGER="yarn"; break;;
            4) PKG_MANAGER="bun"; break;;
            *) echo "Invalid choice.";;
        esac
    done
    log_info "Package manager: $PKG_MANAGER"

    # Update build commands based on package manager
    case $PKG_MANAGER in
        pnpm)
            FRONTEND_BUILD_CMD="${FRONTEND_BUILD_CMD/npm/pnpm}"
            FRONTEND_START_CMD="${FRONTEND_START_CMD/npm/pnpm}"
            ;;
        yarn)
            FRONTEND_BUILD_CMD="${FRONTEND_BUILD_CMD/npm run/yarn}"
            FRONTEND_START_CMD="${FRONTEND_START_CMD/npm/yarn}"
            ;;
        bun)
            FRONTEND_BUILD_CMD="${FRONTEND_BUILD_CMD/npm/bun}"
            FRONTEND_START_CMD="${FRONTEND_START_CMD/npm/bun}"
            ;;
    esac

    # Environment variables for build
    echo ""
    read -p "Configure build-time environment variables? (y/n) [n]: " setup_env
    setup_env=${setup_env:-n}
    if [[ $setup_env =~ ^[Yy]$ ]]; then
        FRONTEND_ENV_VARS=()
        echo -e "${DIM}Enter environment variables (format: KEY=value), empty line to finish:${NC}"
        while true; do
            read -p "  > " env_var
            if [ -z "$env_var" ]; then
                break
            fi
            FRONTEND_ENV_VARS+=("$env_var")
        done
        if [ ${#FRONTEND_ENV_VARS[@]} -gt 0 ]; then
            log_info "Configured ${#FRONTEND_ENV_VARS[@]} environment variable(s)"
        fi
    fi

    # API URL configuration (common for frontends)
    echo ""
    read -p "Enter backend API URL (or leave empty): " FRONTEND_API_URL
    if [ -n "$FRONTEND_API_URL" ]; then
        log_info "API URL: $FRONTEND_API_URL"
    fi
}

# Get domain configuration
get_domain_config() {
    echo ""
    echo -e "${BOLD}Domain Configuration:${NC}"

    while true; do
        read -p "Enter domain name (e.g., example.com or api.example.com): " DOMAIN
        if [ -n "$DOMAIN" ]; then
            # Basic domain validation
            if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                echo "Invalid domain format. Please use format like example.com or api.example.com"
            fi
        else
            echo "Domain cannot be empty."
        fi
    done

    SERVER_ALIASES=""
    INCLUDE_WWW=false

    # Count dots to determine if subdomain
    local dot_count=$(echo "$DOMAIN" | tr -cd '.' | wc -c | tr -d ' ')

    if [ "$dot_count" -eq 1 ]; then
        # Root domain like example.com - offer www
        read -p "Include www subdomain? (y/n) [y]: " include_www
        include_www=${include_www:-y}
        if [[ $include_www =~ ^[Yy]$ ]]; then
            INCLUDE_WWW=true
            SERVER_ALIASES="www.$DOMAIN"
        fi

        read -p "Add additional subdomains? (comma-separated, or leave empty): " extra_subdomains
        if [ -n "$extra_subdomains" ]; then
            IFS=',' read -ra SUBDOMAINS <<< "$extra_subdomains"
            for sub in "${SUBDOMAINS[@]}"; do
                sub=$(echo "$sub" | xargs)  # trim whitespace
                if [ -n "$sub" ]; then
                    if [ -n "$SERVER_ALIASES" ]; then
                        SERVER_ALIASES="$SERVER_ALIASES ${sub}.${DOMAIN}"
                    else
                        SERVER_ALIASES="${sub}.${DOMAIN}"
                    fi
                fi
            done
        fi
    else
        log_info "Subdomain detected - skipping www alias"
    fi

    log_info "Domain: $DOMAIN"
    if [ -n "$SERVER_ALIASES" ]; then
        log_info "Aliases: $SERVER_ALIASES"
    fi
}

# Get app directory
get_app_directory() {
    echo ""
    echo -e "${BOLD}Application Directory:${NC}"

    local default_dir="/var/www/$DOMAIN"
    read -p "Enter app root directory [$default_dir]: " APP_ROOT
    APP_ROOT=${APP_ROOT:-$default_dir}

    # Normalize path (remove trailing slash)
    APP_ROOT="${APP_ROOT%/}"

    log_info "App directory: $APP_ROOT"
}

# Get port configuration
get_port_config() {
    echo ""
    echo -e "${BOLD}Port Configuration:${NC}"

    # Check if this is a static deployment (no reverse proxy needed)
    if [[ "$APP_TYPE" == "static" || "$APP_TYPE" == "php" ]]; then
        USE_PROXY=false
        APP_PORT=""
        log_info "No reverse proxy needed for $APP_TYPE"
        return
    fi

    # Frontend frameworks: check if it's static/SPA mode
    if [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|react|vue|angular|svelte)$ ]]; then
        if [[ "$FRONTEND_MODE" == "static" || "$FRONTEND_MODE" == "spa" ]]; then
            USE_PROXY=false
            APP_PORT=""
            log_info "No reverse proxy needed for $APP_TYPE in $FRONTEND_MODE mode"
            return
        fi
    fi

    USE_PROXY=true

    case $APP_TYPE in
        nodejs) default_port=3000;;
        python) default_port=8000;;
        proxy) default_port=3000;;
        nextjs) default_port=3000;;
        nuxtjs) default_port=3000;;
        svelte) default_port=3000;;
        *) default_port=3000;;
    esac

    while true; do
        read -p "Enter application port [$default_port]: " APP_PORT
        APP_PORT=${APP_PORT:-$default_port}

        # Validate port
        if [[ "$APP_PORT" =~ ^[0-9]+$ ]] && [ "$APP_PORT" -ge 1 ] && [ "$APP_PORT" -le 65535 ]; then
            break
        else
            echo "Invalid port number. Please enter a number between 1 and 65535."
        fi
    done

    log_info "Application port: $APP_PORT"
}

# Get Git repository
get_git_config() {
    echo ""
    echo -e "${BOLD}Git Repository (optional):${NC}"

    read -p "Clone from Git repository? (y/n) [n]: " use_git
    use_git=${use_git:-n}

    if [[ $use_git =~ ^[Yy]$ ]]; then
        USE_GIT=true

        while true; do
            read -p "Enter Git repository URL: " GIT_REPO
            if [ -n "$GIT_REPO" ]; then
                # Basic URL validation
                if [[ "$GIT_REPO" =~ ^(https?://|git@) ]]; then
                    break
                else
                    echo "Invalid repository URL. Use https:// or git@ format."
                fi
            else
                echo "Repository URL cannot be empty."
            fi
        done

        read -p "Enter branch name [main]: " GIT_BRANCH
        GIT_BRANCH=${GIT_BRANCH:-main}

        log_info "Git repo: $GIT_REPO (branch: $GIT_BRANCH)"
    else
        USE_GIT=false
        GIT_REPO=""
        GIT_BRANCH=""
    fi
}

# Get SSL configuration
get_ssl_config() {
    echo ""
    echo -e "${BOLD}SSL/TLS Configuration:${NC}"
    echo -e "  1) Let's Encrypt  ${DIM}(free, auto-renewal, recommended)${NC}"
    echo -e "  2) Self-signed    ${DIM}(for testing/development)${NC}"
    echo -e "  3) No SSL         ${DIM}(HTTP only - not recommended)${NC}"
    echo -e "  4) Existing cert  ${DIM}(provide certificate paths)${NC}"
    echo ""

    while true; do
        read -p "Enter choice [1-4]: " choice
        case $choice in
            1) SSL_TYPE="letsencrypt"; break;;
            2) SSL_TYPE="selfsigned"; break;;
            3) SSL_TYPE="none"; break;;
            4) SSL_TYPE="existing"; break;;
            *) echo "Invalid choice. Please enter 1-4.";;
        esac
    done

    if [ "$SSL_TYPE" == "letsencrypt" ]; then
        while true; do
            read -p "Enter email for Let's Encrypt notifications: " SSL_EMAIL
            if [[ "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                echo "Please enter a valid email address."
            fi
        done
    elif [ "$SSL_TYPE" == "existing" ]; then
        while true; do
            read -p "Enter path to SSL certificate: " SSL_CERT_PATH
            read -p "Enter path to SSL private key: " SSL_KEY_PATH

            if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
                break
            else
                echo "Certificate or key file not found. Please check the paths."
            fi
        done
    fi

    log_info "SSL type: $SSL_TYPE"
}

# Get process manager config
get_pm_config() {
    # Skip for static/SPA apps and backends that don't need process management
    local needs_pm=false

    case $APP_TYPE in
        nodejs|python)
            needs_pm=true
            ;;
        nextjs|nuxtjs|svelte)
            # Only SSR mode needs process management
            if [[ "$FRONTEND_MODE" == "ssr" || "$FRONTEND_MODE" == "standalone" ]]; then
                needs_pm=true
            fi
            ;;
    esac

    if [ "$needs_pm" = false ]; then
        USE_PM2=false
        USE_SYSTEMD=false
        return
    fi

    echo ""
    echo -e "${BOLD}Process Manager:${NC}"
    echo -e "  1) PM2       ${DIM}(recommended, easy management)${NC}"
    echo -e "  2) Systemd   ${DIM}(native, no extra dependencies)${NC}"
    echo -e "  3) None      ${DIM}(manual process management)${NC}"
    echo ""

    while true; do
        read -p "Enter choice [1-3] [1]: " pm_choice
        pm_choice=${pm_choice:-1}
        case $pm_choice in
            1) USE_PM2=true; USE_SYSTEMD=false; break;;
            2) USE_PM2=false; USE_SYSTEMD=true; break;;
            3) USE_PM2=false; USE_SYSTEMD=false; break;;
            *) echo "Invalid choice. Please enter 1-3.";;
        esac
    done

    if [ "$USE_PM2" = true ] || [ "$USE_SYSTEMD" = true ]; then
        read -p "Enter app name [$DOMAIN]: " PM2_APP_NAME
        PM2_APP_NAME=${PM2_APP_NAME:-$DOMAIN}
        # Sanitize app name for systemd (replace dots with dashes)
        SYSTEMD_APP_NAME=$(echo "$PM2_APP_NAME" | tr '.' '-')

        if [ "$APP_TYPE" == "nodejs" ]; then
            read -p "Enter start command [npm start]: " START_CMD
            START_CMD=${START_CMD:-"npm start"}
        elif [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|svelte)$ ]]; then
            # Use the framework's start command
            START_CMD="${FRONTEND_START_CMD:-npm start}"
            log_info "Start command: $START_CMD"
        elif [ "$APP_TYPE" == "python" ]; then
            local default_cmd="uvicorn app.main:app --host 127.0.0.1 --port $APP_PORT"
            read -p "Enter start command [$default_cmd]: " START_CMD
            START_CMD=${START_CMD:-"$default_cmd"}
        fi

        log_info "Process manager: $([ "$USE_PM2" = true ] && echo "PM2" || echo "Systemd")"
        log_info "App name: $PM2_APP_NAME"
    fi
}

# Get PHP configuration
get_php_config() {
    if [ "$APP_TYPE" != "php" ]; then
        return
    fi

    echo ""
    echo -e "${BOLD}PHP Configuration:${NC}"

    # Detect installed PHP version
    if command_exists php; then
        PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
        log_info "Detected PHP version: $PHP_VERSION"
    else
        PHP_VERSION="8.3"
        log_warning "PHP not detected. Will install PHP $PHP_VERSION"
    fi

    read -p "Enter document root relative to app directory [public]: " PHP_DOC_ROOT
    PHP_DOC_ROOT=${PHP_DOC_ROOT:-public}

    read -p "Install common PHP extensions? (y/n) [y]: " install_ext
    install_ext=${install_ext:-y}
    INSTALL_PHP_EXT=$([[ $install_ext =~ ^[Yy]$ ]] && echo true || echo false)
}

# Get database configuration
get_database_config() {
    echo ""
    echo -e "${BOLD}Database Setup (optional):${NC}"
    echo "  1) MySQL/MariaDB"
    echo "  2) PostgreSQL"
    echo "  3) None (skip database setup)"
    echo ""

    while true; do
        read -p "Enter choice [1-3] [3]: " db_choice
        db_choice=${db_choice:-3}
        case $db_choice in
            1) INSTALL_DATABASE="mysql"; break;;
            2) INSTALL_DATABASE="postgresql"; break;;
            3) INSTALL_DATABASE="none"; break;;
            *) echo "Invalid choice. Please enter 1-3.";;
        esac
    done

    if [ "$INSTALL_DATABASE" != "none" ]; then
        log_info "Database: $INSTALL_DATABASE"
    fi
}

# Get firewall configuration
get_firewall_config() {
    echo ""
    echo -e "${BOLD}Firewall Configuration:${NC}"

    read -p "Configure UFW firewall? (y/n) [y]: " setup_ufw
    setup_ufw=${setup_ufw:-y}
    SETUP_FIREWALL=$([[ $setup_ufw =~ ^[Yy]$ ]] && echo true || echo false)

    if [ "$SETUP_FIREWALL" = true ]; then
        log_info "UFW firewall will be configured"
    fi
}

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

# Update package lists
update_packages() {
    log_step "Updating package lists..."
    if apt-get update >> "$LOG_FILE" 2>&1; then
        log_success "Package lists updated"
    else
        log_warning "Package update had some issues, continuing..."
    fi
}

# Install essential packages
install_essentials() {
    log_step "Installing essential packages..."

    local essentials="curl wget git ca-certificates gnupg lsb-release software-properties-common"
    for pkg in $essentials; do
        install_package "$pkg" true
    done
}

# Install Apache2
install_apache() {
    log_step "Setting up Apache2..."

    install_package "apache2"

    # Enable required modules
    local modules="proxy proxy_http proxy_wstunnel proxy_fcgi rewrite ssl headers expires deflate"
    for mod in $modules; do
        if a2enmod $mod >> "$LOG_FILE" 2>&1; then
            log_debug "Enabled Apache module: $mod"
        fi
    done

    # Backup default config
    backup_item "/etc/apache2/sites-available/000-default.conf"

    systemctl enable apache2 >> "$LOG_FILE" 2>&1 || true
    systemctl start apache2 >> "$LOG_FILE" 2>&1 || true

    log_success "Apache2 configured"
}

# Install Nginx
install_nginx() {
    log_step "Setting up Nginx..."

    install_package "nginx"

    # Backup default config
    backup_item "/etc/nginx/sites-available/default"

    systemctl enable nginx >> "$LOG_FILE" 2>&1 || true
    systemctl start nginx >> "$LOG_FILE" 2>&1 || true

    log_success "Nginx configured"
}

# Install Node.js
install_nodejs() {
    log_step "Setting up Node.js..."

    # Use configured version or default to 20
    local node_ver="${NODE_VERSION:-20}"

    if command_exists node; then
        local current_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$current_version" == "$node_ver" ]; then
            log_success "Node.js $(node -v) already installed"
        else
            log_info "Node.js $current_version installed, but $node_ver.x requested"
            log_info "Installing Node.js ${node_ver}.x..."
            install_node_version "$node_ver"
        fi
    else
        log_info "Installing Node.js ${node_ver}.x..."
        install_node_version "$node_ver"
    fi

    # Install alternative package managers if needed
    install_package_manager

    # Install PM2 if needed
    if [ "$USE_PM2" = true ]; then
        if ! command_exists pm2; then
            log_info "Installing PM2..."
            npm install -g pm2 >> "$LOG_FILE" 2>&1
            log_success "PM2 installed"
        else
            log_success "PM2 already installed"
        fi
    fi
}

# Helper function to install specific Node.js version
install_node_version() {
    local version=$1

    # Use NodeSource repository
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${version}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

    apt-get update >> "$LOG_FILE" 2>&1
    apt-get install -y nodejs >> "$LOG_FILE" 2>&1

    log_success "Node.js $(node -v) installed"
}

# Install alternative package managers (pnpm, yarn, bun)
install_package_manager() {
    case $PKG_MANAGER in
        pnpm)
            if ! command_exists pnpm; then
                log_info "Installing pnpm..."
                npm install -g pnpm >> "$LOG_FILE" 2>&1
                log_success "pnpm installed"
            else
                log_success "pnpm already installed"
            fi
            ;;
        yarn)
            if ! command_exists yarn; then
                log_info "Installing yarn..."
                npm install -g yarn >> "$LOG_FILE" 2>&1
                log_success "yarn installed"
            else
                log_success "yarn already installed"
            fi
            ;;
        bun)
            if ! command_exists bun; then
                log_info "Installing bun..."
                curl -fsSL https://bun.sh/install | bash >> "$LOG_FILE" 2>&1
                # Add bun to path for current session
                export BUN_INSTALL="$HOME/.bun"
                export PATH="$BUN_INSTALL/bin:$PATH"
                # Also install globally via npm as fallback
                if ! command_exists bun; then
                    npm install -g bun >> "$LOG_FILE" 2>&1 || log_warning "bun installation had issues"
                fi
                log_success "bun installed"
            else
                log_success "bun already installed"
            fi
            ;;
    esac
}

# Install Python
install_python() {
    log_step "Setting up Python..."

    install_package "python3"
    install_package "python3-venv"
    install_package "python3-pip"
    install_package "python3-dev"
    install_package "build-essential"

    # Install database development libraries for Python packages
    log_info "Installing database development libraries..."
    install_package "libpq-dev" true           # PostgreSQL
    install_package "pkg-config" true          # Required for mysqlclient

    # Try different MySQL dev package names (varies by distro version)
    if ! package_installed "libmysqlclient-dev" && ! package_installed "default-libmysqlclient-dev" && ! package_installed "libmariadb-dev"; then
        log_info "Installing MySQL development libraries..."
        apt-get install -y default-libmysqlclient-dev >> "$LOG_FILE" 2>&1 || \
        apt-get install -y libmysqlclient-dev >> "$LOG_FILE" 2>&1 || \
        apt-get install -y libmariadb-dev >> "$LOG_FILE" 2>&1 || \
        log_warning "MySQL dev libraries not available - mysqlclient may not build"
    fi

    log_success "Python $(python3 --version | cut -d ' ' -f 2) ready"

    # Install PM2 for Python process management if needed
    if [ "$USE_PM2" = true ]; then
        if ! command_exists node; then
            log_info "Installing Node.js for PM2..."
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null
            echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
            apt-get update >> "$LOG_FILE" 2>&1
            install_package "nodejs"
        fi
        if ! command_exists pm2; then
            npm install -g pm2 >> "$LOG_FILE" 2>&1
            log_success "PM2 installed"
        fi
    fi
}

# Install PHP
install_php() {
    log_step "Setting up PHP..."

    install_package "php"
    install_package "php-fpm"
    install_package "php-cli"

    if [ "$INSTALL_PHP_EXT" = true ]; then
        log_info "Installing PHP extensions..."
        local extensions="php-mysql php-pgsql php-sqlite3 php-mbstring php-xml php-curl php-zip php-gd php-intl php-bcmath php-redis"
        for ext in $extensions; do
            install_package "$ext" true
        done
    fi

    # Get PHP-FPM socket path
    PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
    PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

    systemctl enable "php${PHP_VERSION}-fpm" >> "$LOG_FILE" 2>&1 || true
    systemctl start "php${PHP_VERSION}-fpm" >> "$LOG_FILE" 2>&1 || true

    log_success "PHP $PHP_VERSION configured"
}

# Install Database
install_database() {
    if [ "$INSTALL_DATABASE" == "none" ]; then
        return
    fi

    log_step "Setting up $INSTALL_DATABASE..."

    if [ "$INSTALL_DATABASE" == "mysql" ]; then
        install_package "mysql-server" true || install_package "mariadb-server" true

        if package_installed "mysql-server" || package_installed "mariadb-server"; then
            systemctl enable mysql >> "$LOG_FILE" 2>&1 || systemctl enable mariadb >> "$LOG_FILE" 2>&1 || true
            systemctl start mysql >> "$LOG_FILE" 2>&1 || systemctl start mariadb >> "$LOG_FILE" 2>&1 || true
            log_success "MySQL/MariaDB installed"
            log_warning "Run 'sudo mysql_secure_installation' to secure your database"
        fi
    elif [ "$INSTALL_DATABASE" == "postgresql" ]; then
        install_package "postgresql"
        install_package "postgresql-contrib"

        systemctl enable postgresql >> "$LOG_FILE" 2>&1 || true
        systemctl start postgresql >> "$LOG_FILE" 2>&1 || true
        log_success "PostgreSQL installed"
    fi
}

# Setup Firewall
setup_firewall() {
    if [ "$SETUP_FIREWALL" != true ]; then
        return
    fi

    log_step "Configuring UFW firewall..."

    install_package "ufw"

    # Configure UFW
    ufw --force reset >> "$LOG_FILE" 2>&1
    ufw default deny incoming >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1

    # Allow SSH
    ufw allow ssh >> "$LOG_FILE" 2>&1

    # Allow web server
    if [ "$WEB_SERVER" == "apache2" ]; then
        ufw allow 'Apache Full' >> "$LOG_FILE" 2>&1
    else
        ufw allow 'Nginx Full' >> "$LOG_FILE" 2>&1
    fi

    # Enable UFW
    echo "y" | ufw enable >> "$LOG_FILE" 2>&1

    log_success "UFW firewall configured"
}

# Setup application directory
setup_app_directory() {
    log_step "Setting up application directory..."

    # Create directory
    mkdir -p "$APP_ROOT"

    if [ "$USE_GIT" = true ]; then
        if [ -d "$APP_ROOT/.git" ]; then
            log_info "Git repository exists, pulling latest..."
            cd "$APP_ROOT"
            git fetch origin >> "$LOG_FILE" 2>&1 || true
            git checkout "$GIT_BRANCH" >> "$LOG_FILE" 2>&1 || true
            git pull origin "$GIT_BRANCH" >> "$LOG_FILE" 2>&1 || true
        else
            log_info "Cloning repository..."
            # Remove directory if it exists but is not a git repo
            if [ -d "$APP_ROOT" ] && [ "$(ls -A "$APP_ROOT" 2>/dev/null)" ]; then
                backup_item "$APP_ROOT"
                rm -rf "$APP_ROOT"
            fi

            if git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_ROOT" >> "$LOG_FILE" 2>&1; then
                log_success "Repository cloned"
            else
                log_error "Failed to clone repository"
                mkdir -p "$APP_ROOT"
            fi
        fi
    fi

    # Set ownership
    chown -R www-data:www-data "$APP_ROOT"
    chmod -R 755 "$APP_ROOT"

    log_success "App directory ready: $APP_ROOT"
}

# Setup Node.js app
setup_nodejs_app() {
    log_step "Setting up Node.js application..."

    cd "$APP_ROOT"

    # Create .env if needed
    if [ ! -f ".env" ] && [ ! -f ".env.local" ] && [ ! -f ".env.production" ]; then
        cat > .env.local << EOF
# Application environment
NODE_ENV=production
PORT=$APP_PORT
EOF
        log_info "Created .env.local"
    fi

    # Install dependencies
    if [ -f "package.json" ]; then
        log_info "Installing npm dependencies..."

        # Try npm ci first, then npm install
        if npm ci --omit=dev >> "$LOG_FILE" 2>&1; then
            log_debug "npm ci succeeded"
        elif npm install --omit=dev >> "$LOG_FILE" 2>&1; then
            log_debug "npm install succeeded"
        else
            log_warning "npm install with --omit=dev failed, trying full install..."
            npm install >> "$LOG_FILE" 2>&1 || log_warning "npm install had issues"
        fi

        # Build if build script exists
        if grep -q '"build"' package.json 2>/dev/null; then
            log_info "Building application..."
            npm run build >> "$LOG_FILE" 2>&1 || log_warning "Build had issues"
        fi

        log_success "Node.js app configured"
    else
        log_warning "No package.json found"
    fi

    chown -R www-data:www-data "$APP_ROOT"
}

# Setup Python app
setup_python_app() {
    log_step "Setting up Python application..."

    cd "$APP_ROOT"

    # Create virtual environment
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        log_info "Created virtual environment"
    fi

    # Activate and install dependencies
    source venv/bin/activate

    log_info "Upgrading pip..."
    pip install --upgrade pip >> "$LOG_FILE" 2>&1

    # Ensure uvicorn and gunicorn are installed (common for Python web apps)
    log_info "Installing web server packages..."
    pip install uvicorn gunicorn >> "$LOG_FILE" 2>&1 || true

    if [ -f "requirements.txt" ]; then
        log_info "Installing Python dependencies (this may take a while)..."

        if pip install -r requirements.txt >> "$LOG_FILE" 2>&1; then
            log_success "Python dependencies installed"
        else
            log_warning "Some dependencies may have failed. Check $LOG_FILE"
        fi
    else
        log_warning "No requirements.txt found"
    fi

    deactivate

    chown -R www-data:www-data "$APP_ROOT"

    log_success "Python app configured"
}

# Setup Frontend application (Next.js, Nuxt.js, React, Vue, Angular, Svelte)
setup_frontend_app() {
    log_step "Setting up $APP_TYPE application..."

    cd "$APP_ROOT"

    # Create environment file with build-time variables
    create_frontend_env_file

    # Install dependencies based on package manager
    if [ -f "package.json" ]; then
        log_info "Installing dependencies with $PKG_MANAGER..."

        case $PKG_MANAGER in
            npm)
                npm ci >> "$LOG_FILE" 2>&1 || npm install >> "$LOG_FILE" 2>&1 || log_warning "Dependency installation had issues"
                ;;
            pnpm)
                pnpm install --frozen-lockfile >> "$LOG_FILE" 2>&1 || pnpm install >> "$LOG_FILE" 2>&1 || log_warning "Dependency installation had issues"
                ;;
            yarn)
                yarn install --frozen-lockfile >> "$LOG_FILE" 2>&1 || yarn install >> "$LOG_FILE" 2>&1 || log_warning "Dependency installation had issues"
                ;;
            bun)
                bun install --frozen-lockfile >> "$LOG_FILE" 2>&1 || bun install >> "$LOG_FILE" 2>&1 || log_warning "Dependency installation had issues"
                ;;
        esac

        log_success "Dependencies installed"

        # Build the application
        log_info "Building $APP_TYPE application..."
        log_info "Build command: $FRONTEND_BUILD_CMD"

        # Set environment for build
        export NODE_ENV=production

        if $FRONTEND_BUILD_CMD >> "$LOG_FILE" 2>&1; then
            log_success "$APP_TYPE build completed"
        else
            log_error "Build failed. Check $LOG_FILE for details"
            return 1
        fi

        # Verify build output exists
        verify_frontend_build

    else
        log_warning "No package.json found"
    fi

    chown -R www-data:www-data "$APP_ROOT"

    log_success "$APP_TYPE application configured"
}

# Create frontend environment file
create_frontend_env_file() {
    local env_file=""

    case $APP_TYPE in
        nextjs)
            env_file=".env.production"
            ;;
        nuxtjs)
            env_file=".env"
            ;;
        react|vue|angular|svelte)
            env_file=".env.production"
            ;;
    esac

    # Only create if no env file exists
    if [ -n "$env_file" ] && [ ! -f "$env_file" ]; then
        log_info "Creating $env_file..."

        # Start with basic config
        cat > "$env_file" << EOF
# Production environment
NODE_ENV=production
EOF

        # Add port for SSR apps
        if [[ "$FRONTEND_MODE" == "ssr" || "$FRONTEND_MODE" == "standalone" ]] && [ -n "$APP_PORT" ]; then
            echo "PORT=$APP_PORT" >> "$env_file"
        fi

        # Add API URL if configured
        if [ -n "$FRONTEND_API_URL" ]; then
            case $APP_TYPE in
                nextjs)
                    echo "NEXT_PUBLIC_API_URL=$FRONTEND_API_URL" >> "$env_file"
                    ;;
                nuxtjs)
                    echo "NUXT_PUBLIC_API_URL=$FRONTEND_API_URL" >> "$env_file"
                    ;;
                react)
                    echo "VITE_API_URL=$FRONTEND_API_URL" >> "$env_file"
                    echo "REACT_APP_API_URL=$FRONTEND_API_URL" >> "$env_file"
                    ;;
                vue)
                    echo "VITE_API_URL=$FRONTEND_API_URL" >> "$env_file"
                    echo "VUE_APP_API_URL=$FRONTEND_API_URL" >> "$env_file"
                    ;;
                angular)
                    # Angular uses environment.ts files, but we can still set
                    echo "API_URL=$FRONTEND_API_URL" >> "$env_file"
                    ;;
                svelte)
                    echo "VITE_API_URL=$FRONTEND_API_URL" >> "$env_file"
                    echo "PUBLIC_API_URL=$FRONTEND_API_URL" >> "$env_file"
                    ;;
            esac
        fi

        # Add custom environment variables
        if [ -n "${FRONTEND_ENV_VARS+x}" ] && [ ${#FRONTEND_ENV_VARS[@]} -gt 0 ]; then
            echo "" >> "$env_file"
            echo "# Custom environment variables" >> "$env_file"
            for var in "${FRONTEND_ENV_VARS[@]}"; do
                echo "$var" >> "$env_file"
            done
        fi

        log_success "Created $env_file"
    fi
}

# Verify frontend build output
verify_frontend_build() {
    local build_ok=false

    case $APP_TYPE in
        nextjs)
            if [ "$FRONTEND_MODE" == "static" ]; then
                [ -d "$APP_ROOT/out" ] && build_ok=true
            else
                [ -d "$APP_ROOT/.next" ] && build_ok=true
            fi
            ;;
        nuxtjs)
            if [ "$FRONTEND_MODE" == "static" ]; then
                [ -d "$APP_ROOT/dist" ] && build_ok=true
            else
                [ -d "$APP_ROOT/.output" ] && build_ok=true
            fi
            ;;
        react)
            [ -d "$APP_ROOT/$FRONTEND_STATIC_DIR" ] && build_ok=true
            ;;
        vue)
            [ -d "$APP_ROOT/dist" ] && build_ok=true
            ;;
        angular)
            [ -d "$APP_ROOT/$FRONTEND_STATIC_DIR" ] && build_ok=true
            ;;
        svelte)
            [ -d "$APP_ROOT/build" ] && build_ok=true
            ;;
    esac

    if [ "$build_ok" = true ]; then
        log_success "Build output verified"
    else
        log_warning "Build output directory not found. Build may have failed."
    fi
}

# Get frontend document root (for static/SPA deployments)
get_frontend_doc_root() {
    case $APP_TYPE in
        nextjs)
            if [ "$FRONTEND_MODE" == "static" ]; then
                echo "$APP_ROOT/out"
            else
                echo "$APP_ROOT"
            fi
            ;;
        nuxtjs)
            if [ "$FRONTEND_MODE" == "static" ]; then
                echo "$APP_ROOT/dist"
            elif [ "$FRONTEND_MODE" == "spa" ]; then
                echo "$APP_ROOT/.output/public"
            else
                echo "$APP_ROOT"
            fi
            ;;
        react)
            echo "$APP_ROOT/$FRONTEND_STATIC_DIR"
            ;;
        vue)
            echo "$APP_ROOT/dist"
            ;;
        angular)
            echo "$APP_ROOT/$FRONTEND_STATIC_DIR"
            ;;
        svelte)
            if [ "$FRONTEND_MODE" == "static" ] || [ "$FRONTEND_MODE" == "spa" ]; then
                echo "$APP_ROOT/build"
            else
                echo "$APP_ROOT"
            fi
            ;;
        *)
            echo "$APP_ROOT"
            ;;
    esac
}

# Setup PM2
setup_pm2() {
    if [ "$USE_PM2" != true ]; then
        return
    fi

    log_step "Configuring PM2..."

    cd "$APP_ROOT"

    # Create log directory
    mkdir -p /var/log/pm2
    chown -R www-data:www-data /var/log/pm2

    # Create ecosystem file based on app type
    if [ "$APP_TYPE" == "nodejs" ]; then
        cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    cwd: '$APP_ROOT',
    script: 'npm',
    args: 'start',
    env: {
      NODE_ENV: 'production',
      PORT: $APP_PORT
    },
    instances: 'max',
    exec_mode: 'cluster',
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/var/log/pm2/${PM2_APP_NAME}-error.log',
    out_file: '/var/log/pm2/${PM2_APP_NAME}-out.log',
    merge_logs: true,
    time: true
  }]
};
EOF
    elif [ "$APP_TYPE" == "nextjs" ]; then
        # Next.js SSR/Standalone configuration
        if [ "$FRONTEND_MODE" == "standalone" ]; then
            cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    cwd: '$APP_ROOT/.next/standalone',
    script: 'server.js',
    env: {
      NODE_ENV: 'production',
      PORT: $APP_PORT,
      HOSTNAME: '127.0.0.1'
    },
    instances: 'max',
    exec_mode: 'cluster',
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/var/log/pm2/${PM2_APP_NAME}-error.log',
    out_file: '/var/log/pm2/${PM2_APP_NAME}-out.log',
    merge_logs: true,
    time: true
  }]
};
EOF
            # Copy static and public folders for standalone mode
            if [ -d "$APP_ROOT/.next/static" ]; then
                cp -r "$APP_ROOT/.next/static" "$APP_ROOT/.next/standalone/.next/" 2>/dev/null || true
            fi
            if [ -d "$APP_ROOT/public" ]; then
                cp -r "$APP_ROOT/public" "$APP_ROOT/.next/standalone/" 2>/dev/null || true
            fi
        else
            # Standard Next.js SSR
            local pkg_cmd="npm"
            [ "$PKG_MANAGER" == "pnpm" ] && pkg_cmd="pnpm"
            [ "$PKG_MANAGER" == "yarn" ] && pkg_cmd="yarn"
            [ "$PKG_MANAGER" == "bun" ] && pkg_cmd="bun"

            cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    cwd: '$APP_ROOT',
    script: '$pkg_cmd',
    args: 'start',
    env: {
      NODE_ENV: 'production',
      PORT: $APP_PORT
    },
    instances: 1,
    exec_mode: 'fork',
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/var/log/pm2/${PM2_APP_NAME}-error.log',
    out_file: '/var/log/pm2/${PM2_APP_NAME}-out.log',
    merge_logs: true,
    time: true
  }]
};
EOF
        fi
    elif [ "$APP_TYPE" == "nuxtjs" ]; then
        # Nuxt.js SSR configuration
        cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    cwd: '$APP_ROOT',
    script: '.output/server/index.mjs',
    env: {
      NODE_ENV: 'production',
      PORT: $APP_PORT,
      HOST: '127.0.0.1',
      NITRO_PORT: $APP_PORT,
      NITRO_HOST: '127.0.0.1'
    },
    instances: 'max',
    exec_mode: 'cluster',
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/var/log/pm2/${PM2_APP_NAME}-error.log',
    out_file: '/var/log/pm2/${PM2_APP_NAME}-out.log',
    merge_logs: true,
    time: true
  }]
};
EOF
    elif [ "$APP_TYPE" == "svelte" ] && [ "$FRONTEND_MODE" == "ssr" ]; then
        # SvelteKit SSR configuration
        cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    cwd: '$APP_ROOT',
    script: 'build/index.js',
    env: {
      NODE_ENV: 'production',
      PORT: $APP_PORT,
      HOST: '127.0.0.1'
    },
    instances: 'max',
    exec_mode: 'cluster',
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/var/log/pm2/${PM2_APP_NAME}-error.log',
    out_file: '/var/log/pm2/${PM2_APP_NAME}-out.log',
    merge_logs: true,
    time: true
  }]
};
EOF
    elif [ "$APP_TYPE" == "python" ]; then
        # Parse the start command
        local py_script=$(echo "$START_CMD" | awk '{print $1}')
        local py_args=$(echo "$START_CMD" | cut -d' ' -f2- -s)

        # If py_args is empty (single word command), set it to empty string
        [ "$py_args" = "$py_script" ] && py_args=""

        cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    cwd: '$APP_ROOT',
    script: './venv/bin/$py_script',
    args: '$py_args',
    interpreter: 'none',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/var/log/pm2/${PM2_APP_NAME}-error.log',
    out_file: '/var/log/pm2/${PM2_APP_NAME}-out.log',
    merge_logs: true,
    time: true
  }]
};
EOF
    fi

    chown www-data:www-data ecosystem.config.js

    # Stop existing app if running
    pm2 delete "$PM2_APP_NAME" >> "$LOG_FILE" 2>&1 || true

    # Start app with proper user
    log_info "Starting application with PM2..."
    cd "$APP_ROOT"

    if sudo -u www-data pm2 start ecosystem.config.js >> "$LOG_FILE" 2>&1; then
        log_debug "PM2 started as www-data"
    else
        pm2 start ecosystem.config.js >> "$LOG_FILE" 2>&1 || log_warning "PM2 start had issues"
    fi

    # Save PM2 process list
    sudo -u www-data pm2 save >> "$LOG_FILE" 2>&1 || pm2 save >> "$LOG_FILE" 2>&1 || true

    # Setup startup script
    pm2 startup systemd -u www-data --hp /var/www >> "$LOG_FILE" 2>&1 || true

    log_success "PM2 configured"
}

# Setup Systemd service
setup_systemd() {
    if [ "$USE_SYSTEMD" != true ]; then
        return
    fi

    log_step "Configuring Systemd service..."

    local service_file="/etc/systemd/system/${SYSTEMD_APP_NAME}.service"

    if [ "$APP_TYPE" == "nodejs" ]; then
        cat > "$service_file" << EOF
[Unit]
Description=$PM2_APP_NAME Node.js Application
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_ROOT
Environment=NODE_ENV=production
Environment=PORT=$APP_PORT
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/${SYSTEMD_APP_NAME}.log
StandardError=append:/var/log/${SYSTEMD_APP_NAME}.error.log

[Install]
WantedBy=multi-user.target
EOF
    elif [ "$APP_TYPE" == "python" ]; then
        cat > "$service_file" << EOF
[Unit]
Description=$PM2_APP_NAME Python Application
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_ROOT
Environment=PATH=$APP_ROOT/venv/bin:/usr/bin
ExecStart=$APP_ROOT/venv/bin/$START_CMD
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/${SYSTEMD_APP_NAME}.log
StandardError=append:/var/log/${SYSTEMD_APP_NAME}.error.log

[Install]
WantedBy=multi-user.target
EOF
    fi

    # Create log files
    touch "/var/log/${SYSTEMD_APP_NAME}.log" "/var/log/${SYSTEMD_APP_NAME}.error.log"
    chown www-data:www-data "/var/log/${SYSTEMD_APP_NAME}.log" "/var/log/${SYSTEMD_APP_NAME}.error.log"

    # Reload and start service
    systemctl daemon-reload
    systemctl enable "${SYSTEMD_APP_NAME}" >> "$LOG_FILE" 2>&1
    systemctl start "${SYSTEMD_APP_NAME}" >> "$LOG_FILE" 2>&1 || log_warning "Service start had issues"

    log_success "Systemd service configured: ${SYSTEMD_APP_NAME}"
}

# ============================================================================
# APACHE CONFIGURATION
# ============================================================================

create_apache_config() {
    log_step "Creating Apache virtual host..."

    local config_file="/etc/apache2/sites-available/${DOMAIN}.conf"

    # Backup existing config
    backup_item "$config_file"

    # Build ServerAlias line
    local alias_line=""
    if [ -n "$SERVER_ALIASES" ]; then
        alias_line="    ServerAlias $SERVER_ALIASES"
    fi

    # Determine document root for frontend static apps
    local frontend_doc_root=""
    if [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|react|vue|angular|svelte)$ ]] && [[ "$FRONTEND_MODE" == "static" || "$FRONTEND_MODE" == "spa" ]]; then
        frontend_doc_root=$(get_frontend_doc_root)
    fi

    if [ "$USE_PROXY" = true ]; then
        # Reverse proxy configuration (for SSR apps and backend services)
        cat > "$config_file" << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
$alias_line

    # Proxy settings
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$APP_PORT/
    ProxyPassReverse / http://127.0.0.1:$APP_PORT/

    # WebSocket support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://127.0.0.1:$APP_PORT/\$1" [P,L]

    # Timeouts for long-running connections
    ProxyTimeout 300

    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # Logging
    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF
    elif [ -n "$frontend_doc_root" ]; then
        # Frontend SPA/Static configuration with optimized caching
        cat > "$config_file" << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
$alias_line

    DocumentRoot $frontend_doc_root

    <Directory $frontend_doc_root>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted

        # SPA fallback - serve index.html for all routes
        RewriteEngine On
        RewriteBase /
        RewriteRule ^index\.html\$ - [L]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . /index.html [L]
    </Directory>

    # Enable compression
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css application/javascript application/json image/svg+xml application/wasm
    </IfModule>

    # Cache static assets with hashed filenames (immutable)
    <IfModule mod_expires.c>
        ExpiresActive On

        # HTML - no cache (SPA needs fresh HTML)
        <FilesMatch "\.html\$">
            ExpiresDefault "access plus 0 seconds"
            Header set Cache-Control "no-cache, no-store, must-revalidate"
        </FilesMatch>

        # Hashed assets (JS, CSS with hash in filename) - cache forever
        <FilesMatch "\.[a-f0-9]{8,}\.(js|css)\$">
            ExpiresDefault "access plus 1 year"
            Header set Cache-Control "public, max-age=31536000, immutable"
        </FilesMatch>

        # Regular JS/CSS without hash
        <FilesMatch "\.(js|css)\$">
            ExpiresDefault "access plus 1 month"
            Header set Cache-Control "public, max-age=2592000"
        </FilesMatch>

        # Images and fonts
        <FilesMatch "\.(jpg|jpeg|png|gif|ico|svg|webp|avif|woff|woff2|ttf|eot)\$">
            ExpiresDefault "access plus 1 year"
            Header set Cache-Control "public, max-age=31536000, immutable"
        </FilesMatch>

        # JSON and other data files
        <FilesMatch "\.(json|xml)\$">
            ExpiresDefault "access plus 1 hour"
            Header set Cache-Control "public, max-age=3600"
        </FilesMatch>
    </IfModule>

    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # Hide sensitive files
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>

    # Block access to source maps in production (optional - remove if needed for debugging)
    <FilesMatch "\.map\$">
        Require all denied
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF
    elif [ "$APP_TYPE" == "php" ]; then
        # PHP configuration
        cat > "$config_file" << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
$alias_line

    DocumentRoot $APP_ROOT/$PHP_DOC_ROOT

    <Directory $APP_ROOT/$PHP_DOC_ROOT>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:$PHP_FPM_SOCK|fcgi://localhost"
    </FilesMatch>

    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # Hide sensitive files
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF
    else
        # Static files configuration
        cat > "$config_file" << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
$alias_line

    DocumentRoot $APP_ROOT

    <Directory $APP_ROOT>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Enable compression
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css application/javascript application/json image/svg+xml
    </IfModule>

    # Cache static assets
    <IfModule mod_expires.c>
        ExpiresActive On
        ExpiresByType image/jpg "access plus 1 year"
        ExpiresByType image/jpeg "access plus 1 year"
        ExpiresByType image/gif "access plus 1 year"
        ExpiresByType image/png "access plus 1 year"
        ExpiresByType image/webp "access plus 1 year"
        ExpiresByType image/svg+xml "access plus 1 year"
        ExpiresByType text/css "access plus 1 month"
        ExpiresByType application/javascript "access plus 1 month"
        ExpiresByType font/woff2 "access plus 1 year"
    </IfModule>

    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF
    fi

    # Enable site
    a2ensite "${DOMAIN}.conf" >> "$LOG_FILE" 2>&1
    a2dissite 000-default.conf >> "$LOG_FILE" 2>&1 || true

    # Test and reload
    if apache2ctl configtest >> "$LOG_FILE" 2>&1; then
        systemctl reload apache2 >> "$LOG_FILE" 2>&1
        log_success "Apache virtual host created"
    else
        log_error "Apache configuration test failed. Check $LOG_FILE"
    fi
}

# ============================================================================
# NGINX CONFIGURATION
# ============================================================================

create_nginx_config() {
    log_step "Creating Nginx server block..."

    local config_file="/etc/nginx/sites-available/${DOMAIN}"

    # Backup existing config
    backup_item "$config_file"

    # Build server_name line
    local server_names="$DOMAIN"
    if [ -n "$SERVER_ALIASES" ]; then
        server_names="$DOMAIN $SERVER_ALIASES"
    fi

    # Determine document root for frontend static apps
    local frontend_doc_root=""
    if [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|react|vue|angular|svelte)$ ]] && [[ "$FRONTEND_MODE" == "static" || "$FRONTEND_MODE" == "spa" ]]; then
        frontend_doc_root=$(get_frontend_doc_root)
    fi

    if [ "$USE_PROXY" = true ]; then
        # Reverse proxy configuration (for SSR apps and backend services)
        cat > "$config_file" << EOF
upstream ${DOMAIN//./_}_backend {
    server 127.0.0.1:$APP_PORT;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name $server_names;

    # Proxy settings
    location / {
        proxy_pass http://${DOMAIN//./_}_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml application/wasm;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;
}
EOF
    elif [ -n "$frontend_doc_root" ]; then
        # Frontend SPA/Static configuration with optimized caching
        cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $server_names;

    root $frontend_doc_root;
    index index.html;

    # Security - hide sensitive files
    location ~ /\. {
        deny all;
    }

    # Block source maps in production
    location ~* \.map\$ {
        deny all;
    }

    # SPA fallback - serve index.html for all routes
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Cache hashed assets (immutable) - matches patterns like main.abc123.js
    location ~* \.[a-f0-9]{8,}\.(js|css)\$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }

    # Cache static assets (images, fonts)
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp|avif|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }

    # Cache regular JS/CSS (without hash)
    location ~* \.(js|css)\$ {
        expires 1M;
        add_header Cache-Control "public, max-age=2592000";
        access_log off;
    }

    # No cache for HTML (SPA needs fresh HTML)
    location ~* \.html\$ {
        expires -1;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # Cache JSON and data files briefly
    location ~* \.(json|xml)\$ {
        expires 1h;
        add_header Cache-Control "public, max-age=3600";
    }

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml application/wasm;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;
}
EOF
    elif [ "$APP_TYPE" == "php" ]; then
        # PHP configuration
        cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $server_names;

    root $APP_ROOT/$PHP_DOC_ROOT;
    index index.php index.html index.htm;

    # Security - hide sensitive files
    location ~ /\. {
        deny all;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:$PHP_FPM_SOCK;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;
}
EOF
    else
        # Static files configuration
        cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $server_names;

    root $APP_ROOT;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }

    # Security - hide sensitive files
    location ~ /\. {
        deny all;
    }

    # Cache static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|webp|woff|woff2|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;
}
EOF
    fi

    # Enable site
    ln -sf "$config_file" "/etc/nginx/sites-enabled/${DOMAIN}"
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    # Test and reload
    if nginx -t >> "$LOG_FILE" 2>&1; then
        systemctl reload nginx >> "$LOG_FILE" 2>&1
        log_success "Nginx server block created"
    else
        log_error "Nginx configuration test failed. Check $LOG_FILE"
    fi
}

# ============================================================================
# SSL CONFIGURATION
# ============================================================================

setup_ssl() {
    if [ "$SSL_TYPE" == "none" ]; then
        log_info "Skipping SSL setup"
        return
    fi

    log_step "Setting up SSL..."

    case $SSL_TYPE in
        letsencrypt)
            setup_letsencrypt
            ;;
        selfsigned)
            setup_selfsigned
            ;;
        existing)
            setup_existing_ssl
            ;;
    esac
}

setup_letsencrypt() {
    install_package "certbot"

    # Build domain list for certbot
    local domains="-d $DOMAIN"
    if [ -n "$SERVER_ALIASES" ]; then
        for alias in $SERVER_ALIASES; do
            domains="$domains -d $alias"
        done
    fi

    if [ "$WEB_SERVER" == "apache2" ]; then
        install_package "python3-certbot-apache"

        log_info "Obtaining Let's Encrypt certificate..."
        if certbot --apache $domains --non-interactive --agree-tos --email "$SSL_EMAIL" --redirect >> "$LOG_FILE" 2>&1; then
            log_success "Let's Encrypt SSL configured"
        else
            log_warning "Certbot failed. You can run manually: sudo certbot --apache $domains"
        fi
    else
        install_package "python3-certbot-nginx"

        log_info "Obtaining Let's Encrypt certificate..."
        if certbot --nginx $domains --non-interactive --agree-tos --email "$SSL_EMAIL" --redirect >> "$LOG_FILE" 2>&1; then
            log_success "Let's Encrypt SSL configured"
        else
            log_warning "Certbot failed. You can run manually: sudo certbot --nginx $domains"
        fi
    fi

    # Enable auto-renewal
    systemctl enable certbot.timer >> "$LOG_FILE" 2>&1 || true
    systemctl start certbot.timer >> "$LOG_FILE" 2>&1 || true
}

setup_selfsigned() {
    local ssl_dir="/etc/ssl/$DOMAIN"
    mkdir -p "$ssl_dir"

    log_info "Generating self-signed certificate..."

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$ssl_dir/privkey.pem" \
        -out "$ssl_dir/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN" \
        >> "$LOG_FILE" 2>&1

    SSL_CERT_PATH="$ssl_dir/fullchain.pem"
    SSL_KEY_PATH="$ssl_dir/privkey.pem"

    configure_ssl_vhost

    log_success "Self-signed SSL certificate created"
    log_warning "Browsers will show a security warning for self-signed certificates"
}

setup_existing_ssl() {
    configure_ssl_vhost
    log_success "Existing SSL certificate configured"
}

configure_ssl_vhost() {
    local server_names="$DOMAIN"
    if [ -n "$SERVER_ALIASES" ]; then
        server_names="$DOMAIN $SERVER_ALIASES"
    fi

    if [ "$WEB_SERVER" == "apache2" ]; then
        local ssl_config="/etc/apache2/sites-available/${DOMAIN}-ssl.conf"

        # Read the HTTP config and modify for SSL
        if [ "$USE_PROXY" = true ]; then
            cat > "$ssl_config" << EOF
<VirtualHost *:443>
    ServerName $DOMAIN
    $([ -n "$SERVER_ALIASES" ] && echo "    ServerAlias $SERVER_ALIASES")

    SSLEngine on
    SSLCertificateFile $SSL_CERT_PATH
    SSLCertificateKeyFile $SSL_KEY_PATH

    # Proxy settings
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$APP_PORT/
    ProxyPassReverse / http://127.0.0.1:$APP_PORT/

    # WebSocket support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://127.0.0.1:$APP_PORT/\$1" [P,L]

    ProxyTimeout 300

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_ssl_access.log combined
</VirtualHost>
EOF
        else
            cat > "$ssl_config" << EOF
<VirtualHost *:443>
    ServerName $DOMAIN
    $([ -n "$SERVER_ALIASES" ] && echo "    ServerAlias $SERVER_ALIASES")

    SSLEngine on
    SSLCertificateFile $SSL_CERT_PATH
    SSLCertificateKeyFile $SSL_KEY_PATH

    DocumentRoot $APP_ROOT$([ "$APP_TYPE" == "php" ] && echo "/$PHP_DOC_ROOT")

    <Directory $APP_ROOT$([ "$APP_TYPE" == "php" ] && echo "/$PHP_DOC_ROOT")>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    $([ "$APP_TYPE" == "php" ] && echo "
    <FilesMatch \.php$>
        SetHandler \"proxy:unix:$PHP_FPM_SOCK|fcgi://localhost\"
    </FilesMatch>")

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_ssl_access.log combined
</VirtualHost>
EOF
        fi

        # Add HTTP to HTTPS redirect
        cat >> "/etc/apache2/sites-available/${DOMAIN}.conf" << EOF

# Redirect HTTP to HTTPS
<VirtualHost *:80>
    ServerName $DOMAIN
    $([ -n "$SERVER_ALIASES" ] && echo "    ServerAlias $SERVER_ALIASES")
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
EOF

        a2ensite "${DOMAIN}-ssl.conf" >> "$LOG_FILE" 2>&1
        apache2ctl configtest >> "$LOG_FILE" 2>&1 && systemctl reload apache2 >> "$LOG_FILE" 2>&1

    else
        # Nginx SSL configuration
        cat >> "/etc/nginx/sites-available/${DOMAIN}" << EOF

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $server_names;

    ssl_certificate $SSL_CERT_PATH;
    ssl_certificate_key $SSL_KEY_PATH;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    $(if [ "$USE_PROXY" = true ]; then
        echo "
    location / {
        proxy_pass http://${DOMAIN//./_}_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }"
    else
        echo "
    root $APP_ROOT$([ "$APP_TYPE" == "php" ] && echo "/$PHP_DOC_ROOT");
    index index$([ "$APP_TYPE" == "php" ] && echo ".php") index.html;

    location / {
        try_files \$uri \$uri/ $([ "$APP_TYPE" == "php" ] && echo "/index.php?\$query_string" || echo "=404");
    }

    $([ "$APP_TYPE" == "php" ] && echo "
    location ~ \.php$ {
        fastcgi_pass unix:$PHP_FPM_SOCK;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }")"
    fi)

    access_log /var/log/nginx/${DOMAIN}_ssl_access.log;
    error_log /var/log/nginx/${DOMAIN}_ssl_error.log;
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $server_names;
    return 301 https://\$host\$request_uri;
}
EOF

        nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx >> "$LOG_FILE" 2>&1
    fi
}

# ============================================================================
# HELPER SCRIPTS
# ============================================================================

create_helper_scripts() {
    log_step "Creating helper scripts..."

    # Update script
    cat > "$APP_ROOT/update.sh" << 'SCRIPT_HEADER'
#!/bin/bash
set -e
SCRIPT_HEADER

    cat >> "$APP_ROOT/update.sh" << EOF
echo "Updating $DOMAIN..."
cd "$APP_ROOT"

# Pull latest code
if [ -d ".git" ]; then
    git pull origin ${GIT_BRANCH:-main}
fi

EOF

    if [ "$APP_TYPE" == "nodejs" ]; then
        cat >> "$APP_ROOT/update.sh" << EOF
# Update Node.js dependencies
npm ci --omit=dev || npm install --omit=dev
npm run build 2>/dev/null || true
EOF
    elif [ "$APP_TYPE" == "python" ]; then
        cat >> "$APP_ROOT/update.sh" << EOF
# Update Python dependencies
source venv/bin/activate
pip install -r requirements.txt
alembic upgrade head 2>/dev/null || true
deactivate
EOF
    elif [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|react|vue|angular|svelte)$ ]]; then
        # Frontend update script
        local install_cmd=""
        local build_cmd="$FRONTEND_BUILD_CMD"
        case $PKG_MANAGER in
            npm) install_cmd="npm ci || npm install";;
            pnpm) install_cmd="pnpm install --frozen-lockfile || pnpm install";;
            yarn) install_cmd="yarn install --frozen-lockfile || yarn install";;
            bun) install_cmd="bun install --frozen-lockfile || bun install";;
        esac

        cat >> "$APP_ROOT/update.sh" << EOF
# Update frontend dependencies
export NODE_ENV=production
$install_cmd

# Build frontend
echo "Building $APP_TYPE application..."
$build_cmd
EOF
    fi

    if [ "$USE_PM2" = true ]; then
        echo "pm2 restart $PM2_APP_NAME" >> "$APP_ROOT/update.sh"
    elif [ "$USE_SYSTEMD" = true ]; then
        echo "sudo systemctl restart $SYSTEMD_APP_NAME" >> "$APP_ROOT/update.sh"
    fi

    echo 'echo "Update complete!"' >> "$APP_ROOT/update.sh"

    # Restart script
    cat > "$APP_ROOT/restart.sh" << EOF
#!/bin/bash
echo "Restarting services..."
EOF

    if [ "$USE_PM2" = true ]; then
        echo "pm2 restart $PM2_APP_NAME" >> "$APP_ROOT/restart.sh"
    elif [ "$USE_SYSTEMD" = true ]; then
        echo "sudo systemctl restart $SYSTEMD_APP_NAME" >> "$APP_ROOT/restart.sh"
    fi

    echo "sudo systemctl reload $WEB_SERVER" >> "$APP_ROOT/restart.sh"
    echo 'echo "Services restarted"' >> "$APP_ROOT/restart.sh"

    # Logs script
    cat > "$APP_ROOT/logs.sh" << EOF
#!/bin/bash
echo "=== Application Logs ==="
EOF

    if [ "$USE_PM2" = true ]; then
        echo "pm2 logs $PM2_APP_NAME --lines 50" >> "$APP_ROOT/logs.sh"
    elif [ "$USE_SYSTEMD" = true ]; then
        echo "sudo journalctl -u $SYSTEMD_APP_NAME -n 50 --no-pager" >> "$APP_ROOT/logs.sh"
    fi

    cat >> "$APP_ROOT/logs.sh" << EOF
echo ""
echo "=== Web Server Error Logs ==="
sudo tail -50 /var/log/${WEB_SERVER}/${DOMAIN}*error.log 2>/dev/null || sudo tail -50 /var/log/${WEB_SERVER}/error.log
EOF

    # Status script
    cat > "$APP_ROOT/status.sh" << EOF
#!/bin/bash
echo "=== $DOMAIN Status ==="
echo ""
echo "Web Server ($WEB_SERVER):"
systemctl status $WEB_SERVER --no-pager | head -5
EOF

    if [ "$USE_PM2" = true ]; then
        cat >> "$APP_ROOT/status.sh" << EOF
echo ""
echo "PM2 Application:"
pm2 status $PM2_APP_NAME
EOF
    elif [ "$USE_SYSTEMD" = true ]; then
        cat >> "$APP_ROOT/status.sh" << EOF
echo ""
echo "Application Service:"
systemctl status $SYSTEMD_APP_NAME --no-pager | head -10
EOF
    fi

    if [ "$SSL_TYPE" == "letsencrypt" ]; then
        cat >> "$APP_ROOT/status.sh" << EOF
echo ""
echo "SSL Certificate:"
sudo certbot certificates 2>/dev/null | grep -A3 "$DOMAIN" || echo "No Let's Encrypt certificate found"
EOF
    fi

    # Make scripts executable
    chmod +x "$APP_ROOT"/*.sh
    chown -R www-data:www-data "$APP_ROOT"

    log_success "Helper scripts created"
}

# ============================================================================
# SUMMARY
# ============================================================================

print_summary() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                    ${GREEN}SETUP COMPLETE!${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo "  Domain:          $DOMAIN"
    [ -n "$SERVER_ALIASES" ] && echo "  Aliases:         $SERVER_ALIASES"
    echo "  Web Server:      $WEB_SERVER"
    echo "  App Type:        $APP_TYPE"
    # Show frontend-specific config
    if [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|react|vue|angular|svelte)$ ]]; then
        echo "  Deploy Mode:     $FRONTEND_MODE"
        echo "  Node.js:         v${NODE_VERSION}.x"
        echo "  Pkg Manager:     $PKG_MANAGER"
    fi
    echo "  App Directory:   $APP_ROOT"
    [ "$USE_PROXY" = true ] && echo "  App Port:        $APP_PORT"
    echo "  SSL:             $SSL_TYPE"
    [ "$USE_PM2" = true ] && echo "  Process Manager: PM2 ($PM2_APP_NAME)"
    [ "$USE_SYSTEMD" = true ] && echo "  Process Manager: Systemd ($SYSTEMD_APP_NAME)"
    [ "$SETUP_FIREWALL" = true ] && echo "  Firewall:        UFW enabled"
    echo ""
    echo -e "${BOLD}URLs:${NC}"
    if [ "$SSL_TYPE" != "none" ]; then
        echo -e "  ${GREEN}https://$DOMAIN${NC}"
    else
        echo -e "  ${YELLOW}http://$DOMAIN${NC}"
    fi
    echo ""
    echo -e "${BOLD}Helper Scripts:${NC}"
    echo "  Update:   sudo $APP_ROOT/update.sh"
    echo "  Restart:  sudo $APP_ROOT/restart.sh"
    echo "  Logs:     $APP_ROOT/logs.sh"
    echo "  Status:   $APP_ROOT/status.sh"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    if [ "$USE_PM2" = true ]; then
        echo "  pm2 status                      # Check app status"
        echo "  pm2 logs $PM2_APP_NAME          # View app logs"
        echo "  pm2 restart $PM2_APP_NAME       # Restart app"
    elif [ "$USE_SYSTEMD" = true ]; then
        echo "  systemctl status $SYSTEMD_APP_NAME   # Check app status"
        echo "  journalctl -u $SYSTEMD_APP_NAME -f   # View app logs"
        echo "  systemctl restart $SYSTEMD_APP_NAME  # Restart app"
    fi
    echo "  systemctl status $WEB_SERVER    # Web server status"
    echo ""
    echo -e "${BOLD}Log File:${NC}"
    echo "  $LOG_FILE"
    echo ""

    if [ "$APP_TYPE" == "python" ]; then
        echo -e "${YELLOW}Note:${NC} Don't forget to:"
        echo "  1. Create your .env file: nano $APP_ROOT/.env"
        echo "  2. Run migrations: cd $APP_ROOT && source venv/bin/activate && alembic upgrade head"
        echo ""
    fi

    if [ "$APP_TYPE" == "nodejs" ]; then
        echo -e "${YELLOW}Note:${NC} Configure environment variables in:"
        echo "  $APP_ROOT/.env.local or $APP_ROOT/.env.production"
        echo ""
    fi

    # Frontend-specific notes
    if [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|react|vue|angular|svelte)$ ]]; then
        echo -e "${YELLOW}Frontend Deployment Notes:${NC}"
        if [[ "$FRONTEND_MODE" == "ssr" || "$FRONTEND_MODE" == "standalone" ]]; then
            echo "  Your $APP_TYPE app is running in SSR mode"
            echo "  - Application is proxied through $WEB_SERVER"
            if [ "$USE_PM2" = true ]; then
                echo "  - Process managed by PM2"
            fi
        else
            echo "  Your $APP_TYPE app is deployed as static files"
            echo "  - Files served from: $(get_frontend_doc_root)"
        fi
        echo ""
        echo -e "${BOLD}Rebuild & Redeploy:${NC}"
        echo "  cd $APP_ROOT && $FRONTEND_BUILD_CMD"
        if [[ "$FRONTEND_MODE" == "ssr" || "$FRONTEND_MODE" == "standalone" ]] && [ "$USE_PM2" = true ]; then
            echo "  pm2 restart $PM2_APP_NAME"
        fi
        echo ""
    fi

    if [ "$INSTALL_DATABASE" != "none" ]; then
        echo -e "${YELLOW}Database:${NC} $INSTALL_DATABASE is installed"
        if [ "$INSTALL_DATABASE" == "mysql" ]; then
            echo "  Run: sudo mysql_secure_installation"
        fi
        echo ""
    fi

    echo -e "${GREEN}Setup completed successfully!${NC}"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header
    check_root
    detect_os

    # Gather configuration
    select_web_server
    select_app_type
    get_domain_config
    get_app_directory
    get_port_config
    get_git_config
    get_php_config
    get_pm_config
    get_database_config
    get_firewall_config
    get_ssl_config

    echo ""
    echo -e "${BOLD}Configuration Summary:${NC}"
    echo "  Web Server:    $WEB_SERVER"
    echo "  App Type:      $APP_TYPE"
    # Show frontend-specific info
    if [[ "$APP_TYPE" =~ ^(nextjs|nuxtjs|react|vue|angular|svelte)$ ]]; then
        echo "  Mode:          $FRONTEND_MODE"
        echo "  Node.js:       v${NODE_VERSION}.x"
        echo "  Pkg Manager:   $PKG_MANAGER"
    fi
    echo "  Domain:        $DOMAIN"
    echo "  Directory:     $APP_ROOT"
    [ "$USE_PROXY" = true ] && echo "  Port:          $APP_PORT"
    echo "  SSL:           $SSL_TYPE"
    [ "$USE_GIT" = true ] && echo "  Git:           $GIT_REPO ($GIT_BRANCH)"
    echo ""

    read -p "Continue with installation? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Setup cancelled by user"
        exit 1
    fi

    echo ""
    log_step "Starting installation..."
    echo ""

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Install components
    update_packages
    install_essentials

    case $WEB_SERVER in
        apache2) install_apache;;
        nginx) install_nginx;;
    esac

    case $APP_TYPE in
        nodejs) install_nodejs;;
        python) install_python;;
        php) install_php;;
        nextjs|nuxtjs|react|vue|angular|svelte) install_nodejs;;
    esac

    install_database
    setup_firewall

    # Setup application
    setup_app_directory

    case $APP_TYPE in
        nodejs) setup_nodejs_app;;
        python) setup_python_app;;
        nextjs|nuxtjs|react|vue|angular|svelte) setup_frontend_app;;
    esac

    setup_pm2
    setup_systemd

    # Configure web server
    case $WEB_SERVER in
        apache2) create_apache_config;;
        nginx) create_nginx_config;;
    esac

    # Setup SSL
    setup_ssl

    # Create helper scripts
    create_helper_scripts

    # Print summary
    print_summary
}

# Run main function
main "$@"
