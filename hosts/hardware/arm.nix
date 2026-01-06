{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # VMs no necesitan firmware de hardware físico
  hardware.enableRedistributableFirmware = lib.mkForce false;

  boot = {
    kernelModules = [ ];
    extraModulePackages = [ ];

    initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];

    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };
}
