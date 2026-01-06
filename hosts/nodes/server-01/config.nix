{
  hostname = "server-01";
  system = "aarch64-linux";
  disk = "/dev/sda";

  deploy = {
    ip = "46.224.186.182"; # Set after creating server in Hetzner Console
    sshUser = "admin";
    remoteBuild = true;
  };

  k3s = {
    enable = true;
    role = "server";
    serverAddr = ""; # First server - starts the cluster
    exposeServices = false; # Set to true to expose services via public ingress
  };

  wireguard = {
    enable = true;
    ip = "10.100.10.1";
    isServer = true;
  };

  nfs.enable = true;
}
