#!/bin/bash
set -e  # Exit on error

SQL_USER="${SQL_USER:-sa}"
SQL_PASSWORD="${SQL_PASSWORD:-yourStrongPassword1}"
SQL_PORT="${SQL_PORT:-1433}"
SQL_DB="FreeTDSKitTestDB"

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
check_brew_package "mssql-tools"

# Check if Docker is running
if ! docker info &>/dev/null; then
    echo "❌ Docker is not running. Starting Docker..."
    open -a Docker
    
    # Wait for Docker to start
    echo "🐳 Waiting for Docker to start..."
    while ! docker info &>/dev/null; do
        sleep 1
    done
else
    echo "✅ Docker is running"
fi

#sed -i.bak -E \
#    "s/SA_PASSWORD=.*/SA_PASSWORD=${SQL_PASSWORD}/; s/1433:1433/${SQL_PORT}:${SQL_PORT}/"

# Start Docker services
if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    echo "🐳 Starting Docker services..."
    cd "$SCRIPT_DIR"  # Change to the directory containing docker-compose.yml
    docker compose up -d
    
    # Poll for SQL Server to be ready
    echo "Waiting for SQL Server to be ready..."
    SQL_SERVER_READY=false
    for _ in {1..30}; do  # Check for up to 30 seconds
        if /opt/homebrew/bin/sqlcmd -S localhost,$SQL_PORT -U "$SQL_USER" -P "$SQL_PASSWORD" -Q "SELECT 1" &>/dev/null; then
            echo "✅ SQL Server is ready"
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

echo "Checking for  db..."
if /opt/homebrew/bin/sqlcmd -S localhost,$SQL_PORT -U "$SQL_USER" -P "$SQL_PASSWORD" -Q "SELECT name FROM sys.databases WHERE name = '${SQL_DB}'" -h -1 | grep -q GeoLens; then
    echo "✅ Database '${SQL_DB}' already exists. Skipping setup."
else
    echo "‼️ Database '${SQL_DB}' does not exist. Running db-setup.sql to create and populate the database..."
    /opt/homebrew/bin/sqlcmd -S localhost,$SQL_PORT -U "$SQL_USER" -P "$SQL_PASSWORD" -i "$SCRIPT_DIR/db-setup.sql"
        echo "✅ Database and tables created"
fi
# Run the tests
echo "🧪 Running tests..."
swift test --filter FreeTDSKitIntegrationTests -Xswiftc -DINTEGRATION_TESTS

# Stop Docker services after tests
echo "🐳 Stopping Docker services..."
docker compose down
