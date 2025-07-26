{ ... }:
{
  nodes.host = {
    virtualisation.nspawn.containers = {
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
}
