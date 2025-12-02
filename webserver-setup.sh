#!/bin/bash

# ============================================================================
# Universal Web Server Setup Script
# ============================================================================
# A comprehensive tool for setting up web applications with:
# - Apache2 or Nginx (auto-install if missing)
# - Reverse proxy configuration
# - Static file serving
# - SSL/TLS with Let's Encrypt or self-signed
# - Multiple app support (Node.js, Python, PHP, static)
# - PM2 process management for Node.js/Python apps
#
# Usage:
#   chmod +x webserver-setup.sh
#   sudo ./webserver-setup.sh
#
# ============================================================================

set -e

VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${MAGENTA}[STEP]${NC} $1"; }

# Header
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                  Universal Web Server Setup v${VERSION}                  ║"
    echo "║                   Apache2 • Nginx • SSL • Proxy                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "Cannot detect OS. This script supports Ubuntu/Debian."
        exit 1
    fi

    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_warning "This script is optimized for Ubuntu/Debian. Proceeding anyway..."
    fi

    log_info "Detected OS: $OS $OS_VERSION"
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Install package if not installed
install_package() {
    local pkg=$1
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        log_info "Installing $pkg..."
        apt-get install -y "$pkg" >/dev/null 2>&1
        log_success "$pkg installed"
    else
        log_success "$pkg already installed"
    fi
}

# ============================================================================
# MENU FUNCTIONS
# ============================================================================

# Select web server
select_web_server() {
    echo ""
    echo -e "${BOLD}Select Web Server:${NC}"
    echo "  1) Apache2"
    echo "  2) Nginx"
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
    echo "  1) Node.js (Next.js, Express, etc.)"
    echo "  2) Python (FastAPI, Django, Flask)"
    echo "  3) PHP (Laravel, WordPress, etc.)"
    echo "  4) Static Files (HTML, CSS, JS)"
    echo "  5) Reverse Proxy Only (app already running)"
    echo ""

    while true; do
        read -p "Enter choice [1-5]: " choice
        case $choice in
            1) APP_TYPE="nodejs"; break;;
            2) APP_TYPE="python"; break;;
            3) APP_TYPE="php"; break;;
            4) APP_TYPE="static"; break;;
            5) APP_TYPE="proxy"; break;;
            *) echo "Invalid choice. Please enter 1-5.";;
        esac
    done

    log_info "Selected app type: $APP_TYPE"
}

# Get domain configuration
get_domain_config() {
    echo ""
    echo -e "${BOLD}Domain Configuration:${NC}"

    read -p "Enter domain name (e.g., example.com or api.example.com): " DOMAIN
    while [ -z "$DOMAIN" ]; do
        echo "Domain cannot be empty."
        read -p "Enter domain name: " DOMAIN
    done

    # Check if domain already has a subdomain (e.g., api.example.com has 2 dots worth of parts)
    SERVER_ALIASES=""
    INCLUDE_WWW=false

    # Count dots: example.com = 1 dot, api.example.com = 2 dots
    case "$DOMAIN" in
        *.*.*)
            # Already a subdomain like api.example.com - skip www question
            log_info "Subdomain detected - skipping www alias"
            ;;
        *.*)
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
                    if [ -n "$SERVER_ALIASES" ]; then
                        SERVER_ALIASES="$SERVER_ALIASES ${sub}.${DOMAIN}"
                    else
                        SERVER_ALIASES="${sub}.${DOMAIN}"
                    fi
                done
            fi
            ;;
        *)
            log_warning "Invalid domain format. Please use format like example.com"
            ;;
    esac

    log_info "Domain: $DOMAIN"
    [ -n "$SERVER_ALIASES" ] && log_info "Aliases: $SERVER_ALIASES"
}

# Get app directory
get_app_directory() {
    echo ""
    echo -e "${BOLD}Application Directory:${NC}"

    default_dir="/var/www/$DOMAIN"
    read -p "Enter app root directory [$default_dir]: " APP_ROOT
    APP_ROOT=${APP_ROOT:-$default_dir}

    log_info "App directory: $APP_ROOT"
}

# Get port configuration
get_port_config() {
    echo ""
    echo -e "${BOLD}Port Configuration:${NC}"

    if [[ "$APP_TYPE" == "static" || "$APP_TYPE" == "php" ]]; then
        USE_PROXY=false
        APP_PORT=""
        log_info "No reverse proxy needed for $APP_TYPE"
        return
    fi

    USE_PROXY=true

    case $APP_TYPE in
        nodejs) default_port=3000;;
        python) default_port=8000;;
        proxy) default_port=3000;;
        *) default_port=3000;;
    esac

    read -p "Enter application port [$default_port]: " APP_PORT
    APP_PORT=${APP_PORT:-$default_port}

    # Validate port
    if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]] || [ "$APP_PORT" -lt 1 ] || [ "$APP_PORT" -gt 65535 ]; then
        log_error "Invalid port number. Using default: $default_port"
        APP_PORT=$default_port
    fi

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
        read -p "Enter Git repository URL: " GIT_REPO
        while [ -z "$GIT_REPO" ]; do
            echo "Repository URL cannot be empty."
            read -p "Enter Git repository URL: " GIT_REPO
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
    echo "  1) Let's Encrypt (recommended for production)"
    echo "  2) Self-signed certificate (for testing)"
    echo "  3) No SSL (HTTP only)"
    echo "  4) Existing certificate (provide paths)"
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
        read -p "Enter email for Let's Encrypt notifications: " SSL_EMAIL
        while [ -z "$SSL_EMAIL" ]; do
            echo "Email is required for Let's Encrypt."
            read -p "Enter email: " SSL_EMAIL
        done
    elif [ "$SSL_TYPE" == "existing" ]; then
        read -p "Enter path to SSL certificate: " SSL_CERT_PATH
        read -p "Enter path to SSL private key: " SSL_KEY_PATH
    fi

    log_info "SSL type: $SSL_TYPE"
}

# Get process manager config
get_pm_config() {
    if [[ "$APP_TYPE" != "nodejs" && "$APP_TYPE" != "python" ]]; then
        USE_PM2=false
        return
    fi

    echo ""
    echo -e "${BOLD}Process Manager:${NC}"
    read -p "Use PM2 for process management? (y/n) [y]: " use_pm2
    use_pm2=${use_pm2:-y}

    if [[ $use_pm2 =~ ^[Yy]$ ]]; then
        USE_PM2=true

        read -p "Enter app name for PM2 [$DOMAIN]: " PM2_APP_NAME
        PM2_APP_NAME=${PM2_APP_NAME:-$DOMAIN}

        if [ "$APP_TYPE" == "nodejs" ]; then
            read -p "Enter start command [npm start]: " PM2_START_CMD
            PM2_START_CMD=${PM2_START_CMD:-"npm start"}
        elif [ "$APP_TYPE" == "python" ]; then
            read -p "Enter start command [uvicorn app.main:app --host 127.0.0.1 --port $APP_PORT]: " PM2_START_CMD
            PM2_START_CMD=${PM2_START_CMD:-"uvicorn app.main:app --host 127.0.0.1 --port $APP_PORT"}
        fi

        log_info "PM2 app name: $PM2_APP_NAME"
    else
        USE_PM2=false
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
        PHP_VERSION="8.2"
        log_warning "PHP not detected. Will install PHP $PHP_VERSION"
    fi

    read -p "Enter document root relative to app directory [public]: " PHP_DOC_ROOT
    PHP_DOC_ROOT=${PHP_DOC_ROOT:-public}

    read -p "Install common PHP extensions? (y/n) [y]: " install_ext
    install_ext=${install_ext:-y}
    INSTALL_PHP_EXT=$([[ $install_ext =~ ^[Yy]$ ]] && echo true || echo false)
}

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

# Update package lists
update_packages() {
    log_step "Updating package lists..."
    apt-get update >/dev/null 2>&1
    log_success "Package lists updated"
}

# Install Apache2
install_apache() {
    log_step "Setting up Apache2..."

    install_package "apache2"

    # Enable required modules
    local modules="proxy proxy_http proxy_wstunnel proxy_fcgi rewrite ssl headers expires"
    for mod in $modules; do
        a2enmod $mod >/dev/null 2>&1 || true
    done

    systemctl enable apache2 >/dev/null 2>&1
    systemctl start apache2 >/dev/null 2>&1

    log_success "Apache2 configured"
}

# Install Nginx
install_nginx() {
    log_step "Setting up Nginx..."

    install_package "nginx"

    systemctl enable nginx >/dev/null 2>&1
    systemctl start nginx >/dev/null 2>&1

    log_success "Nginx configured"
}

# Install Node.js
install_nodejs() {
    log_step "Setting up Node.js..."

    if command_exists node; then
        NODE_VERSION=$(node -v)
        log_success "Node.js $NODE_VERSION already installed"
    else
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
        apt-get install -y nodejs >/dev/null 2>&1
        log_success "Node.js $(node -v) installed"
    fi

    # Install PM2
    if [ "$USE_PM2" = true ]; then
        if ! command_exists pm2; then
            npm install -g pm2 >/dev/null 2>&1
            log_success "PM2 installed"
        else
            log_success "PM2 already installed"
        fi
    fi
}

# Install Python
install_python() {
    log_step "Setting up Python..."

    install_package "python3"
    install_package "python3-venv"
    install_package "python3-pip"

    log_success "Python $(python3 --version | cut -d ' ' -f 2) ready"

    # Install PM2 for Python process management
    if [ "$USE_PM2" = true ]; then
        if ! command_exists node; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
            apt-get install -y nodejs >/dev/null 2>&1
        fi
        if ! command_exists pm2; then
            npm install -g pm2 >/dev/null 2>&1
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
        local extensions="php-mysql php-pgsql php-sqlite3 php-mbstring php-xml php-curl php-zip php-gd php-intl php-bcmath"
        for ext in $extensions; do
            install_package "$ext" 2>/dev/null || true
        done
    fi

    # Get PHP-FPM socket path
    PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
    PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

    systemctl enable php${PHP_VERSION}-fpm >/dev/null 2>&1
    systemctl start php${PHP_VERSION}-fpm >/dev/null 2>&1

    log_success "PHP $PHP_VERSION configured"
}

# Setup application directory
setup_app_directory() {
    log_step "Setting up application directory..."

    mkdir -p "$APP_ROOT"

    if [ "$USE_GIT" = true ]; then
        if [ -d "$APP_ROOT/.git" ]; then
            log_info "Git repository exists, pulling latest..."
            cd "$APP_ROOT"
            git pull origin "$GIT_BRANCH" 2>/dev/null || true
        else
            # Clone to temp and move (in case directory has files)
            rm -rf "$APP_ROOT"
            git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_ROOT"
            log_success "Repository cloned"
        fi
    fi

    # Set permissions
    chown -R www-data:www-data "$APP_ROOT"
    chmod -R 755 "$APP_ROOT"

    log_success "App directory ready: $APP_ROOT"
}

# Setup Node.js app
setup_nodejs_app() {
    log_step "Setting up Node.js application..."

    cd "$APP_ROOT"

    # Create .env if needed
    if [ ! -f ".env" ] && [ ! -f ".env.local" ]; then
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
        sudo -u www-data npm ci --production=false 2>/dev/null || sudo -u www-data npm install 2>/dev/null || {
            npm ci --production=false 2>/dev/null || npm install 2>/dev/null
        }

        # Build if build script exists
        if grep -q '"build"' package.json; then
            log_info "Building application..."
            sudo -u www-data npm run build 2>/dev/null || npm run build 2>/dev/null || true
        fi

        log_success "Node.js app configured"
    else
        log_warning "No package.json found"
    fi
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

    # Install dependencies
    if [ -f "requirements.txt" ]; then
        log_info "Installing Python dependencies (this may take a while)..."
        source venv/bin/activate
        pip install --upgrade pip 2>&1 | tail -1
        if pip install -r requirements.txt 2>&1 | tee /tmp/pip_install.log | tail -5; then
            log_success "Python dependencies installed"
        else
            log_error "Failed to install some dependencies. Check /tmp/pip_install.log"
            cat /tmp/pip_install.log | grep -i "error" | head -5
        fi
        deactivate
    else
        log_warning "No requirements.txt found"
    fi

    chown -R www-data:www-data "$APP_ROOT"
}

# Setup PM2
setup_pm2() {
    if [ "$USE_PM2" != true ]; then
        return
    fi

    log_step "Configuring PM2..."

    cd "$APP_ROOT"

    # Create ecosystem file
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
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/var/log/pm2/${PM2_APP_NAME}-error.log',
    out_file: '/var/log/pm2/${PM2_APP_NAME}-out.log'
  }]
};
EOF
    elif [ "$APP_TYPE" == "python" ]; then
        cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    cwd: '$APP_ROOT',
    script: 'venv/bin/uvicorn',
    args: 'app.main:app --host 127.0.0.1 --port $APP_PORT',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/var/log/pm2/${PM2_APP_NAME}-error.log',
    out_file: '/var/log/pm2/${PM2_APP_NAME}-out.log'
  }]
};
EOF
    fi

    # Create log directory
    mkdir -p /var/log/pm2
    chown -R www-data:www-data /var/log/pm2

    # Stop existing app if running
    pm2 delete "$PM2_APP_NAME" 2>/dev/null || true

    # Start app
    sudo -u www-data pm2 start ecosystem.config.js 2>/dev/null || pm2 start ecosystem.config.js
    sudo -u www-data pm2 save 2>/dev/null || pm2 save

    # Setup startup
    pm2 startup systemd -u www-data --hp /var/www 2>/dev/null || true

    log_success "PM2 configured"
}

# ============================================================================
# APACHE CONFIGURATION
# ============================================================================

create_apache_config() {
    log_step "Creating Apache virtual host..."

    local config_file="/etc/apache2/sites-available/${DOMAIN}.conf"

    # Build ServerAlias line
    local alias_line=""
    if [ -n "$SERVER_ALIASES" ]; then
        alias_line="ServerAlias $SERVER_ALIASES"
    fi

    if [ "$USE_PROXY" = true ]; then
        # Reverse proxy configuration
        cat > "$config_file" << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    $alias_line

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$APP_PORT/
    ProxyPassReverse / http://127.0.0.1:$APP_PORT/

    # WebSocket support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://127.0.0.1:$APP_PORT/\$1" [P,L]

    # Security headers
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"

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
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"

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
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css application/javascript application/json
    </IfModule>

    # Cache static assets
    <IfModule mod_expires.c>
        ExpiresActive On
        ExpiresByType image/jpg "access plus 1 year"
        ExpiresByType image/jpeg "access plus 1 year"
        ExpiresByType image/gif "access plus 1 year"
        ExpiresByType image/png "access plus 1 year"
        ExpiresByType image/webp "access plus 1 year"
        ExpiresByType text/css "access plus 1 month"
        ExpiresByType application/javascript "access plus 1 month"
    </IfModule>

    # Security headers
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF
    fi

    # Enable site
    a2ensite "${DOMAIN}.conf" >/dev/null 2>&1
    a2dissite 000-default.conf 2>/dev/null || true

    # Test and reload
    apache2ctl configtest
    systemctl reload apache2

    log_success "Apache virtual host created"
}

# ============================================================================
# NGINX CONFIGURATION
# ============================================================================

create_nginx_config() {
    log_step "Creating Nginx server block..."

    local config_file="/etc/nginx/sites-available/${DOMAIN}"

    # Build server_name line
    local server_names="$DOMAIN"
    if [ -n "$SERVER_ALIASES" ]; then
        server_names="$DOMAIN $SERVER_ALIASES"
    fi

    if [ "$USE_PROXY" = true ]; then
        # Reverse proxy configuration
        cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $server_names;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";

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

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:$PHP_FPM_SOCK;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";

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
        try_files \$uri \$uri/ =404;
    }

    # Enable gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    # Cache static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|webp|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;
}
EOF
    fi

    # Enable site
    ln -sf "$config_file" "/etc/nginx/sites-enabled/${DOMAIN}"
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    # Test and reload
    nginx -t
    systemctl reload nginx

    log_success "Nginx server block created"
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

    if [ "$WEB_SERVER" == "apache2" ]; then
        install_package "python3-certbot-apache"

        local domains="-d $DOMAIN"
        [ -n "$SERVER_ALIASES" ] && domains="$domains $(echo $SERVER_ALIASES | sed 's/ / -d /g' | sed 's/^/-d /')"

        certbot --apache $domains --non-interactive --agree-tos --email "$SSL_EMAIL" --redirect || {
            log_warning "Certbot failed. You can run manually:"
            echo "sudo certbot --apache -d $DOMAIN"
        }
    else
        install_package "python3-certbot-nginx"

        local domains="-d $DOMAIN"
        [ -n "$SERVER_ALIASES" ] && domains="$domains $(echo $SERVER_ALIASES | sed 's/ / -d /g' | sed 's/^/-d /')"

        certbot --nginx $domains --non-interactive --agree-tos --email "$SSL_EMAIL" --redirect || {
            log_warning "Certbot failed. You can run manually:"
            echo "sudo certbot --nginx -d $DOMAIN"
        }
    fi

    # Enable auto-renewal
    systemctl enable certbot.timer 2>/dev/null || true
    systemctl start certbot.timer 2>/dev/null || true

    log_success "Let's Encrypt SSL configured"
}

setup_selfsigned() {
    local ssl_dir="/etc/ssl/$DOMAIN"
    mkdir -p "$ssl_dir"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$ssl_dir/privkey.pem" \
        -out "$ssl_dir/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN" \
        2>/dev/null

    SSL_CERT_PATH="$ssl_dir/fullchain.pem"
    SSL_KEY_PATH="$ssl_dir/privkey.pem"

    configure_ssl_vhost

    log_success "Self-signed SSL certificate created"
    log_warning "Browsers will show a security warning for self-signed certificates"
}

setup_existing_ssl() {
    if [ ! -f "$SSL_CERT_PATH" ] || [ ! -f "$SSL_KEY_PATH" ]; then
        log_error "SSL certificate or key file not found"
        return
    fi

    configure_ssl_vhost

    log_success "Existing SSL certificate configured"
}

configure_ssl_vhost() {
    if [ "$WEB_SERVER" == "apache2" ]; then
        # Add SSL configuration to Apache
        local ssl_config="/etc/apache2/sites-available/${DOMAIN}-ssl.conf"

        cat > "$ssl_config" << EOF
<VirtualHost *:443>
    ServerName $DOMAIN
    $([ -n "$SERVER_ALIASES" ] && echo "ServerAlias $SERVER_ALIASES")

    SSLEngine on
    SSLCertificateFile $SSL_CERT_PATH
    SSLCertificateKeyFile $SSL_KEY_PATH

    $(cat /etc/apache2/sites-available/${DOMAIN}.conf | grep -v "VirtualHost" | grep -v "ServerName" | grep -v "ServerAlias")
</VirtualHost>
EOF

        a2ensite "${DOMAIN}-ssl.conf" >/dev/null 2>&1
        systemctl reload apache2

    else
        # Add SSL to Nginx
        local config_file="/etc/nginx/sites-available/${DOMAIN}"

        cat >> "$config_file" << EOF

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN $(echo $SERVER_ALIASES);

    ssl_certificate $SSL_CERT_PATH;
    ssl_certificate_key $SSL_KEY_PATH;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    $(cat /etc/nginx/sites-available/${DOMAIN} | grep -A 100 "location" | head -n -1)
}
EOF

        nginx -t && systemctl reload nginx
    fi
}

# ============================================================================
# HELPER SCRIPTS
# ============================================================================

create_helper_scripts() {
    log_step "Creating helper scripts..."

    # Update script
    cat > "$APP_ROOT/update.sh" << EOF
#!/bin/bash
set -e
echo "Updating $DOMAIN..."
cd "$APP_ROOT"

# Pull latest code
git pull origin ${GIT_BRANCH:-main} 2>/dev/null || true

# Update based on app type
EOF

    if [ "$APP_TYPE" == "nodejs" ]; then
        cat >> "$APP_ROOT/update.sh" << EOF
npm ci
npm run build 2>/dev/null || true
EOF
    elif [ "$APP_TYPE" == "python" ]; then
        cat >> "$APP_ROOT/update.sh" << EOF
source venv/bin/activate
pip install -r requirements.txt
alembic upgrade head 2>/dev/null || true
deactivate
EOF
    fi

    if [ "$USE_PM2" = true ]; then
        cat >> "$APP_ROOT/update.sh" << EOF

# Restart PM2 app
pm2 restart $PM2_APP_NAME
EOF
    fi

    cat >> "$APP_ROOT/update.sh" << EOF

echo "Update complete!"
EOF

    # Restart script
    cat > "$APP_ROOT/restart.sh" << EOF
#!/bin/bash
EOF

    if [ "$USE_PM2" = true ]; then
        echo "pm2 restart $PM2_APP_NAME" >> "$APP_ROOT/restart.sh"
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
    fi

    cat >> "$APP_ROOT/logs.sh" << EOF
echo ""
echo "=== Web Server Logs ==="
tail -50 /var/log/${WEB_SERVER}/${DOMAIN}*error.log 2>/dev/null || tail -50 /var/log/${WEB_SERVER}/error.log
EOF

    # Status script
    cat > "$APP_ROOT/status.sh" << EOF
#!/bin/bash
echo "=== Service Status ==="
systemctl status $WEB_SERVER --no-pager | head -5
EOF

    if [ "$USE_PM2" = true ]; then
        echo "echo ''" >> "$APP_ROOT/status.sh"
        echo "echo '=== PM2 Status ==='" >> "$APP_ROOT/status.sh"
        echo "pm2 status" >> "$APP_ROOT/status.sh"
    fi

    # Make executable
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
    echo "  Domain:        $DOMAIN"
    [ -n "$SERVER_ALIASES" ] && echo "  Aliases:       $SERVER_ALIASES"
    echo "  Web Server:    $WEB_SERVER"
    echo "  App Type:      $APP_TYPE"
    echo "  App Directory: $APP_ROOT"
    [ "$USE_PROXY" = true ] && echo "  App Port:      $APP_PORT"
    echo "  SSL:           $SSL_TYPE"
    echo ""
    echo -e "${BOLD}URLs:${NC}"
    if [ "$SSL_TYPE" != "none" ]; then
        echo "  https://$DOMAIN"
    else
        echo "  http://$DOMAIN"
    fi
    echo ""
    echo -e "${BOLD}Helper Scripts:${NC}"
    echo "  Update:   $APP_ROOT/update.sh"
    echo "  Restart:  $APP_ROOT/restart.sh"
    echo "  Logs:     $APP_ROOT/logs.sh"
    echo "  Status:   $APP_ROOT/status.sh"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    if [ "$USE_PM2" = true ]; then
        echo "  pm2 status                    # Check app status"
        echo "  pm2 logs $PM2_APP_NAME        # View app logs"
        echo "  pm2 restart $PM2_APP_NAME     # Restart app"
    fi
    echo "  sudo systemctl status $WEB_SERVER   # Web server status"
    echo "  sudo tail -f /var/log/$WEB_SERVER/${DOMAIN}_error.log"
    echo ""

    if [ "$APP_TYPE" == "python" ]; then
        echo -e "${YELLOW}Note:${NC} Don't forget to create your .env file:"
        echo "  nano $APP_ROOT/.env"
        echo ""
    fi

    if [ "$APP_TYPE" == "nodejs" ] && [ ! -f "$APP_ROOT/.env.local" ]; then
        echo -e "${YELLOW}Note:${NC} You may need to configure environment variables:"
        echo "  nano $APP_ROOT/.env.local"
        echo ""
    fi
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
    get_ssl_config

    echo ""
    echo -e "${BOLD}Ready to proceed with installation.${NC}"
    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Setup cancelled"
        exit 1
    fi

    echo ""
    log_step "Starting installation..."
    echo ""

    # Install components
    update_packages

    case $WEB_SERVER in
        apache2) install_apache;;
        nginx) install_nginx;;
    esac

    case $APP_TYPE in
        nodejs) install_nodejs;;
        python) install_python;;
        php) install_php;;
    esac

    # Setup application
    setup_app_directory

    case $APP_TYPE in
        nodejs) setup_nodejs_app;;
        python) setup_python_app;;
    esac

    setup_pm2

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
