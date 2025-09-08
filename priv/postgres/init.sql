-- Create the EventStore schema and tables
-- This script will be run when PostgreSQL starts for the first time

-- Create the event store schema
CREATE SCHEMA IF NOT EXISTS eventstore;

-- Enable the uuid-ossp extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- EventStore tables will be created automatically by the eventstore library
-- This script just ensures the database and schema are ready