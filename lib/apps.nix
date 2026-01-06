{ pkgs, nixos-anywhere, agenix }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  nixos-anywhere-pkg = nixos-anywhere.packages.${system}.default;
  agenix-pkg = agenix.packages.${system}.default;
  constants = import ./constants.nix;

  # Importar configuración de server-01 para obtener la IP del túnel
  server01Config = import ../hosts/nodes/server-01/config.nix;

  # Wrapper que inyecta las dependencias en el script
  wrapScript = name: script: vars:
    pkgs.writeShellScript name ''
      ${builtins.concatStringsSep "\n" (map (v: "export ${v}") vars)}
      source ${script}
    '';
in
{
  check = {
    type = "app";
    program = toString (pkgs.writeShellScript "check" ''
      ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check . && nix flake check --no-build "$@"
    '');
    meta.description = "Check formatting and validate flake";
  };

  keygen = {
    type = "app";
    program = toString (wrapScript "keygen" ./scripts/keygen.sh [
      "ADMIN_SSH_KEY='${constants.admin.sshKey}'"
      "AGE_BIN='${pkgs.age}/bin/age'"
      "SSH_KEYGEN_BIN='${pkgs.openssh}/bin/ssh-keygen'"
      "AGENIX_BIN='${agenix-pkg}/bin/agenix'"
      "SCRIPT_BIN='${pkgs.util-linux}/bin/script'"
      "WG_BIN='${pkgs.wireguard-tools}/bin/wg'"
      "JQ_BIN='${pkgs.jq}/bin/jq'"
    ]);
    meta.description = "Generate SSH and WireGuard keys for a host";
  };

  install = {
    type = "app";
    program = toString (wrapScript "install" ./scripts/install.sh [
      "AGE_BIN='${pkgs.age}/bin/age'"
      "NIXOS_ANYWHERE_BIN='${nixos-anywhere-pkg}/bin/nixos-anywhere'"
      "JQ_BIN='${pkgs.jq}/bin/jq'"
    ]);
    meta.description = "Install NixOS on a remote host";
  };

  install-minimal = {
    type = "app";
    program = toString (wrapScript "install-minimal" ./scripts/install-minimal.sh [
      "AGE_BIN='${pkgs.age}/bin/age'"
      "NIXOS_ANYWHERE_BIN='${nixos-anywhere-pkg}/bin/nixos-anywhere'"
      "JQ_BIN='${pkgs.jq}/bin/jq'"
    ]);
    meta.description = "Install minimal NixOS for bootstrap (Phase 1)";
  };

  deploy = {
    type = "app";
    program = toString (wrapScript "deploy" ./scripts/deploy.sh [
      "JQ_BIN='${pkgs.jq}/bin/jq'"
    ]);
    meta.description = "Deploy configuration with remote build (Phase 2)";
  };

  seal = {
    type = "app";
    program = toString (wrapScript "seal" ./scripts/seal.sh [
      "KUBESEAL_BIN='${pkgs.kubeseal}/bin/kubeseal'"
    ]);
    meta.description = "Seal Kubernetes secrets with kubeseal";
  };

  tunnel = {
    type = "app";
    program = toString (pkgs.writeShellScript "tunnel" ''
      export SERVER_IP="${server01Config.deploy.ip}"
      source ${./scripts/tunnel.sh}
    '');
    meta.description = "SSH tunnel to access K8s services locally";
  };

  agenix = {
    type = "app";
    program = "${agenix-pkg}/bin/agenix";
    meta.description = "Agenix CLI";
  };
}
