# ArgoCD IngressRoute - Traefik CRD for proper HTTP backend routing
#
# Using IngressRoute instead of standard Ingress because:
# - Traefik ignores serversscheme annotation on Ingress resources
# - IngressRoute allows explicit scheme control for backend connections
# - Supports gRPC (h2c) for ArgoCD CLI access
#
{ pkgs, lib ? pkgs.lib, domain }:

let
  argocdHost = "argocd.${domain}";

  # IngressRoute for ArgoCD web UI and API
  ingressRoute = ''
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: argocd-server
      namespace: argocd
      labels:
        app.kubernetes.io/name: argocd-server
        app.kubernetes.io/component: server
    spec:
      entryPoints:
        - websecure
      routes:
        # HTTP/HTTPS traffic (web UI and REST API)
        - kind: Rule
          match: Host(`${argocdHost}`)
          priority: 10
          services:
            - name: argocd-server
              port: 80
              scheme: http
        # gRPC traffic (ArgoCD CLI)
        - kind: Rule
          match: Host(`${argocdHost}`) && Header(`Content-Type`, `application/grpc`)
          priority: 11
          services:
            - name: argocd-server
              port: 80
              scheme: h2c
      tls:
        secretName: argocd-server-tls
  '';

  # Certificate for ArgoCD using cert-manager
  certificate = ''
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: argocd-server-tls
      namespace: argocd
    spec:
      secretName: argocd-server-tls
      issuerRef:
        name: letsencrypt-prod
        kind: ClusterIssuer
      dnsNames:
        - ${argocdHost}
  '';

  manifest = lib.concatStringsSep "\n---\n" [
    ingressRoute
    certificate
  ];
in
pkgs.writeText "argocd-ingress.yaml" manifest
