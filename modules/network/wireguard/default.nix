{ config, lib, conf, hosts, ... }:
let
  inherit (conf) hostname;
  enabled = conf.wireguard.enable or false;

  # Check if this node is ready (has publicKey in hosts.nodes)
  nodeReady = hosts.nodes ? ${hostname};

  # Get this node and others from hosts (only if ready)
  thisNode = if nodeReady then hosts.nodes.${hostname} else null;
  otherNodes = if nodeReady then lib.filterAttrs (name: _: name != hostname) hosts.nodes else { };

  # Find WireGuard server (only among ready nodes)
  serverNode =
    if hosts.nodes != { }
    then lib.findFirst (node: node.wg.isServer) null (lib.attrValues hosts.nodes)
    else null;
  serverName =
    if hosts.nodes != { }
    then lib.findFirst (name: hosts.nodes.${name}.wg.isServer) null (lib.attrNames hosts.nodes)
    else null;

  isServer = if thisNode != null then thisNode.wg.isServer else false;

  # Only actually enable if node is ready (has publicKey)
  actuallyEnabled = enabled && nodeReady;
in
{
  imports = lib.optionals actuallyEnabled [
    (if isServer then ./server.nix else ./peer.nix)
  ];

  config = lib.mkIf actuallyEnabled {
    # Secret: WireGuard private key
    age.secrets.wireguard-private = {
      file = ../../../secrets/wireguard-${hostname}.age;
      mode = "0400";
    };

    # DNS: resolve hostnames via WireGuard IPs
    networking.hosts = lib.mapAttrs' (name: node: lib.nameValuePair node.ip.wg [ name ]) hosts.nodes;

    # WireGuard interface
    networking.wireguard.interfaces.wg0 = {
      ips = [ "${thisNode.ip.wg}/24" ];
      listenPort = lib.mkIf isServer hosts.wireguard.port;
      privateKeyFile = config.age.secrets.wireguard-private.path;
    };

    # Firewall: allow WireGuard port (server only)
    networking.firewall.allowedUDPPorts = lib.mkIf isServer [ hosts.wireguard.port ];
  };

  # Export for use in server.nix and peer.nix
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
