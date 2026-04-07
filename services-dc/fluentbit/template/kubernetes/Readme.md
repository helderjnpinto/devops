# Install guide using helm chart and configuration for open Observe

## Prerequisites

- Kubernetes cluster
- Helm 3+
- OpenObserve instance running and accessible

## Docs for reference

- https://docs.fluentbit.io/manual/installation/downloads/kubernetes

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
