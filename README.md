# ChatGPT Desktop, remotely on NixOS

This flake packages OpenAI's official Linux preview and provides a NixOS module
that runs it in a dedicated headless Wayland session. The launcher binds the
configured address and protects the VNC session with WayVNC authentication.

The upstream package currently supports Ubuntu, Debian, and Fedora—not NixOS.
This packaging is therefore best-effort and pins the exact upstream download.

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

The server uses WayVNC authentication plus a locally generated TLS certificate.
Because this is a public address, allow TCP/5900 only from trusted source IPs in
your firewall/security group. The password is read from the environment and is
never stored in the flake.

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
