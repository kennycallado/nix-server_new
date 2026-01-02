# Garage WebUI - Admin interface for Garage S3 storage
#
# Provides:
# - Cluster health status
# - Layout management
# - Bucket management and browser
# - Access key management
#
# https://github.com/khairul169/garage-webui
#
{ pkgs, lib ? pkgs.lib, garageWebuiConfig }:

let
  # Deployment
  deployment = ''
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: garage-webui
      namespace: garage
      labels:
        app.kubernetes.io/name: garage-webui
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: garage-webui
      template:
        metadata:
          labels:
            app.kubernetes.io/name: garage-webui
        spec:
          # Corre en control-plane (tolera el taint)
          tolerations:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
              effect: NoSchedule
          containers:
            - name: garage-webui
              image: khairul169/garage-webui:${garageWebuiConfig.version}
              imagePullPolicy: IfNotPresent
              ports:
                - name: http
                  containerPort: 3909
              env:
                # Garage Admin API endpoint (internal service)
                - name: API_BASE_URL
                  value: "http://garage.garage.svc.cluster.local:3903"
                # Garage S3 API endpoint (internal service)
                - name: S3_ENDPOINT_URL
                  value: "http://garage.garage.svc.cluster.local:3900"
                # S3 Region (must match garage config)
                - name: S3_REGION
                  value: "${garageWebuiConfig.s3Region}"
                # Admin token (from SealedSecret garage-secrets)
                - name: API_ADMIN_KEY
                  valueFrom:
                    secretKeyRef:
                      name: garage-secrets
                      key: admin-token
                ${lib.optionalString (garageWebuiConfig.authUserPass != "") ''
                # Basic auth (format: username:bcrypt_hash)
                - name: AUTH_USER_PASS
                  value: "${garageWebuiConfig.authUserPass}"
                ''}
              resources:
                requests:
                  cpu: "50m"
                  memory: "64Mi"
                limits:
                  cpu: "200m"
                  memory: "128Mi"
              livenessProbe:
                httpGet:
                  path: /
                  port: http
                initialDelaySeconds: 10
                periodSeconds: 30
              readinessProbe:
                httpGet:
                  path: /
                  port: http
                initialDelaySeconds: 5
                periodSeconds: 10
  '';

  # Service con NodePort para acceso externo
  service = ''
    apiVersion: v1
    kind: Service
    metadata:
      name: garage-webui
      namespace: garage
      labels:
        app.kubernetes.io/name: garage-webui
    spec:
      type: NodePort
      selector:
        app.kubernetes.io/name: garage-webui
      ports:
        - name: http
          port: 3909
          targetPort: 3909
          nodePort: 32009
  '';

  manifest = lib.concatStringsSep "\n---\n" [
    deployment
    service
  ];
in
pkgs.writeText "garage-webui.yaml" manifest
