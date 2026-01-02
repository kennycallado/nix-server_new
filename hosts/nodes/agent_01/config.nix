{
  hostname = "agent_01";
  system = "aarch64-linux";
  disk = "/dev/sda";

  deploy = {
    ip = "5.75.153.143";
    sshUser = "admin";
    remoteBuild = true;
  };

  k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://server_01:6443"; # Usa nombre DNS vía WireGuard
  };

  wireguard = {
    enable = true;
    ip = "10.100.10.2";
    publicKey = "FfZMZrwyycV/o56g/e9cB4PgU8YqeYwG5G5NItr+Ij0=";
    isServer = false;
  };
}
