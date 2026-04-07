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
          default = { };
        };
      };
    };

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
              instances.default = {
                envFile = "/tmp/openclaw-test.env";
              };
              documents = pkgs.writeTextDir "documents/AGENTS.md" "# Agent\n"
                // pkgs.writeTextDir "documents/SOUL.md" "# Soul\n"
                // pkgs.writeTextDir "documents/TOOLS.md" "# Tools\n";
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
  envFileKey = builtins.deepSeq hasEnvFileVar "ok";

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
  };

  doCheck = true;
  checkPhase = "${nodejs_22}/bin/node ${../scripts/check-config-validity.mjs}";
  installPhase = "${../scripts/empty-install.sh}";
}
