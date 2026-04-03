# OpenObserve Deployment Guide

Deploy OpenObserve for centralized observability with Kubernetes cluster integration.

---

## Part 1 — Private Server Setup

### 1. Docker Compose Configuration

Versions can be accessed at:

- https://gallery.ecr.aws/zinclabs/openobserve
- https://github.com/openobserve/openobserve/tags

```yaml
services:
  openobserve:
    image: public.ecr.aws/zinclabs/openobserve:v0.80.0-rc2
    container_name: openobserve
    restart: unless-stopped
    
    env_file:
      - .env
    
    volumes:
      - ./data:/data
    
    ports:
      - "5080:5080"
```

### 2. Start OpenObserve

```bash
docker compose up -d
```

### 3. Access OpenObserve

Open your browser and navigate to:

```
http://127.0.0.1:5080
```

### 4. Create API Access

In the OpenObserve UI:
- Go to Settings → API Keys
- Create an API key OR use email/password authentication

Generate base64 credentials:
```bash
echo -n "admin@example.com:StrongPassword123!" | base64
```

---

## Part 2 — Kubernetes Integration

### 1. Add Helm Repository

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```

### 2. Create OpenTelemetry Collector Configuration

Create `otel-values.yaml`:

```yaml
mode: daemonset

image:
  repository: otel/opentelemetry-collector-contrib

extraVolumes:
  - name: varlog
    hostPath:
      path: /var/log

extraVolumeMounts:
  - name: varlog
    mountPath: /var/log

config:
  receivers:
    filelog:
      include: [ /var/log/containers/*.log ]
      start_at: beginning

    otlp:
      protocols:
        http:
        grpc:

    kubeletstats:
      collection_interval: 20s
      auth_type: serviceAccount
      endpoint: https://${env:K8S_NODE_NAME}:10250
      insecure_skip_verify: true

  processors:
    batch:
    memory_limiter:
      limit_mib: 512
      check_interval: 1s

  exporters:
    otlphttp/openobserve:
      endpoint: http://YOUR_SERVER_IP:5080/api/default
      headers:
        Authorization: "Basic YOUR_BASE64"
      compression: gzip

  service:
    pipelines:
      logs:
        receivers: [filelog]
        processors: [memory_limiter, batch]
        exporters: [otlphttp/openobserve]

      metrics:
        receivers: [kubeletstats]
        processors: [memory_limiter, batch]
        exporters: [otlphttp/openobserve]

      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlphttp/openobserve]
```

### 3. Deploy OpenTelemetry Collector

```bash
helm install otel open-telemetry/opentelemetry-collector -f otel-values.yaml
```

### 4. Alternative: Fluent Bit

For a lighter-weight log collection option, you can use Fluent Bit instead of OpenTelemetry.

#### Step 1: Install Fluent Bit

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
helm upgrade --install fluent-bit fluent/fluent-bit --namespace fluent-bit --create-namespace
```

This installs Fluent Bit as a DaemonSet (one pod per node) with necessary RBAC permissions.

#### Step 2: Get OpenObserve Configuration

In OpenObserve UI, navigate to:

```text
OpenObserve UI > Ingestion > Logs > Fluentbit
```

Copy the configuration from there, or use this template:

#### Step 3: Configure Fluent Bit

Get the current ConfigMap and modify it:

```bash
kubectl -n fluent-bit get configmap fluent-bit -o yaml > fluent-bit.yaml
```

Edit `fluent-bit.yaml` and replace the OUTPUT sections with:

```yaml
[OUTPUT]
    Name http
    Match *
    URI /api/default/default/_json
    Host localhost
    Port 5080
    tls Off
    Format json
    Json_date_key _timestamp
    Json_date_format iso8601
    HTTP_User admin@example.com
    HTTP_Passwd KN3cpELh2IRxpcIA
    compress gzip
```

#### Step 4: Apply Configuration

```bash
kubectl apply -f fluent-bit.yaml
```

#### Step 5: Restart Fluent Bit Pods

```bash
kubectl delete pods -n fluent-bit -l app.kubernetes.io/name=fluent-bit
```

#### Optional: Add Filters

To filter logs by namespace, pod, or labels, add FILTER sections before the OUTPUT:

```yaml
[FILTER]
    Name grep
    Match *
    Regex kubernetes.namespace_name ^(your-namespace)$
```

#### Verify Deployment

Check Fluent Bit logs:
```bash
kubectl logs -n fluent-bit -l app.kubernetes.io/name=fluent-bit
```

Verify logs in OpenObserve:

- Go to Logs → streams
- Look for incoming log data

### 5. Verify Deployment

Check collector logs:
```bash
# For OpenTelemetry
kubectl logs -l app.kubernetes.io/name=opentelemetry-collector

# For Fluent Bit
kubectl logs -l app.kubernetes.io/name=fluent-bit
```

Verify data in OpenObserve:
- Go to Logs → streams
- Look for `kubernetes_*` streams and container logs

---

## Configuration Requirements

### Update These Values

In `otel-values.yaml`, replace:
- `YOUR_SERVER_IP` with your OpenObserve server IP
- `YOUR_BASE64` with your base64-encoded credentials

### Network Connectivity

Ensure your Kubernetes cluster can reach the OpenObserve server:
```bash
curl http://YOUR_SERVER_IP:5080/healthz
```

---

## Architecture Overview

```
Kubernetes Cluster
   ↓ (All nodes)
OpenTelemetry Collector (DaemonSet)
   ↓ (Logs, metrics, traces)
Network
   ↓
OpenObserve Server (Docker)
```

---

## Troubleshooting

### Common Issues

1. **Wrong endpoint**: Must be `http://SERVER_IP:5080/api/default`
2. **Logs not working**: Ensure `/var/log/containers` path is correct
3. **Network blocked**: Test connectivity from cluster to server
4. **Auth errors**: Verify base64 encoding format is `email:password`

### Optional Enhancements

Consider adding:
- HTTPS with reverse proxy
- Kubernetes dashboards
- High-volume logging with buffering
- Auto-instrumentation for traces

---

## Quick Start Commands

```bash
# Start OpenObserve
docker compose up -d

# Deploy to Kubernetes
helm install otel open-telemetry/opentelemetry-collector -f otel-values.yaml

# Check status
kubectl logs -l app.kubernetes.io/name=opentelemetry-collector
```
