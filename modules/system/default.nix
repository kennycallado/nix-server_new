{ pkgs, config, conf, constants, ... }:

{
  imports = [
    ./packages.nix
    ../services/openssh.nix
  ];

  system.stateVersion = "25.11";

  # Locale y timezone
  time.timeZone = "Europe/Madrid";
  console.keyMap = "es";
  i18n.defaultLocale = "es_ES.UTF-8";

  # Secretos
  age.secrets.admin-password.file = ../../secrets/users-admin_password.age;
  age.secrets.root-password.file = ../../secrets/users-root_password.age;

  # Usuarios declarativos (contraseñas se actualizan en cada deploy)
  users.mutableUsers = false;

  users.users.root = {
    hashedPasswordFile = config.age.secrets.root-password.path;
  };

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.age.secrets.admin-password.path;
    openssh.authorizedKeys.keys = [ constants.admin.sshKey ];
  };

  # Sudo sin contraseña para wheel
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  nix = {
    settings = {
      auto-optimise-store = true;

      trusted-users = [ "root" "@wheel" ];
      trusted-substituters = [ "https://nix-community.cachix.org" ];
      trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
    };

    gc = {
      dates = "weekly";
      options = "--delete-older-than 7d";
      automatic = true;
    };

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  services.journald.extraConfig = ''
    SystemMaxUse=2G
  '';
}
