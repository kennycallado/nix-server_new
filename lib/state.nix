# State Layer - Merges node definitions with dynamic state
#
# This module implements the "3-layer architecture":
#   Layer 1: Definition (hosts/nodes/*/config.nix) - What we want
#   Layer 2: Providers (modules/providers/*.nix) - Catalog of options
#   Layer 3: State (hosts/state/*.json) - What exists
#
# Usage:
#   state = import ./lib/state.nix { inherit root; };
#   mergedConfig = state.mergeNode "server_01" rawConfig;
#
# Arguments:
#   root - Path to project root (for resolving state files)

{ root }:
let
  # ===== Layer 3: Read State Files =====

  # Read and parse JSON state files
  nodesStatePath = root + "/hosts/state/nodes.json";
  wireguardStatePath = root + "/hosts/state/wireguard.json";

  nodesState =
    if builtins.pathExists nodesStatePath
    then builtins.fromJSON (builtins.readFile nodesStatePath)
    else { };

  wireguardState =
    if builtins.pathExists wireguardStatePath
    then builtins.fromJSON (builtins.readFile wireguardStatePath)
    else { };

  # ===== Layer 2: Load Provider Catalogs =====

  providersDir = root + "/modules/providers";

  providers = {
    hetzner =
      if builtins.pathExists (providersDir + "/hetzner.nix")
      then import (providersDir + "/hetzner.nix")
      else null;
    manual =
      if builtins.pathExists (providersDir + "/manual.nix")
      then import (providersDir + "/manual.nix")
      else null;
  };

  # ===== Validation Helpers =====

  # Validate that a type exists in the provider catalog
  validateType = provider: type:
    let
      catalog = providers.${provider} or null;
    in
    if catalog == null then
      throw "Unknown provider '${provider}'"
    else if catalog.types == { } then
      true  # Manual provider has no types (anything goes)
    else if catalog.types ? ${type} then
      true
    else
      throw "Unknown type '${type}' for provider '${provider}'. Available: ${builtins.concatStringsSep ", " (builtins.attrNames catalog.types)}";

  # Validate that a location exists in the provider catalog  
  validateLocation = provider: location:
    let
      catalog = providers.${provider} or null;
    in
    if catalog == null then
      throw "Unknown provider '${provider}'"
    else if catalog.locations == { } then
      true  # Manual provider has no locations
    else if catalog.locations ? ${location} then
      true
    else
      throw "Unknown location '${location}' for provider '${provider}'. Available: ${builtins.concatStringsSep ", " (builtins.attrNames catalog.locations)}";

  # ===== Core Merge Function =====

  # Merge a node's config.nix with state data
  # Returns the config with deploy.ip and wireguard.publicKey injected from state
  mergeNode = name: config:
    let
      nodeState = nodesState.${name} or null;
      wgState = wireguardState.${name} or null;

      # Get IP from state, fallback to config (for backwards compatibility during migration)
      deployIp =
        if nodeState != null && nodeState ? public_ip && nodeState.public_ip != null
        then nodeState.public_ip
        else config.deploy.ip or null;

      # Get WireGuard public key from state, fallback to config
      wgPublicKey =
        if wgState != null && wgState ? public_key && wgState.public_key != null
        then wgState.public_key
        else config.wireguard.publicKey or null;

      # Validate infra specs if present
      _ =
        if config ? infra && config.infra ? provider then
          let
            provider = config.infra.provider;
            type = config.infra.type or (providers.${provider}.defaults.type or null);
            location = config.infra.location or (providers.${provider}.defaults.location or null);
          in
          (if type != null then validateType provider type else true) &&
          (if location != null then validateLocation provider location else true)
        else true;

    in
    config // {
      deploy = (config.deploy or { }) // {
        ip = deployIp;
      };
      wireguard = (config.wireguard or { }) // {
        publicKey = wgPublicKey;
      };
      # Add resolved state metadata (useful for scripts)
      _state = {
        provider_id = nodeState.provider_id or null;
        status = nodeState.status or "unknown";
        type = nodeState.type or (config.infra.type or null);
        location = nodeState.location or (config.infra.location or null);
      };
    };

  # ===== Bulk Operations =====

  # Merge all nodes at once
  # Input: attrset of { nodeName = config; }
  # Output: attrset of { nodeName = mergedConfig; }
  mergeAllNodes = configs:
    builtins.mapAttrs mergeNode configs;

  # Get state for a specific node (raw, without merge)
  getNodeState = name: {
    node = nodesState.${name} or null;
    wireguard = wireguardState.${name} or null;
  };

  # Check if a node has state (is provisioned)
  hasState = name:
    nodesState ? ${name} && nodesState.${name}.public_ip != null;

in
{
  # Core exports
  inherit mergeNode mergeAllNodes;

  # State accessors
  inherit nodesState wireguardState getNodeState hasState;

  # Provider catalog
  inherit providers;

  # Validation utilities (for use in scripts)
  inherit validateType validateLocation;
}
