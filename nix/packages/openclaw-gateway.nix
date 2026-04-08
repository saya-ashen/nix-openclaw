{
  lib,
  stdenvNoCC,
  buildPackages,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_22,
  makeWrapper,
  versionCheckHook,
  installShellFiles,
  gatewaySrc ? null,
  version ?
    if gatewaySrc == null
    then "2026.4.5"
    else "unstable",
  srcHash ? "sha256-dpBLqxSsSlvyaAG6DV/D/BSvrca93LtF4ritnlGZSho=",
  pnpmDepsHash ? "sha256-sBpaoGacWmipWmnKmdVTKu/T8mzOQFAIX0VKORiHvUc=",
}:
stdenvNoCC.mkDerivation (finalAttrs: let
  resolvedSrc =
    if gatewaySrc != null
    then gatewaySrc
    else
      fetchFromGitHub {
        owner = "openclaw";
        repo = "openclaw";
        tag = "v${finalAttrs.version}";
        hash = srcHash;
      };
  rolldown = null;
in {
  pname = "openclaw";
  inherit version;

  src = resolvedSrc;

  inherit pnpmDepsHash;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = finalAttrs.pnpmDepsHash;
  };

  nativeBuildInputs = [
    pnpmConfigHook
    pnpm_10
    nodejs_22
    makeWrapper
    installShellFiles
  ];

  buildPhase = ''
    runHook preBuild

    pnpm install --frozen-lockfile

    ${lib.optionalString (rolldown != null) ''
      # Replace pnpm-installed rolldown with the Nix-built version when available.
      rm -rf node_modules/rolldown node_modules/@rolldown/pluginutils
      mkdir -p node_modules/@rolldown node_modules/.pnpm/node_modules/@rolldown
      cp -r ${rolldown}/lib/node_modules/rolldown node_modules/rolldown
      cp -r ${rolldown}/lib/node_modules/@rolldown/pluginutils node_modules/@rolldown/pluginutils
      cp -r ${rolldown}/lib/node_modules/rolldown node_modules/.pnpm/node_modules/rolldown
      cp -r ${rolldown}/lib/node_modules/@rolldown/pluginutils node_modules/.pnpm/node_modules/@rolldown/pluginutils
      chmod -R u+w node_modules/rolldown node_modules/@rolldown/pluginutils \
        node_modules/.pnpm/node_modules/rolldown node_modules/.pnpm/node_modules/@rolldown/pluginutils
    ''}

    # In Nix sandbox, npm install has no network access. Patch the staging
    # script to accept version-mismatched deps from root node_modules
    # instead of falling back to npm install.
    sed -i 's/if (installedVersion === null || !dependencyVersionSatisfied(spec, installedVersion)) {/if (installedVersion === null) {/' scripts/stage-bundled-plugin-runtime-deps.mjs
    pnpm build
    pnpm ui:build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    libdir=$out/lib/openclaw
    mkdir -p $libdir $out/bin

    cp --reflink=auto -r package.json dist node_modules $libdir/
    cp --reflink=auto -r assets docs skills patches extensions $libdir/

    rm -f $libdir/node_modules/.pnpm/node_modules/clawdbot \
      $libdir/node_modules/.pnpm/node_modules/moltbot \
      $libdir/node_modules/.pnpm/node_modules/openclaw-control-ui

    # Remove broken symlinks created by pnpm workspace linking in extensions
    find $libdir/extensions -xtype l -delete

    makeWrapper ${lib.getExe nodejs_22} $out/bin/openclaw \
      --add-flags "$libdir/dist/index.js" \
      --set NODE_PATH "$libdir/node_modules"
    ln -s $out/bin/openclaw $out/bin/moltbot
    ln -s $out/bin/openclaw $out/bin/clawdbot

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenvNoCC.hostPlatform.emulatorAvailable buildPackages) (
    let
      emulator = stdenvNoCC.hostPlatform.emulator buildPackages;
    in ''
      installShellCompletion --cmd openclaw \
        --bash <(${emulator} $out/bin/openclaw completion --shell bash) \
        --fish <(${emulator} $out/bin/openclaw completion --shell fish) \
        --zsh <(${emulator} $out/bin/openclaw completion --shell zsh)
    ''
  );

  nativeInstallCheckInputs = [versionCheckHook];
  doInstallCheck = true;

  passthru = {
    pnpmDeps = finalAttrs.pnpmDeps;
    rolldownPackage = rolldown;
    updateScript = ./update.sh;
  };

  meta = {
    description = "Self-hosted, open-source AI assistant/agent";
    longDescription = ''
      Self-hosted AI assistant/agent connected to all your apps on your Linux
      or macOS machine and controlled via your choice of chat app.

      Note: Project is in early/rapid development and uses LLMs to parse untrusted
      content while having full access to system by default.

      Parsing untrusted input with LLMs leaves them vulnerable to prompt injection.

      (Originally known as Moltbot and ClawdBot)
    '';
    homepage = "https://openclaw.ai";
    changelog =
      if gatewaySrc == null
      then "https://github.com/openclaw/openclaw/releases/tag/v${version}"
      else null;
    license = lib.licenses.mit;
    mainProgram = "openclaw";
    maintainers = with lib.maintainers; [
      chrisportela
      mkg20001
    ];
    platforms = with lib.platforms; linux ++ darwin;
  };
})
