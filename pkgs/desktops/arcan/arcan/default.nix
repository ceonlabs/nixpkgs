{ lib
, stdenv
, fetchFromGitHub
, fetchgit
, cmake
, file
, glib
, gumbo
, jbig2dec
, leptonica
, libglvnd
, libdrm
, libffi
, libusb1
, libuvc
, lua5_1
, luajit
, libxkbcommon
, makeWrapper
, mesa
, openal
, openjpeg
, pcre
, pkg-config
, sqlite
, valgrind
, wayland
, wayland-protocols
, buildManPages ? true, ruby
, useBuiltinLua ? true
, useStaticFreetype ? true
, useStaticLibuvc ? true
, useStaticOpenAL ? true
, useStaticSqlite ? true
, xz
, xorg
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

 # buildInputs = [
 #   freetype
 #   mesa
 #   libglvnd
 #   openal
 #   sqlite
 #   libxcb
 #   xorg.libX11
 # ];

  buildInputs = [
    #ffmpeg
    xorg.libX11
    file
    libxkbcommon
    glib
    gumbo
    jbig2dec
    leptonica
    libglvnd
    libdrm
    libffi
    libusb1
    libuvc
    lua5_1
    luajit
    mesa
    openal
    openjpeg.dev
    pcre
    sqlite
    valgrind
    wayland
    wayland-protocols
    xz
  ];
  patches = [
    # Nixpkgs-specific: redirect vendoring
    #./000-openal.patch
    #./001-luajit.patch
    #./002-libuvc.patch
    #./004-x11.patch
    ./005-respect-hybrid.diff
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
    "-DVIDEO_PLATFORM=egl-dri"
    "-DAGP_PLATFORM=gl21"
    "-DENGINE_BUILDTAG=${finalAttrs.version}"
    "-DENABLE_LWA=OFF"
    "-DDISABLE_FSRV_NET=ON"
    "-DDISABLE_FSRV_TERMINAL=ON"
    "-DDISABLE_FSRV_REMOTING=ON"
    "-DDISABLE_FSRV_GAME=ON"
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
    (cmakeFeatureFlag "HYBRID_SDL" false)
    (cmakeFeatureFlag "HYBRID_HEADLESS" false)
    (cmakeFeatureFlag "DISABLE_WAYLAND" true)
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
