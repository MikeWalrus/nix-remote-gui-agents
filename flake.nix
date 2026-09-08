{
  description = "ChatGPT Desktop in a headless, SSH-tunnelled VNC session";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
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
        in
        rec {
          chatgpt-desktop = pkgs.callPackage ./nix/package.nix { };
          chatgpt-remote = pkgs.callPackage ./nix/remote.nix {
            chatgpt = chatgpt-desktop;
            listenAddress = "128.105.102.153";
          };
          default = chatgpt-remote;
        }
      );

      nixosModules = rec {
        chatgpt-remote = import ./nix/module.nix;
        default = chatgpt-remote;
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
