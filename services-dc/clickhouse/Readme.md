# Setup clickhouse

Change the .env to rename the default admin and password

Enter in the terminal of docker image to execute the init.sql

```bash

root@clickhouse:/# clickhouse-client

docker exec -it clickhouse clickhouse-client --multiquery --user click_admin --password < /docker-entrypoint-initdb.d/init_app_user.sql


```
