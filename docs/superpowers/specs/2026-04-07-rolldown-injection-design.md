## Summary

Fix the `openclaw-gateway` packaging so module and `callPackage` consumers cannot override the upstream-pinned `rolldown` version with `pkgs.rolldown`.

## Problem

`nix/packages/openclaw-gateway.nix` currently accepts `rolldown ? null`.
Because callers often instantiate it through `pkgs.callPackage`, any `pkgs.rolldown` in scope can be injected automatically.
When that injected package is older than the version pinned by upstream `pnpm-lock.yaml`, the build replaces the lockfile-resolved `rolldown` with an incompatible binary and fails with errors like `Unknown module type: copy`.

## Goals

- Always use the upstream lockfile's `rolldown` dependency graph during gateway builds.
- Make the main package and Nix checks follow the same dependency source.
- Prevent future regressions where `callPackage` silently reintroduces an external `rolldown` override.

## Non-Goals

- No broader changes to OpenClaw's build pipeline.
- No new version-resolution logic against `pnpm-lock.yaml`.
- No attempt to keep supporting externally injected `rolldown` packages.

## Design

### Package interface

Remove the `rolldown` argument from `nix/packages/openclaw-gateway.nix`.
This closes the accidental `callPackage` injection path.

### Build behavior

Remove the build-time block that deletes `node_modules/rolldown` and copies files from a Nix-provided `rolldown` package.
After `pnpm install --frozen-lockfile`, the build should keep using the dependency versions selected by upstream.

### Check behavior

Remove the matching `rolldownPackage` replacement blocks from:

- `nix/checks/openclaw-gateway-tests.nix`
- `nix/checks/openclaw-config-options.nix`

This keeps the checks aligned with the package build and avoids split behavior between package and tests.

### Regression coverage

Add a targeted Nix eval regression that instantiates `openclaw-gateway.nix` with an explicit `rolldown = pkgs.rolldown` argument and asserts the resulting derivation does not expose that override through `passthru` or build inputs.

## Verification

- Evaluate the new regression check and watch it fail before the fix.
- Apply the package and check changes.
- Re-run the regression check and confirm it passes.
- Re-evaluate `.#packages.x86_64-linux.openclaw-gateway.buildInputs` and confirm no external `rolldown` is present.

## Risks

- If any downstream consumer intentionally depended on the override hook, this is a breaking change.
- That break is acceptable because the hook bypasses upstream dependency pins and is the direct source of the build failure.
