{
  lib,
  pkgs,
  stdenvNoCC,
}:
let
  mkNpmPluginPackage = import ./mk-openclaw-npm-plugin.nix {
    inherit pkgs lib;
  };

  normalizePluginMeta = meta: {
    name = meta.name or (throw "openclaw plugin package is missing passthru.openclawPlugin.name");
    skills = meta.skills or [ ];
    packages = meta.packages or [ ];
    needs = {
      stateDirs = (meta.needs or { }).stateDirs or [ ];
      requiredEnv = (meta.needs or { }).requiredEnv or [ ];
    };
  };
in
{
  mkOpenclawPlugin =
    {
      name,
      src,
      packages ? [ ],
      skills ? [ ],
      needs ? { },
      passthru ? { },
      meta ? { },
      ...
    }@args:
    let
      pluginMeta = normalizePluginMeta {
        inherit name skills packages needs;
      };
      extraArgs = builtins.removeAttrs args [
        "name"
        "src"
        "packages"
        "skills"
        "needs"
        "passthru"
        "meta"
      ];
    in
    stdenvNoCC.mkDerivation (extraArgs // {
      pname = name;
      version = extraArgs.version or "0-unstable";
      inherit src;
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        cp -R --no-preserve=mode,ownership "$src"/. "$out"
        runHook postInstall
      '';
      passthru = passthru // {
        openclawPlugin = pluginMeta;
      };
      meta = meta;
    });

  mkOpenclawNpmPlugin =
    {
      packageName,
      version,
      packageLock,
      npmDepsHash,
      pname ? let
        s = lib.replaceStrings [ "@" "/" ] [ "" "-" ] packageName;
      in
      s,
      packages ? [ ],
      skills ? [ ],
      needs ? { },
      passthru ? { },
      meta ? { },
      ...
    }@args:
    let
      pluginMeta = normalizePluginMeta {
        name = pname;
        inherit skills packages needs;
      };
      basePackage = mkNpmPluginPackage {
        inherit
          packageName
          version
          packageLock
          npmDepsHash
          pname
          ;
      };
      extraArgs = builtins.removeAttrs args [
        "packageName"
        "version"
        "packageLock"
        "npmDepsHash"
        "pname"
        "packages"
        "skills"
        "needs"
        "passthru"
        "meta"
      ];
    in
    basePackage.overrideAttrs (old: extraArgs // {
      passthru = (old.passthru or { }) // passthru // {
        openclawPlugin = pluginMeta;
      };
      meta = (old.meta or { }) // meta // {
        description = meta.description or "OpenClaw plugin package for ${packageName}";
        platforms = meta.platforms or lib.platforms.all;
      };
    });
}
