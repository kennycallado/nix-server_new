{ pkgs, agenix }:

{
  default = pkgs.mkShell {
    packages = [
      pkgs.deploy-rs
      agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    shellHook = "echo 'Dev environment loaded'";
  };
}
