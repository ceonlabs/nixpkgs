{ version, hash }:

{ stdenv, lib, fetchurl, fetchpatch
, meson, pkg-config, ninja
, fetchFromGitLab
, intltool, bison, flex, file, python3Packages
, expat, libdrm, xorg
, llvmPackages_15
, libelf
, libglvnd
#, vulkan-loader, glslang
, galliumDrivers ? ["swrast" "asahi"]
, vulkanDrivers ? ["swrast"]
, eglPlatforms ? [ ]
, vulkanLayers ? [ ]
, withValgrind ? lib.meta.availableOn stdenv.hostPlatform valgrind-light && !valgrind-light.meta.broken, valgrind-light
, enableGalliumNine ? false # stdenv.isLinux
, enableOSMesa ? false #stdenv.isLinux
, enableOpenCL ? false #stdenv.isLinux && stdenv.isx86_64
, enablePatentEncumberedCodecs ? false
, jdupes
, zstd
, udev
}:

/** Packaging design:
  - The basic mesa ($out) contains headers and libraries (GLU is in libGLU now).
    This or the mesa attribute (which also contains GLU) are small (~ 2 MB, mostly headers)
    and are designed to be the buildInput of other packages.
  - DRI drivers are compiled into $drivers output, which is much bigger and
    depends on LLVM. These should be searched at runtime in
    "/run/opengl-driver{,-32}/lib/*" and so are kind-of impure (given by NixOS).
    (I suppose on non-NixOS one would create the appropriate symlinks from there.)
  - libOSMesa is in $osmesa (~4 MB)
*/

let
  # Release calendar: https://www.mesa3d.org/release-calendar.html
  # Release frequency: https://www.mesa3d.org/releasing.html#schedule
  branch = lib.versions.major version;

  withLibdrm = lib.meta.availableOn stdenv.hostPlatform libdrm;


  self = stdenv.mkDerivation {
  pname = "mesa";
    version = "23.1.0";
  src = fetchFromGitLab {
    # tracking: https://github.com/AsahiLinux/PKGBUILDs/blob/main/mesa-asahi-edge/PKGBUILD
    domain = "gitlab.freedesktop.org";
    owner = "asahi";
    repo = "mesa";
    rev = "asahi-20230311";
    hash = "sha256-Qy1OpjTohSDGwONK365QFH9P8npErswqf2TchUxR1tQ=";
  };
  

  # TODO:
  #  revive ./dricore-gallium.patch when it gets ported (from Ubuntu), as it saved
  #  ~35 MB in $drivers; watch https://launchpad.net/ubuntu/+source/mesa/+changelog
  patches = [
    # fixes pkgsMusl.mesa build
    ./musl.patch

    #./opencl.patch
    #./disk_cache-include-dri-driver-path-in-cache-key.patch
  ];

  # IMPORTANT FOR ARCAN
  postPatch = ''
    patchShebangs .

    # The drirc.d directory cannot be installed to $drivers as that would cause a cyclic dependency:
    substituteInPlace src/util/xmlconfig.c --replace \
      'DATADIR "/drirc.d"' '"${placeholder "out"}/share/drirc.d"'
    substituteInPlace src/util/meson.build --replace \
      "get_option('datadir')" "'${placeholder "out"}/share'"
    substituteInPlace src/amd/vulkan/meson.build --replace \
      "get_option('datadir')" "'${placeholder "out"}/share'"
  '';

  outputs = [ "out" "dev" "drivers" ]
    ++ lib.optional stdenv.isLinux "driversdev";
  
  preConfigure = ''
    PATH=${llvmPackages_15.libllvm.dev}/bin:$PATH
  '';

  # TODO: Figure out how to enable opencl without having a runtime dependency on clang
  mesonFlags = [
    "--sysconfdir=/etc"
    "--datadir=${placeholder "drivers"}/share" # Vendor files
    "-Dxlib-lease=disabled"
    "-Dglx=disabled"
    "-Dgallium-va=disabled"
    "-Dgallium-vdpau=disabled"
    "-Dgallium-xa=disabled"
    # does not make any sense
    "-Dandroid-libbacktrace=disabled"
    # do not want to add the dependencies
    "-Dlibunwind=disabled"
    "-Dlmsensors=disabled"
    # Don't build in debug mode
    # https://gitlab.freedesktop.org/mesa/mesa/blob/master/docs/meson.html#L327
    "-Db_ndebug=true"

    #"-Ddisk-cache-key=${placeholder "drivers"}"
    "-Ddri-search-path=${libglvnd.driverLink}/lib/dri"

    "-Dplatforms=${lib.concatStringsSep "," eglPlatforms}"
    "-Dgallium-drivers=${lib.concatStringsSep "," galliumDrivers}"
    "-Dvulkan-drivers=${lib.concatStringsSep "," vulkanDrivers}"

    "-Ddri-drivers-path=${placeholder "drivers"}/lib/dri"
    #"-Dvdpau-libs-path=${placeholder "drivers"}/lib/vdpau"
    #"-Domx-libs-path=${placeholder "drivers"}/lib/bellagio"
    #"-Dva-libs-path=${placeholder "drivers"}/lib/dri"
    #"-Dd3d-drivers-path=${placeholder "drivers"}/lib/d3d"

    #"-Dgallium-nine=${lib.boolToString enableGalliumNine}" # Direct3D in Wine
    #"-Dosmesa=${lib.boolToString enableOSMesa}" # used by wine
    "-Dmicrosoft-clc=disabled" # Only relevant on Windows (OpenCL 1.2 API on top of D3D12)
    "-Dintel-clc=disabled"

    # To enable non-mesa gbm backends to be found (e.g. Nvidia)
    #"-Dgbm-backends-path=${libglvnd.driverLink}/lib/gbm:${placeholder "out"}/lib/gbm"
    # IMPORTANT FOR ARCAN
    "-Dglvnd=true"
  ];

  buildInputs = [
    libglvnd
    ]
    ++ lib.optional withValgrind valgrind-light;
  
  depsBuildBuild = [ pkg-config ];

  nativeBuildInputs = [
    zstd
    udev 
    libelf
    expat
    meson pkg-config ninja
    xorg.libpthreadstubs /*or another sha1 provider*/
    intltool bison flex file
    python3Packages.python python3Packages.mako python3Packages.ply
    jdupes #glslang
    llvmPackages_15.libllvm
  ];

  propagatedBuildInputs = [
   # libXdamage libXxf86vm
  ] ++ lib.optional withLibdrm libdrm;

  doCheck = false;

  postInstall = ''
    # Some installs don't have any drivers so this directory is never created.
    mkdir -p $drivers $osmesa
  '' + lib.optionalString stdenv.isLinux ''
    mkdir -p $drivers/lib

    if [ -n "$(shopt -s nullglob; echo "$out/lib/libxatracker"*)" -o -n "$(shopt -s nullglob; echo "$out/lib/libvulkan_"*)" ]; then
      # move gallium-related stuff to $drivers, so $out doesn't depend on LLVM
      mv -t $drivers/lib       \
        $out/lib/libxatracker* \
        $out/lib/libvulkan_*
    fi

    if [ -n "$(shopt -s nullglob; echo "$out"/lib/lib*_mesa*)" ]; then
      # Move other drivers to a separate output
      mv -t $drivers/lib $out/lib/lib*_mesa*
    fi

    # Update search path used by glvnd
    for js in $drivers/share/glvnd/egl_vendor.d/*.json; do
      substituteInPlace "$js" --replace '"libEGL_' '"'"$drivers/lib/libEGL_"
    done

    # Update search path used by Vulkan (it's pointing to $out but
    # drivers are in $drivers)
    for js in $drivers/share/vulkan/icd.d/*.json; do
      substituteInPlace "$js" --replace "$out" "$drivers"
    done
  '' + lib.optionalString enableOpenCL ''
    # Move OpenCL stuff
    mkdir -p $opencl/lib
    mv -t "$opencl/lib/"     \
      $out/lib/gallium-pipe   \
      $out/lib/lib*OpenCL*

    # We construct our own .icd files that contain absolute paths.
    mkdir -p $opencl/etc/OpenCL/vendors/
    echo $opencl/lib/libMesaOpenCL.so > $opencl/etc/OpenCL/vendors/mesa.icd
  '' + lib.optionalString enableOSMesa ''
    # move libOSMesa to $osmesa, as it's relatively big
    mkdir -p $osmesa/lib
    mv -t $osmesa/lib/ $out/lib/libOSMesa*
  '' + lib.optionalString (vulkanLayers != []) ''
    mv -t $drivers/lib $out/lib/libVkLayer*
    for js in $drivers/share/vulkan/{im,ex}plicit_layer.d/*.json; do
      substituteInPlace "$js" --replace '"libVkLayer_' '"'"$drivers/lib/libVkLayer_"
    done
  '';

  postFixup = lib.optionalString stdenv.isLinux ''
    # set the default search path for DRI drivers; used e.g. by X server
    substituteInPlace "$dev/lib/pkgconfig/dri.pc" --replace "$drivers" "${libglvnd.driverLink}"
    [ -f "$dev/lib/pkgconfig/d3d.pc" ] && substituteInPlace "$dev/lib/pkgconfig/d3d.pc" --replace "$drivers" "${libglvnd.driverLink}"

    # remove pkgconfig files for GL/EGL; they are provided by libGL.
    rm -f $dev/lib/pkgconfig/{gl,egl}.pc

    # Move development files for libraries in $drivers to $driversdev
    mkdir -p $driversdev/include
    mv $dev/include/xa_* $dev/include/d3d* -t $driversdev/include || true
    mkdir -p $driversdev/lib/pkgconfig
    for pc in lib/pkgconfig/{xatracker,d3d}.pc; do
      if [ -f "$dev/$pc" ]; then
        substituteInPlace "$dev/$pc" --replace $out $drivers
        mv $dev/$pc $driversdev/$pc
      fi
    done

    # NAR doesn't support hard links, so convert them to symlinks to save space.
    jdupes --hard-links --link-soft --recurse "$drivers"

    # add RPATH so the drivers can find the moved libgallium and libdricore9
    # moved here to avoid problems with stripping patchelfed files
    for lib in $drivers/lib/*.so* $drivers/lib/*/*.so*; do
      if [[ ! -L "$lib" ]]; then
        patchelf --set-rpath "$(patchelf --print-rpath $lib):$drivers/lib" "$lib"
      fi
    done
  '';

  env.NIX_CFLAGS_COMPILE = toString (lib.optionals stdenv.isDarwin [ "-fno-common" ] ++ lib.optionals enableOpenCL [
    "-UPIPE_SEARCH_DIR"
    "-DPIPE_SEARCH_DIR=\"${placeholder "opencl"}/lib/gallium-pipe\""
  ]);

  passthru = {
    inherit (libglvnd) driverLink;
    inherit llvmPackages_15;

    libdrm = if withLibdrm then libdrm else null;

    tests = lib.optionalAttrs stdenv.isLinux {
      devDoesNotDependOnLLVM = stdenv.mkDerivation {
        name = "mesa-dev-does-not-depend-on-llvm";
        buildCommand = ''
          echo ${self.dev} >>$out
        '';
        disallowedRequisites = [ llvmPackages_15.llvm self.drivers ];
      };
    };
  };

  meta = with lib; {
    description = "An open source 3D graphics library";
    longDescription = ''
      The Mesa project began as an open-source implementation of the OpenGL
      specification - a system for rendering interactive 3D graphics. Over the
      years the project has grown to implement more graphics APIs, including
      OpenGL ES (versions 1, 2, 3), OpenCL, OpenMAX, VDPAU, VA API, XvMC, and
      Vulkan.  A variety of device drivers allows the Mesa libraries to be used
      in many different environments ranging from software emulation to
      complete hardware acceleration for modern GPUs.
    '';
    homepage = "https://www.mesa3d.org/";
    changelog = "https://www.mesa3d.org/relnotes/${version}.html";
    license = licenses.mit; # X11 variant, in most files
    platforms = platforms.mesaPlatforms;
    maintainers = with maintainers; [ primeos vcunat ]; # Help is welcome :)
  };
};

in self
