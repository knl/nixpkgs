{ lib
, fetchFromGitHub
, rustPlatform
, pkg-config
, extra-cmake-modules
, expat
, dbus
, libX11
, libXi
, libXtst
, libjpeg
, libnotify
, libpng
, libxkbcommon
, openssl
, xclip
, xdotool
, setxkbmap
, wl-clipboard
, wxGTK32
, xz
, makeWrapper
, stdenv
, AppKit
, Cocoa
, Foundation
, IOKit
, Kernel
, AVFoundation
, Carbon
, QTKit
, AVKit
, WebKit
, waylandSupport ? false
, x11Support ? stdenv.isLinux
, testers
, espanso
}:
# espanso does not support building with both X11 and Wayland support at the same time
assert stdenv.isLinux -> x11Support != waylandSupport;
assert stdenv.isDarwin -> !x11Support;
assert stdenv.isDarwin -> !waylandSupport;

let
  libs = lib.makeLibraryPath ([
    openssl
    expat
    libpng
    libjpeg
    xz
    wxGTK32
  ]);

in
rustPlatform.buildRustPackage rec {
  pname = "espanso";
  version = "2.1.8";

  src = fetchFromGitHub {
    owner = "espanso";
    repo = "espanso";
    rev = "v${version}";
    hash = "sha256-5TUo5B1UZZARgTHbK2+520e3mGZkZ5tTez1qvZvMnxs=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "yaml-rust-0.4.6" = "sha256-wXFy0/s4y6wB3UO19jsLwBdzMy7CGX4JoUt5V6cU7LU=";
    };
  };

  cargoPatches = lib.optionals stdenv.isDarwin [
    ./inject-wx-on-darwin.patch
  ];

  postPatch = lib.optionalString stdenv.isDarwin ''
    substituteInPlace scripts/create_bundle.sh \
      --replace target/mac/ $out/Applications/

    patchShebangs scripts/create_bundle.sh
  '';

  nativeBuildInputs = [
    extra-cmake-modules
    pkg-config
    makeWrapper
    wxGTK32
  ];

  # Ref: https://github.com/espanso/espanso/blob/78df1b704fe2cc5ea26f88fdc443b6ae1df8a989/scripts/build_binary.rs#LL49C3-L62C4
  buildNoDefaultFeatures = true;
  buildFeatures = [
    "modulo"
  ] ++ lib.optionals waylandSupport[
    "wayland"
  ] ++ lib.optionals stdenv.isLinux [
    "vendored-tls"
  ] ++ lib.optionals stdenv.isDarwin [
    "native-tls"
  ];

  buildInputs = [
    wxGTK32
  ] ++ lib.optionals stdenv.isLinux [
    openssl
    dbus
    libnotify
    libxkbcommon
  ] ++ lib.optionals stdenv.isDarwin [
    AppKit
    Cocoa
    Foundation
    IOKit
    Kernel
    AVFoundation
    Carbon
    QTKit
    AVKit
    WebKit
  ] ++ lib.optionals waylandSupport [
    wl-clipboard
  ] ++ lib.optionals x11Support [
    libXi
    libXtst
    libX11
    xclip
    xdotool
  ];

  # Some tests require networking
  doCheck = false;

  postInstall = lib.optionalString (!stdenv.isDarwin) ''
    wrapProgram $out/bin/espanso \
      --prefix PATH : ${lib.makeBinPath (
        lib.optionals stdenv.isLinux [
          libnotify
          setxkbmap
        ] ++ lib.optionals waylandSupport [
          wl-clipboard
        ] ++ lib.optionals x11Support [
          xclip
        ]
      )}
  '' + lib.optionalString stdenv.isDarwin ''
    EXEC_PATH=$out/bin/espanso BUILD_ARCH=current ${stdenv.shell} ./scripts/create_bundle.sh

    mv $out/Applications/Espanso.app/Contents/MacOS/espanso $out/Applications/Espanso.app/Contents/MacOS/.espanso
    makeWrapper $out/Applications/Espanso.app/Contents/MacOS/.espanso $out/Applications/Espanso.app/Contents/MacOS/espanso \
      --prefix LD_LIBRARY_PATH ":" ${libs}
  '';

  passthru.tests.version = testers.testVersion {
    package = espanso;
  };

  meta = with lib; {
    description = "Cross-platform Text Expander written in Rust";
    homepage = "https://espanso.org";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [ kimat thehedgeh0g ];
    platforms = platforms.unix;

    longDescription = ''
      Espanso detects when you type a keyword and replaces it while you're typing.
    '';
  };
}
