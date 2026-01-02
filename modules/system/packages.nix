{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  programs.git.enable = true;

  # Cliente NFS para montar shares
  services.rpcbind.enable = true;
  boot.supportedFilesystems = [ "nfs" ];

  environment.systemPackages = with pkgs; [
    tree
    htop
    curl
    wget

    procps
    killall

    diffutils
    findutils
    util-linux

    cryptsetup
    openssl

    # deploy-rs

    nfs-utils

    jq
    xz
    fzf
    zip
    unar
    gzip
    bzip2
    unzip
    gnutar
    ripgrep
  ];
}
