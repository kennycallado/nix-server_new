{ config, lib, ... }:
let
  inherit (config.wireguard) _hosts _serverNode _serverName _enabled;
in
{
  config = lib.mkIf _enabled {
    networking.wireguard.interfaces.wg0 = {
      # El peer solo conecta al server
      peers = [{
        inherit (_serverNode.wg) publicKey;
        # Permitir todo el tráfico de la red WireGuard a través del server
        allowedIPs = [ _hosts.wireguard.network ];
        # Endpoint del server (IP pública + puerto)
        endpoint = "${_serverNode.ip.public}:${toString _hosts.wireguard.port}";
        # Keepalive para mantener conexión a través de NAT
        persistentKeepalive = 25;
      }];
    };
  };
}
