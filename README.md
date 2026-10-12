# ChatGPT Desktop, remotely on NixOS

This flake uses the NixOS-aware `codex-desktop-linux` and
`claude-desktop-debian` distributions and provides a headless Wayland session
for remote access. The launcher starts both ChatGPT/Codex and Claude Desktop,
binds the configured address, and protects the VNC session with WayVNC
authentication.

`codex-desktop-linux` verifies and repackages OpenAI's signed Linux payload,
then supplies the NixOS runtime and Bubblewrap integration. It shares the
upstream `Codex` profile with the official ChatGPT app, so do not run both at
the same time.

## Run without changing the host configuration

From this repository, run:

```console
WAYVNC_USERNAME=chatgpt WAYVNC_PASSWORD='choose-a-long-password' nix run
```

Keep that process running. From your remote computer, create an SSH tunnel:

```console
ssh -N -L 5900:127.0.0.1:5900 your-user@your-nixos-host
```

Point a VNC viewer at `128.105.102.153:5900` and enter the same username and
password. This runs as your current user, stores normal app state in your home
directory, and needs no rebuild, root access, or NixOS configuration change.
If you close the ChatGPT window, ChatGPT normally stays in the background. Press
`Ctrl+Alt+G` in the VNC session to invoke it again and reopen the hidden window.
Press `Ctrl+Alt+C` to reopen Claude Desktop. Use `Alt+Tab` to switch between the
two windows. A light, high-contrast system tray is shown at the upper-right of
the VNC desktop, so apps that minimize to the tray remain accessible. If either
process actually exits, the launcher restarts it. Stop the launcher with
`Ctrl-C`.

The server uses WayVNC authentication plus a locally generated TLS certificate.
Because this is a public address, allow TCP/5900 only from trusted source IPs in
your firewall/security group. The password is read from the environment and is
never stored in the flake.

The launcher also runs a private GNOME Keyring Secret Service for the VNC
session. On Claude's first request to save a secret, enter a keyring password in
the prompt shown in the VNC desktop. That password encrypts the session user's
keyring on disk; it is not the VNC password and is never supplied to the
launcher. The keyring remains unlocked only for the lifetime of the remote
desktop session. This works without enabling GNOME Keyring or PAM integration
in the host NixOS configuration.

The desktop runtime is supplied by the pinned `codex-desktop-linux` flake input;
update that input normally with `nix flake update codex-desktop-linux`.
The VNC desktop also supplies Apple's SF Pro, SF Mono, New York, SF Compact, and
localized SF families from `apple-fonts.nix`, plus JetBrains Mono. They are
available to both desktop applications through the session's Fontconfig setup.

## Optional: start automatically at boot

```nix
{
  inputs.chatgpt-remote.url = "path:/home/ljx/chatgpt";

  outputs = { nixpkgs, chatgpt-remote, ... }@inputs: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        chatgpt-remote.nixosModules.default
        ({ ... }: {
          services.chatgpt-remote.enable = true;
          services.chatgpt-remote.passwordFile = "/run/keys/chatgpt-vnc";
          services.openssh.enable = true;
        })
      ];
    };
  };
}
```

Rebuild the host, then create the same tunnel from your remote computer:

```console
ssh -N -L 5900:127.0.0.1:5900 your-user@your-nixos-host
```

Point a VNC viewer at `128.105.102.153:5900`. The first connection shows the normal
ChatGPT login flow. App state persists in `/var/lib/chatgpt-remote`.

Useful checks on the host:

```console
systemctl status chatgpt-remote
journalctl -u chatgpt-remote -f
```

The module also exposes `port`, `width`, `height`, `refresh`, `user`, and
`extraArgs`. Do not change `listenAddress` from `127.0.0.1` unless you separately
configure authenticated transport and a firewall.

## Desktop package only

```console
nix build .#chatgpt-desktop
nix run .#chatgpt-desktop
```

The package is x86_64-only because this repository currently pins the official
AMD64 `.deb`.
