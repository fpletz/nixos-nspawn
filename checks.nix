{ inputs, ... }:
let
  testModule =
    { pkgs, config, ... }:
    {
      # silence warning
      system.stateVersion = config.system.nixos.release;
      # debugging in interactive driver
      environment.systemPackages = [ pkgs.tcpdump ];
      # use this test module in the containers recursively
      nixos-nspawn.imports = [
        testModule
        inputs.self.nixosModules.host
      ];
    };
in
{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks = {
        simple-container = pkgs.nixosTest {
          name = "simple-container";
          nodes.host = {
            imports = [
              testModule
              inputs.self.nixosModules.host
            ];
            nixos-nspawn.containers = {
              test.config = {
                networking.hostName = "test-container";
              };
            };
          };

          testScript = ''
            start_all()
            host.wait_for_unit("systemd-nspawn@test.service")
            # needs to wait until networking is configured
            host.wait_until_succeeds("ping -c 1 test")
            host.succeed("machinectl shell test /run/current-system/sw/bin/ping -c 1 host")
          '';
        };

        custom-path-eval = pkgs.nixosTest {
          name = "custom-path-eval";
          nodes.host = {
            imports = [
              testModule
              inputs.self.nixosModules.host
            ];
            nixos-nspawn.containers = {
              test.path =
                (inputs.nixpkgs.lib.nixosSystem {
                  inherit (pkgs) system;
                  modules = [
                    inputs.self.nixosModules.container
                    (
                      { config, ... }:
                      {
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
        };

        static-networking = pkgs.nixosTest {
          name = "static-networking";
          nodes.host = {
            imports = [
              testModule
              inputs.self.nixosModules.host
            ];
            nixos-nspawn.containers = {
              test = {
                config = { };
                network.veth.config = {
                  host = {
                    networkConfig = {
                      DHCPServer = false;
                      Address = [
                        "fc42::1/64"
                        "192.168.42.1/24"
                      ];
                    };
                  };
                  container = {
                    networkConfig = {
                      DHCP = false;
                      Address = [
                        "fc42::2/64"
                        "192.168.42.2/24"
                      ];
                      Gateway = [
                        "fc42::1"
                        "192.168.42.1"
                      ];
                    };
                  };
                };
              };
            };
          };

          testScript = ''
            start_all()
            host.wait_for_unit("systemd-nspawn@test.service")
            host.wait_until_succeeds("ping -6 -c 1 test")
            host.wait_until_succeeds("ping -4 -c 1 test")
          '';
        };

        nginx-reverse-proxy = pkgs.nixosTest {
          name = "nginx-reverse-proxy";
          nodes.host = {
            imports = [
              testModule
              inputs.self.nixosModules.host
            ];
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
        };

        bind-mounts = pkgs.nixosTest {
          name = "bind-mounts";
          nodes.host = {
            imports = [
              testModule
              inputs.self.nixosModules.host
            ];
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
        };
      };
    };
}
