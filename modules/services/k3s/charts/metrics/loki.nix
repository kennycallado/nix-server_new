# Grafana Loki
# Log aggregation system - SingleBinary mode for simplicity
{ serverToleration, metricsConfig }:

{
  name = "loki";
  repo = "https://grafana.github.io/helm-charts";
  version = "6.29.0";
  hash = "sha256-iCECdpytLs6tkNMMHpQERuuzl/m3BXlH6bH+1XHJc5c="; # Will be updated after first build
  extraFieldDefinitions = {
    spec.targetNamespace = "metrics";
    spec.createNamespace = true;
    spec.bootstrap = true;
  };
  values = {
    # Deploy mode: SingleBinary (simple, all-in-one)
    deploymentMode = "SingleBinary";

    # ===== SingleBinary Configuration =====
    singleBinary = {
      replicas = 1;
      tolerations = serverToleration;
      nodeSelector."node-role.kubernetes.io/control-plane" = "true";
      resources = {
        requests = { cpu = "100m"; memory = "256Mi"; };
        limits = { cpu = "500m"; memory = "1Gi"; };
      };
      persistence = {
        enabled = true;
        size = metricsConfig.storage.loki;
      };
    };

    # Disable other deployment modes
    read.replicas = 0;
    write.replicas = 0;
    backend.replicas = 0;

    # ===== Loki Configuration =====
    loki = {
      # Authentication disabled for internal use
      auth_enabled = false;

      # Common config
      commonConfig = {
        replication_factor = 1;
      };

      # Enable OTLP ingestion for OpenTelemetry Collector
      # Accepts logs at: http://loki:3100/otlp/v1/logs
      otlp = {
        enabled = true;
      };

      # Schema config
      schemaConfig = {
        configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
      };

      # Storage config - filesystem for now (can migrate to S3/Garage later)
      storage = {
        type = "filesystem";
      };

      # Limits (retention from constants)
      limits_config = {
        retention_period = metricsConfig.retention;
        ingestion_rate_mb = 10;
        ingestion_burst_size_mb = 20;
        max_streams_per_user = 10000;
        max_entries_limit_per_query = 5000;
      };
    };

    # ===== Disable components not needed in SingleBinary =====
    gateway.enabled = false;
    chunksCache.enabled = false;
    resultsCache.enabled = false;

    # ===== Monitoring =====
    monitoring = {
      selfMonitoring.enabled = false;
      lokiCanary.enabled = false;
    };

    # ===== Test disabled =====
    test.enabled = false;
  };
}
