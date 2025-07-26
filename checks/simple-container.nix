{ ... }:
{
  nodes.host = {
    virtualisation.nspawn.containers = {
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
}
