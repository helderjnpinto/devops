# Install guide using helm chart and configuration for open Observe

## Prerequisites

- Kubernetes cluster
- Helm 3+
- OpenObserve instance running and accessible

## Docs for reference

- <https://docs.fluentbit.io/manual/installation/downloads/kubernetes>

## Installation Steps

If you are using google cloud you may see similar daemonsets already deployed by the google it self.

TODO: Check if we can disable the existing google logging and use only our fluentbit configuration.

1 - Add the Fluent Bit Helm repository:

Use the following command to add the Fluent Helm charts repository:

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
```

Verify the repository was added:

```bash
helm search repo fluent
```

2 - Create a secret with your OpenObserve credentials:

```bash
kubectl create namespace logging
```

```bash
kubectl create secret generic openobserve-credentials \
  --namespace logging \
  --from-literal=host="your-openobserve-host" \
  --from-literal=port="443" \
  --from-literal=username="your-username" \
  --from-literal=password="your-password"
```

3 - Install Fluent Bit using the Helm chart:

### Basic Installation

```bash
helm upgrade --install fluent-bit fluent/fluent-bit-collector \
  --namespace logging \
  --create-namespace
```

### Installation with Custom Values

Create a custom `values.yml` file. You can use the provided example as a starting point:

```bash
cp values.yaml my-custom-values.yaml
```

The example `values.yaml` file includes:

- Custom image configuration
- Resource limits and requests  
- Prometheus service monitor setup
- Custom Fluent Bit configuration for OpenObserve integration
- Environment variables from secrets

Then install with your custom values:

```bash
helm upgrade --install fluent-bit fluent/fluent-bit-collector \
  --namespace logging \
  --create-namespace \
  --values my-custom-values.yaml
```

4 - Verify the installation:

```bash
kubectl get pods -n logging
```

## Maintenance

### Configuration Updates

Fluent Bit is configured with automatic config reload enabled. When you update the ConfigMap, Fluent Bit will automatically detect changes and reload the configuration without requiring a pod restart.

#### Automatic Reload Features

- **Config_Watch**: Monitors configuration files for changes
- **Grace Period**: 30 seconds to complete current processing before reload

#### Update Configuration

1. **Edit the ConfigMap**:

```bash
kubectl edit configmap fluentbit-config --namespace logging
```

2. **Or apply changes from file**:

```bash
kubectl apply -f fluentbit-config.yaml
```

3. **Verify reload** (automatic):

```bash
kubectl logs -l app.kubernetes.io/name=fluent-bit --namespace logging --tail=20
```

Look for messages like:

```text
[info] [engine] detected configuration changes, reloading
[info] [output] http.0: restored
```

#### Manual Reload (if needed)

If automatic reload doesn't work:

```bash
# Restart Fluent Bit pods
kubectl rollout restart daemonset/fluent-bit --namespace logging

# Or use HTTP API
curl -X POST http://fluent-bit.logging.svc.cluster.local:2020/api/v1/reload
```

#### Optional: Install Reloader

For enhanced ConfigMap change detection:

```bash
helm repo add stakater https://stakater.github.io/stakater-charts
helm install reloader stakater/reloader --namespace default
```

The annotation `configmap.reloader.stakater.com/reload: "true"` is already included in the values.yaml for this integration.

## Configuration Management

### Applying ConfigMap Changes

When updating the ConfigMap configuration, follow these steps:

1. **Apply the ConfigMap**:

```bash
kubectl apply -f fluentbit-configmap.yaml --namespace logging
```

2. **Verify the ConfigMap was applied**:

```bash
kubectl get configmap fluentbit-config --namespace logging -o yaml
```

3. **Check Fluent Bit logs for reload**:

```bash
kubectl logs -l app.kubernetes.io/name=fluent-bit --namespace logging --tail=20
```

### TLS Configuration

The current ConfigMap has TLS disabled (`tls: off`). To enable TLS for secure communication with OpenObserve:

1. **Edit the ConfigMap**:

```bash
kubectl edit configmap fluentbit-config --namespace logging
```

2. **Update the TLS settings** in both output sections:

```yaml
outputs:
  - name: http
    match: apps.*
    host: ${OPENOBSERVE_HOST}
    port: ${OPENOBSERVE_PORT}
    uri: /api/default/k8s_apps/_json
    http_user: ${OPENOBSERVE_USERNAME}
    http_passwd: ${OPENOBSERVE_PASSWORD}
    format: json
    tls: on                    # Change from 'off' to 'on'
    tls.verify: on             # Enable certificate verification
    tls.ca_file: /path/to/ca.crt    # Optional: Path to CA certificate
    tls.crt_file: /path/to/client.crt   # Optional: Path to client certificate
    tls.key_file: /path/to/client.key    # Optional: Path to client private key
    compress: gzip
    retry_limit: false
    json_date_key: _timestamp
    json_date_format: iso8601
```

3. **Apply the changes**:

```bash
kubectl apply -f fluentbit-configmap.yaml --namespace logging
```

### Updating Credentials

To update OpenObserve credentials:

1. **Update the secret**:

```bash
kubectl create secret generic openobserve-credentials \
  --namespace logging \
  --from-literal=host="your-new-openobserve-host" \
  --from-literal=port="443" \
  --from-literal=username="your-new-username" \
  --from-literal=password="your-new-password" \
  --dry-run=client -o yaml | kubectl apply -f -
```

2. **Restart Fluent Bit to pick up new credentials**:

```bash
kubectl rollout restart daemonset/fluent-bit --namespace logging
```

3. **Verify the new credentials are working**:

```bash
kubectl logs -l app.kubernetes.io/name=fluent-bit --namespace logging --tail=50 | grep -i "http\|error\|connection"
```

## Troubleshooting and Rollback

### Rollback Commands

#### Rollback Helm Release

To rollback to a previous Helm release:

1. **List release history**:

```bash
helm history fluent-bit --namespace logging
```

2. **Rollback to previous version**:

```bash
helm rollback fluent-bit <revision-number> --namespace logging
```

3. **Or rollback to specific revision**:

```bash
helm rollback fluent-bit 1 --namespace logging  # Rollback to revision 1
```

#### Rollback ConfigMap Changes

1. **Get previous ConfigMap version** (if stored in version control):

```bash
git checkout HEAD~1 -- services-k8s/fluentbit/fluentbit-configmap.yaml
```

2. **Apply the previous version**:

```bash
kubectl apply -f fluentbit-configmap.yaml --namespace logging
```

3. **Or use kubectl to edit and revert changes**:

```bash
kubectl edit configmap fluentbit-config --namespace logging
```

#### Complete Uninstall

If you need to completely remove Fluent Bit:

```bash
helm uninstall fluent-bit --namespace logging
kubectl delete namespace logging
kubectl delete secret openobserve-credentials --namespace logging
```

### Common Issues

#### TLS Connection Issues

If TLS is enabled and you experience connection problems:

1. **Check certificate verification**:
```bash
kubectl logs -l app.kubernetes.io/name=fluent-bit --namespace logging | grep -i "tls\|certificate\|ssl"
```

2. **Test connectivity**:
```bash
kubectl run test-pod --image=curlimages/curl -it --rm --restart=Never --namespace logging -- \
  curl -v https://your-openobserve-host:443/api/default/k8s_apps/_json \
  -u "username:password"
```

#### Credential Issues

If authentication fails:

1. **Verify secret contents**:
```bash
kubectl get secret openobserve-credentials --namespace logging -o yaml
```

2. **Decode and verify credentials**:
```bash
kubectl get secret openobserve-credentials --namespace logging -o jsonpath='{.data.username}' | base64 -d
kubectl get secret openobserve-credentials --namespace logging -o jsonpath='{.data.password}' | base64 -d
```

#### Configuration Not Reloading

If automatic reload doesn't work:

1. **Check if hot_reload is enabled**:
```bash
kubectl get configmap fluentbit-config --namespace logging -o jsonpath='{.data.fluent-bit\.yaml}' | grep hot_reload
```

2. **Force restart**:
```bash
kubectl rollout restart daemonset/fluent-bit --namespace logging
```

3. **Check pod status**:
```bash
kubectl get pods -n logging -l app.kubernetes.io/name=fluent-bit
```
