# Configuración del chart ArgoCD
{ serverToleration }:
{
  name = "argo-cd";
  repo = "https://argoproj.github.io/argo-helm";
  version = "7.8.23";
  hash = "sha256-sLYnWHXNziFc2+/ER3ieTAvfP8erxjZtevdbF6VdasQ=";
  extraFieldDefinitions = {
    spec.targetNamespace = "argocd";
    spec.createNamespace = true;
    spec.bootstrap = true;
  };
  values = {
    crds.install = true;
    crds.keep = true;
    global = {
      nodeSelector."node-role.kubernetes.io/control-plane" = "true";
      tolerations = serverToleration;
    };
    controller = {
      replicas = 1;
      resources = {
        requests = { cpu = "100m"; memory = "256Mi"; };
        limits = { cpu = "500m"; memory = "512Mi"; };
      };
      # Metrics for Prometheus
      metrics = {
        enabled = true;
        serviceMonitor = {
          enabled = true;
          namespace = "argocd";
        };
      };
    };
    server = {
      replicas = 1;
      extraArgs = [ "--insecure" ];
      service.type = "ClusterIP";
      # Ingress disabled - using IngressRoute CRD instead (argocd-ingress.nix)
      # This is required because Traefik ignores serversscheme annotation
      ingress.enabled = false;
      resources = {
        requests = { cpu = "50m"; memory = "128Mi"; };
        limits = { cpu = "200m"; memory = "256Mi"; };
      };
      # Metrics for Prometheus
      metrics = {
        enabled = true;
        serviceMonitor = {
          enabled = true;
          namespace = "argocd";
        };
      };
    };
    repoServer = {
      replicas = 1;
      resources = {
        requests = { cpu = "50m"; memory = "128Mi"; };
        limits = { cpu = "200m"; memory = "256Mi"; };
      };
      # Metrics for Prometheus
      metrics = {
        enabled = true;
        serviceMonitor = {
          enabled = true;
          namespace = "argocd";
        };
      };
    };
    redis = {
      enabled = true;
      resources = {
        requests = { cpu = "50m"; memory = "64Mi"; };
        limits = { cpu = "100m"; memory = "128Mi"; };
      };
      # Redis exporter metrics
      exporter = {
        enabled = true;
        resources = {
          requests = { cpu = "10m"; memory = "32Mi"; };
          limits = { cpu = "50m"; memory = "64Mi"; };
        };
      };
      metrics = {
        enabled = true;
        serviceMonitor = {
          enabled = true;
          namespace = "argocd";
        };
      };
    };
    "redis-ha".enabled = false;
    applicationSet = {
      enabled = true;
      replicas = 1;
      resources = {
        requests = { cpu = "50m"; memory = "64Mi"; };
        limits = { cpu = "100m"; memory = "128Mi"; };
      };
      # Metrics for Prometheus
      metrics = {
        enabled = true;
        serviceMonitor = {
          enabled = true;
          namespace = "argocd";
        };
      };
    };
    dex.enabled = false;
    notifications.enabled = false;
  };
}
