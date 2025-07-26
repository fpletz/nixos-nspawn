{ inputs, ... }:
let
  testModule =
    { pkgs, config, ... }:
    {
      imports = [
        inputs.self.nixosModules.default
      ];

      # silence warning
      system.stateVersion = config.system.nixos.release;

      # debugging in interactive driver
      environment.systemPackages = [ pkgs.tcpdump ];

      # use this test module in the containers recursively
      virtualisation.nspawn = {
        imports = [
          testModule
        ];
      };
    };
in
{
  perSystem =
    { pkgs, lib, ... }:
    let
      checkFiles = lib.mapAttrsToList (fn: _: fn) (
        lib.filterAttrs (fn: type: type == "regular" && lib.hasSuffix ".nix" fn) (builtins.readDir ./checks)
      );
      callCheck = fn: import ./checks/${fn} { inherit pkgs lib inputs; };
      checkExprs = lib.listToAttrs (
        map (fn: lib.nameValuePair (lib.removeSuffix ".nix" fn) (callCheck fn)) checkFiles
      );
      nixosTest =
        (import "${inputs.nixpkgs}/nixos/lib/testing-python.nix" {
          inherit (pkgs.stdenv.hostPlatform) system;
          inherit pkgs;
          extraConfigurations = [ testModule ];
        }).simpleTest;
    in
    {
      checks = lib.mapAttrs (name: expr: nixosTest (expr // { inherit name; })) checkExprs;
    };
}
