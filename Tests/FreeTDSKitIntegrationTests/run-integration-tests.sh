#!/bin/bash
set -e  # Exit on error

FREETDSKIT_SQL_USER="${FREETDSKIT_SQL_USER:-sa}"
FREETDSKIT_SQL_PASSWORD="${FREETDSKIT_SQL_PASSWORD:-YourStrongPassword1}"
FREETDSKIT_SQL_SERVER="${FREETDSKIT_SQL_SERVER:-localhost}"
FREETDSKIT_SQL_PORT="${FREETDSKIT_SQL_PORT:-1438}"
FREETDSKIT_SQL_DB="FreeTDSKitTestDB"
FREETDSKIT_RUN_INTEGRATION_TESTS="${FREETDSKIT_RUN_INTEGRATION_TESTS:-1}"

export FREETDSKIT_SQL_SERVER
export FREETDSKIT_SQL_PORT
export FREETDSKIT_SQL_USER
export FREETDSKIT_SQL_PASSWORD
export FREETDSKIT_SQL_DB
export FREETDSKIT_RUN_INTEGRATION_TESTS

SQLCMD="/opt/homebrew/bin/sqlcmd"

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

sqlcmd_run() {
    "$SQLCMD" -b -C -S "$FREETDSKIT_SQL_SERVER,$FREETDSKIT_SQL_PORT" -U "$FREETDSKIT_SQL_USER" -P "$FREETDSKIT_SQL_PASSWORD" "$@"
}

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
    for _ in {1..90}; do
        if sqlcmd_run -Q "SELECT 1" &>/dev/null; then
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

echo "Checking database and schema..."

DB_EXISTS=false
if sqlcmd_run -d master -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name = '${FREETDSKIT_SQL_DB}'" -h -1 | grep -q "${FREETDSKIT_SQL_DB}"; then
    DB_EXISTS=true
fi

SCHEMA_READY=false
if [ "$DB_EXISTS" = true ] && sqlcmd_run -d "$FREETDSKIT_SQL_DB" -Q "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID(N'dbo.DataTypeTest', N'U') IS NOT NULL AND OBJECT_ID(N'dbo.UpdateTableTest', N'U') IS NOT NULL THEN 1 ELSE 0 END" -h -1 | grep -q "^1$"; then
    SCHEMA_READY=true
fi

if [ "$SCHEMA_READY" = true ]; then
    echo "✅ Database '${FREETDSKIT_SQL_DB}' and required tables already exist. Skipping setup."
else
    echo "‼️ Database '${FREETDSKIT_SQL_DB}' is missing required schema. Running db-setup.sql..."
    sqlcmd_run -d master -i "$SCRIPT_DIR/db-setup.sql"
    echo "✅ Database and tables created"
fi
# Run the tests
echo "🧪 Running integration tests..."
swift test --disable-swift-testing --enable-xctest --filter FreeTDSKitIntegrationTests
echo "✅ Integration tests passed!"

# Stop Docker services after tests
#echo "🐳 Stopping Docker services..."
#docker compose down
