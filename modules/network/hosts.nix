# Auto-descubrimiento de nodos desde hosts/nodes/*/config.nix
# Cada config.nix es la fuente de verdad de su propio nodo
let
  nodesDir = ../../hosts/nodes;

  # Usar lib/discover.nix para descubrir nodos
  discover = import ../../lib/discover.nix;
  nodeNames = discover nodesDir;

  # Importar configs
  nodeConfigs = builtins.listToAttrs (map
    (name: {
      inherit name;
      value = import (nodesDir + "/${name}/config.nix");
    })
    nodeNames);

  # Validar un nodo
  validate = name: cfg:
    let
      check = cond: msg: if !cond then throw "Node '${name}': ${msg}" else true;
    in
    check (cfg ? hostname) "missing 'hostname'" &&
    check (cfg.hostname == name) "hostname '${cfg.hostname}' doesn't match directory" &&
    check (cfg ? deploy.ip) "missing 'deploy.ip'" &&
    check (cfg ? wireguard.enable) "missing 'wireguard.enable'" &&
    (if cfg.wireguard.enable then
      check (cfg ? wireguard.ip) "missing 'wireguard.ip'" &&
      check (cfg ? wireguard.publicKey) "missing 'wireguard.publicKey'" &&
      check (cfg ? wireguard.isServer) "missing 'wireguard.isServer'"
    else true);

  # Validar todos
  allValid = builtins.all (name: validate name nodeConfigs.${name}) nodeNames;

  # Construir estructura de nodos (solo con WireGuard habilitado)
  nodes = assert allValid; builtins.listToAttrs (
    builtins.filter (x: x != null) (map
      (name:
        let cfg = nodeConfigs.${name}; in
        if cfg.wireguard.enable or false then {
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

  # Find the WireGuard server node
  # Returns: node name (string) where wg.isServer == true
  # Throws: if no server found
  findWgServer =
    let
      servers = builtins.filter
        (name: nodes.${name}.wg.isServer or false)
        (builtins.attrNames nodes);
    in
    if builtins.length servers == 0
    then throw "No WireGuard server found in nodes"
    else builtins.head servers;

  # Find the NFS server node
  # Returns: node name (string) where nfs.enable == true in config.nix
  # Falls back to WireGuard server if no NFS server configured
  findNfsServer =
    let
      nfsServers = builtins.filter
        (name: nodeConfigs.${name}.nfs.enable or false)
        nodeNames;
    in
    if builtins.length nfsServers == 0
    then findWgServer  # Fallback to WG server
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
