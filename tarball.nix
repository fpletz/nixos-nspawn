{ inputs, ... }:
{
  flake.nixosModules.versionFlakeFix =
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

  flake.nixosModules.tarball =
    {
      modulesPath,
      pkgs,
      lib,
      config,
      ...
    }:
    let
      initScript = if config.boot.initrd.systemd.enable then "prepare-root" else "init";
    in
    {
      imports = [
        "${modulesPath}/image/file-options.nix"
        ./modules
      ];

      virtualisation.nspawn.isContainer = true;

      # relevant parts from nixpkgs/nixos/modules/virtualisation/lxc-container.nix

      boot.postBootCommands = ''
        # After booting, register the contents of the Nix store in the Nix
        # database.
        if [ -f /nix-path-registration ]; then
          ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration &&
          rm /nix-path-registration
        fi

        # nixos-rebuild also requires a "system" profile
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      '';

      image.baseName = "nixos-nspawn-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";
      image.extension = "tar.xz";
      image.filePath = "tarball/${config.image.fileName}";

      system.build.tarball = pkgs.callPackage "${modulesPath}/../lib/make-system-tarball.nix" {
        fileName = config.image.baseName;
        extraArgs = "--owner=0";

        storeContents = [
          {
            object = config.system.build.toplevel;
            symlink = "none";
          }
        ];

        contents = [
          {
            source = config.system.build.toplevel + "/${initScript}";
            target = "/sbin/init";
          }
          {
            source = config.system.build.toplevel + "/etc/os-release";
            target = "/etc/os-release";
          }
        ];

        extraCommands = "mkdir -p proc sys dev";
      };

      system.build.installBootLoader = pkgs.writeScript "install-sbin-init.sh" ''
        #!${pkgs.runtimeShell}
        ${pkgs.coreutils}/bin/ln -fs "$1/${initScript}" /sbin/init
      '';

      system.activationScripts.installInitScript = lib.mkForce ''
        ln -fs $systemConfig/${initScript} /sbin/init
      '';
    };

  perSystem =
    {
      pkgs,
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
    };
}
