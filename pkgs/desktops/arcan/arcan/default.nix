{ lib
, stdenv
, fetchFromGitHub
, fetchgit
, SDL2
, cmake
, espeak
, file
, freetype
, glib
, gumbo
, harfbuzz
, jbig2dec
, leptonica
, libglvnd
, libdrm
, libffi
, libusb1
, libuvc
, libvlc
, libvncserver
, libxcb
, libxkbcommon
, lua5_1
, luajit
, makeWrapper
, mesa
, mupdf
, openal
, openjpeg
, pcre
, pkg-config
, sqlite
, tesseract
, valgrind
, wayland
, wayland-protocols
, xorg
, buildManPages ? true, ruby
, useBuiltinLua ? true
, useStaticFreetype ? true
, useStaticLibuvc ? true
, useStaticOpenAL ? true
, useStaticSqlite ? true
}:

let
  cmakeFeatureFlag = feature: flag:
    "-D${feature}=${if flag then "on" else "off"}";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "arcan" + lib.optionalString useStaticOpenAL "-static-openal";
  version = "7bf64a1bda2cdf82a2f172035df95235ad187e9d";

  src = fetchFromGitHub {
    owner = "letoram";
    repo = "arcan";
    rev = finalAttrs.version;
    hash = "sha256-DkYzaui6fcVm3YcWyzsxvcRqDx/cFZsWVgZ3rt0fWwE=";
  };

  nativeBuildInputs = [
    cmake
    makeWrapper
    pkg-config
  ] ++ lib.optionals buildManPages [
    ruby
  ];

  buildInputs = [
    freetype
    mesa
    libglvnd
    openal
    sqlite
    libxcb
    xorg.libX11
  ];

  patches = [
    # Nixpkgs-specific: redirect vendoring
    #./000-openal.patch
    #./001-luajit.patch
    #./002-libuvc.patch
    ./004-x11.patch
  ];

  # Emulate external/git/clone.sh
  postUnpack = let
    inherit (import ./clone-sources.nix { inherit fetchFromGitHub fetchgit; })
      letoram-openal-src freetype-src libuvc-src luajit-src;
  in
    ''
      pushd $sourceRoot/external/git/
    ''
    + (lib.optionalString useStaticOpenAL ''
      cp -a ${letoram-openal-src}/ openal
      chmod --recursive 744 openal
    '')
    + (lib.optionalString useStaticFreetype ''
      cp -a ${freetype-src}/ freetype
      chmod --recursive 744 freetype
    '')
    + (lib.optionalString useStaticLibuvc ''
      cp -a ${libuvc-src}/ libuvc
      chmod --recursive 744 libuvc
    '')
    + (lib.optionalString useBuiltinLua ''
      cp -a ${luajit-src}/ luajit
      chmod --recursive 744 luajit
    '') +
    ''
      popd
    '';

  postPatch = ''
    substituteInPlace ./src/platform/posix/paths.c \
      --replace "/usr/bin" "$out/bin" \
      --replace "/usr/share" "$out/share"

    substituteInPlace ./src/CMakeLists.txt --replace "SETUID" "# SETUID"
  '';

  # INFO: Arcan build scripts require the manpages to be generated before the
  # `configure` phase
  preConfigure = lib.optionalString buildManPages ''
    pushd doc
    ruby docgen.rb mangen
    popd
  '';

  cmakeFlags = [
    "-DBUILD_PRESET=everything"
    # The upstream project recommends tagging the distribution
    "-DDISTR_TAG=Nixpkgs"
    "-DENGINE_BUILDTAG=${finalAttrs.version}"
    (cmakeFeatureFlag "FT_DISABLE_BROTLI" true)
    (cmakeFeatureFlag "FT_DISABLE_BZIP2" true)
    (cmakeFeatureFlag "FT_DISABLE_HARFBUZZ" true)
    (cmakeFeatureFlag "FT_DISABLE_PNG" true)
    (cmakeFeatureFlag "FT_DISABLE_ZLIB" true)
    (cmakeFeatureFlag "FT_REQUIRE_BROTLI" false)
    (cmakeFeatureFlag "FT_REQUIRE_BZIP2" false)
    (cmakeFeatureFlag "FT_REQUIRE_HARFBUZZ" false)
    (cmakeFeatureFlag "FT_REQUIRE_PNG" false)
    (cmakeFeatureFlag "FT_REQUIRE_ZLIB" false)
    (cmakeFeatureFlag "HYBRID_SDL" true)
    (cmakeFeatureFlag "HYBRID_HEADLESS" true)
    (cmakeFeatureFlag "DISABLE_FSRV_GAME" true)
    (cmakeFeatureFlag "DISABLE_FSRV_NET" true)
    (cmakeFeatureFlag "DISABLE_FSRV_REMOTING" true)
    (cmakeFeatureFlag "DISABLE_FSRV_AVFEED" true)
    (cmakeFeatureFlag "DISABLE_WAYLAND" false)
    (cmakeFeatureFlag "BUILTIN_LUA" useBuiltinLua)
    (cmakeFeatureFlag "DISABLE_JIT" useBuiltinLua)
    (cmakeFeatureFlag "STATIC_FREETYPE" useStaticFreetype)
    (cmakeFeatureFlag "STATIC_LIBUVC" useStaticLibuvc)
    (cmakeFeatureFlag "STATIC_OPENAL" useStaticOpenAL)
    (cmakeFeatureFlag "STATIC_SQLite3" useStaticSqlite)
    "../src"
  ];

  hardeningDisable = [
    "format"
  ];

  meta = with lib; {
    homepage = "https://arcan-fe.com/";
    description = "Combined Display Server, Multimedia Framework, Game Engine";
    longDescription = ''
      Arcan is a portable and fast self-sufficient multimedia engine for
      advanced visualization and analysis work in a wide range of applications
      e.g. game development, real-time streaming video, monitoring and
      surveillance, up to and including desktop compositors and window managers.
    '';
    license = with licenses; [ bsd3 gpl2Plus lgpl2Plus ];
    maintainers = with maintainers; [ AndersonTorres ];
    platforms = platforms.unix;
  };
})
