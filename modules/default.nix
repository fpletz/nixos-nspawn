{ lib, ... }:
{
  imports = [
    ./host.nix
    ./container.nix
    (lib.mkRemovedOptionModule [ "nixos-nspawn" ] ''
      The `nixos-nspawn` NixOS options were moved to `virtualisation.nspawn`.
    '')
  ];
}
