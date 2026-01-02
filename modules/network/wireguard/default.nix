{ config, lib, conf, hosts, ... }:
let
  hostname = conf.hostname;
  thisNode = hosts.nodes.${hostname};
  otherNodes = lib.filterAttrs (name: _: name != hostname) hosts.nodes;

  # Encuentra el servidor WireGuard
  serverNode = lib.findFirst
    (node: node.wg.isServer)
    (throw "No WireGuard server defined in hosts.nix")
    (lib.attrValues hosts.nodes);

  serverName = lib.findFirst
    (name: hosts.nodes.${name}.wg.isServer)
    (throw "No WireGuard server defined in hosts.nix")
    (lib.attrNames hosts.nodes);

  isServer = thisNode.wg.isServer;
  enabled = conf.wireguard.enable or false;
in
{
  imports = [
    (if isServer then ./server.nix else ./peer.nix)
  ];

  config = lib.mkIf enabled {
    # Secreto: clave privada WireGuard
    age.secrets.wireguard-private = {
      file = ../../../secrets/wireguard-${hostname}.age;
      mode = "0400";
    };

    # /etc/hosts con IPs de WireGuard para resolver nombres
    networking.hosts = lib.mapAttrs'
      (name: node:
        lib.nameValuePair node.ip.wg [ name ]
      )
      hosts.nodes;

    # Interfaz WireGuard
    networking.wireguard.interfaces.wg0 = {
      ips = [ "${thisNode.ip.wg}/24" ];
      listenPort = lib.mkIf isServer hosts.wireguard.port;
      privateKeyFile = config.age.secrets.wireguard-private.path;
    };

    # Firewall: permitir puerto WireGuard (solo server)
    networking.firewall.allowedUDPPorts = lib.mkIf isServer [ hosts.wireguard.port ];
  };

  # Exportar para uso en server.nix y peer.nix
  options.wireguard = {
    _hosts = lib.mkOption { default = hosts; };
    _thisNode = lib.mkOption { default = thisNode; };
    _otherNodes = lib.mkOption { default = otherNodes; };
    _serverNode = lib.mkOption { default = serverNode; };
    _serverName = lib.mkOption { default = serverName; };
    _isServer = lib.mkOption { default = isServer; };
    _enabled = lib.mkOption { default = enabled; };
  };
}
