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
    1. Instalar NixOS manualmente o con nixos-anywhere
    2. Añadir la IP a hosts/state/nodes.json
    3. Ejecutar deploy
  '';
}
