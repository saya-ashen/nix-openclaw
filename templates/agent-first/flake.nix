{
  description = "OpenClaw local (homelab-first)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-openclaw,
      sops-nix,
    }:
    let
      # REPLACE: x86_64-linux (recommended for homelab) or aarch64-linux
      system = "<system>";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ nix-openclaw.overlays.default ];
      };
    in
    {
      # REPLACE: <user> with your username (run `whoami`)
      homeConfigurations."<user>" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          nix-openclaw.homeManagerModules.openclaw
          sops-nix.homeManagerModules.sops
          {
            # Required for Home Manager standalone
            home.username = "<user>";
            # REPLACE: /home/<user>
            home.homeDirectory = "<homeDir>";
            home.stateVersion = "24.11";
            programs.home-manager.enable = true;

            # Secrets are declared here and materialized by sops-nix.
            sops = {
              defaultSopsFile = ./secrets.yaml;
              age.keyFile = "<ageKeyPath>";

              secrets = {
                openclaw-gateway-token = { };
                telegram-bot-token = { };
                anthropic-api-key = { };
              };
            };

            programs.openclaw = {
              # Homelab default: keep AGENTS.md / SOUL.md / TOOLS.md outside Nix.
              manageDocuments = false;

              # Default package path: consume pkgs.openclaw from nixpkgs / overlay.
              package = pkgs.openclaw;

              config = {
                gateway = {
                  mode = "local";
                  auth.tokenFile = config.sops.secrets.openclaw-gateway-token.path;
                };

                providers.anthropic.apiKeyFile = config.sops.secrets.anthropic-api-key.path;

                channels.telegram = {
                  tokenFile = config.sops.secrets.telegram-bot-token.path;
                  allowFrom = [ <allowFrom> ];
                  groups."*".requireMention = true;
                };
              };

              # Keep the main path simple: one declared instance, declarative plugins.
              instances.default = {
                enable = true;

                plugins.hello-world = {
                  package = pkgs.mkOpenclawPlugin {
                    name = "hello-world";
                    src = pkgs.fetchFromGitHub {
                      owner = "acme";
                      repo = "hello-world";
                      rev = "<commit-or-tag>";
                      hash = "sha256-...";
                    };
                  };
                };

                # Example of plugin secrets via sops-managed files:
                # plugins.some-plugin = {
                #   package = pkgs.mkOpenclawPlugin { ... };
                #   env.SOME_PLUGIN_TOKEN_FILE = config.sops.secrets.some-plugin-token.path;
                # };
              };
            };
          }
        ];
      };
    };
}
