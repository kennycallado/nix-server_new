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
    };
    repoServer = {
      replicas = 1;
      resources = {
        requests = { cpu = "50m"; memory = "128Mi"; };
        limits = { cpu = "200m"; memory = "256Mi"; };
      };
    };
    redis = {
      enabled = true;
      resources = {
        requests = { cpu = "50m"; memory = "64Mi"; };
        limits = { cpu = "100m"; memory = "128Mi"; };
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
    };
    dex.enabled = false;
    notifications.enabled = false;
  };
}
