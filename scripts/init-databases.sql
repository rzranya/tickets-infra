-- Runs once on first Postgres container start (docker-entrypoint-initdb.d).
-- One Postgres instance, two databases: auth-service owns identity,
-- ticket-api owns events/tickets/orders. Keeps the data-ownership boundary
-- clean without needing two containers locally.

CREATE DATABASE festival_auth;
CREATE DATABASE festival_tickets;
