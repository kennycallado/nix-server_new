{ conf, config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  hardware = {

    # VMs no necesitan firmware de hardware físico
    enableRedistributableFirmware = lib.mkForce false;

    # Hardware configuration
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  # Boot configuration for x86_64 (BIOS/Legacy mode for Hetzner Cloud)
  boot = {
    loader.grub = {
      enable = true;
      efiSupport = false;
    };

    kernelModules = [ "kvm-intel" "kvm-amd" ];
    initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  };
}
