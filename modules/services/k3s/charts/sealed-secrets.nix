# Sealed Secrets controller for Kubernetes secrets management
# https://github.com/bitnami-labs/sealed-secrets
{ serverToleration }:

{
  name = "sealed-secrets";
  repo = "https://bitnami-labs.github.io/sealed-secrets";
  version = "2.18.0";
  hash = "sha256-yf7276WqEytfUuSy/BruYGhFnyD8jGEn4TUjpnUxfeo=";
  extraFieldDefinitions = {
    spec.targetNamespace = "kube-system";
    spec.createNamespace = false;
    spec.bootstrap = true; # Deploy early - other charts depend on it
  };
  values = {
    # Run on control-plane nodes
    nodeSelector."node-role.kubernetes.io/control-plane" = "true";
    tolerations = serverToleration;

    # Resource limits
    resources = {
      requests = { cpu = "50m"; memory = "64Mi"; };
      limits = { cpu = "200m"; memory = "256Mi"; };
    };

    # Controller configuration
    controller = {
      # Create the controller service account
      create = true;
    };

    # RBAC configuration
    rbac = {
      create = true;
      clusterRole = true;
    };
  };
}
