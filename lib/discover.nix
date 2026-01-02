# Node Discovery Module
# Discovers valid nodes in a directory by scanning for subdirectories containing config.nix
#
# Usage:
#   discover = import ./discover.nix;
#   nodeNames = discover ./hosts/nodes;
#   # Returns: ["server_01" "agent_01" "agent_02"] (order may vary)
#
# Arguments:
#   nodesPath - Path to directory containing node subdirectories
#
# Returns:
#   List of node names (strings) that have a valid config.nix file

nodesPath:
let
  allEntries = builtins.readDir nodesPath;
in
builtins.filter
  (name:
  allEntries.${name} == "directory" &&
  builtins.pathExists (nodesPath + "/${name}/config.nix"))
  (builtins.attrNames allEntries)
