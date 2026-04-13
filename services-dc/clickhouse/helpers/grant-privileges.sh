#!/bin/bash

# Admin user credentials
ADMIN_USER="clickuser"
ADMIN_PASSWORD="clickuser"

# Target user and database
TARGET_USER="database_name"
CLICKHOUSE_HOST="localhost"
CLICKHOUSE_HTTP_PORT="8123"

echo "Granting privileges to $TARGET_USER user using admin account..."

# Grant all necessary privileges including DROP DATABASE
curl -s "http://$CLICKHOUSE_HOST:$CLICKHOUSE_HTTP_PORT/?user=$ADMIN_USER&password=$ADMIN_PASSWORD" \
  -d "GRANT CREATE DATABASE, CREATE TABLE, INSERT, SELECT, ALTER, DROP TABLE, DROP DATABASE ON *.* TO $TARGET_USER" \
  -H "X-ClickHouse-Format: TabSeparated"

# Also grant system privileges that might be needed
curl -s "http://$CLICKHOUSE_HOST:$CLICKHOUSE_HTTP_PORT/?user=$ADMIN_USER&password=$ADMIN_PASSWORD" \
  -d "GRANT SYSTEM MERGES, SYSTEM TTL MERGES ON *.* TO $TARGET_USER" \
  -H "X-ClickHouse-Format: TabSeparated"

echo "Privileges granted successfully!"

# Verify the grants
echo "Current privileges for $TARGET_USER:"
curl -s "http://$CLICKHOUSE_HOST:$CLICKHOUSE_HTTP_PORT/?user=$ADMIN_USER&password=$ADMIN_PASSWORD" \
  -d "SHOW GRANTS FOR $TARGET_USER" \
  -H "X-ClickHouse-Format: TabSeparated"