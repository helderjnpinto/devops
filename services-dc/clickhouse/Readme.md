# Setup clickhouse

Change the .env to rename the default admin and password

Enter in the terminal of docker image to execute the init.sql

```bash
docker exec -i clickhouse clickhouse-client \
  --user "$CLICKHOUSE_ADMIN_USER" \
  --password "$CLICKHOUSE_ADMIN_PASSWORD" \
  --multiquery --echo --verbose < init.sql


```
