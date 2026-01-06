# Metrics Stack (LGTM + OTEL)
# Aggregates all observability charts: Prometheus, Loki, Tempo, OTEL Collector
{ serverToleration, exposeServices, domain, metricsConfig }:

{
  kube-prometheus-stack = import ./prom-stack.nix { inherit serverToleration exposeServices domain metricsConfig; };
  loki = import ./loki.nix { inherit serverToleration metricsConfig; };
  tempo = import ./tempo.nix { inherit serverToleration metricsConfig; };
  otel-collector = import ./otel-collector.nix { inherit serverToleration; };
}
