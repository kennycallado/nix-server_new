# PostgreSQL Cluster using CloudNativePG
#
# Secrets manejados por SealedSecrets (sealedsecrets/postgres.yaml):
# - postgresql-superuser: usuario postgres (superuser)
# - windmill-user: usuario windmill para la aplicación
#
{ serverToleration, pkgs, lib ? pkgs.lib }:

let
  # Namespace
  namespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: postgres
  '';

  # Secrets (postgresql-superuser, windmill-user) son creados por SealedSecrets
  # Ver: sealedsecrets/postgres.yaml

  # Init SQL ConfigMap (no secrets - just roles and grants)
  initConfigMap = ''
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: db-init-global
      namespace: postgres
    data:
      init.sql: |
        -- Global database initialization
        -- Runs as superuser on 'postgres' database
        -- All statements are idempotent (safe to run multiple times)

        -- Create additional roles if they don't exist
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'windmill_user') THEN
            CREATE ROLE windmill_user;
          END IF;
          IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'windmill_admin') THEN
            CREATE ROLE windmill_admin WITH BYPASSRLS;
          END IF;
        END
        $$;

        -- Grants are idempotent
        GRANT windmill_user TO windmill_admin;
        GRANT windmill_admin TO windmill;
  '';

  # App init ConfigMap (schema permissions)
  appInitConfigMap = ''
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: db-init-app
      namespace: postgres
    data:
      init.sql: |
        -- Application database initialization
        -- Runs on the database defined in initdb.database

        -- Windmill: schema permissions
        GRANT ALL ON ALL TABLES IN SCHEMA public TO windmill_user;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO windmill_user;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO windmill_user;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO windmill_user;
  '';

  # PostgreSQL Cluster resource (CRD from CNPG operator)
  cluster = ''
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: postgresql
      namespace: postgres
    spec:
      instances: 1
      primaryUpdateStrategy: unsupervised

      postgresql:
        parameters:
          max_connections: "100"
          shared_buffers: "256MB"

      # Superuser secret
      superuserSecret:
        name: postgresql-superuser

      bootstrap:
        initdb:
          database: windmill
          owner: windmill
          # Secret with windmill user password
          secret:
            name: windmill-user
          # Global init: runs on 'postgres' database (create roles)
          postInitSQLRefs:
            configMapRefs:
              - name: db-init-global
                key: init.sql
          # App init: runs on 'windmill' database (schema permissions)
          postInitApplicationSQLRefs:
            configMapRefs:
              - name: db-init-app
                key: init.sql

      storage:
        size: 3Gi
        storageClass: nfs

      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"

      affinity:
        tolerations:
          - key: node-role.kubernetes.io/control-plane
            operator: Exists
            effect: NoSchedule
  '';

  manifest = lib.concatStringsSep "\n---\n" [
    namespace
    initConfigMap
    appInitConfigMap
    cluster
  ];
in
pkgs.writeText "cnpg-cluster.yaml" manifest
