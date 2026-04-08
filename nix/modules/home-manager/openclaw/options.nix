{
  config,
  lib,
  pkgs,
  ...
}:

let
  openclawLib = import ./lib.nix { inherit config lib pkgs; };
  instanceModule = import ./options-instance.nix { inherit lib openclawLib; };
  pluginOptionModule = lib.types.submodule {
    options = {
      package = lib.mkOption {
        type = lib.types.package;
        description = "Packaged OpenClaw plugin derivation created with pkgs.mkOpenclawPlugin or pkgs.mkOpenclawNpmPlugin.";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf (lib.types.oneOf [
          lib.types.str
          lib.types.path
        ]);
        default = { };
        description = "Plugin environment values exported into the gateway wrapper.";
      };
      settings = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Plugin settings rendered into openclaw.json.plugins.entries.<plugin>.config.";
      };
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether the plugin entry is enabled in runtime config.";
      };
      hooks = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Optional runtime hooks written to openclaw.json.plugins.entries.<plugin>.hooks.";
      };
      subagent = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Optional runtime subagent config written to openclaw.json.plugins.entries.<plugin>.subagent.";
      };
    };
  };
  pluginSlotsOption = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Plugin slot assignments keyed by runtime slot name, e.g. memory or contextEngine.";
  };
  pluginsOptionType = lib.types.submodule {
    freeformType = lib.types.attrsOf pluginOptionModule;
    options = {
      _slots = pluginSlotsOption;
    };
  };
  mkSkillOption = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Skill name (used as the directory name).";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Short description for the skill frontmatter.";
      };
      homepage = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional homepage URL for the skill frontmatter.";
      };
      body = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional skill body (markdown).";
      };
      openclaw = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Optional openclaw metadata for the skill frontmatter.";
      };
      mode = lib.mkOption {
        type = lib.types.enum [
          "symlink"
          "copy"
          "inline"
        ];
        default = "symlink";
        description = "Install mode for the skill (symlink/copy/inline).";
      };
      source = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Source path for the skill (required for symlink/copy).";
      };
    };
  };

in
{
  options.programs.openclaw = {
    enable = lib.mkEnableOption "OpenClaw (batteries-included)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openclaw;
      description = "OpenClaw batteries-included package.";
    };

    toolNames = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "Override the built-in toolchain names (see nix/tools/extended.nix).";
    };

    excludeTools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Tool names to remove from the built-in toolchain.";
    };

    appPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional OpenClaw app package (defaults to package if unset).";
    };

    installApp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install OpenClaw.app at the default location.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${openclawLib.homeDir}/.openclaw";
      description = "State directory for OpenClaw (logs, sessions, config).";
    };

    workspaceDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.programs.openclaw.stateDir}/workspace";
      description = "Workspace directory for Openclaw agent skills (defaults to stateDir/workspace).";
    };

    workspace = {
      pinAgentDefaults = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pin agents.defaults.workspace to each instance workspaceDir when unset (prevents falling back to template ~/.openclaw/workspace).";
      };
    };

    manageConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Manage generated OpenClaw config files (openclaw.json) via Home Manager.";
    };

    manageDocuments = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Manage workspace documents and skills via Home Manager.";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Shell-style env file loaded before launching OpenClaw (lines like KEY=value or export KEY=value).";
    };

    documents = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a documents directory containing AGENTS.md, SOUL.md, and TOOLS.md.";
    };

    skills = lib.mkOption {
      type = lib.types.listOf mkSkillOption;
      default = [ ];
      description = "Declarative skills installed into each instance workspace.";
    };

    plugins = lib.mkOption {
      type = pluginsOptionType;
      default = { };
      description = ''
        Plugins keyed by plugin name under programs.openclaw.plugins.<name>.
        Use programs.openclaw.plugins._slots for runtime slot assignments.
      '';
    };

    launchd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run OpenClaw gateway via launchd (macOS).";
    };

    launchd.label = lib.mkOption {
      type = lib.types.str;
      default = "com.steipete.openclaw.gateway";
      description = "launchd label for the default OpenClaw instance.";
    };

    systemd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run OpenClaw gateway via systemd user service (Linux).";
    };

    systemd.unitName = lib.mkOption {
      type = lib.types.str;
      default = "openclaw-gateway";
      description = "systemd user service unit name for the default OpenClaw instance.";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = { };
      description = "Named OpenClaw instances (prod/test).";
    };

    exposePluginPackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add plugin packages to home.packages so CLIs are on PATH.";
    };

    reloadScript = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install openclaw-reload helper for no-sudo config refresh + gateway restart.";
      };
    };

    config = lib.mkOption {
      type = lib.types.submodule { options = openclawLib.generatedConfigOptions; };
      default = { };
      description = "OpenClaw config (schema-typed).";
    };
  };
}
