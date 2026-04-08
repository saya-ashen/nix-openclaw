# OpenClaw Plugin Architecture (Maintainer Memo)

Purpose: extend OpenClaw capabilities without bloating core; ship tools + skills + config as reproducible units you can pin, test, and roll back. nix-openclaw shows the contract; OpenClaw core should treat the same interface as first-class, even off-Nix.

## What a Plugin Is (and is not)
- **Is:** bundle of binaries/CLIs, skills that teach the agent to use them, optional config/env requirements.
- **Not:** new transports/providers; model plumbing; secrets baked in; inline scripts or ad-hoc package-manager installs; a place for random config outside its scope.
- Why not skills-only: skills without binaries can hallucinate capability. Plugins ground skills in real tools and deliver versioned, reproducible functionality.

## Interface Contract (reference implementation: nix-openclaw)
Every plugin artifact exposes the same fields through `pkgs.mkOpenclawPlugin`, stored in `passthru.openclawPlugin` (host-agnostic shape):

```nix
plugin = pkgs.mkOpenclawPlugin {
  name        = "summarize";                # unique; last-wins on collision
  src         = ./.;                         # plugin source tree
  skills      = [ ./skills/summarize ];      # dirs containing SKILL.md
  packages    = [ pkgs.summarize-cli ];      # binaries placed on PATH
  needs = {
    stateDirs   = [ ".config/summarize" ]; # created under $HOME
    requiredEnv = [ "SUMMARIZE_API_KEY" ];  # must point to files
  };
};
```

Host responsibilities (what the runtime guarantees):
- Build/resolve the plugin package; read `passthru.openclawPlugin`.
- Install `packages`; prepend to PATH for the gateway wrapper.
- Create `needs.stateDirs` under `$HOME`.
- Fail fast if any `requiredEnv` is unset or points to a missing/empty file.
- Copy/symlink `skills` into `workspace/skills/<name>/...`.
- If host config provides `settings`, render it to `openclaw.json.plugins.entries.<plugin>.config` and also to `config.json` in the first `stateDir` when one exists.
- Export `env` (plus required envs) into the gateway wrapper.
- Reject duplicate skill paths; duplicate plugin names: last entry wins.

### Host-side config shape
When enabling a plugin, the host can supply:

```nix
programs.openclaw.plugins = {
  _slots.memory = "repo";

  repo = {
    package = pkgs.mkOpenclawPlugin {
      name = "repo";
      src = pkgs.fetchFromGitHub {
        owner = "owner";
        repo = "repo";
        rev = "<commit-or-tag>";
        hash = "sha256-...";
      };
    };
    env = { KEY = "/run/agenix/key"; EXTRA = "/path/to/file"; };
    settings = { foo = "bar"; retries = 3; };
  };
};
```

- `_slots`: runtime slot assignments such as `memory` or `contextEngine`.
- `env`: values for `requiredEnv` (and any extra env to export).
- `settings`: JSON-rendered into `openclaw.json.plugins.entries.<plugin>.config`, and into `config.json` inside the first `stateDir` when one exists.
- Invariant: `env` still follows the declared `requiredEnv`; `stateDir` is only needed when the plugin also expects on-disk state or a mirrored `config.json`.

## Dev workflow (fast iteration)
- Worktree: build and test plugins outside the core repo; point OpenClaw at a local package (`package = pkgs.mkOpenclawPlugin { name = "my-plugin"; src = /Users/you/code/my-plugin; }`).
- Rebuild loop: change plugin → `home-manager switch` (or host-equivalent) → gateway restarts with new PATH/skills/config; no manual copying.
- Name collisions: use the same plugin `name` to override a pinned version (last entry wins); keep unique names otherwise to avoid surprise overrides.
- Skills placement: skills land under `~/.openclaw*/workspace/skills/<plugin>/...` so you can inspect quickly; delete the workspace to fully reset cached skills.
- Env guardrails: required env vars must point to files (non-empty) or the activation fails—supply temp files during dev to exercise the checks.
- Settings JSON: inspect the rendered plugin entry in `openclaw.json` and, when present, the mirrored `config.json` in the first `stateDir` to confirm schema and defaults before committing.

## Examples

### Minimal capability plugin (bundled `summarize`)
Enable (host side):

```nix
programs.openclaw.plugins.summarize = {
  package = pkgs.mkOpenclawPlugin {
    name = "summarize";
    src = pkgs.fetchTree {
      type = "github";
      owner = "openclaw";
      repo = "nix-steipete-tools";
      dir = "tools/summarize";
      rev = "<pinned-rev>";
      narHash = "sha256-...";
    };
  };
};
```

Plugin contract (inside the plugin repo):

```nix
openclawPlugin = {
  name = "summarize";
  skills = [ ./skills/summarize ];
  packages = [ self.packages.${system}.summarize-cli ];
  needs = { stateDirs = []; requiredEnv = []; };
};
```

### Plugin with required config/env (community `xuezh`)
Enable (host side):

```nix
programs.openclaw.plugins.xuezh = {
  package = pkgs.mkOpenclawPlugin {
    name = "xuezh";
    src = pkgs.fetchFromGitHub {
      owner = "joshp123";
      repo = "xuezh";
      rev = "<commit-or-tag>";
      hash = "sha256-...";
    };
  };
  env = {
    # Required envs (guarded as files):
    XUEZH_AZURE_SPEECH_KEY_FILE = "/run/agenix/xuezh-azure-speech-key";
    XUEZH_AZURE_SPEECH_REGION   = "/run/agenix/xuezh-azure-speech-region"; # file containing e.g. "westeurope"
  };
  settings = {
    audio = {
      backend_global        = "azure.speech";
      process_voice_backend = "azure.speech";
      convert_backend       = "ffmpeg";
      tts_backend           = "edge-tts";
      inline_max_bytes      = 200000;
    };
    azure = {
      speech = {
        key_file = "/run/agenix/xuezh-azure-speech-key";
        region   = "westeurope";
      };
    };
  };
};
```

Plugin contract (inside `xuezh`):

```nix
openclawPlugin = {
  name = "xuezh";
  skills = [ ./skills/xuezh ];
  packages = [ self.packages.${system}.default ];
  needs = {
    stateDirs   = [ ".config/xuezh" ];
    requiredEnv = [ "XUEZH_AZURE_SPEECH_KEY_FILE" "XUEZH_AZURE_SPEECH_REGION" ];
  };
};
```

Host behavior: writes `settings` to `openclaw.json.plugins.entries.xuezh.config`, mirrors them to `~/.config/xuezh/config.json`, exports both envs, and fails if the pointed files are missing/empty.

## Bundled Plugin Set (current)
- summarize, peekaboo, poltergeist, sag, camsnap, gogcli, goplaces, bird, sonoscli, imsg.
- Source of truth: `nix/modules/home-manager/openclaw/plugin-catalog.nix`.
- Each follows the same contract: packages + skills; env/state declared via `needs`; host wiring comes from `programs.openclaw.plugins`; sources are typically pinned in Nix.

## Authoring Rules
- Keep CLIs configurable via env; honor XDG paths; no inline scripts.
- Ship `AGENTS.md` in the plugin repo with knobs/paths (no secrets).
- `SKILL.md` should call the CLI by its PATH name (no absolute paths).
- Declare a `stateDir` only when the plugin also needs an on-disk `config.json` mirror or other persistent files.
- Add CI to build the plugin and validate `requiredEnv`/`stateDir` invariants.

## Why this approach
- Capability grounding: skills map to real tools, not hypothetical ones.
- Reproducibility: versioned bundle of tool + skill + config schema; easy rollback.
- Clean core: main OpenClaw stays transport/model-focused; plugins carry integrations.
- Operational sanity: one toggle wires tools, env, skills; failure is explicit and early.
- Portability: contract is host-agnostic; Nix just enforces determinism and zero drift.
