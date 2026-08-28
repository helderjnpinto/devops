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
#
# Then point any client at localhost:<local-port>. Ctrl+C tears down
# both the port-forward and the bridge pod.
# ============================================================
set -euo pipefail

TARGET_HOST="${1:?Usage: $0 <target-host> [target-port] [local-port] [namespace]}"
TARGET_PORT="${2:-6379}"
LOCAL_PORT="${3:-16379}"
NAMESPACE="${4:-default}"

POD_NAME="redis-proxy-$$"
PF_PID=""

cleanup() {
  echo ""
  echo "Cleaning up..."
  [ -n "${PF_PID}" ] && kill "${PF_PID}" 2>/dev/null || true
  kubectl delete pod -n "${NAMESPACE}" "${POD_NAME}" --wait=false 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Starting bridge pod ${POD_NAME} in namespace ${NAMESPACE} -> ${TARGET_HOST}:${TARGET_PORT}"
kubectl run "${POD_NAME}" -n "${NAMESPACE}" --image=alpine/socat --restart=Never \
  -- "tcp-listen:${TARGET_PORT},fork,reuseaddr" "tcp:${TARGET_HOST}:${TARGET_PORT}"

kubectl wait -n "${NAMESPACE}" --for=condition=Ready "pod/${POD_NAME}" --timeout=30s

echo "Port-forwarding localhost:${LOCAL_PORT} -> ${POD_NAME}:${TARGET_PORT}"
kubectl port-forward -n "${NAMESPACE}" "pod/${POD_NAME}" "${LOCAL_PORT}:${TARGET_PORT}" &
PF_PID=$!

echo ""
echo "Ready — connect to localhost:${LOCAL_PORT}"
echo "  redis-cli -h 127.0.0.1 -p ${LOCAL_PORT} -a <password>"
echo "Press Ctrl+C to stop."
wait "${PF_PID}"
