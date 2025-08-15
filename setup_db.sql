-- Create user postgres if it doesn't exist
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'postgres') THEN
      CREATE ROLE postgres WITH LOGIN SUPERUSER PASSWORD 'postgres';
   END IF;
END
$$;

-- Create the database
DROP DATABASE IF EXISTS thunderline_dev;
CREATE DATABASE thunderline_dev OWNER postgres;
