{
  config,
  lib,
  pkgs,
}: let
  cfg = config.programs.openclaw;
  homeDir = config.home.homeDirectory;
  autoExcludeTools = lib.optionals config.programs.git.enable ["git"];
  effectiveExcludeTools = lib.unique (cfg.excludeTools ++ autoExcludeTools);
  toolOverrides = {
    toolNamesOverride = cfg.toolNames;
    excludeToolNames = effectiveExcludeTools;
  };
  toolOverridesEnabled = cfg.toolNames != null || effectiveExcludeTools != [];
  toolSets = import ../../../tools/extended.nix ({inherit pkgs;} // toolOverrides);
  defaultPackage =
    if toolOverridesEnabled && cfg.package == pkgs.openclaw
    then (pkgs.openclawPackages.withTools toolOverrides).openclaw
    else cfg.package;
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
    toolOverrides
    toolOverridesEnabled
    toolSets
    defaultPackage
    appPackage
    generatedConfigOptions
    resolvePath
    toRelative
    ;
}
