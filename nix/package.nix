{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libnotify,
  libusb1,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  systemdLibs,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "chatgpt-desktop";
  version = "26.901.51231";

  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb";
    hash = "sha256-YlgBiNh8PTqTadq3xztCqKMlGNTfii1brmRm3erFwF4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
  ];

  # These are optional upstream compatibility shims/prebuilds. The Debian
  # package does not depend on Qt or musl and uses the glibc prebuilds here.
  autoPatchelfIgnoreMissingDeps = [
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
    "libc.musl-x86_64.so.1"
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libnotify
    libusb1
    libxkbcommon
    mesa
    nspr
    nss
    pango
    systemdLibs
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
  ];

  unpackPhase = ''
    runHook preUnpack
    ar x "$src"
    tar -xf data.tar.xz
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r usr/* "$out/"

    # Electron enables a Linux-only FD ownership assertion.  In the upstream
    # Linux preview it is tripped by the network-service process on NixOS,
    # turning a recoverable double-close into an immediate SIGILL/SIGTRAP.
    # This is the entry of CrashOnFdOwnershipViolation() for this exact
    # upstream binary (verified from its unique diagnostic string).  Make the
    # diagnostic routine a no-op, matching Electron builds with the assertion
    # disabled.  Keep the version and offset coupled above when updating src.
    printf '\303' | dd of="$out/lib/chatgpt/ChatGPT" bs=1 seek=$((0xcc448f0)) conv=notrunc status=none
    runHook postInstall
  '';

  meta = {
    description = "Official ChatGPT desktop app for Linux (preview)";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "chatgpt";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
