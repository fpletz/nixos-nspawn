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
}
