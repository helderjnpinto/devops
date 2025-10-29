# Redis

## Create a strong password in your environment

Check the env and redis.conf for the acl users

## Start the stack

docker compose up -d

## Add users via CLI

```bash
redis-cli -u redis://admin:SuperSecret123@localhost:6379

```
