# ServiceMonitor for Windmill metrics
#
# Windmill exposes Prometheus metrics on port 8001 when METRICS_ADDR is configured.
# This ServiceMonitor enables Prometheus to scrape those metrics.
#
{ pkgs, lib ? pkgs.lib }:

let
  serviceMonitor = ''
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: windmill
      namespace: windmill
      labels:
        app.kubernetes.io/name: windmill
    spec:
      selector:
        matchLabels:
          operated-prometheus: "true"
      namespaceSelector:
        matchNames:
          - windmill
      endpoints:
        - port: metrics
          path: /metrics
          interval: 30s
          scrapeTimeout: 10s
  '';
in
pkgs.writeText "windmill-servicemonitor.yaml" serviceMonitor
