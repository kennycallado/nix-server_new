{
  hostname = "server-01";
  system = "aarch64-linux";
  disk = "/dev/sda";

  infra = {
    provider = "hetzner";
    type = "cax21";
    location = "nbg1";
  };

  deploy = {
    sshUser = "admin";
    remoteBuild = true;
  };

  k3s = {
    enable = true;
    role = "server";
    serverAddr = ""; # Primer server - inicia el cluster
  };

  wireguard = {
    enable = true;
    ip = "10.100.10.1";
    isServer = true;
  };

  nfs.enable = true;
}
