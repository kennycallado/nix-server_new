# Auto-discovery of nodes from hosts/nodes/*/config.nix
# Each config.nix is the source of truth for its node
# WireGuard public keys are injected from hosts/state/wireguard.json via lib/state.nix
let
  root = ../../.;
  nodesDir = root + "/hosts/nodes";

  # Use lib/discover.nix to discover nodes
  discover = import ../../lib/discover.nix;
  nodeNames = discover nodesDir;

  # Import state layer for merging
  state = import ../../lib/state.nix { inherit root; };

  # Import and merge configs with state
  nodeConfigs = builtins.listToAttrs (map
    (name:
      let
        rawConf = import (nodesDir + "/${name}/config.nix");
      in
      {
        inherit name;
        value = state.mergeNode name rawConf;
      })
    nodeNames);

  # Check if a node has all required WireGuard config (including publicKey from keygen)
  isWgReady = name: cfg:
    cfg.wireguard.enable or false &&
    cfg ? wireguard.ip &&
    cfg ? wireguard.isServer &&
    (cfg.wireguard.publicKey or null) != null;

  # Validate basic node configuration (doesn't require publicKey)
  validate = name: cfg:
    let
      check = cond: msg: if !cond then throw "Node '${name}': ${msg}" else true;
    in
    check (cfg ? hostname) "missing 'hostname'" &&
    check (cfg.hostname == name) "hostname '${cfg.hostname}' doesn't match directory" &&
    check (cfg ? wireguard.enable) "missing 'wireguard.enable'" &&
    (if cfg.wireguard.enable then
      check (cfg ? wireguard.ip) "missing 'wireguard.ip'" &&
      check (cfg ? wireguard.isServer) "missing 'wireguard.isServer'"
    else true);

  # Validate all nodes (basic validation)
  allValid = builtins.all (name: validate name nodeConfigs.${name}) nodeNames;

  # Build nodes structure (only nodes with WireGuard ready - has publicKey)
  nodes = assert allValid; builtins.listToAttrs (
    builtins.filter (x: x != null) (map
      (name:
        let cfg = nodeConfigs.${name}; in
        # Only include if WireGuard is ready (has publicKey from keygen)
        if isWgReady name cfg then {
          inherit name;
          value = {
            ip.public = cfg.deploy.ip;
            ip.wg = cfg.wireguard.ip;
            wg.publicKey = cfg.wireguard.publicKey;
            wg.isServer = cfg.wireguard.isServer;
          };
        } else null
      )
      nodeNames)
  );

  # ===== Dynamic Server Resolvers =====

  # Find the WireGuard server node (only among ready nodes)
  findWgServer =
    let
      servers = builtins.filter
        (name: nodes.${name}.wg.isServer or false)
        (builtins.attrNames nodes);
    in
    if builtins.length servers == 0
    then null # Return null instead of throwing - no server ready yet
    else builtins.head servers;

  # Find the NFS server node (only among ready nodes in hosts.nodes)
  findNfsServer =
    let
      readyNodeNames = builtins.attrNames nodes;
      nfsServers = builtins.filter
        (name: nodeConfigs.${name}.nfs.enable or false)
        readyNodeNames;
    in
    if builtins.length nfsServers == 0
    then findWgServer # Fallback to WG server (could be null)
    else builtins.head nfsServers;

in
{
  wireguard = {
    network = "10.100.10.0/24";
    port = 51820;
  };

  inherit nodes;

  # External clients (no config.nix, manually defined)
  clients = {
    ryzen = {
      ip.wg = "10.100.10.100";
      wg.publicKey = "QUAsyA1ieF4GavRU0l+E+Z1i+x/TIgJ3frZLg9bh0UY=";
    };
  };

  # Dynamic server resolvers
  inherit findWgServer findNfsServer;
}
