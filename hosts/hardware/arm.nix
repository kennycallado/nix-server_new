{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # DHCP genérico - funciona con cualquier interfaz
  # networking.useDHCP = lib.mkDefault true;

  boot = {
    kernelModules = [ ];
    extraModulePackages = [ ];

    initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];

    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  # fileSystems y swapDevices los genera disko automáticamente
}
