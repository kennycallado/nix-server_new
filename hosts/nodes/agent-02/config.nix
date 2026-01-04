{
  hostname = "agent-02";
  system = "aarch64-linux";
  disk = "/dev/sda";

  infra = {
    provider = "hetzner";
    type = "cax11";
    location = "nbg1";
  };

  deploy = {
    sshUser = "admin";
    remoteBuild = true;
  };

  k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://server-01:6443"; # Usa nombre DNS vía WireGuard
  };

  wireguard = {
    enable = true;
    ip = "10.100.10.3";
    isServer = false;
  };
}
