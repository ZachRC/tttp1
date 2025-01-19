#!/bin/bash

# Enable error handling
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check database connection
check_db_connection() {
    log "Testing database connection..."
    if docker-compose exec -T web python -c "
import os
import sys
import psycopg2
from urllib.parse import urlparse
import logging

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger('db_check')

db_url = os.getenv('DATABASE_URL')
if not db_url:
    logger.error('DATABASE_URL is not set')
    sys.exit(1)

try:
    parsed = urlparse(db_url)
    dbname = parsed.path[1:]
    user = parsed.username
    password = parsed.password
    host = parsed.hostname
    port = parsed.port

    logger.info(f'Attempting to connect to {host}:{port} as {user}')
    
    conn = psycopg2.connect(
        dbname=dbname,
        user=user,
        password=password,
        host=host,
        port=port,
        connect_timeout=30,
        sslmode='require'
    )
    
    # Test the connection with a simple query
    with conn.cursor() as cur:
        cur.execute('SELECT 1')
        cur.fetchone()
        
    conn.close()
    logger.info('Database connection successful')
    sys.exit(0)
except Exception as e:
    logger.error(f'Database connection failed: {str(e)}')
    logger.error(f'Connection parameters: host={host}, port={port}, dbname={dbname}, user={user}')
    sys.exit(1)
"; then
        return 0
    else
        return 1
    fi
}

# Function to handle database migrations
handle_migrations() {
    log "Handling database migrations..."

    # Create fresh migrations
    log "Creating fresh migrations..."
    docker-compose exec -T web python manage.py makemigrations main

    # Apply migrations in correct order
    log "Applying migrations in order..."
    docker-compose exec -T web python manage.py migrate contenttypes --fake-initial
    docker-compose exec -T web python manage.py migrate auth --fake-initial
    docker-compose exec -T web python manage.py migrate main --fake-initial
    docker-compose exec -T web python manage.py migrate admin --fake-initial
    docker-compose exec -T web python manage.py migrate sessions --fake-initial

    # Run a final migrate to ensure everything is in sync
    log "Running final migration check..."
    docker-compose exec -T web python manage.py migrate --fake-initial

    # Verify migration status
    log "Verifying migration status..."
    docker-compose exec -T web python manage.py showmigrations

    log "Migration handling completed"
}

# Update system packages
log "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Clean up existing containers and volumes
log "Cleaning up existing containers and volumes..."
docker-compose down -v
docker system prune -f

# Pull latest changes
log "Pulling latest changes from repository..."
git pull origin main

# Create necessary directories
log "Creating necessary directories..."
mkdir -p static media staticfiles

# Build and start containers
log "Building and starting containers..."
docker-compose up --build -d

# Wait for services to be ready
log "Waiting for web service to be ready..."
sleep 10

# Test database connection with retries
max_retries=5
retry_count=0
while [ $retry_count -lt $max_retries ]; do
    if check_db_connection; then
        log "Database connection successful"
        break
    else
        retry_count=$((retry_count + 1))
        if [ $retry_count -eq $max_retries ]; then
            log "Failed to connect to database after $max_retries attempts"
            docker-compose logs web
            exit 1
        fi
        log "Database connection failed, retrying in 5 seconds... (Attempt $retry_count of $max_retries)"
        sleep 5
    fi
done

# Handle database migrations
handle_migrations

# Collect static files
log "Collecting static files..."
docker-compose exec -T web python manage.py collectstatic --noinput

# Restart Nginx
log "Restarting Nginx..."
docker-compose restart nginx

log "Deployment completed successfully!" 