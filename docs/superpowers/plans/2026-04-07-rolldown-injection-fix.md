# Rolldown Injection Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent `openclaw-gateway` builds from silently replacing the upstream-pinned `rolldown` with an externally injected Nix package.

**Architecture:** Remove the accidental `rolldown` parameter from the gateway package interface, then delete the matching replacement logic from the main package build and the two Nix checks that mirrored it. Add one targeted Nix regression check that proves an explicit `rolldown = pkgs.rolldown` argument no longer changes the resulting derivation shape.

**Tech Stack:** Nix flakes, `callPackage`, derivation eval checks, `runCommandNoCC`

---

### Task 1: Add the failing regression check

**Files:**
- Create: `nix/checks/openclaw-rolldown-injection.nix`
- Modify: `flake.nix`

- [ ] **Step 1: Write the failing test**

```nix
{
  pkgs,
}:

let
  gateway = pkgs.callPackage ../packages/openclaw-gateway.nix {
    rolldown = pkgs.rolldown;
  };
in
pkgs.runCommandNoCC "openclaw-rolldown-injection" {
  buildInputsJson = builtins.toJSON (map toString (gateway.buildInputs or [ ]));
  rolldownPassthruJson = builtins.toJSON (gateway.rolldownPackage or null);
} ''
  if [ "$buildInputsJson" != "[]" ]; then
    echo "expected no injected rolldown build input, got: $buildInputsJson" >&2
    exit 1
  fi

  if [ "$rolldownPassthruJson" != "null" ]; then
    echo "expected no rolldown passthru, got: $rolldownPassthruJson" >&2
    exit 1
  fi

  touch "$out"
''
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nix build .#checks.x86_64-linux.rolldown-injection`
Expected: FAIL because the current package still accepts `rolldown`, exposes it via `passthru.rolldownPackage`, and adds it to `buildInputs`.

- [ ] **Step 3: Wire the check into the flake outputs**

```nix
rolldown-injection = pkgs.callPackage ./nix/checks/openclaw-rolldown-injection.nix {
  inherit pkgs;
};
```

- [ ] **Step 4: Re-run the failing check**

Run: `nix build .#checks.x86_64-linux.rolldown-injection`
Expected: still FAIL until the package fix lands.

### Task 2: Remove the injection hook from the gateway package

**Files:**
- Modify: `nix/packages/openclaw-gateway.nix`

- [ ] **Step 1: Remove the injectable package argument**

```nix
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
```

- [ ] **Step 2: Remove the build override logic**

```nix
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

    # In Nix sandbox, npm install has no network access. Patch the staging
    # script to accept version-mismatched deps from root node_modules
    # instead of falling back to npm install.
    sed -i 's/if (installedVersion === null || !dependencyVersionSatisfied(spec, installedVersion)) {/if (installedVersion === null) {/' scripts/stage-bundled-plugin-runtime-deps.mjs
    pnpm build
    pnpm ui:build

    runHook postBuild
  '';
```

- [ ] **Step 3: Remove the passthru field**

```nix
  passthru = {
    pnpmDeps = finalAttrs.pnpmDeps;
    updateScript = ./update.sh;
  };
```

- [ ] **Step 4: Run the regression check**

Run: `nix build .#checks.x86_64-linux.rolldown-injection`
Expected: PASS

### Task 3: Align the Nix checks with the package build

**Files:**
- Modify: `nix/checks/openclaw-gateway-tests.nix`
- Modify: `nix/checks/openclaw-config-options.nix`

- [ ] **Step 1: Remove the mirrored replacement block from gateway tests**

```nix
  buildPhase = ''
    runHook preBuild

    export HOME="$(mktemp -d)"
    export TMPDIR="$HOME/tmp"
    mkdir -p "$TMPDIR"

    pnpm install --offline --frozen-lockfile --ignore-scripts --prod=false

    pnpm build

    runHook postBuild
  '';
```

- [ ] **Step 2: Remove the mirrored replacement block from config-options check**

```nix
  buildPhase = ''
    runHook preBuild

    export HOME="$(mktemp -d)"
    export TMPDIR="$HOME/tmp"
    mkdir -p "$TMPDIR"

    pnpm install --offline --frozen-lockfile --ignore-scripts --prod=false

    pnpm build

    runHook postBuild
  '';
```

- [ ] **Step 3: Run the targeted verification set**

Run: `nix build .#checks.x86_64-linux.rolldown-injection .#packages.x86_64-linux.openclaw-gateway`
Expected: both succeed

- [ ] **Step 4: Re-evaluate the package shape**

Run: `nix eval '.#packages.x86_64-linux.openclaw-gateway.buildInputs'`
Expected: `[ ]`
