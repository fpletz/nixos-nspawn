{ lib, ... }:
{
  boot.isContainer = true;
  console.enable = true;

  # Allow the user to login as root without password.
  users.users.root.initialHashedPassword = lib.mkOverride 150 "";

  networking = {
    useNetworkd = true;
    useDHCP = false;
    useHostResolvConf = false;
    firewall.interfaces."host0" = {
      allowedTCPPorts = [ 5353 ];
      allowedUDPPorts = [ 5353 ];
    };
  };

  system = {
    rebuild.enableNg = true;
    tools.nixos-option.enable = false;
  };

  # FIXME: logrotate currently fails because files in the nix store are not
  # owned by root due to private users, see host.nix. Since we're running
  # ephemerally anyway this shouldn't be an issue, though.
  services.logrotate.enable = false;

  # XXXL nix-daemon detects that sandboxing is not available but it actually works
  nix.settings.sandbox-fallback = lib.mkForce true;

  boot.specialFileSystems = {
    # These are already mounted by systemd-nspawn
    "/dev".enable = false;
    "/proc".enable = false;
    "/dev/pts".enable = false;
    "/dev/shm".enable = false;
    "/run".enable = false;
  };
}
