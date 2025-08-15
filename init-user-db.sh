#!/bin/bash
set -e

# Create the thunderline user and database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER thunderline WITH SUPERUSER PASSWORD 'thunderline';
    ALTER USER thunderline CREATEDB;
    GRANT ALL PRIVILEGES ON DATABASE thunderline_dev TO thunderline;
EOSQL
