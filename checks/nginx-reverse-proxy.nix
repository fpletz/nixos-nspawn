{ pkgs, lib, ... }:
{
  nodes.host = {
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts."default".locations."/".proxyPass = "http://backend";
    };
    nixos-nspawn.containers = {
      backend = {
        config = {
          networking.firewall.allowedTCPPorts = [ 80 ];
          services.nginx = {
            enable = true;
            virtualHosts."backend".locations."/".return = ''200 "hack the planet"'';
          };
        };
      };
    };
  };

  testScript = ''
    start_all()
    host.wait_for_unit("systemd-nspawn@backend.service")
    host.wait_until_succeeds("ping -c 1 backend")
    host.wait_until_succeeds("${lib.getExe pkgs.curl} -v http://localhost | grep 'hack the planet'")
  '';
}
