{
  description = "Declarative NixOS nspawn containers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "nixpkgs";
      };
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks.flakeModule
        ./checks.nix
      ];

      flake.nixosModules = rec {
        default = host;
        container = import ./container.nix;
        host = import ./host.nix;
      };

      perSystem =
        {
          pkgs,
          config,
          lib,
          ...
        }:
        {
          packages.docs =
            let
              optionsMd =
                (pkgs.nixosOptionsDoc {
                  inherit
                    (inputs.nixpkgs.lib.nixosSystem {
                      inherit (pkgs) system;
                      modules = [ inputs.self.nixosModules.host ];
                    })
                    options
                    ;
                  documentType = "none";
                  transformOptions =
                    opt:
                    if lib.hasPrefix "nixos-nspawn" opt.name then
                      opt // { declarations = [ ]; }
                    else
                      { visible = false; };
                }).optionsCommonMark;
            in
            pkgs.stdenv.mkDerivation {
              name = "nixos-nspawn-docs";

              src = inputs.self;

              nativeBuildInputs = [ pkgs.mdbook ];

              buildPhase = ''
                cd docs
                cp ../README.md src/README.md
                ln -sf ${optionsMd} src/options.md
                mdbook build -d $out
              '';
            };

          devShells.default = pkgs.mkShellNoCC {
            packages = [ pkgs.nix-fast-build ];

            inputsFrom = [
              config.treefmt.build.devShell
              config.pre-commit.devShell
            ];
          };

          treefmt = {
            projectRootFile = "flake.lock";
            programs = {
              deadnix.enable = true;
              nixfmt.enable = true;
            };
          };

          pre-commit.settings.hooks = {
            treefmt.enable = true;
          };
        };
    };
}
