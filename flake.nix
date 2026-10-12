{
  description = "ChatGPT Desktop in a headless, SSH-tunnelled VNC session";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    apple-fonts = {
      url = "github:Lyndeno/apple-fonts.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
    claude-desktop-linux.url = "github:aaddrick/claude-desktop-debian";
  };

  outputs =
    {
      self,
      nixpkgs,
      apple-fonts,
      codex-desktop-linux,
      claude-desktop-linux,
    }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "chatgpt-desktop";
          };
          remoteFonts = with apple-fonts.packages.${system}; [
            sf-pro
            sf-mono
            ny
            sf-compact
            sf-arabic
            sf-armenian
            sf-georgian
            sf-hebrew
            pkgs.jetbrains-mono
          ];
        in
        rec {
          chatgpt-desktop = codex-desktop-linux.packages.${system}.codex-desktop;
          claude-desktop = claude-desktop-linux.packages.${system}.claude-desktop;
          chatgpt-remote = pkgs.callPackage ./nix/remote.nix {
            chatgpt = chatgpt-desktop;
            claudeDesktop = claude-desktop;
            fonts = remoteFonts;
            desktopCommand = "codex-desktop";
            claudeCommand = "claude-desktop";
            listenAddress = "128.105.102.153";
          };
          default = chatgpt-remote;
        }
      );

      nixosModules = rec {
        chatgpt-remote = import ./nix/module.nix {
          inherit apple-fonts codex-desktop-linux claude-desktop-linux;
        };
        default = chatgpt-remote;
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
