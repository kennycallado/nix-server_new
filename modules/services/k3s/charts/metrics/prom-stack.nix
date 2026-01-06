# Kube Prometheus Stack
# Includes: Prometheus, Alertmanager, Grafana, Node Exporter, Kube State Metrics
# Grafana is pre-configured with Loki and Tempo as data sources
{ serverToleration, exposeServices, domain, metricsConfig }:

let
  grafanaHost = "grafana.${domain}";
in
{
  name = "kube-prometheus-stack";
  repo = "https://prometheus-community.github.io/helm-charts";
  version = "72.6.2";
  hash = "sha256-zuW88gkeaI+2sIH50RkUMjHX9PzYzDKvtZzCrnByjNg="; # Will be updated after first build
  extraFieldDefinitions = {
    spec.targetNamespace = "metrics";
    spec.createNamespace = true;
    spec.bootstrap = true;
  };
  values = {
    # ===== Global Settings =====
    # Disable components we don't need
    kubeEtcd.enabled = false; # Not accessible in K3s
    kubeControllerManager.enabled = false; # Not accessible in K3s
    kubeScheduler.enabled = false; # Not accessible in K3s
    kubeProxy.enabled = false; # K3s uses kube-proxy differently

    # ===== Prometheus =====
    prometheus = {
      prometheusSpec = {
        # Scheduling
        tolerations = serverToleration;
        nodeSelector."node-role.kubernetes.io/control-plane" = "true";

        # Resources
        resources = {
          requests = { cpu = "250m"; memory = "512Mi"; };
          limits = { cpu = "1000m"; memory = "2Gi"; };
        };

        # Enable remote write receiver for OTEL Collector spanmetrics
        # Accepts writes at: http://prometheus:9090/api/v1/write
        enableRemoteWriteReceiver = true;

        # Storage & Retention (from constants)
        retention = metricsConfig.retention;
        storageSpec.volumeClaimTemplate = {
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = metricsConfig.storage.prometheus;
          };
        };

        # ServiceMonitor selector - match all namespaces
        serviceMonitorSelectorNilUsesHelmValues = false;
        podMonitorSelectorNilUsesHelmValues = false;
        ruleSelectorNilUsesHelmValues = false;
      };
    };

    # ===== Alertmanager =====
    alertmanager = {
      alertmanagerSpec = {
        tolerations = serverToleration;
        nodeSelector."node-role.kubernetes.io/control-plane" = "true";
        resources = {
          requests = { cpu = "10m"; memory = "32Mi"; };
          limits = { cpu = "100m"; memory = "128Mi"; };
        };
        storage.volumeClaimTemplate = {
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = metricsConfig.storage.alertmanager;
          };
        };
      };
    };

    # ===== Grafana =====
    grafana = {
      enabled = true;

      # Scheduling
      tolerations = serverToleration;
      nodeSelector."node-role.kubernetes.io/control-plane" = "true";

      # Resources
      resources = {
        requests = { cpu = "50m"; memory = "128Mi"; };
        limits = { cpu = "200m"; memory = "512Mi"; };
      };

      # Persistence
      persistence = {
        enabled = true;
        size = "2Gi";
      };

      # Admin credentials from SealedSecret (grafana-admin in metrics namespace)
      admin = {
        existingSecret = "grafana-admin";
        userKey = "admin-user";
        passwordKey = "admin-password";
      };

      # Additional data sources: Loki and Tempo
      additionalDataSources = [
        {
          name = "Loki";
          type = "loki";
          uid = "loki";
          url = "http://loki.metrics.svc.cluster.local:3100";
          access = "proxy";
          isDefault = false;
          jsonData = {
            maxLines = 1000;
          };
        }
        {
          name = "Tempo";
          type = "tempo";
          uid = "tempo";
          url = "http://tempo.metrics.svc.cluster.local:3100";
          access = "proxy";
          isDefault = false;
          jsonData = {
            tracesToLogsV2 = {
              datasourceUid = "loki";
              spanStartTimeShift = "-1h";
              spanEndTimeShift = "1h";
              filterByTraceID = true;
              filterBySpanID = false;
            };
            tracesToMetrics = {
              datasourceUid = "prometheus";
            };
            lokiSearch = {
              datasourceUid = "loki";
            };
          };
        }
      ];

      # Ingress (only when exposed)
      ingress = if exposeServices then {
        enabled = true;
        ingressClassName = "traefik";
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
        };
        hosts = [ grafanaHost ];
        tls = [{
          secretName = "grafana-tls";
          hosts = [ grafanaHost ];
        }];
      } else {
        enabled = false;
      };
    };

    # ===== Kube State Metrics =====
    kube-state-metrics = {
      tolerations = serverToleration;
      nodeSelector."node-role.kubernetes.io/control-plane" = "true";
    };

    # ===== Node Exporter =====
    # Runs on ALL nodes (no tolerations/nodeSelector restrictions)
    prometheus-node-exporter = {
      tolerations = [
        {
          effect = "NoSchedule";
          operator = "Exists";
        }
      ];
    };

    # ===== Prometheus Operator =====
    prometheusOperator = {
      tolerations = serverToleration;
      nodeSelector."node-role.kubernetes.io/control-plane" = "true";
      resources = {
        requests = { cpu = "50m"; memory = "64Mi"; };
        limits = { cpu = "200m"; memory = "256Mi"; };
      };
      # Admission webhooks - need tolerations for the jobs
      admissionWebhooks = {
        patch = {
          tolerations = serverToleration;
          nodeSelector."node-role.kubernetes.io/control-plane" = "true";
        };
      };
    };
  };
}
