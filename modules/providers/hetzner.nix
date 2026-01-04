# Catálogo de opciones disponibles en Hetzner Cloud
{
  name = "hetzner";
  provisioner = "hcloud";

  # Tipos de servidor disponibles
  types = {
    # ARM (Ampere)
    cax11 = { cpu = 2; ram = 4; arch = "aarch64-linux"; description = "ARM 2vCPU/4GB"; };
    cax21 = { cpu = 4; ram = 8; arch = "aarch64-linux"; description = "ARM 4vCPU/8GB"; };
    cax31 = { cpu = 8; ram = 16; arch = "aarch64-linux"; description = "ARM 8vCPU/16GB"; };
    cax41 = { cpu = 16; ram = 32; arch = "aarch64-linux"; description = "ARM 16vCPU/32GB"; };

    # x86 (Intel/AMD compartido)
    cpx11 = { cpu = 2; ram = 2; arch = "x86_64-linux"; description = "x86 2vCPU/2GB"; };
    cpx21 = { cpu = 3; ram = 4; arch = "x86_64-linux"; description = "x86 3vCPU/4GB"; };
    cpx31 = { cpu = 4; ram = 8; arch = "x86_64-linux"; description = "x86 4vCPU/8GB"; };
  };

  # Datacenters disponibles
  locations = {
    fsn1 = { city = "Falkenstein"; country = "DE"; };
    nbg1 = { city = "Nuremberg"; country = "DE"; };
    hel1 = { city = "Helsinki"; country = "FI"; };
    ash = { city = "Ashburn"; country = "US"; };
  };

  # Defaults para este provider
  defaults = {
    image = "ubuntu-24.04";
    type = "cax11";
    location = "fsn1";
  };
}
