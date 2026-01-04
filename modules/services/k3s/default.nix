{ config, lib, pkgs, conf, hosts, ... }:
let
  cfg = conf.k3s or { };
  isServer = cfg.role or "agent" == "server";
  isFirstServer = cfg.serverAddr or "" == "";

  serverToleration = [{
    key = "node-role.kubernetes.io/control-plane";
    operator = "Exists";
    effect = "NoSchedule";
  }];

  nfsServerIp = hosts.nodes.${hosts.findNfsServer}.ip.wg;

  # PostgreSQL passwords manejados por SealedSecrets (sealedsecrets/postgres.yaml)

  # Configuración de Garage (S3-compatible object storage)
  # Los secrets (rpcSecret, adminToken, metricsToken) están en SealedSecrets
  garageConfig = {
    version = "v2.1.0";
    replicas = 2; # Un pod por worker node
    replicationFactor = 2; # Datos replicados en 2 nodos
    s3Region = "garage";
    metaStorageSize = "500Mi";
    dataStorageSize = "20Gi";
  };

  # Configuración de Garage WebUI
  # adminToken viene del SealedSecret garage-secrets
  garageWebuiConfig = {
    version = "latest";
    inherit (garageConfig) s3Region;
    # Autenticación básica (opcional)
    # Generar con: htpasswd -nbBC 10 "admin" "password"
    authUserPass = ""; # Formato: "username:$2y$10$..."
  };

  # Helm charts (autoDeployCharts)
  charts = import ./charts { inherit serverToleration nfsServerIp; };

  # Raw manifests (desplegados via k3s auto-deploy)
  manifests = {
    cnpg-cluster = import ./manifests/cnpg-cluster.nix {
      inherit serverToleration pkgs lib;
    };
    # windmill-secret ahora es un SealedSecret (sealedsecrets/windmill.yaml)
    garage = import ./manifests/garage.nix {
      inherit pkgs lib garageConfig;
    };
    garage-webui = import ./manifests/garage-webui.nix {
      inherit pkgs lib garageWebuiConfig;
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
        "--disable=servicelb"
        "--write-kubeconfig-mode=644"
        # Taint para que workloads no corran en control-plane
        # Los helm-install jobs de k3s toleran este taint cuando spec.bootstrap=true
        "--node-taint=node-role.kubernetes.io/control-plane:NoSchedule"
        "--tls-san=${hosts.nodes.${hosts.findWgServer}.ip.wg}"
      ])
      ++ (cfg.extraFlags or [ ])
    );

    # Helm charts auto-desplegados (solo en servers)
    autoDeployCharts = lib.mkIf isServer charts;
  };

  # Manifests adicionales para k3s auto-deploy
  systemd.tmpfiles.rules = lib.mkIf (isServer && (cfg.enable or false)) [
    "L+ /var/lib/rancher/k3s/server/manifests/cnpg-cluster.yaml - - - - ${manifests.cnpg-cluster}"
    "L+ /var/lib/rancher/k3s/server/manifests/garage.yaml - - - - ${manifests.garage}"
    "L+ /var/lib/rancher/k3s/server/manifests/garage-webui.yaml - - - - ${manifests.garage-webui}"
    # SealedSecrets - se desencriptan automáticamente por el controller
    "L+ /var/lib/rancher/k3s/server/manifests/garage-sealed.yaml - - - - ${./sealedsecrets/garage.yaml}"
    "L+ /var/lib/rancher/k3s/server/manifests/postgres-sealed.yaml - - - - ${./sealedsecrets/postgres.yaml}"
    "L+ /var/lib/rancher/k3s/server/manifests/windmill-sealed.yaml - - - - ${./sealedsecrets/windmill.yaml}"
  ];

  # Abrir puertos necesarios
  networking.firewall = lib.mkIf (cfg.enable or false) {
    allowedTCPPorts = lib.optionals isServer [ 6443 2379 2380 ] ++ [ 10250 ];
    allowedUDPPorts = [ 8472 ];
  };

  # Dependencias
  environment.systemPackages = lib.mkIf (cfg.enable or false) [
    pkgs.k3s
    pkgs.kubectl
    pkgs.kubernetes-helm
  ];
}
