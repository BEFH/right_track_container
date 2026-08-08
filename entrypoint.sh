#!/bin/sh
set -e

DATA_DIR="/data"
NODE_DIR="$DATA_DIR/node"
MYSQL_DATA_DIR="$DATA_DIR/mysql-data"
MYSQL_RUN_DIR="$DATA_DIR/mysql-run"
MYSQL_SOCKET="$MYSQL_RUN_DIR/mariadb.sock"
ADMIN_CREDENTIALS_FILE="$DATA_DIR/.mysql_root_credentials"
SERVER_CONFIG="$DATA_DIR/server.json"
RT_API_SQL_URL="https://raw.githubusercontent.com/right-track/right-track-server/refs/heads/master/rt_api.sql"

mkdir -p "$DATA_DIR"
cd "$DATA_DIR" || exit 1

export PATH="$NODE_DIR/bin:$PATH"

# ---------- MariaDB first-run init ----------
FIRST_RUN=0
if [ ! -d "$MYSQL_DATA_DIR/mysql" ]; then
    FIRST_RUN=1
fi

mkdir -p "$MYSQL_DATA_DIR" "$MYSQL_RUN_DIR"
chown -R appuser:appuser "$MYSQL_DATA_DIR" "$MYSQL_RUN_DIR"

if [ "$FIRST_RUN" -eq 1 ]; then
    echo "Initializing MariaDB data directory..."
    su -s /bin/sh appuser -c "mariadb-install-db \
        --datadir='$MYSQL_DATA_DIR' \
        --auth-root-authentication-method=normal \
        --skip-test-db" > /dev/null
fi

su -s /bin/sh appuser -c "mariadbd \
    --datadir='$MYSQL_DATA_DIR' \
    --socket='$MYSQL_SOCKET' \
    --pid-file='$MYSQL_RUN_DIR/mariadb.pid' \
    --bind-address=127.0.0.1 \
    --port=3306" &
MARIADB_PID=$!

i=0
while [ ! -S "$MYSQL_SOCKET" ] && [ "$i" -lt 30 ]; do
    sleep 1
    i=$((i + 1))
done
[ -S "$MYSQL_SOCKET" ] || { echo "MariaDB failed to start"; exit 1; }

if [ "$FIRST_RUN" -eq 1 ]; then
    echo "First run: creating root password, app user, and rt_api database..."

    ROOT_PW=$(openssl rand -base64 32)
    APP_PW=$(openssl rand -base64 32)

    mariadb --socket="$MYSQL_SOCKET" -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PW}';
CREATE DATABASE IF NOT EXISTS rt_api;
CREATE USER IF NOT EXISTS 'rt_api'@'127.0.0.1' IDENTIFIED BY '${APP_PW}';
GRANT ALL PRIVILEGES ON rt_api.* TO 'rt_api'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

    curl -fsSL "$RT_API_SQL_URL" -o "$DATA_DIR/rt_api.sql"
    mariadb --socket="$MYSQL_SOCKET" -u root -p"$ROOT_PW" rt_api < "$DATA_DIR/rt_api.sql"
    rm -f "$DATA_DIR/rt_api.sql"

    umask 077
    printf 'MYSQL_ROOT_PASSWORD=%s\n' "$ROOT_PW" > "$ADMIN_CREDENTIALS_FILE"
    chmod 600 "$ADMIN_CREDENTIALS_FILE"
    unset ROOT_PW

    APP_PW_GENERATED="$APP_PW"
    unset APP_PW
fi

# ---------- Node install ----------
echo "=== Checking Local Installation in Appdata ==="

install_node() {
    TARBALL="node-${LATEST_VERSION}-linux-x64.tar.xz"
    URL="https://nodejs.org/dist/latest/$TARBALL"
    echo "Downloading $TARBALL..."
    curl -fsSL "$URL" -o "/tmp/$TARBALL"
    mkdir -p "$NODE_DIR"
    tar -xf "/tmp/$TARBALL" -C "$NODE_DIR" --strip-components=1
    rm -rf "/tmp/$TARBALL"
    echo "Node.js installed successfully: $(node -v)"
}

LATEST_VERSION=$(curl -s https://nodejs.org/dist/latest/ | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

if [ ! -x "$NODE_DIR/bin/node" ]; then
    echo "Node.js not found in appdata. Fetching latest version..."
    [ -z "$LATEST_VERSION" ] && { echo "Error: could not resolve latest Node version"; exit 1; }
    install_node
else
    CURRENT_VERSION=$(node -v)
    echo "Existing Node.js installation found: $CURRENT_VERSION. Checking for updates..."
    if [ -n "$LATEST_VERSION" ] && [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        echo "Updating Node.js from $CURRENT_VERSION to $LATEST_VERSION..."
        rm -rf "$NODE_DIR"
        install_node
    else
        echo "Node.js is already up to date ($CURRENT_VERSION)."
    fi
fi

echo "Checking/Updating Right Track packages..."
npm install -g right-track/right-track-server \
  right-track/right-track-agency-mnr --no-fund --no-audit

# ---------- server.json ----------
if [ ! -f "$SERVER_CONFIG" ]; then
    cat <<EOF > "$SERVER_CONFIG"
{
    "database": {
        "host": "127.0.0.1",
        "username": "rt_api",
        "password": "${APP_PW_GENERATED}"
    },
    "agencies": [
        {
            "require": "right-track-agency-mnr"
        }
    ]
}
EOF
    chmod 600 "$SERVER_CONFIG"
fi
unset APP_PW_GENERATED

# ---------- Shutdown handling ----------
cleanup() {
    echo "Shutting down..."
    ADMIN_PW=$(grep MYSQL_ROOT_PASSWORD "$ADMIN_CREDENTIALS_FILE" | cut -d= -f2-)
    mariadb-admin --socket="$MYSQL_SOCKET" -u root -p"$ADMIN_PW" shutdown 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

# Hand ownership of everything the Node process touches to appuser
chown -R appuser:appuser "$DATA_DIR" 2>/dev/null || true
# Re-lock credential/config files that must not be group/world readable
chmod 600 "$ADMIN_CREDENTIALS_FILE" "$SERVER_CONFIG" 2>/dev/null || true

echo "Starting Right Track API Server..."
su -s /bin/sh appuser -c "right-track-server '$SERVER_CONFIG'" &
NODE_PID=$!
wait "$NODE_PID"
