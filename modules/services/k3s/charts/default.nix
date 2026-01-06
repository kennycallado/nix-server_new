{ serverToleration, nfsServerIp, exposeServices, domain, metricsConfig }:

let
  # Import metrics stack (Prometheus, Loki, Tempo)
  metricsCharts = import ./metrics { inherit serverToleration exposeServices domain metricsConfig; };
in
{
  traefik-ingress = import ./traefik.nix { inherit serverToleration exposeServices; };
  cert-manager = import ./cert-manager.nix { inherit serverToleration; };
  sealed-secrets = import ./sealed-secrets.nix { inherit serverToleration; };
  nfs-provisioner = import ./nfs-provisioner.nix { inherit nfsServerIp serverToleration; };
  argocd = import ./argocd.nix { inherit serverToleration; };
  cnpg-operator = import ./cnpg-operator.nix { inherit serverToleration; };
  windmill = import ./windmill.nix { inherit serverToleration exposeServices domain; };
} // metricsCharts
