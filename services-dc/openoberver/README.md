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

### 4. Alternative: Fluent Bit with Advanced Filtering

For a lighter-weight log collection option with advanced filtering capabilities, you can use Fluent Bit instead of OpenTelemetry.

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

Copy the configuration from there, or use our comprehensive configuration below.

#### Step 3: Configure Fluent Bit with Custom Filters

Our advanced configuration includes:
- Kubernetes metadata enrichment
- Custom service filtering based on labels and annotations
- Environment-based filtering
- Sensitive data redaction
- Correlation ID generation for distributed tracing

Get the current ConfigMap and modify it:

```bash
kubectl -n fluent-bit get configmap fluent-bit -o yaml > fluent-bit.yaml
```

Replace the configuration with our comprehensive setup:

```bash
# Apply our pre-configured setup
kubectl apply -f fluent-bit-config.yaml
kubectl apply -f parsers.conf
kubectl create configmap correlation-script --from-file=correlation.lua -n fluent-bit
```

Or manually edit `fluent-bit.yaml` and replace the configuration sections with:

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

#### Step 5: Set Environment Variables

```bash
kubectl set env daemonset/fluent-bit -n fluent-bit \
  OPENOBSERVE_HOST=YOUR_SERVER_IP \
  OPENOBSERVE_PORT=5080 \
  OPENOBSERVE_USER=admin@example.com \
  OPENOBSERVE_PASSWORD=YourPassword \
  ENVIRONMENT=production \
  CLUSTER_NAME=main-cluster
```

#### Step 6: Restart Fluent Bit Pods

```bash
kubectl delete pods -n fluent-bit -l app.kubernetes.io/name=fluent-bit
```

#### Custom Filter Examples

**Filter by Service Labels:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.labels.observability enabled
```

**Filter by Namespace:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.namespace_name ^(production|staging)$
```

**Filter by Annotations:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.annotations.logging\.include true
```

**Exclude Debug Logs:**
```yaml
[FILTER]
    Name    grep
    Match   kube.*
    Exclude kubernetes.labels.log_level debug
```

#### Service Labeling for Observability

To include services in observability, add labels to your deployments:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  template:
    metadata:
      labels:
        observability: enabled
        app.kubernetes.io/name: my-service
        log_level: info
      annotations:
        logging.include: "true"
        logging.parser: "json"
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

## Advanced Filtering Examples

### Label-Based Filtering

**Include only services with observability enabled:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.labels.observability enabled
```

**Filter by specific applications:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.labels\.app\.kubernetes\.io/name ^(web-api|payment-service|user-service)$
```

**Exclude system components:**
```yaml
[FILTER]
    Name    grep
    Match   kube.*
    Exclude kubernetes.labels\.app\.kubernetes\.io/component kube-system
```

### Annotation-Based Filtering

**Include services with logging annotation:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.annotations\.logging\.include true
```

**Filter by custom parser annotations:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.annotations\.logging\.parser (json|nginx|apache)
```

### Namespace-Based Filtering

**Production environments only:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.namespace_name ^(production|prod)$
```

**Exclude monitoring namespaces:**
```yaml
[FILTER]
    Name    grep
    Match   kube.*
    Exclude kubernetes.namespace_name ^(monitoring|logging|kube-system)$
```

### Log Level Filtering

**Filter by log level labels:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.labels.log_level ^(info|warn|error)$
```

**Exclude debug and trace logs in production:**
```yaml
[FILTER]
    Name    grep
    Match   kube.*
    Exclude kubernetes.namespace_name production
    Exclude kubernetes.labels.log_level debug
    Exclude kubernetes.labels.log_level trace
```

### Complex Multi-Filter Examples

**Web applications with error logs only:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.labels.app-type web

[FILTER]
    Name   grep
    Match  kube.*
    Regex  log_processed.level error
```

**Payment service with sensitive data redaction:**
```yaml
[FILTER]
    Name   grep
    Match  kube.*
    Regex  kubernetes.labels\.app\.kubernetes\.io/name payment-service

[FILTER]
    Name    modify
    Match   kube.*
    Remove  credit_card
    Remove  ssn
    Remove  bank_account
```

---

## Configuration Requirements

### Update These Values

**For OpenTelemetry:**
In `otel-values.yaml`, replace:
- `YOUR_SERVER_IP` with your OpenObserve server IP
- `YOUR_BASE64` with your base64-encoded credentials

**For Fluent Bit:**
Set these environment variables:
- `OPENOBSERVE_HOST`: Your OpenObserve server IP
- `OPENOBSERVE_PORT`: OpenObserve port (default: 5080)
- `OPENOBSERVE_USER`: OpenObserve username
- `OPENOBSERVE_PASSWORD`: OpenObserve password
- `ENVIRONMENT`: Environment name (production, staging, etc.)
- `CLUSTER_NAME`: Kubernetes cluster identifier

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
┌─────────────────────┐
│  Fluent Bit Daemon  │  ← Advanced filtering
│  Service            │    - Label-based filtering
│                     │    - Annotation filtering
│  • Tail logs        │    - Namespace filtering
│  • Kubernetes meta  │    - Log level filtering
│  • Custom filters   │    - Sensitive data redaction
└─────────────────────┘
   ↓ (Filtered logs)
Network
   ↓
OpenObserve Server (Docker)
   ↓
   └─ Dashboard & Analytics
```

### Filter Processing Order

1. **Input**: Tail container logs
2. **Kubernetes Filter**: Add metadata (labels, annotations, namespace)
3. **Custom Filters**: Apply user-defined filtering rules
4. **Output**: Send filtered logs to OpenObserve

---

## Troubleshooting

### Common Issues

1. **Wrong endpoint**: Must be `http://SERVER_IP:5080/api/default`
2. **Logs not working**: Ensure `/var/log/containers` path is correct
3. **Network blocked**: Test connectivity from cluster to server
4. **Auth errors**: Verify base64 encoding format is `email:password`
5. **Filters not working**: Check label/annotation syntax and regex patterns
6. **High resource usage**: Optimize filters and consider buffer sizes

### Troubleshooting Commands

**Check Fluent Bit configuration:**
```bash
kubectl -n fluent-bit get configmap fluent-bit -o yaml
```

**Test filter regex:**
```bash
kubectl logs -n fluent-bit -l app.kubernetes.io/name=fluent-bit | grep "filter"
```

**Verify metadata enrichment:**
```bash
kubectl logs -n fluent-bit -l app.kubernetes.io/name=fluent-bit | grep "kubernetes"
```

### Optional Enhancements

Consider adding:
- HTTPS with reverse proxy
- Kubernetes dashboards
- High-volume logging with buffering
- Auto-instrumentation for traces
- **Advanced alerting based on filtered logs**
- **Log retention policies by service**
- **Multi-cluster observability**
- **Custom parsers for application-specific formats**

### Performance Optimization

**Buffer Configuration:**
```yaml
Mem_Buf_Limit     100MB
Buffer_Chunk_Size 64KB
Buffer_Max_Size   128KB
```

**Filter Optimization:**
- Place most restrictive filters first
- Use efficient regex patterns
- Consider using `exclude` over `regex` when possible

---

## Quick Start Commands

**OpenObserve Server:**
```bash
# Start OpenObserve
docker compose up -d
```

**Fluent Bit with Advanced Filtering:**
```bash
# Install Fluent Bit
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
helm upgrade --install fluent-bit fluent/fluent-bit --namespace fluent-bit --create-namespace

# Apply advanced configuration
kubectl apply -f fluent-bit-config.yaml
kubectl apply -f parsers.conf
kubectl create configmap correlation-script --from-file=correlation.lua -n fluent-bit

# Set environment variables
kubectl set env daemonset/fluent-bit -n fluent-bit \
  OPENOBSERVE_HOST=YOUR_SERVER_IP \
  OPENOBSERVE_USER=admin@example.com \
  OPENOBSERVE_PASSWORD=YourPassword

# Restart pods
kubectl delete pods -n fluent-bit -l app.kubernetes.io/name=fluent-bit
```

**OpenTelemetry Alternative:**
```bash
# Deploy to Kubernetes
helm install otel open-telemetry/opentelemetry-collector -f otel-values.yaml
```

**Verify Deployment:**
```bash
# Check Fluent Bit
kubectl logs -n fluent-bit -l app.kubernetes.io/name=fluent-bit

# Check OpenTelemetry (if used)
kubectl logs -l app.kubernetes.io/name=opentelemetry-collector
```
