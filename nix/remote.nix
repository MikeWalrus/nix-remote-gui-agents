{
  lib,
  makeFontsConf,
  writeShellApplication,
  coreutils,
  dbus,
  firefox,
  fuse3,
  gsettings-desktop-schemas,
  gnome-keyring,
  gtk3,
  labwc,
  openssl,
  polkit_gnome,
  wayvnc,
  waybar,
  wlr-randr,
  xdg-desktop-portal,
  xdg-desktop-portal-gtk,
  codexDesktop,
  claudeDesktop,
  fonts ? [ ],
  codexCommand ? "codex-desktop",
  claudeCommand ? "claude-desktop",
  listenAddress ? "127.0.0.1",
  port ? 5900,
  width ? 1920,
  height ? 1080,
  refresh ? 60,
  extraArgs ? [ ],
}:

let
  fontConfig = makeFontsConf {
    fontDirectories = fonts;
  };
  firefoxLauncher = writeShellApplication {
    name = "ai-desktop-firefox";
    runtimeInputs = [
      coreutils
      firefox
    ];
    text = ''
      profile_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/ai-desktop-remote/firefox"
      mkdir -p "$profile_dir"
      exec env MOZ_ENABLE_WAYLAND=1 firefox --no-remote --profile "$profile_dir" "$@"
    '';
  };
  waybarConfig = builtins.toFile "chatgpt-remote-waybar.json" (
    builtins.toJSON {
      layer = "top";
      position = "top";
      height = 36;
      "modules-right" = [ "tray" ];
      tray = {
        icon-size = 26;
        spacing = 12;
      };
    }
  );
  waybarStyle = builtins.toFile "chatgpt-remote-waybar.css" ''
    window#waybar {
      background: #f8fafc;
      color: #0f172a;
      border-bottom: 1px solid #cbd5e1;
    }
    #tray {
      padding: 0 14px;
    }
  '';
  rcXml = builtins.toFile "chatgpt-remote-rc.xml" ''
    <?xml version="1.0"?>
    <labwc_config>
      <keyboard>
        <keybind key="C-A-g">
          <action name="Execute">
            <command>${codexCommand} --ozone-platform=wayland --enable-features=UseOzonePlatform --disable-gpu --password-store=basic</command>
          </action>
        </keybind>
        <keybind key="C-A-c">
          <action name="Execute">
            <command>env CLAUDE_USE_WAYLAND=1 ${claudeCommand} --ozone-platform=wayland --enable-features=UseOzonePlatform --disable-gpu</command>
          </action>
        </keybind>
        <keybind key="C-A-f">
          <action name="Execute">
            <command>ai-desktop-firefox</command>
          </action>
        </keybind>
      </keyboard>
      <windowRules>
        <windowRule identifier="*">
          <action name="Maximize" />
        </windowRule>
        <windowRule title="Authenticate">
          <action name="ToggleMaximize" />
          <action name="Raise" />
          <action name="Focus" />
        </windowRule>
      </windowRules>
    </labwc_config>
  '';
in
writeShellApplication {
  name = "ai-desktop-remote";
  runtimeInputs = [
    codexDesktop
    claudeDesktop
    firefoxLauncher
    coreutils
    dbus
    fuse3
    gsettings-desktop-schemas
    gnome-keyring
    gtk3
    labwc
    openssl
    polkit_gnome
    wayvnc
    waybar
    wlr-randr
    xdg-desktop-portal
    xdg-desktop-portal-gtk
  ]
  ++ fonts;
  text = ''
    # D-Bus reads its service directories when it starts, so export the portal
    # locations before creating our private session bus.
    export XDG_DATA_DIRS="${xdg-desktop-portal}/share:${xdg-desktop-portal-gtk}/share:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:${gtk3}/share/gsettings-schemas/${gtk3.name}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    export XDG_CURRENT_DESKTOP=labwc
    if test -z "''${DBUS_SESSION_BUS_ADDRESS:-}"; then
      exec dbus-run-session -- "$0" "$@"
    fi

    runtime_base="''${XDG_RUNTIME_DIR:-}"
    if test -z "$runtime_base"; then
      runtime_uid="$(id -u)"
      runtime_base="/tmp/chatgpt-remote-$runtime_uid"
    fi
    XDG_RUNTIME_DIR="$runtime_base/chatgpt-remote-session"
    export XDG_RUNTIME_DIR
    TMPDIR="$XDG_RUNTIME_DIR/tmp"
    TMP="$TMPDIR"
    export TMPDIR TMP
    mkdir -p "$XDG_RUNTIME_DIR" "$TMPDIR"
    chmod 700 "$XDG_RUNTIME_DIR"

    config_dir="$XDG_RUNTIME_DIR/chatgpt-remote-labwc"
    mkdir -p "$config_dir"
    cp --remove-destination ${rcXml} "$config_dir/rc.xml"

    : "''${WAYVNC_USERNAME:?Set WAYVNC_USERNAME before starting}"
    : "''${WAYVNC_PASSWORD:?Set WAYVNC_PASSWORD before starting}"
    cert_dir="$XDG_RUNTIME_DIR/wayvnc-tls"
    mkdir -p "$cert_dir"
    chmod 700 "$cert_dir"
    if ! test -s "$cert_dir/key.pem" || ! test -s "$cert_dir/cert.pem"; then
      openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -subj "/CN=chatgpt-remote" \
        -keyout "$cert_dir/key.pem" -out "$cert_dir/cert.pem" >/dev/null 2>&1
      chmod 600 "$cert_dir/key.pem" "$cert_dir/cert.pem"
    fi
    wayvnc_config="$config_dir/wayvnc.conf"
    cat > "$wayvnc_config" <<EOF
    address=${listenAddress}
    port=${toString port}
    enable_auth=true
    username=$WAYVNC_USERNAME
    password=$WAYVNC_PASSWORD
    private_key_file=$cert_dir/key.pem
    certificate_file=$cert_dir/cert.pem
    EOF
    chmod 600 "$wayvnc_config"

    export WLR_BACKENDS=headless
    export WLR_LIBINPUT_NO_DEVICES=1
    export WLR_RENDERER=pixman
    export WAYLAND_DISPLAY=wayland-0
    export NIXOS_OZONE_WL=1
    export FONTCONFIG_FILE=${fontConfig}
    # Start a Secret Service on this private D-Bus session. This gives Claude a
    # real GNOME Keyring without depending on the host's desktop or PAM setup.
    keyring_environment="$(gnome-keyring-daemon --start --components=secrets)"
    eval "$keyring_environment"
    keyring_pid="''${GNOME_KEYRING_PID:-}"

    labwc --config-dir "$config_dir" &
    compositor_pid="$!"
    codex_pid=""
    claude_pid=""
    server_pid=""
    tray_pid=""
    polkit_agent_pid=""
    cleanup() {
      test -z "$server_pid" || kill "$server_pid" 2>/dev/null || true
      test -z "$codex_pid" || kill "$codex_pid" 2>/dev/null || true
      test -z "$claude_pid" || kill "$claude_pid" 2>/dev/null || true
      test -z "$tray_pid" || kill "$tray_pid" 2>/dev/null || true
      test -z "$polkit_agent_pid" || kill "$polkit_agent_pid" 2>/dev/null || true
      test -z "$keyring_pid" || kill "$keyring_pid" 2>/dev/null || true
      kill "$compositor_pid" 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    for _ in $(seq 1 100); do
      if test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"; then
        break
      fi
      sleep 0.1
    done

    if ! test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"; then
      echo "Wayland compositor did not become ready" >&2
      exit 1
    fi

    wlr-randr --output HEADLESS-1 --custom-mode ${toString width}x${toString height}@${toString refresh}Hz

    # Register a Polkit agent on this session bus. Authorization prompts then
    # appear in the VNC desktop and still require the host user's password.
    ${polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 &
    polkit_agent_pid="$!"

    waybar --config ${waybarConfig} --style ${waybarStyle} &
    tray_pid="$!"

    launch_codex() {
      ${codexCommand} \
        --ozone-platform=wayland \
        --enable-features=UseOzonePlatform \
        --disable-gpu \
        --password-store=basic \
        ${lib.escapeShellArgs extraArgs} &
      codex_pid="$!"
    }
    launch_claude() {
      CLAUDE_USE_WAYLAND=1 ${claudeCommand} \
        --ozone-platform=wayland \
        --enable-features=UseOzonePlatform \
        --disable-gpu &
      claude_pid="$!"
    }
    launch_codex
    launch_claude
    codex_restart_count=0
    claude_restart_count=0

    echo "Codex and Claude Desktop are available via VNC at ${listenAddress}:${toString port}" >&2
    wayvnc --config="$wayvnc_config" --output=HEADLESS-1 &
    server_pid="$!"
    while kill -0 "$server_pid" 2>/dev/null; do
      if test -n "$codex_pid" && ! kill -0 "$codex_pid" 2>/dev/null; then
        codex_restart_count=$((codex_restart_count + 1))
        if test "$codex_restart_count" -lt 4; then
          echo "Codex Desktop exited; restarting it" >&2
          sleep 1
          launch_codex
        else
          echo "Codex Desktop crashed repeatedly; leaving the VNC session running" >&2
          codex_pid=""
        fi
      fi
      if test -n "$claude_pid" && ! kill -0 "$claude_pid" 2>/dev/null; then
        claude_restart_count=$((claude_restart_count + 1))
        if test "$claude_restart_count" -lt 4; then
          echo "Claude Desktop exited; restarting it" >&2
          sleep 1
          launch_claude
        else
          echo "Claude Desktop crashed repeatedly; leaving the VNC session running" >&2
          claude_pid=""
        fi
      fi
      sleep 1
    done
  '';

  meta = {
    description = "Run Codex and Claude Desktop with a system tray in a rootless headless VNC session";
    mainProgram = "ai-desktop-remote";
  };
}
