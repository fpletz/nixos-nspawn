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
      inputs.nixpkgs.follows = "nixpkgs";
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
        ./tarball.nix
      ];

      flake.nixosModules = {
        default = import ./modules;
      };

      perSystem =
        {
          pkgs,
          config,
          lib,
          system,
          ...
        }:
        {
          packages.docs =
            let
              optionsMd =
                (pkgs.nixosOptionsDoc {
                  inherit
                    (inputs.nixpkgs.lib.nixosSystem {
                      inherit system;
                      modules = [ inputs.self.nixosModules.default ];
                    })
                    options
                    ;
                  documentType = "none";
                  transformOptions =
                    opt:
                    if lib.hasPrefix "virtualisation.nspawn" opt.name then
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
                ln -sf $PWD/README.md docs/src/README.md
                ln -sf ${optionsMd} docs/src/options.md
                mdbook build -d $out docs
              '';
            };

          devShells.default = pkgs.mkShellNoCC {
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
