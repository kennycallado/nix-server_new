{ config, lib, ... }:
let
  inherit (config.wireguard) _hosts _otherNodes _enabled;

  # Peers de nodos del cluster
  nodePeers = lib.mapAttrsToList
    (name: node: {
      publicKey = node.wg.publicKey;
      allowedIPs = [ "${node.ip.wg}/32" ];
      persistentKeepalive = 25;
    })
    _otherNodes;

  # Peers de clientes externos
  clientPeers = lib.mapAttrsToList
    (name: client: {
      publicKey = client.wg.publicKey;
      allowedIPs = [ "${client.ip.wg}/32" ];
      persistentKeepalive = 25;
    })
    (_hosts.clients or { });
in
{
  config = lib.mkIf _enabled {
    networking.wireguard.interfaces.wg0 = {
      # El server define todos los peers (agents + clientes externos)
      peers = nodePeers ++ clientPeers;
    };
  };
}
