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
      ];

      flake.nixosModules = rec {
        default = host;
        host = import ./host.nix;
        container = import ./container.nix;
        tarball = import ./tarball.nix;
        versionFlakeFix =
          {
            config,
            pkgs,
            lib,
            ...
          }:
          {
            nix = {
              channel.enable = false;
              registry.nixos-nspawn.flake = inputs.self;
              nixPath = lib.mkDefault [ "nixos-config=/etc/nixos/configuration.nix" ];

              settings = {
                extra-experimental-features = [
                  "flakes"
                  "nix-command"
                ];
              };
            };

            nixpkgs.flake = {
              source = lib.mkDefault inputs.nixpkgs;
              setNixPath = true;
              setFlakeRegistry = true;
            };

            system.configurationRevision = inputs.self.shortRev or "dirty";

            system.nixos = {
              versionSuffix = lib.mkDefault ".${inputs.nixpkgs.shortRev}";
              revision = lib.mkDefault (inputs.nixpkgs.rev or inputs.nixpkgs.shortRev);
            };

            environment.systemPackages = [
              # Needed for flakes to fetch git revisions
              pkgs.git
            ];

            # At creation time we do not have state yet, so just default to latest.
            system.stateVersion = lib.mkDefault config.system.nixos.release;
          };
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
          packages.tarball =
            let
              nixosSystem = pkgs.nixos [
                inputs.self.nixosModules.versionFlakeFix
                inputs.self.nixosModules.tarball
                (
                  # Generates a configuration.nix so nixos-rebuild works
                  { modulesPath, ... }:
                  {
                    imports = [ "${modulesPath}/profiles/clone-config.nix" ];
                    installer.cloneConfigIncludes =
                      let
                        selfFlakeRef = ''(builtins.getFlake "nixos-nspawn")'';
                      in
                      lib.mkForce [
                        "${selfFlakeRef}.nixosModules.versionFlakeFix"
                        "${selfFlakeRef}.nixosModules.tarball"
                      ];
                  }
                )
              ];
            in
            nixosSystem.config.system.build.tarball
            // {
              meta.description = "NixOS nspawn tarball for ${system} - ${pkgs.stdenv.hostPlatform.linux-kernel.name}";
              inherit (nixosSystem) config;
            };

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
