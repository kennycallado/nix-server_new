# PostgreSQL Cluster using CloudNativePG
#
# Secrets manejados por SealedSecrets (sealedsecrets/postgres.yaml):
# - postgresql-superuser: usuario postgres (superuser)
# - windmill-user: usuario windmill para la aplicación
# - cnpg-s3-creds: credenciales S3 para backups a Garage
#
{ pkgs, lib ? pkgs.lib, serverToleration ? [ ], backupsConfig }:

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

  # Custom Metrics for Windmill (Community Edition Workaround)
  # Format follows CNPG custom queries spec:
  # https://cloudnative-pg.io/documentation/current/monitoring/#user-defined-metrics
  metricsConfigMap = ''
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: windmill-metrics
      namespace: postgres
      labels:
        cnpg.io/reload: "true"
    data:
      queries: |
        windmill_workers_active:
          query: |
            SELECT count(*) as count 
            FROM worker_ping 
            WHERE ping_at > NOW() - INTERVAL '30 seconds'
          target_databases:
            - windmill
          metrics:
            - count:
                usage: "GAUGE"
                description: "Number of active Windmill workers"

        windmill_jobs_completed:
          query: |
            SELECT 
              COALESCE(j.kind::text, 'unknown') as kind,
              c.status::text as status,
              count(*) as count
            FROM v2_job_completed c
            LEFT JOIN v2_job j ON c.id = j.id
            WHERE c.completed_at > NOW() - INTERVAL '1 hour'
            GROUP BY j.kind, c.status
          target_databases:
            - windmill
          metrics:
            - kind:
                usage: "LABEL"
                description: "Type of the job (script, flow, etc)"
            - status:
                usage: "LABEL"
                description: "Completion status of the job"
            - count:
                usage: "GAUGE"
                description: "Number of completed jobs in the last hour"

        windmill_jobs_queued:
          query: |
            SELECT 
              COALESCE(j.kind::text, 'unknown') as kind,
              CASE WHEN q.running THEN 'running' ELSE 'queued' END as status,
              count(*) as count
            FROM v2_job_queue q
            LEFT JOIN v2_job j ON q.id = j.id
            WHERE q.created_at > NOW() - INTERVAL '1 hour'
            GROUP BY j.kind, q.running
          target_databases:
            - windmill
          metrics:
            - kind:
                usage: "LABEL"
                description: "Type of the job (script, flow, etc)"
            - status:
                usage: "LABEL"
                description: "Queue status (running or queued)"
            - count:
                usage: "GAUGE"
                description: "Number of jobs in queue"
  '';

  # PostgreSQL Cluster resource (CRD from CNPG operator)
  cluster = ''
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: postgresql
      namespace: postgres
    spec:
      instances: 1 # TODO: maybe per instance...
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

      # Monitoring - enables PodMonitor for Prometheus
      monitoring:
        enablePodMonitor: true
        customQueriesConfigMap:
          - name: windmill-metrics
            key: queries

      # Backups to Garage (S3-compatible)
      backup:
        barmanObjectStore:
          destinationPath: s3://cnpg-backups/
          endpointURL: http://garage.garage.svc.cluster.local:3900
          s3Credentials:
            accessKeyId:
              name: cnpg-s3-creds
              key: ACCESS_KEY_ID
            secretAccessKey:
              name: cnpg-s3-creds
              key: ACCESS_SECRET_KEY
          wal:
            compression: gzip
          data:
            compression: gzip
        retentionPolicy: "${backupsConfig.retention}"
  '';

  # Scheduled backup
  scheduledBackup = ''
    apiVersion: postgresql.cnpg.io/v1
    kind: ScheduledBackup
    metadata:
      name: postgresql-daily-backup
      namespace: postgres
    spec:
      schedule: "0 3 * * *"
      backupOwnerReference: self
      cluster:
        name: postgresql
      immediate: true
  '';

  manifest = lib.concatStringsSep "\n---\n" [
    namespace
    initConfigMap
    appInitConfigMap
    metricsConfigMap
    cluster
    scheduledBackup
  ];
in
pkgs.writeText "cnpg-cluster.yaml" manifest
