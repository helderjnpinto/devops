# Redis live migration with RIOT (in Kubernetes)

[RIOT](https://redis.github.io/riotx/) is a CLI for moving data in and out of Redis. This
covers the one thing it's genuinely great at: migrating a Redis instance to another with
**zero downtime**, run as a throwaway pod in a Kubernetes cluster.

## When to reach for it

- Moving from an in-cluster Redis to a managed one (or vice versa)
- Splitting one Redis database into several (fan-out by key pattern)
- Any cutover where you can't afford a stop-the-world dump/restore

## Running it

The image ships the `riot` binary on `PATH`. Launch it as a plain pod, kept alive so you can
`kubectl exec` into it and run jobs as background processes:

```bash
kubectl run riot-migrate -n <namespace> --image=riotx/riot:v4.1.3 \
  --restart=Never --command -- sleep infinity

kubectl wait -n <namespace> --for=condition=Ready pod/riot-migrate --timeout=60s
```

Live replication (initial scan + ongoing keyspace-notification stream, runs until you stop it):

```bash
kubectl exec -n <namespace> riot-migrate -- riot replicate \
  --mode live \
  <SOURCE_HOST>:<SOURCE_PORT> <TARGET_HOST>:<TARGET_PORT> \
  --source-pass '<SOURCE_PASSWORD>' \
  --target-pass '<TARGET_PASSWORD>'
```

Delete the pod when every consumer has cut over — it's disposable, nothing else depends on it.

## Gotchas (all found the hard way)

**`--mode live` needs keyspace notifications enabled on the source.** RIOT subscribes to them
for the ongoing stream; without this it silently only does the initial scan.

```bash
redis-cli -h <SOURCE_HOST> -a <SOURCE_PASSWORD> CONFIG SET notify-keyspace-events KEA
```

**Cross-version replication needs `--struct`.** By default RIOT copies keys via Redis's binary
`DUMP`/`RESTORE`, which is not guaranteed compatible across major version gaps — you'll see
`ERR DUMP payload version or checksum are wrong`. Add `--struct` to replicate through native
commands (`GET`/`SET`, `HSET`, etc.) instead — slower, but version-agnostic.

**Managed Redis (GCP Memorystore, some others) rejects `CLIENT SETNAME`.** RIOT sends one on
every connection by default, which fails outright against instances that block admin commands.
Symptom: `ERR unknown command 'CLIENT'` right after a connection that otherwise looks fine (auth
succeeded, it just dies on the very next command). Fix: `--target-client=''` (and `--source-client=''`
if the source is managed too).

**Fan-out one DB into several, with a rename.** `--key-include`/`--key-exclude` (glob patterns)
scope a job to a subset of keys; run one job per destination. `--key-proc` (a SpEL template) can
rewrite key names in flight — handy when the destination uses a different prefix convention:

```bash
--key-include 'app:cache:*' \
--key-proc "#{key.replace('app:cache:', 'app:cache:v2:')}"
```

**Splitting one source db across several target db indices.** If several services share db 0
on the source but should land on separate db indices on the target (e.g. to isolate them once
migrated), run one job per service: same source, `--key-include` scoped to that service's
prefix, and the db index given on the *target* side of the URI. The source stays plain
`host:port` (db 0 is implicit); the target needs the `redis://` scheme to carry a db path:

```bash
# service A: db 0 -> db 1
riot replicate --mode live <SOURCE_HOST>:<SOURCE_PORT> "redis://<TARGET_HOST>:<TARGET_PORT>/1" \
  --source-pass '<SOURCE_PASSWORD>' --target-pass '<TARGET_PASSWORD>' --target-client '' \
  --key-include 'serviceA:*'

# service B: db 0 -> db 2, run concurrently
riot replicate --mode live <SOURCE_HOST>:<SOURCE_PORT> "redis://<TARGET_HOST>:<TARGET_PORT>/2" \
  --source-pass '<SOURCE_PASSWORD>' --target-pass '<TARGET_PASSWORD>' --target-client '' \
  --key-include 'serviceB:*'
```

Everything else (host, source db, password) can stay identical between jobs — only
`--key-include` and the target db path change. Combine with `--key-proc` from above if you also
want to rename the prefix during the same move.

**Verify before you trust it.** `--dry-run` does everything except write. Compare a handful of
real keys (value + TTL) between source and destination by hand before cutting anything over —
don't rely on RIOT's own progress bar as proof of correctness.

## Full flag reference

`riot replicate --help` inside the pod — it's the source of truth for whatever version you're
actually running, more so than any doc (including this one).

## Inspecting a private-IP target from outside the cluster

If either side has no public IP (typical for managed Redis on a private network),
`kubectl port-forward` can't reach it directly — there's no in-cluster Service for it. Use
[`redis-proxy.sh`](./redis-proxy.sh) in this folder to bridge through a disposable pod instead:

```bash
./redis-proxy.sh <target-host> [target-port] [local-port] [namespace]
```

Same idea RIOT itself needs when run from outside the cluster against a private target — this
script is the standalone version for when you just want to poke around with `redis-cli` or a GUI.
