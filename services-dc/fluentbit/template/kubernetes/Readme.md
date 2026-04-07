# Install guide using helm chart and configuration for open Observe

## Prerequisites

- Kubernetes cluster
- Helm 3+
- OpenObserve instance running and accessible

## Docs for reference

- https://docs.fluentbit.io/manual/installation/downloads/kubernetes

## Installation Steps

1. Add the Fluent Bit Helm repository:

Use the following command to add the Fluent Helm charts repository

```bash

helm repo add fluent https://fluent.github.io/helm-charts
```

To validate that the repository was added, run helm search repo fluent to ensure the charts were added. The default chart can then be installed by running the following command:

```bash
helm upgrade --install fluent-bit fluent/fluent-bit
```

1. Create a namespace for logging:

```bash
kubectl create namespace logging
```

3. Create a secret with your OpenObserve credentials:

```bash
kubectl create secret generic openobserve-credentials \
  --namespace logging \
  --from-literal=host="your-openobserve-host" \
  --from-literal=port="443" \
  --from-literal=username="your-username" \
  --from-literal=password="your-password"
```

4. Install Fluent Bit using the Helm chart:

```bash
helm install fluent-bit fluent/fluent-bit \
  --namespace logging \
  -f values.yaml
```

5. Verify the installation:

```bash
kubectl get pods -n logging
```

