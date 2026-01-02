{
  hostname = "server_01";
  system = "aarch64-linux";
  disk = "/dev/sda";

  deploy = {
    ip = "46.224.152.241";
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
    publicKey = "it3v1PIyMe2DrbiChELtPJEAND+5NbAf6YHU/cqyRAo=";
    isServer = true;
  };

  nfs.enable = true;
}
