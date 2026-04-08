{
  lib,
  pkgs,
  stdenv,
  nodejs_22,
  openclawGateway,
}:

let
  stubModule =
    { lib, ... }:
    {
      options = {
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
        };

        home.homeDirectory = lib.mkOption {
          type = lib.types.str;
          default = "/tmp";
        };

        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };

        home.file = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        home.activation = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        launchd.agents = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        systemd.user.services = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        programs.git.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };

        lib = lib.mkOption {
          type = lib.types.attrs;
          default = {
            hm.dag.entryAfter = _: data: { inherit data; };
            hm.dag.entryBefore = _: data: { inherit data; };
          };
        };
      };
    };

  npmPackageLock = pkgs.writeText "example-plugin-package-lock.json" ''
    {
      "name": "example-plugin-bundle",
      "version": "0.0.1",
      "lockfileVersion": 3,
      "requires": true,
      "packages": {
        "": {
          "name": "example-plugin-bundle",
          "version": "0.0.1",
          "dependencies": {
            "left-pad": "1.3.0"
          }
        },
        "node_modules/left-pad": {
          "version": "1.3.0",
          "resolved": "https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz",
          "integrity": "sha512-XI5MPzVNApjAyhQzvS0lH4w6NucpN0xijnndQvoD0t2k4OQNCg4b8ZcJj9AJY6M8J3Pafz5o8w2kD0JjD4bYkg==",
          "deprecated": "use String.prototype.padStart()"
        }
      }
    }
  '';

  moduleEval = lib.evalModules {
    modules = [
      stubModule
      ../modules/home-manager/openclaw.nix
      (
        { lib, ... }:
        {
          config = {
            home.homeDirectory = "/tmp";
            programs.git.enable = false;
            lib.file.mkOutOfStoreSymlink = path: path;
             programs.openclaw = {
               enable = true;
               launchd.enable = false;
               systemd.enable = false;
               plugins = {
                 _slots = {
                   memory = "example-plugin";
                 };
                 example-plugin = {
                   package = pkgs.mkOpenclawPlugin {
                     name = "example-plugin";
                     src = builtins.path {
                       name = "example-plugin-src";
                       path = pkgs.writeTextDir "manifest.json" "{}\n";
                     };
                   };
                   settings = {
                     greeting = "hello";
                   };
                 };
                 left-pad = {
                   package = pkgs.mkOpenclawNpmPlugin {
                     packageName = "left-pad";
                     version = "1.3.0";
                     packageLock = npmPackageLock;
                     npmDepsHash = "sha256-bqFLk/e2z2jCyaSRhGrF0ln+Q1skoUNSH4BDsMyz8ck=";
                     pname = "left-pad-plugin";
                   };
                 };
               };
               instances.default = {
                 envFile = "/tmp/openclaw-test.env";
                 plugins = {
                   _slots = {
                     contextEngine = "left-pad";
                   };
                   example-plugin.settings = {
                     profile = "default";
                   };
                 };
               };
              documents = builtins.path {
                name = "documents";
                path = pkgs.runCommand "openclaw-documents" { } ''
                  mkdir -p "$out"
                  cp ${pkgs.writeText "AGENTS.md" "# Agent\n"} "$out/AGENTS.md"
                  cp ${pkgs.writeText "SOUL.md" "# Soul\n"} "$out/SOUL.md"
                  cp ${pkgs.writeText "TOOLS.md" "# Tools\n"} "$out/TOOLS.md"
                '';
              };
              config = {
                gateway = {
                  bind = "tailnet";
                  auth = {
                    mode = "token";
                    token = "test-token";
                  };
                  reload = {
                    mode = "hot";
                    debounceMs = 500;
                  };
                };
                discovery.mdns.mode = "minimal";
              };
            };
          };
        }
      )
    ];
    specialArgs = { inherit pkgs; };
  };

  configPathKey = ".openclaw/openclaw.json";
  documentsPathKeys = [
    ".openclaw/workspace/AGENTS.md"
    ".openclaw/workspace/SOUL.md"
    ".openclaw/workspace/TOOLS.md"
  ];
  configJson = moduleEval.config.home.file."${configPathKey}".text;
  parsedConfig = builtins.fromJSON configJson;
  pluginEntry = (((parsedConfig.plugins or { }).entries or { })."example-plugin" or null);
  pluginSlots = (parsedConfig.plugins or { }).slots or { };
  pluginEntryHasConfig =
    pluginEntry != null
    && (pluginEntry.enabled or false)
    && ((pluginEntry.config or { }).greeting or null) == "hello"
    && ((pluginEntry.config or { }).profile or null) == "default";
  pluginEntryKey = if pluginEntryHasConfig then "ok" else throw "Expected example-plugin config in openclaw.json plugins.entries.";
  pluginSlotsKey =
    if (pluginSlots.memory or null) == "example-plugin" && (pluginSlots.contextEngine or null) == "left-pad"
    then "ok"
    else throw "Expected plugins._slots to render to openclaw.json plugins.slots.";
  configFile = pkgs.writeText "openclaw-config.json" configJson;
  documentsTexts = map (
    pathKey:
    let
      entry = moduleEval.config.home.file."${pathKey}";
    in
    entry.text or (throw "Expected managed document ${pathKey} to be written as text.")
  ) documentsPathKeys;
  documentsKey = builtins.deepSeq documentsTexts "ok";
  systemdEnv = moduleEval.config.systemd.user.services.openclaw-gateway.Service.Environment or [ ];
  hasEnvFileVar = builtins.elem "OPENCLAW_ENV_FILE=/tmp/openclaw-test.env" systemdEnv;
  envFileKey = if hasEnvFileVar then "ok" else throw "Expected OPENCLAW_ENV_FILE in systemd environment.";

in
stdenv.mkDerivation {
  pname = "openclaw-config-validity";
  version = lib.getVersion openclawGateway;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ nodejs_22 ];

  env = {
    OPENCLAW_CONFIG_PATH = configFile;
    OPENCLAW_SRC = "${openclawGateway}/lib/openclaw";
    OPENCLAW_DOCUMENTS_TEXT = documentsKey;
    OPENCLAW_ENV_FILE_KEY = envFileKey;
    OPENCLAW_PLUGIN_ENTRY_KEY = pluginEntryKey;
    OPENCLAW_PLUGIN_SLOTS_KEY = pluginSlotsKey;
  };

  doCheck = true;
  checkPhase = "${nodejs_22}/bin/node ${../scripts/check-config-validity.mjs}";
  installPhase = "${../scripts/empty-install.sh}";
}
