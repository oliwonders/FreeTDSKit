#!/bin/bash
set -e  # Exit on error

FREETDSKIT_SQL_USER="${FREETDSKIT_SQL_USER:-sa}"
FREETDSKIT_SQL_PASSWORD="${FREETDSKIT_SQL_PASSWORD:-YourStrongPassword1}"
FREETDSKIT_SQL_SERVER="localhost"
FREETDSKIT_SQL_PORT="${FREETDSKIT_SQL_PORT:-1438}"
FREETDSKIT_SQL_DB="FreeTDSKitTestDB"

export FREETDSKIT_SQL_SERVER
export FREETDSKIT_SQL_PORT
export FREETDSKIT_SQL_USER
export FREETDSKIT_SQL_PASSWORD
export FREETDSKIT_SQL_DB

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to check if a brew package is installed
check_brew_package() {
    if ! brew list "$1" &>/dev/null; then
        echo "❌ $1 is not installed. Installing..."
        brew install "$1"
    else
        echo "✅ $1 is installed"
    fi
}

# Check for required packages
check_brew_package "docker"
check_brew_package "sqlcmd"

# Check if Docker is running
if ! docker info &>/dev/null; then
    echo "❌ docker is not running. Starting Docker..."
    open -a Docker
    
    # Wait for Docker to start
    echo "🐳 waiting for Docker to start..."
    while ! docker info &>/dev/null; do
        sleep 1
    done
else
    echo "✅ docker is running"
fi

#sed -i.bak -E \
#    "s/SA_PASSWORD=.*/SA_PASSWORD=${FREETDSKIT_SQL_PASSWORD}/; s/1433:1433/${FREETDSKIT_SQL_PORT}:${FREETDSKIT_SQL_PORT}/"

# Start Docker services
if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    echo "🐳 starting Docker services..."
    cd "$SCRIPT_DIR"  # Change to the directory containing docker-compose.yml
    docker compose up -d
    
    # Poll for SQL Server to be ready
    echo "waiting for SQL Server to be ready..."
    echo "testing with: sqlcmd -S $FREETDSKIT_SQL_SERVER,$FREETDSKIT_SQL_PORT -U $FREETDSKIT_SQL_USER -P $FREETDSKIT_SQL_PASSWORD"
    SQL_SERVER_READY=false
    for _ in {1..30}; do  # Check for up to 30 seconds
if /opt/homebrew/bin/sqlcmd -S $FREETDSKIT_SQL_SERVER,$FREETDSKIT_SQL_PORT -U "$FREETDSKIT_SQL_USER" -P "$FREETDSKIT_SQL_PASSWORD" -Q "SELECT 1" &>/dev/null; then
            echo "✅ SQL Server is ready on $FREETDSKIT_SQL_SERVER,$FREETDSKIT_SQL_PORT"
            SQL_SERVER_READY=true
            break
        fi
        echo "⏳ Waiting for SQL Server..."
        sleep 1
    done

    if [ "$SQL_SERVER_READY" = false ]; then
        echo "❌ SQL Server did not become ready in time."
        exit 1
    fi
else
    echo "❌ docker-compose.yml not found in $SCRIPT_DIR"
    exit 1
fi

echo "Checking for  db... with "
if /opt/homebrew/bin/sqlcmd -S $FREETDSKIT_SQL_SERVER,$FREETDSKIT_SQL_PORT -U "$FREETDSKIT_SQL_USER" -P "$FREETDSKIT_SQL_PASSWORD" -Q "SELECT name FROM sys.databases WHERE name = '${FREETDSKIT_SQL_DB}'" -h -1 | grep -q "${FREETDSKIT_SQL_DB}"; then
    echo "✅ Database '${FREETDSKIT_SQL_DB}' already exists. Skipping setup."
else
    echo "‼️ Database '${FREETDSKIT_SQL_DB}' does not exist. Running db-setup.sql to create and populate the database..."
    /opt/homebrew/bin/sqlcmd -S $FREETDSKIT_SQL_SERVER,$FREETDSKIT_SQL_PORT -U "$FREETDSKIT_SQL_USER" -P "$FREETDSKIT_SQL_PASSWORD" -i "$SCRIPT_DIR/db-setup.sql"
        echo "✅ Database and tables created"
fi
# Run the tests
echo "🧪 Running integration tests..."
swift test --disable-swift-testing --enable-xctest -Xswiftc -DINTEGRATION_TESTS
echo "✅ Integration tests passed!"

# Stop Docker services after tests
#echo "🐳 Stopping Docker services..."
#docker compose down
