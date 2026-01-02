{ device ? "/dev/sda", ... }:

{
  disko.devices = {
    disk.main = {
      inherit device;
      type = "disk";
      content = {
        type = "gpt";

        partitions = {
          ESP = {
            priority = 1;
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
              extraArgs = [ "-n" "BOOT" ];
            };
          };

          root = {
            priority = 2;
            size = "100%";
            end = "-4G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              extraArgs = [ "-L" "ROOT" ];
            };
          };

          swap = {
            priority = 3;
            size = "4G";
            content = {
              type = "swap";
              resumeDevice = true;
              extraArgs = [ "-L" "SWAP" ];
            };
          };
        };
      };
    };
  };
}
