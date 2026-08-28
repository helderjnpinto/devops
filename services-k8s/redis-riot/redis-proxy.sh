#!/usr/bin/env bash
# ============================================================
# redis-proxy.sh — port-forward to a Redis (or any TCP service) that
# has no public IP, by bridging through a disposable socat pod inside
# the cluster's network.
#
# Useful for managed Redis (GCP Memorystore, AWS ElastiCache, etc.) on a
# private network — kubectl port-forward only works against in-cluster
# Services/Pods, so this creates one to forward through.
#
# Usage:
#   ./redis-proxy.sh <target-host> [target-port] [local-port] [namespace]
#
# Examples:
#   ./redis-proxy.sh 10.0.0.5
#   ./redis-proxy.sh 10.0.0.5 6379 16379 my-namespace
#   REDIS_PASSWORD='...' ./redis-proxy.sh 10.0.0.5
#
# REDIS_PASSWORD (env var, not a positional arg — keeps it out of shell
# history / `ps`) is optional. If set, the script PINGs through the tunnel
# once it's up to confirm auth actually works, and prints a ready-to-copy
# redis-cli command with it filled in.
#
# Then point any client at localhost:<local-port>. Ctrl+C tears down
# both the port-forward and the bridge pod.
# ============================================================
set -euo pipefail

TARGET_HOST="${1:?Usage: $0 <target-host> [target-port] [local-port] [namespace]}"
TARGET_PORT="${2:-6379}"
LOCAL_PORT="${3:-16379}"
NAMESPACE="${4:-default}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

POD_NAME="redis-proxy-$$"
PF_PID=""
CREATED_NS=""
 
cleanup() {
  echo ""
  echo "Cleaning up..."
  [ -n "${PF_PID}" ] && kill "${PF_PID}" 2>/dev/null || true
  kubectl delete pod -n "${NAMESPACE}" "${POD_NAME}" --wait=false 2>/dev/null || true
  if [ -n "${CREATED_NS}" ]; then
    kubectl delete namespace "${NAMESPACE}" --wait=false 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
 
# Create the namespace if it doesn't already exist (idempotent).
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Creating namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}"
  CREATED_NS="1"
fi
 
echo "Starting bridge pod ${POD_NAME} in namespace ${NAMESPACE} -> ${TARGET_HOST}:${TARGET_PORT}"
kubectl run "${POD_NAME}" -n "${NAMESPACE}" --image=alpine/socat --restart=Never \
  -- "tcp-listen:${TARGET_PORT},fork,reuseaddr" "tcp:${TARGET_HOST}:${TARGET_PORT}"

kubectl wait -n "${NAMESPACE}" --for=condition=Ready "pod/${POD_NAME}" --timeout=30s

echo "Port-forwarding localhost:${LOCAL_PORT} -> ${POD_NAME}:${TARGET_PORT}"
kubectl port-forward -n "${NAMESPACE}" "pod/${POD_NAME}" "${LOCAL_PORT}:${TARGET_PORT}" &>/dev/null &
PF_PID=$!
sleep 2

echo ""
if [ -n "${REDIS_PASSWORD}" ] && command -v redis-cli >/dev/null 2>&1; then
  if redis-cli -h 127.0.0.1 -p "${LOCAL_PORT}" -a "${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q PONG; then
    echo "Auth check: PONG (password is correct, tunnel works end-to-end)"
  else
    echo "Auth check: FAILED — tunnel is up but PING didn't return PONG (check the password)"
  fi
  echo ""
  echo "Ready — connect to localhost:${LOCAL_PORT}"
  echo "  redis-cli -h 127.0.0.1 -p ${LOCAL_PORT} -a '${REDIS_PASSWORD}'"
else
  echo "Ready — connect to localhost:${LOCAL_PORT}"
  echo "  redis-cli -h 127.0.0.1 -p ${LOCAL_PORT} -a <password>"
fi
echo "Press Ctrl+C to stop."
wait "${PF_PID}"
