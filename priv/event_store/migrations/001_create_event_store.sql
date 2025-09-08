-- EventStore database schema migration
-- This will be run by the EventStore library during initialization

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- EventStore will create its own tables when initialized
-- This file serves as a placeholder for any custom setup
-- The actual EventStore tables will be created automatically