{
  admin = {
    sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICg4qvvrvP7BSMLUqPNz2+syXHF1+7qGutKBA9ndPBB+ kennycallado@hotmail.com";
    email = "kennycallado@hotmail.com";
  };

  # Domain configuration - change this for different environments
  # staging: staging.example.com, prod: example.com
  domain = "kennycallado.dev";

  # Observability settings - adjust for different environments
  # dev: shorter retention, smaller storage
  # prod: longer retention, larger storage
  metrics = {
    retention = "168h"; # 7 days (used by Prometheus, Loki, Tempo)
    storage = {
      prometheus = "10Gi";
      alertmanager = "1Gi";
      loki = "10Gi";
      tempo = "10Gi";
    };
  };

  # Backup settings
  backups = {
    retention = "7d"; # PostgreSQL backup retention
  };

  # WireGuard external clients (machines without config.nix)
  # These are manually managed devices that connect to the cluster
  wgClients = {
    ryzen = {
      ip = "10.100.10.100";
      publicKey = "QUAsyA1ieF4GavRU0l+E+Z1i+x/TIgJ3frZLg9bh0UY=";
    };
  };
}
