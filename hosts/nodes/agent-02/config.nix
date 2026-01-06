{
  hostname = "agent-02";
  system = "aarch64-linux";
  disk = "/dev/sda";

  deploy = {
    ip = "5.75.153.143"; # Set after creating server in Hetzner Console
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
    ip = "10.100.10.3";
    isServer = false;
  };
}
