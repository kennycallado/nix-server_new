{ serverToleration }:

{
  name = "cloudnative-pg";
  repo = "https://cloudnative-pg.github.io/charts";
  version = "0.27.0";
  hash = "sha256-ObGgzQzGuWT4VvuMgZzFiI8U+YX/JM868lZpZnrFBGw=";
  extraFieldDefinitions = {
    spec.targetNamespace = "cnpg-system";
    spec.createNamespace = true;
    # Bootstrap para que se instale temprano y los CRDs estén disponibles
    spec.bootstrap = true;
  };
  values = {
    crds.create = true;
    nodeSelector."node-role.kubernetes.io/control-plane" = "true";
    tolerations = serverToleration;
    resources = {
      requests = { cpu = "100m"; memory = "256Mi"; };
      limits = { cpu = "500m"; memory = "512Mi"; };
    };
  };
}
