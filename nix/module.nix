{
  codex-desktop-linux,
  claude-desktop-linux,
}:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.chatgpt-remote;
  system = pkgs.stdenv.hostPlatform.system;
  chatgpt = codex-desktop-linux.packages.${system}.codex-desktop;
  claudeDesktop = claude-desktop-linux.packages.${system}.claude-desktop;
  start = pkgs.callPackage ./remote.nix {
    inherit chatgpt claudeDesktop;
    desktopCommand = "codex-desktop";
    claudeCommand = "claude-desktop";
    inherit (cfg)
      listenAddress
      port
      width
      height
      refresh
      extraArgs
      ;
  };
in
{
  options.services.chatgpt-remote = {
    enable = lib.mkEnableOption "a headless ChatGPT/Codex and Claude Desktop session reachable over VNC";

    user = lib.mkOption {
      type = lib.types.str;
      default = "chatgpt-remote";
      description = "Unprivileged system user that owns the desktop session.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "128.105.102.153";
      description = "VNC listen address. This is publicly reachable; use a firewall and strong credentials.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "chatgpt";
      description = "VNC authentication username.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = "Environment file containing WAYVNC_PASSWORD=... (mode 0600).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5900;
      description = "VNC TCP port.";
    };

    width = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1920;
      description = "Virtual display width.";
    };

    height = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1080;
      description = "Virtual display height.";
    };

    refresh = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "Virtual display refresh rate.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional command-line arguments passed to ChatGPT/Codex.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = "/var/lib/${cfg.user}";
      createHome = true;
    };
    users.groups.${cfg.user} = { };

    systemd.services.chatgpt-remote = {
      description = "Headless ChatGPT/Codex and Claude Desktop VNC session";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        HOME = "/var/lib/${cfg.user}";
        XDG_CONFIG_HOME = "/var/lib/${cfg.user}/.config";
        XDG_CACHE_HOME = "/var/lib/${cfg.user}/.cache";
        XDG_DATA_HOME = "/var/lib/${cfg.user}/.local/share";
        WAYVNC_USERNAME = cfg.username;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.user;
        ExecStart = lib.getExe start;
        Restart = "on-failure";
        RestartSec = 3;
        RuntimeDirectory = cfg.user;
        RuntimeDirectoryMode = "0700";
        StateDirectory = cfg.user;
        StateDirectoryMode = "0700";
        UMask = "0077";
        EnvironmentFile = cfg.passwordFile;
      };
    };
  };
}
