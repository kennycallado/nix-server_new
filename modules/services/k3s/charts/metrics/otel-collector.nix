# OpenTelemetry Collector
# Central telemetry gateway for all cluster applications
# Receives OTLP from: Windmill, client apps, any service with OTEL instrumentation
# Forwards to: Tempo (traces), Loki (logs), Prometheus (metrics)
#
# Replaces grafana/otel-lgtm with production-ready separated components
#
# Apps can send telemetry to:
#   - gRPC: otel-collector.metrics.svc.cluster.local:4317
#   - HTTP: otel-collector.metrics.svc.cluster.local:4318
#
{ serverToleration }:

{
  name = "opentelemetry-collector";
  repo = "https://open-telemetry.github.io/opentelemetry-helm-charts";
  version = "0.108.0";
  hash = "sha256-DqLqkEBEBf0HSPbFwJ2hzlgcsWZomkZxrrmP8sANeCs=";
  extraFieldDefinitions = {
    spec.targetNamespace = "metrics";
    spec.createNamespace = true;
    spec.bootstrap = true;
  };
  values = {
    # ===== Deployment mode =====
    mode = "deployment"; # Single replica deployment (not daemonset)
    replicaCount = 1;

    # ===== Scheduling =====
    tolerations = serverToleration;
    nodeSelector."node-role.kubernetes.io/control-plane" = "true";

    # ===== Resources =====
    resources = {
      requests = { cpu = "100m"; memory = "256Mi"; };
      limits = { cpu = "500m"; memory = "512Mi"; };
    };

    # ===== Ports exposed to cluster =====
    ports = {
      # OTLP gRPC - primary protocol for most SDKs
      otlp = {
        enabled = true;
        containerPort = 4317;
        servicePort = 4317;
        protocol = "TCP";
      };
      # OTLP HTTP - alternative for environments without gRPC
      otlp-http = {
        enabled = true;
        containerPort = 4318;
        servicePort = 4318;
        protocol = "TCP";
      };
      # Prometheus metrics endpoint (self-monitoring)
      metrics = {
        enabled = true;
        containerPort = 8888;
        servicePort = 8888;
        protocol = "TCP";
      };
    };

    # ===== OTEL Collector Configuration =====
    config = {
      # ===== Receivers =====
      # Accept OTLP from any application in the cluster
      receivers = {
        otlp = {
          protocols = {
            grpc = {
              endpoint = "0.0.0.0:4317";
            };
            http = {
              endpoint = "0.0.0.0:4318";
              # CORS for browser-based apps
              cors = {
                allowed_origins = [ "*" ];
                allowed_headers = [ "*" ];
              };
            };
          };
        };
      };

      # ===== Processors =====
      processors = {
        # Batch for efficiency
        batch = {
          timeout = "5s";
          send_batch_size = 1000;
        };
        # Memory protection
        memory_limiter = {
          check_interval = "1s";
          limit_mib = 400;
          spike_limit_mib = 100;
        };
        # Add cluster metadata to all telemetry
        resource = {
          attributes = [
            { key = "cluster"; value = "windmill-cluster"; action = "upsert"; }
          ];
        };
      };

      # ===== Connectors =====
      # Generate Prometheus metrics from spans (RED metrics)
      connectors = {
        spanmetrics = {
          histogram = {
            explicit = {
              buckets = [ "5ms" "10ms" "25ms" "50ms" "100ms" "250ms" "500ms" "1s" "2.5s" "5s" "10s" ];
            };
          };
          # Dimensions to include in metrics (from span attributes)
          dimensions = [
            { name = "service.name"; }
            { name = "service.namespace"; }
            # Windmill-specific
            { name = "job_id"; }
            { name = "script_path"; }
            { name = "workspace_id"; }
            { name = "worker_id"; }
            { name = "language"; }
          ];
          dimensions_cache_size = 1000;
          exemplars = { enabled = true; };
          metrics_flush_interval = "15s";
        };
      };

      # ===== Exporters =====
      exporters = {
        # Traces to Tempo (OTLP gRPC)
        otlp = {
          endpoint = "tempo.metrics.svc.cluster.local:4317";
          tls = { insecure = true; };
        };
        # Logs to Loki (OTLP HTTP endpoint)
        otlphttp = {
          endpoint = "http://loki.metrics.svc.cluster.local:3100/otlp";
          tls = { insecure = true; };
        };
        # Span metrics to Prometheus (remote write)
        prometheusremotewrite = {
          endpoint = "http://kube-prometheus-stack-prometheus.metrics.svc.cluster.local:9090/api/v1/write";
          tls = { insecure = true; };
        };
        # Debug exporter (optional, for troubleshooting)
        # debug = { verbosity = "detailed"; };
      };

      # ===== Service Pipelines =====
      service = {
        pipelines = {
          # Traces: OTLP -> process -> Tempo + spanmetrics connector
          traces = {
            receivers = [ "otlp" ];
            processors = [ "memory_limiter" "resource" "batch" ];
            exporters = [ "otlp" "spanmetrics" ];
          };
          # Logs: OTLP -> process -> Loki
          logs = {
            receivers = [ "otlp" ];
            processors = [ "memory_limiter" "resource" "batch" ];
            exporters = [ "otlphttp" ];
          };
          # Metrics from spans: spanmetrics connector -> Prometheus
          "metrics/spanmetrics" = {
            receivers = [ "spanmetrics" ];
            exporters = [ "prometheusremotewrite" ];
          };
        };
        # Telemetry for the collector itself
        telemetry = {
          metrics = {
            address = "0.0.0.0:8888";
          };
        };
      };
    };

    # ===== Service =====
    service = {
      type = "ClusterIP";
    };

    # ===== ServiceMonitor for Prometheus =====
    serviceMonitor = {
      enabled = true;
      metricsEndpoints = [{
        port = "metrics";
        interval = "30s";
      }];
    };
  };
}
