{ config, lib, conf, hosts, ... }:
let
  inherit (conf) hostname;
  enabled = conf.wireguard.enable or false;

  # Solo buscar este nodo si está en hosts.nodes (provisionado)
  nodeExists = hosts.nodes ? ${hostname};
  thisNode = if nodeExists then hosts.nodes.${hostname} else null;
  otherNodes = if nodeExists then lib.filterAttrs (name: _: name != hostname) hosts.nodes else { };

  # Encuentra el servidor WireGuard (solo si hay nodos)
  hasNodes = hosts.nodes != { };
  serverNode =
    if hasNodes then lib.findFirst (node: node.wg.isServer) null (lib.attrValues hosts.nodes) else null;

  serverName =
    if hasNodes then
      lib.findFirst (name: hosts.nodes.${name}.wg.isServer) null (lib.attrNames hosts.nodes)
    else
      null;

  isServer = if thisNode != null then thisNode.wg.isServer else false;

  # Solo habilitar si el nodo existe en hosts (provisionado) y wireguard enabled
  actuallyEnabled = enabled && nodeExists;
in
{
  imports = lib.optionals (actuallyEnabled && thisNode != null) [
    (if isServer then ./server.nix else ./peer.nix)
  ];

  config = lib.mkIf actuallyEnabled {
    # Secreto: clave privada WireGuard
    age.secrets.wireguard-private = {
      file = ../../../secrets/wireguard-${hostname}.age;
      mode = "0400";
    };

    # /etc/hosts con IPs de WireGuard para resolver nombres
    networking.hosts = lib.mapAttrs' (name: node: lib.nameValuePair node.ip.wg [ name ]) hosts.nodes;

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
    _enabled = lib.mkOption { default = actuallyEnabled; };
  };
}
