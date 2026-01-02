# Configuración del chart cert-manager
{ serverToleration }:
{
  name = "cert-manager";
  repo = "https://charts.jetstack.io";
  version = "v1.19.2";
  hash = "sha256-h+La+pRr0FxWvol7L+LhcfK7+tlsnUhAnUsRiNJAr28=";
  extraFieldDefinitions = {
    spec.targetNamespace = "cert-manager";
    spec.createNamespace = true;
    spec.bootstrap = true;
  };
  values = {
    crds.enabled = true;
    tolerations = serverToleration;
    webhook.tolerations = serverToleration;
    cainjector.tolerations = serverToleration;
    startupapicheck.tolerations = serverToleration;
    nodeSelector."node-role.kubernetes.io/control-plane" = "true";
    webhook.nodeSelector."node-role.kubernetes.io/control-plane" = "true";
    cainjector.nodeSelector."node-role.kubernetes.io/control-plane" = "true";
    startupapicheck.nodeSelector."node-role.kubernetes.io/control-plane" = "true";
  };
}
