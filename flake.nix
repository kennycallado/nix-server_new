{
  description = "Webslab server configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.darwin.follows = "";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, systems, disko, agenix, deploy-rs, nixos-anywhere, ... }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);

      # Node discovery using lib/discover.nix
      discover = import ./lib/discover.nix;
      nodesDir = ./hosts/nodes;
      nodeNames = discover nodesDir;

      # Centralized hosts data (network configuration, dynamic resolvers)
      hosts = import ./modules/network/hosts.nix;

      # Node factory
      mkNode = import ./lib/mkNode.nix;

      # Build all nodes directly with mkNode (no default.nix needed per node)
      nodes = nixpkgs.lib.genAttrs nodeNames (name:
        mkNode {
          inherit nixpkgs disko agenix deploy-rs hosts;
          configDir = ./hosts/nodes/${name};
          root = ./.;
        }
      );
    in
    {
      nixosConfigurations = nixpkgs.lib.mapAttrs (_: node: node.nixosConfig) nodes;
      deploy.nodes = nixpkgs.lib.mapAttrs (_: node: node.deployNode) nodes;

      devShells = eachSystem (system:
        import ./lib/devShells.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit agenix;
        }
      );

      apps = eachSystem (system:
        import ./lib/apps.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit nixos-anywhere agenix;
        }
      );

      checks = eachSystem (system:
        import ./lib/checks.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          lib = nixpkgs.lib;
          root = ./.;
          inherit system self deploy-rs;
        }
      );

      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
