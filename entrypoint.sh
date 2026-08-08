#!/bin/sh

DATA_DIR="/data"
NODE_DIR="$DATA_DIR/node"

# Ensure appdata mount point exists and move into it
mkdir -p "$DATA_DIR"
cd "$DATA_DIR" || exit 1

echo "=== Checking Local Installation in Appdata ==="

# Prepend local node directory to PATH
export PATH="$NODE_DIR/bin:$PATH"

# Reusable function for downloading and installing Node.js
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

# Fetch latest version string from nodejs.org
LATEST_VERSION=$(curl -s https://nodejs.org/dist/latest/ | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

# 1. Check if Node.js is already installed locally in appdata
if [ ! -x "$NODE_DIR/bin/node" ]; then
    echo "Node.js not found in appdata. Fetching latest version..."
    if [ -z "$LATEST_VERSION" ]; then
        echo "Error: Could not resolve the latest Node version and no local installation exists."
        exit 1
    fi
    install_node
else
    CURRENT_VERSION=$(node -v)
    echo "Existing Node.js installation found: $CURRENT_VERSION. Checking for updates..."

    if [ -n "$LATEST_VERSION" ] && [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        echo "Updating Node.js from $CURRENT_VERSION to $LATEST_VERSION..."
        # Safely wipe old node directory without risking POSIX glob expansion errors
        rm -rf "$NODE_DIR"
        install_node
    else
        echo "Node.js is already up to date ($CURRENT_VERSION)."
    fi
fi

# 2. Ensure package.json exists in appdata
if [ ! -f "package.json" ]; then
    cat <<EOF > package.json
{
  "name": "right-track-mnr-data",
  "version": "1.0.0",
  "private": true,
  "dependencies": {}
}
EOF
fi

# 3. Ensure Right Track packages are installed and up to date
echo "Checking/Updating Right Track packages..."
npm install right-track-server@latest right-track-agency-mnr@latest right-track-db-build@latest --no-fund --no-audit

# 4. Build or update the GTFS database
echo "Checking GTFS database status..."
npx right-track-db-build --agency mnr

# 5. Ensure server.json exists
if [ ! -f "server.json" ]; then
    cat <<EOF > server.json
{
  "port": 8080,
  "agencies": [
    "right-track-agency-mnr"
  ]
}
EOF
fi

# 6. Start the API Server
echo "Starting Right Track API Server..."
exec npx right-track-server "$DATA_DIR/server.json"
