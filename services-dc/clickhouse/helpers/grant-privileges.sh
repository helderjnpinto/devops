#!/bin/bash

# Admin user credentials
ADMIN_USER="clickuser"
ADMIN_PASSWORD="clickuser"

echo "Granting privileges to pulse_gateway user using admin account..."

# Grant all necessary privileges to databasenamehere user
curl -s "http://localhost:8123/?user=$ADMIN_USER&password=$ADMIN_PASSWORD" \
  -d "GRANT CREATE DATABASE, CREATE TABLE, INSERT, SELECT, ALTER, DROP TABLE ON *.* TO databasenamehere" \
  -H "X-ClickHouse-Format: TabSeparated"

echo "Privileges granted successfully!"