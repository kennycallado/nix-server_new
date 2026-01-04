{ lib, modulesPath, ... }:

{
  imports = [
    # qemu-guest: módulos virtio necesarios para VMs en Hetzner
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # VMs no necesitan firmware de hardware físico
  hardware.enableRedistributableFirmware = lib.mkForce false;

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
