# Traefik Ingress Controller
{ serverToleration, exposeServices }:
{
  name = "traefik";
  repo = "https://traefik.github.io/charts";
  version = "34.4.1";
  hash = "sha256-jD7Jj4LrONhKozDi5LBn8oiVlbVm4TCrS7dUXVGXgBU=";
  extraFieldDefinitions = {
    spec.targetNamespace = "kube-system";
    spec.bootstrap = true;
  };
  values = {
    tolerations = serverToleration;
    nodeSelector."node-role.kubernetes.io/control-plane" = "true";
    service = {
      type = "ClusterIP";
    };
    # Port configuration
    # When exposeServices=true: use hostPort to bind to host ports 80/443
    # When exposeServices=false: only expose internally (no hostPort)
    ports =
      if exposeServices then {
        web = {
          port = 8000;
          exposedPort = 80;
          hostPort = 80;
        };
        websecure = {
          port = 8443;
          exposedPort = 443;
          hostPort = 443;
        };
        # Metrics entrypoint for Prometheus
        metrics = {
          port = 9100;
          exposedPort = 9100;
          expose.default = false;
        };
      } else {
        web = {
          port = 8000;
          exposedPort = 80;
          # No hostPort - only accessible via tunnel/port-forward
        };
        websecure = {
          port = 8443;
          exposedPort = 443;
          # No hostPort - only accessible via tunnel/port-forward
        };
        # Metrics entrypoint for Prometheus
        metrics = {
          port = 9100;
          exposedPort = 9100;
          expose.default = false;
        };
      };
    # Required for hostPort to work properly (still useful for node affinity)
    deployment.kind = "DaemonSet";
    # Logs
    logs = {
      general.level = "DEBUG";
      access.enabled = true;
    };
    # ===== Metrics for Prometheus =====
    metrics = {
      prometheus = {
        entryPoint = "metrics";
        # ServiceMonitor for Prometheus Operator
        serviceMonitor = {
          enabled = true;
          namespace = "kube-system";
          namespaceSelector = { };
          interval = "30s";
        };
      };
    };
  };
}
