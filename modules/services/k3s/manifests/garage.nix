# Garage - S3-compatible distributed object storage
#
# Garage is designed for small self-hosted geo-distributed deployments.
# With replication_factor = 2, it works perfectly with 2 worker nodes.
#
# Post-deployment setup required:
#   kubectl exec -n garage garage-0 -- /garage status
#   kubectl exec -n garage garage-0 -- /garage layout assign <node_id> -z dc1 -c 10G
#   kubectl exec -n garage garage-0 -- /garage layout apply --version 1
#
{ pkgs, lib ? pkgs.lib, garageConfig }:

let
  # Namespace
  namespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: garage
  '';

  # ConfigMap con garage.toml template (se procesa con initContainer solo para POD_IP)
  # Los secrets se inyectan via env vars nativas de Garage (GARAGE_RPC_SECRET, etc.)
  configMap = ''
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: garage-config
      namespace: garage
    data:
      garage.toml.template: |
        metadata_dir = "/var/lib/garage/meta"
        data_dir = "/var/lib/garage/data"
        db_engine = "lmdb"

        replication_factor = ${toString garageConfig.replicationFactor}

        rpc_bind_addr = "[::]:3901"
        rpc_public_addr = "__MY_POD_IP__:3901"

        [s3_api]
        s3_region = "${garageConfig.s3Region}"
        api_bind_addr = "[::]:3900"
        root_domain = ".s3.garage.local"

        [s3_web]
        bind_addr = "[::]:3902"
        root_domain = ".web.garage.local"
        index = "index.html"

        [admin]
        api_bind_addr = "[::]:3903"

        [kubernetes_discovery]
        namespace = "garage"
        service_name = "garage"
        skip_crd = true
  '';

  # Service headless para StatefulSet y descubrimiento
  serviceHeadless = ''
    apiVersion: v1
    kind: Service
    metadata:
      name: garage
      namespace: garage
      labels:
        app.kubernetes.io/name: garage
    spec:
      clusterIP: None
      selector:
        app.kubernetes.io/name: garage
      ports:
        - name: s3-api
          port: 3900
          targetPort: 3900
        - name: rpc
          port: 3901
          targetPort: 3901
        - name: web
          port: 3902
          targetPort: 3902
        - name: admin
          port: 3903
          targetPort: 3903
  '';

  # Service con NodePort para acceso externo
  serviceNodePort = ''
    apiVersion: v1
    kind: Service
    metadata:
      name: garage-external
      namespace: garage
      labels:
        app.kubernetes.io/name: garage
    spec:
      type: NodePort
      selector:
        app.kubernetes.io/name: garage
      ports:
        - name: s3-api
          port: 3900
          targetPort: 3900
          nodePort: 32000
        - name: admin
          port: 3903
          targetPort: 3903
          nodePort: 32003
  '';

  # ServiceAccount
  serviceAccount = ''
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: garage
      namespace: garage
  '';

  # ClusterRole para kubernetes_discovery
  clusterRole = ''
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: garage
    rules:
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["get", "watch", "list"]
      - apiGroups: ["deuxfleurs.fr"]
        resources: ["garagenodes"]
        verbs: ["get", "watch", "list", "create", "update", "patch", "delete"]
  '';

  # ClusterRoleBinding
  clusterRoleBinding = ''
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: garage
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: garage
    subjects:
      - kind: ServiceAccount
        name: garage
        namespace: garage
  '';

  # CRD para GarageNodes (kubernetes_discovery)
  garageNodeCRD = ''
    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: garagenodes.deuxfleurs.fr
    spec:
      group: deuxfleurs.fr
      names:
        kind: GarageNode
        listKind: GarageNodeList
        plural: garagenodes
        singular: garagenode
        shortNames:
          - gn
      scope: Namespaced
      versions:
        - name: v1
          served: true
          storage: true
          schema:
            openAPIV3Schema:
              type: object
              properties:
                spec:
                  type: object
                  x-kubernetes-preserve-unknown-fields: true
                status:
                  type: object
                  x-kubernetes-preserve-unknown-fields: true
  '';

  # StatefulSet
  statefulSet = ''
    apiVersion: apps/v1
    kind: StatefulSet
    metadata:
      name: garage
      namespace: garage
      labels:
        app.kubernetes.io/name: garage
    spec:
      serviceName: garage
      replicas: ${toString garageConfig.replicas}
      podManagementPolicy: Parallel
      selector:
        matchLabels:
          app.kubernetes.io/name: garage
      template:
        metadata:
          labels:
            app.kubernetes.io/name: garage
        spec:
          serviceAccountName: garage
          terminationGracePeriodSeconds: 30
          # Solo en workers, no en control-plane
          affinity:
            nodeAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                nodeSelectorTerms:
                  - matchExpressions:
                      - key: node-role.kubernetes.io/control-plane
                        operator: DoesNotExist
            # Distribuir pods entre nodos
            podAntiAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                - labelSelector:
                    matchLabels:
                      app.kubernetes.io/name: garage
                  topologyKey: kubernetes.io/hostname
          initContainers:
            - name: init-config
              image: busybox:1.36
              command:
                - sh
                - -c
                - |
                  sed "s/__MY_POD_IP__/$MY_POD_IP/g" /config-template/garage.toml.template > /config/garage.toml
              env:
                - name: MY_POD_IP
                  valueFrom:
                    fieldRef:
                      fieldPath: status.podIP
              volumeMounts:
                - name: config-template
                  mountPath: /config-template
                - name: config
                  mountPath: /config
          containers:
            - name: garage
              image: dxflrs/arm64_garage:${garageConfig.version}
              imagePullPolicy: IfNotPresent
              env:
                - name: RUST_LOG
                  value: "garage=info"
                # Secrets via Garage native env vars (from SealedSecret)
                - name: GARAGE_RPC_SECRET
                  valueFrom:
                    secretKeyRef:
                      name: garage-secrets
                      key: rpc-secret
                - name: GARAGE_ADMIN_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: garage-secrets
                      key: admin-token
                - name: GARAGE_METRICS_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: garage-secrets
                      key: metrics-token
              ports:
                - name: s3-api
                  containerPort: 3900
                - name: rpc
                  containerPort: 3901
                - name: web
                  containerPort: 3902
                - name: admin
                  containerPort: 3903
              volumeMounts:
                - name: config
                  mountPath: /etc/garage.toml
                  subPath: garage.toml
                - name: meta
                  mountPath: /var/lib/garage/meta
                - name: data
                  mountPath: /var/lib/garage/data
              resources:
                requests:
                  cpu: "100m"
                  memory: "256Mi"
                limits:
                  cpu: "500m"
                  memory: "512Mi"
              livenessProbe:
                httpGet:
                  path: /health
                  port: admin
                initialDelaySeconds: 30
                periodSeconds: 10
              readinessProbe:
                httpGet:
                  path: /health
                  port: admin
                initialDelaySeconds: 10
                periodSeconds: 5
          volumes:
            - name: config-template
              configMap:
                name: garage-config
            - name: config
              emptyDir: {}
      volumeClaimTemplates:
        - metadata:
            name: meta
          spec:
            accessModes: ["ReadWriteOnce"]
            storageClassName: local-path
            resources:
              requests:
                storage: ${garageConfig.metaStorageSize}
        - metadata:
            name: data
          spec:
            accessModes: ["ReadWriteOnce"]
            storageClassName: local-path
            resources:
              requests:
                storage: ${garageConfig.dataStorageSize}
  '';

  # ServiceMonitor for Prometheus (metrics on port 3903 with bearer token)
  serviceMonitor = ''
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: garage
      namespace: garage
      labels:
        app.kubernetes.io/name: garage
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: garage
      endpoints:
        - port: admin
          path: /metrics
          interval: 30s
          scrapeTimeout: 10s
          bearerTokenSecret:
            name: garage-secrets
            key: metrics-token
  '';

  manifest = lib.concatStringsSep "\n---\n" [
    namespace
    garageNodeCRD
    serviceAccount
    clusterRole
    clusterRoleBinding
    configMap
    serviceHeadless
    serviceNodePort
    statefulSet
    serviceMonitor
  ];
in
pkgs.writeText "garage.yaml" manifest
