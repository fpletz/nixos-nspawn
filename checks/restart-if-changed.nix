{ pkgs, lib, ... }:
{
  nodes.host = {
    virtualisation.nspawn.containers = {
      backend = {
        config = {
          networking.firewall.allowedTCPPorts = [ 80 ];
          services.nginx = {
            enable = true;
            virtualHosts."backend".locations."/".return = lib.mkDefault ''200 "hack the planet"'';
          };
        };
      };
    };

    specialisation."changed-container".configuration = {
      virtualisation.nspawn.containers.backend.config.services.nginx.virtualHosts."backend".locations."/".return =
        ''404 "planet not found"'';
    };
  };

  testScript =
    { nodes, ... }:
    let
      specialisations = "${nodes.host.system.build.toplevel}/specialisation";
    in
    ''
      start_all()
      host.wait_for_unit("systemd-nspawn@backend.service")
      host.wait_until_succeeds("ping -c 1 backend")
      host.wait_until_succeeds("${lib.getExe pkgs.curl} -v http://backend | grep 'hack the planet'")

      host.succeed("${specialisations}/changed-container/bin/switch-to-configuration test")

      # Wait until nginx is up again, then make sure we have the *right* response
      host.wait_until_succeeds("${lib.getExe pkgs.curl} -v http://backend")
      host.succeed("${lib.getExe pkgs.curl} -v http://backend | grep 'planet not found'")
    '';
}
