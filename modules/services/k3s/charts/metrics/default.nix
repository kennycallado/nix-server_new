# Metrics Stack (LGTM)
# Aggregates all observability charts: Prometheus, Loki, Tempo
{ serverToleration, exposeServices, domain, metricsConfig }:

{
  kube-prometheus-stack = import ./prom-stack.nix { inherit serverToleration exposeServices domain metricsConfig; };
  loki = import ./loki.nix { inherit serverToleration metricsConfig; };
  tempo = import ./tempo.nix { inherit serverToleration metricsConfig; };
}
