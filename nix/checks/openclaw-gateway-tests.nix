{
  lib,
  stdenv,
  bun,
  vips,
  openclawGateway,
}:

stdenv.mkDerivation {
  pname = "openclaw-gateway-tests";
  version = lib.getVersion openclawGateway;

  src = openclawGateway.src;
  nativeBuildInputs = openclawGateway.nativeBuildInputs ++ [ bun ];
  buildInputs = (openclawGateway.buildInputs or [ ]) ++ [ vips ];

  env = {
    inherit (openclawGateway) pnpmDeps;
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
      # Match the main package build so tests use the Nix-built rolldown when available.
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
  checkPhase = ''
    export HOME="$(mktemp -d)"
    export TMPDIR="${HOME}/tmp"
    mkdir -p "$TMPDIR"
    export OPENCLAW_LOG_DIR="${TMPDIR}/openclaw-logs"
    mkdir -p "$OPENCLAW_LOG_DIR"
    mkdir -p /tmp/openclaw || true
    chmod 700 /tmp/openclaw || true
    if [ -d "$PWD/dist-runtime/extensions" ]; then
      export OPENCLAW_BUNDLED_PLUGINS_DIR="$PWD/dist-runtime/extensions"
    else
      unset OPENCLAW_BUNDLED_PLUGINS_DIR
    fi

    exec node node_modules/vitest/vitest.mjs run --config vitest.gateway.config.ts --testTimeout=20000
  '';

  installPhase = "${../scripts/empty-install.sh}";
}
