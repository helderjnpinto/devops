# Fluent Bit Docker Setup

This repository contains a Docker setup for Fluent Bit with YAML configuration, providing a flexible and modern log processing solution.

## Overview

Fluent Bit is a fast and lightweight log processor and forwarder which is part of the Fluentd ecosystem. This setup uses the modern YAML configuration format introduced in Fluent Bit v3.2.

## Quick Start

### Using Docker Compose (Recommended)

1. **Clone and navigate to the directory:**
   ```bash
   cd fluentbit
   ```

2. **Create a logs directory:**
   ```bash
   mkdir -p logs
   ```

3. **Start Fluent Bit:**
   ```bash
   docker-compose up -d
   ```

4. **Check status:**
   ```bash
   docker-compose ps
   ```

5. **View logs:**
   ```bash
   docker-compose logs -f fluent-bit
   ```

### Using Docker directly

1. **Build the image:**
   ```bash
   docker build -t fluent-bit-custom .
   ```

2. **Run the container:**
   ```bash
   docker run -d \
     --name fluent-bit \
     -p 2020:2020 \
     -v $(pwd)/fluent-bit.yaml:/fluent-bit/etc/fluent-bit.yaml:ro \
     -v $(pwd)/logs:/var/log:ro \
     fluent-bit-custom
   ```

## Configuration

### Main Configuration (fluent-bit.yaml)

The configuration uses the modern YAML format with the following sections:

- **service**: Global Fluent Bit settings
- **pipeline**: Inputs, filters, and outputs
- **parsers**: Custom log parsers

#### Service Section
```yaml
service:
    flush: 1              # Flush interval in seconds
    daemon: off           # Run as daemon
    log_level: info       # Log level
    http_server: on       # Enable HTTP API
    http_listen: 0.0.0.0  # Listen address
    http_port: 2020       # HTTP API port
```

#### Pipeline Inputs
- **tail**: Reads log files from `/var/log/*.log`
- **systemd**: Reads systemd logs for ssh and docker services

#### Pipeline Filters
- **kubernetes**: Kubernetes metadata enrichment
- **grep**: Filters logs containing "error"

#### Pipeline Outputs
- **stdout**: Outputs to console in JSON format
- **file**: Outputs to `/var/log/fluent-bit/output.log`

### Customizing Configuration

1. **Edit `fluent-bit.yaml`** to modify inputs, filters, or outputs
2. **Restart the container** to apply changes:
   ```bash
   docker-compose restart fluent-bit
   ```

## Monitoring

### HTTP API

Fluent Bit provides an HTTP API on port 2020:

- **Metrics:** `http://localhost:2020/api/v1/metrics`
- **Plugins:** `http://localhost:2020/api/v1/plugins`
- **Config:** `http://localhost:2020/api/v1/config`

### Example API calls:

```bash
# Get metrics
curl http://localhost:2020/api/v1/metrics

# Get plugin information
curl http://localhost:2020/api/v1/plugins

# Get current configuration
curl http://localhost:2020/api/v1/config
```

## Testing

### Add test logs

1. **Create test log files:**
   ```bash
   echo '{"time": "2024-01-01T12:00:00.000Z", "level": "info", "message": "Test log"}' > logs/test.log
   echo '{"time": "2024-01-01T12:01:00.000Z", "level": "error", "message": "Test error log"}' >> logs/test.log
   ```

2. **Monitor Fluent Bit output:**
   ```bash
   docker-compose logs -f fluent-bit
   ```

### Verify processing

Check the output file:
```bash
docker exec fluent-bit cat /var/log/fluent-bit/output.log
```

## Common Use Cases

### 1. File Log Collection
Modify the tail input to watch specific files:
```yaml
inputs:
    - name: tail
      path: /var/log/app/*.log
      tag: app.*
      parser: json
```

### 2. System Log Collection
Add more systemd units:
```yaml
inputs:
    - name: systemd
      tag: systemd.*
      systemd_filter:
        - _SYSTEMD_UNIT=nginx.service
        - _SYSTEMD_UNIT=postgresql.service
```

### 3. Forward to External Service
Replace stdout output with external service:
```yaml
outputs:
    - name: elastic
      match: *
      host: elasticsearch
      port: 9200
      index: fluent-bit
```

## Environment Variables

You can customize behavior using environment variables:

- `FLUENT_BIT_LOG_LEVEL`: Set log level (debug, info, warn, error)
- `FLUENT_BIT_FLUSH`: Set flush interval in seconds

Example:
```bash
docker-compose run -e FLUENT_BIT_LOG_LEVEL=debug fluent-bit
```

## Volumes

- **./logs:/var/log**: Read-only access to host log files
- **fluent-bit-data:/var/log/fluent-bit**: Persistent storage for Fluent Bit internal files

## Troubleshooting

### Common Issues

1. **Permission denied on log files:**
   ```bash
   sudo chmod 644 logs/*.log
   ```

2. **Container won't start:**
   ```bash
   docker-compose logs fluent-bit
   ```

3. **Configuration syntax error:**
   ```bash
   docker run --rm -v $(pwd)/fluent-bit.yaml:/config.yaml fluent/fluent-bit:3.2 --config=/config.yaml --dry-run
   ```

### Debug Mode

Enable debug logging:
```yaml
service:
    log_level: debug
```

Or via environment variable:
```bash
FLUENT_BIT_LOG_LEVEL=debug docker-compose up
```

## Resources

- [Fluent Bit Official Documentation](https://docs.fluentbit.io/)
- [YAML Configuration Guide](https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/yaml)
- [Fluent Bit GitHub](https://github.com/fluent/fluent-bit)

## License

This configuration is provided as-is under the same terms as Fluent Bit.
