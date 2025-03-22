#!/bin/bash
set -e

echo "Waiting for PostgreSQL to be ready..."
sleep 5  # Simple delay to allow the container to start up

# Try to connect to the database
if pg_isready -h postgres -U postgres; then
  echo "PostgreSQL is ready - initializing database..."

  # Create the database if it doesn't exist
  echo "Creating database if it doesn't exist..."
  mix ash_postgres.create || true  # Continue even if it fails (database might already exist)

  # Run migrations
  echo "Running migrations..."
  mix ash.migrate || true  # Continue even if it fails

  echo "Database initialization complete!"
else
  echo "PostgreSQL is not available - skipping database initialization"
fi 