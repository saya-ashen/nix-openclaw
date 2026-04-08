{
  lib,
  ...
}:
{
  imports = [
    (lib.mkRemovedOptionModule [ "programs" "openclaw" "firstParty" ] "Use programs.openclaw.plugins.<name> instead.")
    (lib.mkRemovedOptionModule [ "programs" "openclaw" "customPlugins" ] "Use programs.openclaw.plugins.<name> = { package = pkgs.mkOpenclawPlugin ...; settings = { ...; }; env = { ...; }; }.")
    (lib.mkRemovedOptionModule [ "programs" "openclaw" "bundledPlugins" ] "Use programs.openclaw.plugins.<name> and programs.openclaw.plugins._slots instead.")
    ./options.nix
    ./config.nix
  ];
}
