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
    
    # First, clear the migration history and tables
    log "Clearing migration state..."
    docker-compose exec -T web python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'core.settings')
import django
django.setup()
from django.db import connection

with connection.cursor() as cursor:
    # Drop tables in correct order with CASCADE
    cursor.execute('''
        DROP TABLE IF EXISTS django_admin_log CASCADE;
        DROP TABLE IF EXISTS auth_permission CASCADE;
        DROP TABLE IF EXISTS django_content_type CASCADE;
        DROP TABLE IF EXISTS django_migrations CASCADE;
        DROP TABLE IF EXISTS auth_group_permissions CASCADE;
        DROP TABLE IF EXISTS auth_user_groups CASCADE;
        DROP TABLE IF EXISTS auth_user_user_permissions CASCADE;
        DROP TABLE IF EXISTS auth_group CASCADE;
        DROP TABLE IF EXISTS main_customuser CASCADE;
        DROP TABLE IF EXISTS main_video CASCADE;
    ''')
    
    # Recreate migrations table
    cursor.execute('''
        CREATE TABLE django_migrations (
            id SERIAL PRIMARY KEY,
            app VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL,
            applied TIMESTAMP WITH TIME ZONE NOT NULL
        );
    ''')
    
    # Create content type table with correct structure
    cursor.execute('''
        CREATE TABLE django_content_type (
            id SERIAL PRIMARY KEY,
            app_label VARCHAR(100) NOT NULL,
            model VARCHAR(100) NOT NULL,
            CONSTRAINT django_content_type_app_label_model_unique UNIQUE (app_label, model)
        );
    ''')
"

    # Remove all existing migrations except __init__.py
    log "Cleaning up migration files..."
    docker-compose exec -T web bash -c "cd /app/main/migrations && find . -type f ! -name '__init__.py' -delete"

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