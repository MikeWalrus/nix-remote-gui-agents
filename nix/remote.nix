{
  lib,
  writeShellApplication,
  coreutils,
  dbus,
  labwc,
  openssl,
  wayvnc,
  wlr-randr,
  chatgpt,
  listenAddress ? "127.0.0.1",
  port ? 5900,
  width ? 1920,
  height ? 1080,
  refresh ? 60,
  extraArgs ? [ ],
}:

let
  rcXml = builtins.toFile "chatgpt-remote-rc.xml" ''
    <?xml version="1.0"?>
    <labwc_config>
      <keyboard>
        <keybind key="C-A-g">
          <action name="Execute">
            <command>chatgpt --ozone-platform=wayland --enable-features=UseOzonePlatform --disable-gpu --disable-crashpad-for-testing --password-store=basic</command>
          </action>
        </keybind>
      </keyboard>
      <windowRules>
        <windowRule identifier="*">
          <action name="Maximize" />
        </windowRule>
      </windowRules>
    </labwc_config>
  '';
in
writeShellApplication {
  name = "chatgpt-remote";
  runtimeInputs = [
    chatgpt
    coreutils
    dbus
    labwc
    openssl
    wayvnc
    wlr-randr
  ];
  text = ''
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

    labwc --config-dir "$config_dir" &
    compositor_pid="$!"
    app_pid=""
    server_pid=""
    cleanup() {
      test -z "$server_pid" || kill "$server_pid" 2>/dev/null || true
      test -z "$app_pid" || kill "$app_pid" 2>/dev/null || true
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

    launch_chatgpt() {
      chatgpt \
        --ozone-platform=wayland \
        --enable-features=UseOzonePlatform \
        --disable-gpu \
        --disable-crashpad-for-testing \
        --password-store=basic \
        ${lib.escapeShellArgs extraArgs} &
      app_pid="$!"
    }
    launch_chatgpt
    restart_count=0

    echo "ChatGPT is available via VNC at ${listenAddress}:${toString port}" >&2
    wayvnc --config="$wayvnc_config" --output=HEADLESS-1 &
    server_pid="$!"
    while kill -0 "$server_pid" 2>/dev/null; do
      if ! kill -0 "$app_pid" 2>/dev/null; then
        restart_count=$((restart_count + 1))
        if test "$restart_count" -ge 4; then
          echo "ChatGPT crashed repeatedly; stopping after 4 launches" >&2
          exit 1
        fi
        echo "ChatGPT exited; restarting it" >&2
        sleep 1
        launch_chatgpt
      fi
      sleep 1
    done
  '';

  meta = {
    description = "Run ChatGPT Desktop in a rootless headless VNC session";
    mainProgram = "chatgpt-remote";
  };
}
