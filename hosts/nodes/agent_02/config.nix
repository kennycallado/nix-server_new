{
  hostname = "agent_02";
  system = "aarch64-linux";
  disk = "/dev/sda";

  deploy = {
    ip = "46.224.186.182";
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
    ip = "10.100.10.3";
    publicKey = "xNTg6EmpCWe/PzbO6bd1SlBaye6fnF6AfunNyKfmy1g=";
    isServer = false;
  };
}
