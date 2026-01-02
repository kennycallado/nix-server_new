{ conf, ... }:

{
  imports = [
    ./wireguard
  ];

  networking.hostName = conf.hostname;
  networking.firewall.enable = true;
}
