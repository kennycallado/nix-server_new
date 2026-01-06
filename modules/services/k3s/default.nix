{ config, lib, pkgs, conf, hosts, constants, ... }:
let
  cfg = conf.k3s or { };
  isServer = cfg.role or "agent" == "server";
  isFirstServer = cfg.serverAddr or "" == "";
  exposeServices = cfg.exposeServices or false; # Whether to expose services via public ingress

  # Domain configuration from constants (e.g., "kennycallado.dev", "staging.example.com")
  domain = constants.domain;
  adminEmail = constants.admin.email;
  metricsConfig = constants.metrics;
  backupsConfig = constants.backups;

  serverToleration = [{
    key = "node-role.kubernetes.io/control-plane";
    operator = "Exists";
    effect = "NoSchedule";
  }];

  # NFS server IP (only available when nodes have WireGuard keys)
  nfsServerIp =
    if hosts.findNfsServer != null
    then hosts.nodes.${hosts.findNfsServer}.ip.wg
    else "10.100.10.1"; # Fallback, will be updated when keys are generated

  # Calculate number of agent nodes for Garage replicas
  # Agent nodes are those without wg.isServer (non-control-plane nodes)
  agentNodes = lib.filterAttrs (n: v: !(v.wg.isServer or false)) hosts.nodes;
  numAgents = lib.length (lib.attrNames agentNodes);

  # Ensure at least 1 replica if no agents are defined (though unlikely)
  garageReplicas = if numAgents > 0 then numAgents else 1;

  # PostgreSQL passwords manejados por SealedSecrets (sealedsecrets/postgres.yaml)

  # Configuración de Garage (S3-compatible object storage)
  # Los secrets (rpcSecret, adminToken, metricsToken) están en SealedSecrets
  garageConfig = {
    version = "v2.1.0";
    replicas = garageReplicas; # Un pod por worker node
    replicationFactor = if garageReplicas < 2 then 1 else 2; # Datos replicados en 2 nodos (o 1 si solo hay 1)
    s3Region = "garage";
    metaStorageSize = "500Mi";
    dataStorageSize = "20Gi";
  };

  # Configuración de Garage WebUI
  # adminToken viene del SealedSecret garage-secrets
  # authUserPass viene del SealedSecret garage-webui-auth
  garageWebuiConfig = {
    version = "latest";
    inherit (garageConfig) s3Region;
  };

  # Helm charts (autoDeployCharts)
  charts = import ./charts { inherit serverToleration nfsServerIp exposeServices domain metricsConfig; };

  # Raw manifests (desplegados via k3s auto-deploy)
  manifests = {
    cnpg-cluster = import ./manifests/cnpg-cluster.nix {
      inherit serverToleration pkgs lib backupsConfig;
    };
    # windmill-secret ahora es un SealedSecret (sealedsecrets/windmill.yaml)
    garage = import ./manifests/garage.nix {
      inherit pkgs lib garageConfig;
    };
    garage-webui = import ./manifests/garage-webui.nix {
      inherit pkgs lib garageWebuiConfig;
    };
    cluster-issuer = import ./manifests/cluster-issuer.nix {
      inherit pkgs lib adminEmail;
    };
    argocd-ingress = import ./manifests/argocd-ingress.nix {
      inherit pkgs lib domain;
    };
    windmill-servicemonitor = import ./manifests/windmill-servicemonitor.nix {
      inherit pkgs lib;
    };
  };
in
{
  # Token compartido para el cluster (secreto)
  age.secrets.k3s-token = lib.mkIf (cfg.enable or false) {
    file = ../../../secrets/services-k3s_token.age;
  };

  # Clave de Sealed Secrets para reproducibilidad (solo en server)
  # Esta clave se inyecta en k8s para que el controller use siempre la misma
  age.secrets.sealed-secrets-key = lib.mkIf (isServer && (cfg.enable or false)) {
    file = ../../../secrets/sealed-secrets-key.age;
    mode = "0600";
    owner = "root";
  };

  # Generar manifest de sealed-secrets-key antes de que k3s arranque
  # El manifest se crea en /var/lib/rancher/k3s/server/manifests/ para auto-deploy
  system.activationScripts.sealed-secrets-key = lib.mkIf (isServer && (cfg.enable or false)) {
    text = ''
      ${(import ./manifests/sealed-secrets-key.nix {
        inherit pkgs lib;
        sealedSecretsKeyPath = config.age.secrets.sealed-secrets-key.path;
        sealedSecretsCertPath = ../../../secrets/sealed-secrets-cert.pem;
      }).generateManifest}
    '';
    deps = [ "agenix" ]; # Debe ejecutarse después de que agenix desencripte
  };

  services.k3s = lib.mkIf (cfg.enable or false) {
    enable = true;
    role = cfg.role or "agent";
    tokenFile = config.age.secrets.k3s-token.path;

    # Si no hay serverAddr, es el primer server (inicia cluster)
    # Si hay serverAddr, se une al cluster existente
    serverAddr = lib.mkIf (!isFirstServer) cfg.serverAddr;

    extraFlags = lib.concatStringsSep " " (
      (lib.optionals isServer [
        "--disable=traefik"
        "--write-kubeconfig-mode=644"
        # Taint para que workloads no corran en control-plane
        # Los helm-install jobs de k3s toleran este taint cuando spec.bootstrap=true
        "--node-taint=node-role.kubernetes.io/control-plane:NoSchedule"
        "--tls-san=${
          if hosts.findWgServer != null
          then hosts.nodes.${hosts.findWgServer}.ip.wg
          else "10.100.10.1"
        }"
      ])
      ++ (cfg.extraFlags or [ ])
    );

    # Helm charts auto-desplegados (solo en servers)
    autoDeployCharts = lib.mkIf isServer charts;
  };

  # Manifests adicionales para k3s auto-deploy
  systemd.tmpfiles.rules = lib.mkIf (isServer && (cfg.enable or false)) ([
    "L+ /var/lib/rancher/k3s/server/manifests/cnpg-cluster.yaml - - - - ${manifests.cnpg-cluster}"
    "L+ /var/lib/rancher/k3s/server/manifests/garage.yaml - - - - ${manifests.garage}"
    "L+ /var/lib/rancher/k3s/server/manifests/garage-webui.yaml - - - - ${manifests.garage-webui}"
    "L+ /var/lib/rancher/k3s/server/manifests/cluster-issuer.yaml - - - - ${manifests.cluster-issuer}"
    "L+ /var/lib/rancher/k3s/server/manifests/windmill-servicemonitor.yaml - - - - ${manifests.windmill-servicemonitor}"
    # SealedSecrets - se desencriptan automáticamente por el controller
    "L+ /var/lib/rancher/k3s/server/manifests/garage-sealed.yaml - - - - ${./sealedsecrets/garage.yaml}"
    "L+ /var/lib/rancher/k3s/server/manifests/postgres-sealed.yaml - - - - ${./sealedsecrets/postgres.yaml}"
    "L+ /var/lib/rancher/k3s/server/manifests/windmill-sealed.yaml - - - - ${./sealedsecrets/windmill.yaml}"
    "L+ /var/lib/rancher/k3s/server/manifests/windmill-superadmin-sealed.yaml - - - - ${./sealedsecrets/windmill-superadmin.yaml}"
    "L+ /var/lib/rancher/k3s/server/manifests/grafana-admin-sealed.yaml - - - - ${./sealedsecrets/grafana-admin.yaml}"
  ] ++ lib.optionals exposeServices [
    # Public ingress for ArgoCD (only when exposeServices is true)
    "L+ /var/lib/rancher/k3s/server/manifests/argocd-ingress.yaml - - - - ${manifests.argocd-ingress}"
  ]);

  # Abrir puertos necesarios
  networking.firewall = lib.mkIf (cfg.enable or false) {
    allowedTCPPorts = lib.optionals isServer [ 6443 2379 2380 ]
      ++ [ 10250 ]
      ++ lib.optionals exposeServices [ 80 443 ]; # Only expose HTTP/HTTPS when exposeServices is true
    allowedUDPPorts = [ 8472 ];
  };

  # Dependencias
  environment.systemPackages = lib.mkIf (cfg.enable or false) [
    pkgs.k3s
    pkgs.kubectl
    pkgs.kubernetes-helm
  ];
}
