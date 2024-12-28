{ pkgs, lib, ... }:
{
  nodes.host = {
    systemd.tmpfiles.settings."www" = {
      "/srv/www/index.html".f = {
        argument = "fnord";
      };
      "/srv/pgsql".d = { };
      "/srv/nextcloud".d = { };
    };
    nixos-nspawn.containers = {
      database = {
        autoStart = false;
        binds = {
          "/var/lib/postgresql" = {
            hostPath = "/srv/pgsql";
            options = [ "idmap" ];
          };
        };
        config = {
          services.postgresql = {
            enable = true;
          };
        };
        network.veth.zone = "internal";
      };
      test = {
        binds = {
          "/srv/www" = {
            readOnly = true;
          };
          "/var/lib/nextcloud" = {
            hostPath = "/srv/nextcloud";
            options = [ "idmap" ];
          };
        };
        config = {
          networking.firewall.allowedTCPPorts = [ 80 ];
          services.nginx = {
            enable = true;
            virtualHosts."test".root = "/srv/www";
          };
          services.nextcloud = {
            enable = true;
            hostName = "test.local";
            config = {
              adminpassFile = "/srv/www/index.html";
              #dbtype = "pgsql";
            };
          };
        };
        network.veth.zone = "internal";
      };
    };
  };

  testScript = ''
    start_all()
    host.wait_for_unit("systemd-nspawn@test.service")
    host.wait_until_succeeds("ping -c 1 test")
    host.wait_until_succeeds("${lib.getExe pkgs.curl} -v http://test | grep fnord")
    # Check if Nextcloud works
    host.wait_until_succeeds("${lib.getExe pkgs.curl} -Lv http://test.local | grep Login")
  '';
}
