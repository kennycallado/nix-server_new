let
  # Admin (tu máquina local)
  admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICg4qvvrvP7BSMLUqPNz2+syXHF1+7qGutKBA9ndPBB+";

  # Hosts (copiar de secrets/hosts/<name>.pub después de keygen)
  server_01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPSU/RF++FftGyfoGeq5JcXd9XfcVZgW6SOKo2OEXB6Q";
  agent_01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEarQwbQb19k4Bp7iK9oOxM/ePvCq3LSwN20myktfNNR";
  agent_02 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHhbxg/YxtWjhid5XxbuI0xsnNGHcKZGo8zqg6SGyTJG";

  allKeys = [ admin server_01 agent_01 agent_02 ];
in
{
  "users-root_password.age".publicKeys = allKeys;
  "users-admin_password.age".publicKeys = allKeys;
  "services-k3s_token.age".publicKeys = allKeys;

  # WireGuard - cada nodo solo necesita su propia clave privada
  "wireguard-server_01.age".publicKeys = [ admin server_01 ];
  "wireguard-agent_01.age".publicKeys = [ admin agent_01 ];
  "wireguard-agent_02.age".publicKeys = [ admin agent_02 ];

  # Sealed Secrets - clave maestra para reproducibilidad
  # Solo el server necesita la clave privada (para inyectarla en k8s)
  "sealed-secrets-key.age".publicKeys = [ admin server_01 ];

  # Hetzner Cloud Token (solo para uso local por admin)
  "hcloud-token.age".publicKeys = [ admin ];
}
