{ lib, openclawLib }:

{ name, config, ... }:
let
  pluginOptionModule = lib.types.submodule {
    options = {
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Optional package override for this plugin instance.";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf (lib.types.oneOf [
          lib.types.str
          lib.types.path
        ]);
        default = { };
        description = "Plugin environment overrides exported into the gateway wrapper.";
      };
      settings = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Plugin settings overrides rendered into openclaw.json.plugins.entries.<plugin>.config.";
      };
      enabled = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Optional runtime enabled override for this plugin.";
      };
      hooks = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Optional runtime hooks override for this plugin.";
      };
      subagent = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Optional runtime subagent override for this plugin.";
      };
    };
  };
  pluginsOptionType = lib.types.submodule {
    freeformType = lib.types.attrsOf pluginOptionModule;
    options = {
      _slots = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Per-instance plugin slot overrides keyed by runtime slot name.";
      };
    };
  };
in
{
  options = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable this OpenClaw instance.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = openclawLib.defaultPackage;
      description = "OpenClaw batteries-included package.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default =
        if name == "default" then
          "${openclawLib.homeDir}/.openclaw"
        else
          "${openclawLib.homeDir}/.openclaw-${name}";
      description = "State directory for this OpenClaw instance (logs, sessions, config).";
    };

    workspaceDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.stateDir}/workspace";
      description = "Workspace directory for this OpenClaw instance.";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.stateDir}/openclaw.json";
      description = "Path to generated OpenClaw config JSON.";
    };

    logPath = lib.mkOption {
      type = lib.types.str;
      default =
        if name == "default" then
          "/tmp/openclaw/openclaw-gateway.log"
        else
          "/tmp/openclaw/openclaw-gateway-${name}.log";
      description = "Log path for this OpenClaw gateway instance.";
    };

    gatewayPort = lib.mkOption {
      type = lib.types.int;
      default = 18789;
      description = "Gateway port used by the OpenClaw desktop app.";
    };

    gatewayPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Local path to OpenClaw gateway source (dev only).";
    };

    gatewayPnpmDepsHash = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = lib.fakeHash;
      description = "pnpmDeps hash for local gateway builds (omit to let Nix suggest the correct hash).";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Shell-style env file loaded before launching this OpenClaw instance.";
    };

    plugins = lib.mkOption {
      type = pluginsOptionType;
      default = { };
      description = ''
        Per-instance plugin overrides keyed by plugin name.
        The same shape as programs.openclaw.plugins, with _slots reserved for slot overrides.
      '';
    };

    config = lib.mkOption {
      type = lib.types.submodule { options = openclawLib.generatedConfigOptions; };
      default = { };
      description = "OpenClaw config (schema-typed).";
    };

    launchd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run OpenClaw gateway via launchd (macOS).";
    };

    launchd.label = lib.mkOption {
      type = lib.types.str;
      default =
        if name == "default" then
          "com.steipete.openclaw.gateway"
        else
          "com.steipete.openclaw.gateway.${name}";
      description = "launchd label for this instance.";
    };

    systemd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run OpenClaw gateway via systemd user service (Linux).";
    };

    systemd.unitName = lib.mkOption {
      type = lib.types.str;
      default = if name == "default" then "openclaw-gateway" else "openclaw-gateway-${name}";
      description = "systemd user service unit name for this instance.";
    };

    app.install.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install OpenClaw.app for this instance.";
    };

    app.install.path = lib.mkOption {
      type = lib.types.str;
      default = "${openclawLib.homeDir}/Applications/OpenClaw.app";
      description = "Destination path for this instance's OpenClaw.app bundle.";
    };

    appDefaults = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = name == "default";
        description = "Configure macOS app defaults for this instance.";
      };

      attachExistingOnly = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Attach existing gateway only (macOS).";
      };

      nixMode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable OpenClaw Nix mode in the macOS app via defaults (openclaw.nixMode).";
      };
    };
  };
}
