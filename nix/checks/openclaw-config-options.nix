{
  lib,
  pkgs,
  stdenv,
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

  pluginEval = lib.evalModules {
    modules = [
      stubModule
      ../modules/home-manager/openclaw.nix
      (
        { lib, options, ... }:
        {
          config = {
            home.homeDirectory = "/tmp";
            programs.git.enable = false;
            lib.file.mkOutOfStoreSymlink = path: path;
            programs.openclaw = {
              enable = true;
              launchd.enable = false;
              systemd.enable = false;
              plugins.example-plugin = {
                package = pkgs.mkOpenclawPlugin {
                  name = "example-plugin";
                  src = builtins.path {
                    name = "example-plugin-src";
                    path = pkgs.writeTextDir "manifest.json" "{}\n";
                  };
                };
              };
              instances.default.plugins = {
                _slots.memory = "example-plugin";
              };
            };
          };
        }
      )
    ];
    specialArgs = { inherit pkgs; };
  };

  pluginEvalKey = builtins.deepSeq pluginEval.config.assertions "ok";
in
stdenv.mkDerivation {
  pname = "openclaw-config-options";
  version = lib.getVersion openclawGateway;

  src = openclawGateway.src;
  nativeBuildInputs = openclawGateway.nativeBuildInputs;
  buildInputs = openclawGateway.buildInputs or [ ];

  env = {
    inherit (openclawGateway) pnpmDeps;
    CONFIG_OPTIONS_GENERATOR = "${../scripts/generate-config-options.ts}";
    CONFIG_OPTIONS_GOLDEN = "${../generated/openclaw-config-options.nix}";
    NODE_ENGINE_CHECK = "${../scripts/check-node-engine.ts}";
    OPENCLAW_PLUGIN_EVAL = pluginEvalKey;
    OPENCLAW_SCHEMA_REV = lib.getVersion openclawGateway;
  };

  postPatch = ''
    if [ -f package.json ]; then
      sed -i '/"packageManager"[[:space:]]*:/d' package.json
    fi

    if [ -f scripts/stage-bundled-plugin-runtime-deps.mjs ]; then
      sed -i 's/if (installedVersion === null || !dependencyVersionSatisfied(spec, installedVersion)) {/if (installedVersion === null) {/' scripts/stage-bundled-plugin-runtime-deps.mjs
    fi
  '';

  buildPhase = ''
    runHook preBuild

    export HOME="$(mktemp -d)"
    export TMPDIR="$HOME/tmp"
    mkdir -p "$TMPDIR"

    pnpm install --offline --frozen-lockfile --ignore-scripts --prod=false

    ${lib.optionalString ((openclawGateway.rolldownPackage or null) != null) ''
      rm -rf node_modules/rolldown node_modules/@rolldown/pluginutils
      mkdir -p node_modules/@rolldown node_modules/.pnpm/node_modules/@rolldown
      cp -r ${openclawGateway.rolldownPackage}/lib/node_modules/rolldown node_modules/rolldown
      cp -r ${openclawGateway.rolldownPackage}/lib/node_modules/@rolldown/pluginutils node_modules/@rolldown/pluginutils
      cp -r ${openclawGateway.rolldownPackage}/lib/node_modules/rolldown node_modules/.pnpm/node_modules/rolldown
      cp -r ${openclawGateway.rolldownPackage}/lib/node_modules/@rolldown/pluginutils node_modules/.pnpm/node_modules/@rolldown/pluginutils
      chmod -R u+w node_modules/rolldown node_modules/@rolldown/pluginutils \
        node_modules/.pnpm/node_modules/rolldown node_modules/.pnpm/node_modules/@rolldown/pluginutils
    ''}

    pnpm build

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = "${../scripts/config-options-check.sh}";

  installPhase = "${../scripts/empty-install.sh}";
}
