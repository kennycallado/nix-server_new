{ config, lib, conf, hosts, ... }:
{
  config = lib.mkIf (conf.nfs.enable or false) {
    # Crear directorio NFS
    systemd.tmpfiles.rules = [
      "d /srv/nfs 0755 root root -"
    ];

    # Servidor NFS
    services.nfs.server = {
      enable = true;
      exports = ''
        /srv/nfs  ${hosts.wireguard.network}(rw,sync,no_subtree_check,no_root_squash)
      '';
      # Usar puertos fijos para lockd y mountd
      lockdPort = 4001;
      mountdPort = 4002;
      statdPort = 4000;
    };

    # Firewall - abrir puertos NFS para red WireGuard
    # 2049: nfs, 111: portmapper, 4000-4002: statd/lockd/mountd
    networking.firewall.allowedTCPPorts = [ 111 2049 4000 4001 4002 ];
    networking.firewall.allowedUDPPorts = [ 111 2049 4000 4001 4002 ];
  };
}
