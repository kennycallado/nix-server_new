# ClusterIssuer for cert-manager using Let's Encrypt
{ pkgs, lib ? pkgs.lib, email ? "admin@kennycallado.dev" }:

let
  # Let's Encrypt Production Issuer
  letsencrypt-prod = ''
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: ${email}
        privateKeySecretRef:
          name: letsencrypt-prod-account-key
        solvers:
        - http01:
            ingress:
              class: traefik-ingress
              podTemplate:
                spec:
                  nodeSelector:
                    node-role.kubernetes.io/control-plane: "true"
                  tolerations:
                  - key: node-role.kubernetes.io/control-plane
                    operator: Exists
                    effect: NoSchedule
  '';

  # Let's Encrypt Staging Issuer (useful for testing to avoid rate limits)
  letsencrypt-staging = ''
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-staging
    spec:
      acme:
        server: https://acme-staging-v02.api.letsencrypt.org/directory
        email: ${email}
        privateKeySecretRef:
          name: letsencrypt-staging-account-key
        solvers:
        - http01:
            ingress:
              class: traefik-ingress
              podTemplate:
                spec:
                  nodeSelector:
                    node-role.kubernetes.io/control-plane: "true"
                  tolerations:
                  - key: node-role.kubernetes.io/control-plane
                    operator: Exists
                    effect: NoSchedule
  '';

  manifest = lib.concatStringsSep "\n---\n" [
    letsencrypt-prod
    letsencrypt-staging
  ];
in
pkgs.writeText "cluster-issuer.yaml" manifest
