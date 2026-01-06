{
  hostname = "agent-01";
  system = "aarch64-linux";
  disk = "/dev/sda";

  deploy = {
    ip = "46.224.152.241"; # Set after creating server in Hetzner Console
    sshUser = "admin";
    remoteBuild = true;
  };

  k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://server-01:6443"; # DNS via WireGuard
  };

  wireguard = {
    enable = true;
    ip = "10.100.10.2";
    isServer = false;
  };
}
