# Configuración de hardware para servidores x86_64
{ config, lib, modulesPath, ... }:

{
  imports = [
    # qemu-guest: módulos virtio necesarios para VMs en Hetzner
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  hardware = {

    # VMs no necesitan firmware de hardware físico
    enableRedistributableFirmware = lib.mkForce false;

    # Hardware configuration
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  # Boot configuration for x86_64
  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
    };

    initrd.availableKernelModules = [
      "ahci"
      "xhci_pci"
      "virtio_pci"
      "virtio_scsi"
      "sd_mod"
      "sr_mod"
    ];

    kernelModules = [
      "kvm-intel"
      "kvm-amd"
    ];
  };

  # Networking
  networking.useDHCP = lib.mkDefault true;
}
