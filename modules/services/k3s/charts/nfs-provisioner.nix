# Configuración del chart nfs-subdir-external-provisioner
{ nfsServerIp, serverToleration }:
{
  name = "nfs-subdir-external-provisioner";
  repo = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner";
  version = "4.0.18";
  hash = "sha256-qEIWPB9e7cSJPh9oXkJJsN3WJTPDyUEijuaglqwwj28=";
  extraFieldDefinitions = {
    spec.targetNamespace = "nfs-provisioner";
    spec.createNamespace = true;
    # Bootstrap = true para que el helm-install job tolere el taint del control-plane
    spec.bootstrap = true;
  };
  values = {
    nfs.server = nfsServerIp;
    nfs.path = "/srv/nfs";
    storageClass = {
      name = "nfs";
      defaultClass = true;
      reclaimPolicy = "Retain";
    };
    nodeSelector."node-role.kubernetes.io/control-plane" = "true";
    tolerations = serverToleration;
  };
}
