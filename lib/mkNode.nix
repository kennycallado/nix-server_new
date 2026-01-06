# Node Factory - Generates NixOS and deploy-rs configurations from config.nix
#
# Usage:
#   mkNode = import ./lib/mkNode.nix;
#   node = mkNode {
#     inherit nixpkgs disko agenix deploy-rs;
#     configDir = ./hosts/nodes/server_01;
#     root = ./.;
#     hosts = import ./modules/network/hosts.nix;
#   };
#   # node.nixosConfig        - NixOS system configuration (full)
#   # node.nixosConfigMinimal - NixOS minimal configuration (bootstrap)
#   # node.deployNode         - deploy-rs node configuration
#
# Arguments:
#   nixpkgs   - nixpkgs input
#   disko     - disko input
#   agenix    - agenix input
#   deploy-rs - deploy-rs input
#   configDir - Path to node directory (containing config.nix)
#   root      - Project root path (for state.nix)
#   hosts     - Aggregated hosts data from modules/network/hosts.nix

{ nixpkgs, disko, agenix, deploy-rs, configDir, root, hosts }:
let
  # Import raw node configuration
  rawConf = import (configDir + "/config.nix");

  # Import state layer and merge with config
  state = import (root + "/lib/state.nix") { inherit root; };
  conf = state.mergeNode rawConf.hostname rawConf;

  # Import centralized constants
  constants = import ./constants.nix;

  # Hardware module selection based on architecture
  hardwareModule = {
    "aarch64-linux" = configDir + "/../../hardware/arm.nix";
    "x86_64-linux" = configDir + "/../../hardware/x86.nix";
  }.${conf.system} or (throw "Unsupported system architecture: ${conf.system}");

  # Base modules (always included)
  baseModules = [
    disko.nixosModules.disko
    agenix.nixosModules.default

    (import (configDir + "/../../hardware/disko.nix") { device = conf.disk; })
    hardwareModule

    (configDir + "/../../../modules/system")
    (configDir + "/../../../modules/network")

    (configDir + "/../../../modules/services/k3s")
    (configDir + "/../../../modules/services/openssh.nix")
  ];

  # Conditional modules based on config flags
  conditionalModules =
    if conf.nfs.enable or false then [ (configDir + "/../../../modules/services/nfs.nix") ] else [ ];

  # All modules combined (full configuration)
  allModules = baseModules ++ conditionalModules;

  # Minimal modules for bootstrap (Phase 1)
  # Only: disko + hardware + bootstrap minimal
  minimalModules = [
    disko.nixosModules.disko
    (import (configDir + "/../../hardware/disko.nix") { device = conf.disk; })
    hardwareModule
    (configDir + "/../../../modules/system/minimal.nix")

    # Inherit network identity from node config
    {
      networking.hostName = conf.hostname;
    }
  ];

  # Build NixOS configuration (full)
  nixosConfig = nixpkgs.lib.nixosSystem {
    inherit (conf) system;
    specialArgs = {
      inherit conf hosts constants;
    };
    modules = allModules;
  };

  # Build NixOS configuration (minimal for bootstrap)
  nixosConfigMinimal = nixpkgs.lib.nixosSystem {
    inherit (conf) system;
    specialArgs = {
      inherit conf;
    };
    modules = minimalModules;
  };

  # Build deploy-rs packages
  deployPkgs = import nixpkgs {
    inherit (conf) system;
    overlays = [ deploy-rs.overlays.default ];
  };

in
{
  inherit nixosConfig nixosConfigMinimal;

  deployNode = {
    hostname = conf.deploy.ip;
    sshOpts = [ "-t" "-oControlMaster=no" "-p" "22" ];

    magicRollback = false;
    autoRollback = true;
    remoteBuild = conf.deploy.remoteBuild or true;

    profiles.system = {
      inherit (conf.deploy) sshUser;
      user = "root";
      path = deployPkgs.deploy-rs.lib.activate.nixos nixosConfig;
    };
  };
}
