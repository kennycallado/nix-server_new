{ lib, pkgs, ... }:

{
  # Sistema base
  system.stateVersion = "25.11";

  # Networking basico (DHCP)
  networking.useDHCP = lib.mkDefault true;

  # Locale y timezone
  time.timeZone = "Europe/Madrid";
  console.keyMap = "es";
  i18n.defaultLocale = "es_ES.UTF-8";

  # Firewall minimo - solo SSH
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # SSH para acceso remoto
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Usuario admin con SSH key (necesario para deploy-rs)
  users = {
    mutableUsers = false;

    users.root = {
      # En bootstrap, root solo accede por SSH key
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICg4qvvrvP7BSMLUqPNz2+syXHF1+7qGutKBA9ndPBB+ kennycallado@hotmail.com"
      ];
    };

    users.admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      # Password sera configurado en deploy completo via agenix
      # Por ahora solo acceso SSH
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICg4qvvrvP7BSMLUqPNz2+syXHF1+7qGutKBA9ndPBB+ kennycallado@hotmail.com"
      ];
    };
  };

  # Sudo sin password para admin (necesario para deploy-rs)
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  # Nix configurado para flakes y remote builds
  nix = {
    settings = {
      auto-optimise-store = true;
      trusted-users = [ "root" "admin" "@wheel" ];

      # Cache binario oficial
      substituters = [ "https://cache.nixos.org" ];
      trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    };

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Paquetes minimos para administracion y debug
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    curl
    wget
  ];

  # Journal limitado
  services.journald.extraConfig = ''
    SystemMaxUse=500M
  '';
}
