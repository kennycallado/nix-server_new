{ serverToleration, exposeServices, domain }:

let
  windmillHost = "windmill.${domain}";

  # InitContainer que espera a que PostgreSQL esté disponible
  waitForPostgres = {
    name = "wait-for-postgres";
    image = "busybox:1.36";
    command = [
      "sh"
      "-c"
      ''
        echo "Waiting for PostgreSQL to be ready..."
        until nc -z postgresql-rw.postgres.svc.cluster.local 5432; do
          echo "PostgreSQL not ready, waiting..."
          sleep 5
        done
        echo "PostgreSQL is ready!"
      ''
    ];
  };
in
{
  name = "windmill";
  repo = "https://windmill-labs.github.io/windmill-helm-charts";
  version = "4.0.21";
  hash = "sha256-UeW2i05o13lHkKCzS7ycnjD37jEu4+0IOvP7qe3D3uw=";
  extraFieldDefinitions = {
    spec.targetNamespace = "windmill";
    spec.createNamespace = true;
    # Bootstrap = true para que el helm-install job tolere el taint del control-plane
    spec.bootstrap = true;
  };
  values = {
    # PostgreSQL externo (CloudNativePG)
    postgresql.enabled = false;

    # Minio deshabilitado
    minio.enabled = false;

    # Configuración principal de Windmill
    windmill = {
      baseDomain = windmillHost;
      baseProtocol = "https";
      appReplicas = 1;
      lspReplicas = 1;
      multiplayerReplicas = 0; # Solo Enterprise

      # Conexión a PostgreSQL externo via Secret
      # Secret 'windmill-db-url' creado por postgres-secrets-inject systemd service
      databaseUrlSecretName = "windmill-db-url";

      # App (servidor principal) - corre en control-plane
      app = {
        tolerations = serverToleration;
        initContainers = [ waitForPostgres ];
        resources = {
          requests = { cpu = "100m"; memory = "256Mi"; };
          limits = { cpu = "500m"; memory = "512Mi"; };
        };
        # Superadmin credentials from SealedSecret + Metrics
        extraEnv = [
          {
            name = "SUPERADMIN_INITIAL_EMAIL";
            valueFrom.secretKeyRef = {
              name = "windmill-superadmin";
              key = "email";
            };
          }
          {
            name = "SUPERADMIN_INITIAL_PASSWORD";
            valueFrom.secretKeyRef = {
              name = "windmill-superadmin";
              key = "password";
            };
          }
          # Enable Prometheus metrics endpoint on port 8001
          { name = "METRICS_ADDR"; value = "0.0.0.0:8001"; }
        ];
      };

      # Worker groups - corren en control-plane
      workerGroups = [
        {
          name = "default";
          replicas = 1;
          tolerations = serverToleration;
          initContainers = [ waitForPostgres ];
          resources = {
            requests = { cpu = "200m"; memory = "512Mi"; };
            limits = { cpu = "1000m"; memory = "1Gi"; };
          };
          privileged = false;
        }
        {
          name = "native";
          replicas = 1;
          tolerations = serverToleration;
          initContainers = [ waitForPostgres ];
          resources = {
            requests = { cpu = "50m"; memory = "64Mi"; };
            limits = { cpu = "200m"; memory = "128Mi"; };
          };
          extraEnv = [
            { name = "NUM_WORKERS"; value = "4"; }
            { name = "SLEEP_QUEUE"; value = "200"; }
          ];
          privileged = false;
        }
        {
          name = "gpu";
          replicas = 0; # Deshabilitado
        }
      ];

      # LSP - corre en control-plane
      lsp = {
        tolerations = serverToleration;
        resources = {
          requests = { cpu = "50m"; memory = "128Mi"; };
          limits = { cpu = "200m"; memory = "256Mi"; };
        };
      };
    };

    # Ingress configuration (only when exposeServices is true)
    ingress = if exposeServices then {
      enabled = true;
      className = "traefik-ingress";
      annotations = {
        "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
        "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
        "traefik.ingress.kubernetes.io/router.tls" = "true";
      };
      tls = [{
        hosts = [ windmillHost ];
        secretName = "windmill-tls";
      }];
    } else {
      enabled = false;
    };

    # ===== Metrics for Prometheus =====
    # Windmill exposes /metrics on port 8001
    serviceMonitor = {
      enabled = true;
      namespace = "windmill";
      labels = { };
      interval = "30s";
      scrapeTimeout = "10s";
    };
  };
}
