{ pkgs, nixos-anywhere, agenix }:
let
  system = pkgs.stdenv.hostPlatform.system;
  nixos-anywhere-pkg = nixos-anywhere.packages.${system}.default;
  agenix-pkg = agenix.packages.${system}.default;
  constants = import ./constants.nix;

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
      nix flake check --all-systems --impure
    '');
    meta.description = "Run flake checks";
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

  rekey = {
    type = "app";
    program = toString (wrapScript "rekey" ./scripts/rekey.sh [
      "AGENIX_BIN='${agenix-pkg}/bin/agenix'"
      "SCRIPT_BIN='${pkgs.util-linux}/bin/script'"
    ]);
    meta.description = "Re-encrypt all secrets with agenix";
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

  provision = {
    type = "app";
    program = toString (wrapScript "provision" ./scripts/provision.sh [
      "HCLOUD_BIN='${pkgs.hcloud}/bin/hcloud'"
      "JQ_BIN='${pkgs.jq}/bin/jq'"
      "AGE_BIN='${pkgs.age}/bin/age'"
    ]);
    meta.description = "Create Hetzner server and install NixOS";
  };

  seal = {
    type = "app";
    program = toString (wrapScript "seal" ./scripts/seal.sh [
      "KUBESEAL_BIN='${pkgs.kubeseal}/bin/kubeseal'"
    ]);
    meta.description = "Seal Kubernetes secrets with kubeseal";
  };

  status = {
    type = "app";
    program = toString (wrapScript "status" ./scripts/status.sh [
      "HCLOUD_BIN='${pkgs.hcloud}/bin/hcloud'"
      "JQ_BIN='${pkgs.jq}/bin/jq'"
    ]);
    meta.description = "Show cluster status (local vs Hetzner)";
  };

  agenix = {
    type = "app";
    program = "${agenix-pkg}/bin/agenix";
    meta.description = "Agenix CLI";
  };
}
