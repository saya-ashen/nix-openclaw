{
  config,
  lib,
  pkgs,
}: let
  cfg = config.programs.openclaw;
  homeDir = config.home.homeDirectory;
  defaultPackage = cfg.package;
  appPackage =
    if cfg.appPackage != null
    then cfg.appPackage
    else defaultPackage;
  generatedConfigOptions = import ../../../generated/openclaw-config-options.nix {lib = lib;};

  resolvePath = p:
    if lib.hasPrefix "~/" p
    then "${homeDir}/${lib.removePrefix "~/" p}"
    else p;

  toRelative = p:
    if lib.hasPrefix "${homeDir}/" p
    then lib.removePrefix "${homeDir}/" p
    else p;
in {
  inherit
    cfg
    homeDir
    defaultPackage
    appPackage
    generatedConfigOptions
    resolvePath
    toRelative
    ;
}
