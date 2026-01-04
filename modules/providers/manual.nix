# Provider para servidores bare-metal o manuales
{
  name = "manual";
  provisioner = "none";

  # No hay catálogo de tipos - es hardware arbitrario
  types = { };
  locations = { };

  defaults = { };

  # Instrucciones para el operador
  instructions = ''
    Para añadir un servidor bare-metal:

    OPCIÓN A: Servidor YA tiene NixOS instalado
      1. Crear hosts/nodes/<hostname>/config.nix con infra.provider = "manual"
      2. Añadir la IP a hosts/state/nodes.json
      3. nix run .#keygen -- <hostname>
      4. nix run nixpkgs#deploy-rs -- .#<hostname>

    OPCIÓN B: Servidor tiene otro SO (Debian, rescue mode, etc.)
      1. Crear hosts/nodes/<hostname>/config.nix con infra.provider = "manual"
      2. Añadir la IP a hosts/state/nodes.json
      3. nix run .#keygen -- <hostname>
      4. nix run .#install -- <hostname>   # nixos-anywhere reemplaza el SO
      5. nix run nixpkgs#deploy-rs -- .#<hostname>  # para futuros cambios

    ALTERNATIVA: Usar provision.sh con provider manual
      1. Crear hosts/nodes/<hostname>/config.nix con infra.provider = "manual"
      2. nix run .#provision -- <hostname>
         (te pedirá la IP y ejecutará keygen + install automáticamente)
  '';
}
