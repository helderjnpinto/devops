FROM fluent/fluent-bit:5.0.2

# Copy custom configuration
COPY fluent-bit.yaml /fluent-bit/etc/

# Expose metrics port
EXPOSE 2020

# Default command with custom configuration
CMD ["/fluent-bit/bin/fluent-bit", "--config=/fluent-bit/etc/fluent-bit.yaml"]
