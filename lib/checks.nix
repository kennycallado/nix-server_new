{ pkgs, lib, system, self, deploy-rs, root }:
{
  formatting = pkgs.runCommand "check-formatting" { } ''
    cd ${root}
    ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check .
    touch $out
  '';
}
// lib.optionalAttrs (system == "aarch64-linux") {
  server_01-build = self.deploy.nodes.server_01.profiles.system.path;
}
  // lib.optionalAttrs (system == "aarch64-linux")
  (deploy-rs.lib.${system}.deployChecks self.deploy)
