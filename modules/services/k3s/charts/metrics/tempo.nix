# Grafana Tempo
# Distributed tracing backend - SingleBinary mode for simplicity
# Receives traces via OTLP (OpenTelemetry) and Jaeger protocols
{ serverToleration, metricsConfig }:

{
  name = "tempo";
  repo = "https://grafana.github.io/helm-charts";
  version = "1.24.1";
  hash = "sha256-iVa4Oho60rMKQAioML+I7q7tK3VPdgTO2db+cS+ur8k=";
  extraFieldDefinitions = {
    spec.targetNamespace = "metrics";
    spec.createNamespace = true;
    spec.bootstrap = true;
  };
  values = {
    # ===== Scheduling (root level for this chart) =====
    tolerations = serverToleration;
    nodeSelector."node-role.kubernetes.io/control-plane" = "true";

    # ===== Resources =====
    resources = {
      requests = { cpu = "100m"; memory = "256Mi"; };
      limits = { cpu = "500m"; memory = "1Gi"; };
    };

    # ===== Tempo config =====
    tempo = {
      # Receivers - enable OTLP (gRPC and HTTP) for OpenTelemetry
      receivers = {
        otlp = {
          protocols = {
            grpc = {
              endpoint = "0.0.0.0:4317";
            };
            http = {
              endpoint = "0.0.0.0:4318";
            };
          };
        };
        jaeger = {
          protocols = {
            thrift_http = {
              endpoint = "0.0.0.0:14268";
            };
            grpc = {
              endpoint = "0.0.0.0:14250";
            };
          };
        };
      };

      # Storage configuration - local filesystem
      storage = {
        trace = {
          backend = "local";
          local = {
            path = "/var/tempo/traces";
          };
          wal = {
            path = "/var/tempo/wal";
          };
        };
      };

      # Retention (from constants)
      retention = metricsConfig.retention;
    };

    # ===== Persistence =====
    persistence = {
      enabled = true;
      size = metricsConfig.storage.tempo;
    };

    # ===== Service =====
    service = {
      type = "ClusterIP";
    };

    # ===== Tempo Query (Jaeger UI compatible) =====
    tempoQuery = {
      enabled = false; # We use Grafana for querying
    };
  };
}
