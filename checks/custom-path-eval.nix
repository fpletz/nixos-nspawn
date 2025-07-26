{ pkgs, inputs, ... }:
{
  nodes.host = {
    virtualisation.nspawn.containers = {
      test.path =
        (inputs.nixpkgs.lib.nixosSystem {
          inherit (pkgs) system;
          modules = [
            inputs.self.nixosModules.default
            (
              { config, ... }:
              {
                virtualisation.nspawn.isContainer = true;
                networking.hostName = "test-container";
                # silence warning
                system.stateVersion = config.system.nixos.release;
              }
            )
          ];
        }).config.system.build.toplevel;
    };
  };

  testScript = ''
    start_all()
    host.wait_for_unit("systemd-nspawn@test.service")
  '';
}
