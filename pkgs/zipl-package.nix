{
  musl,
  gcc14Stdenv,
  fetchFromGitHub,
  systemd,
  cryptsetup,
  net-snmp,
  fuse3,
  openssl,
  patchelf,
  glibc,
  bash,
  pkg-config,
  json_c,
  lib,
  wrapCCWith,
  wrapBintoolsWith,
  overrideCC,
  gcc14,
  binutils-unwrapped,
}:
let
  # see https://github.com/ibm-s390-linux/s390-tools/issues/171 for why
  # i set gcc14 here
  stdenv = gcc14Stdenv;
  pname = "s390-tools";
  version = "2.33.1";
  march =
    with lib;
    if
      lib.attrsets.hasAttrByPath [
        "gcc"
        "arch"
      ] stdenv.targetPlatform
    then
      stdenv.targetPlatform.gcc.arch
    else
      lib.warn "no march specified: selecting z900 (gcc's default)" "z900";

  makeFlags =
    with lib.strings;
    (optionalString stdenv.hostPlatform.isS390x "HOST_ARCH=s390x ")
    + (optionalString (stdenv.buildPlatform != stdenv.hostPlatform) # cross
      "BUILD_ARCH=${stdenv.buildPlatform.system} CROSS_COMPILE=s390x-unknown-linux-gnu-"
    );
in
# TODO confirm this works like intended
lib.warnIf
  (lib.lists.any (m: m == march) [
    "z900"
    "z990"
    "arch6"
    "z9-109"
    "z9-ec"
    "arch7"
  ])
  "gcc.arch = \"${march}\" is broken for zipl"
  stdenv.mkDerivation
  {
    inherit pname version;
    src = fetchFromGitHub {
      owner = "ibm-s390-linux";
      repo = pname;
      rev = "v${version}";
      hash = "sha256-flH2v1z7wpDqGV2R/uS4aBKxdtGtEgO03UjbSA+sBWQ=";
    };
    nativeBuildInputs = [
      bash
      #gettext
      pkg-config
      #perl
      #net-snmp.dev
      #ncurses.dev
      #fuse3
      ##pkgs.cargo
      #curl.dev
      #json_c.dev
      #libxml2.dev
      #pkgs.gcc14.stdenv.cc
      #glibc.static
    ];
    buildInputs = [
      systemd.dev
      cryptsetup.dev
      net-snmp.dev
      #glibc.static.out
      glibc.dev
      #ncurses.dev
      fuse3
      #pkgs.cargo
      openssl
      #curl.dev
      json_c.dev
      #libxml2.dev
    ];
    hardeningDisable = [ "all" ];
    patchPhase = ''
      patchShebangs --build .
      substituteInPlace \
      common.mak --replace-fail "override SHELL := /bin/bash" "override SHELL := bash"

      substituteInPlace Makefile \
      --replace-fail "LIB_DIRS = libvtoc libzds libdasd libccw libvmcp libekmfweb \\" "LIB_DIRS = #\\" \
      --replace-fail "TOOL_DIRS = zipl zdump fdasd dasdfmt dasdview tunedasd \\" "TOOL_DIRS = zipl dasdfmt netboot zdev#\\"

    '';
      #--replace-fail "TOOL_DIRS = zipl zdump fdasd dasdfmt dasdview tunedasd \\" "TOOL_DIRS = zipl dasdfmt zfcpdump netboot zdev#\\"
    buildPhase =
      let
        zfcpdump =
          let
            gcc_static = wrapCCWith {
              cc = gcc14.cc;
              bintools = wrapBintoolsWith {
                bintools = binutils-unwrapped;
                libc = musl;
              };
            };
          in
          (overrideCC stdenv gcc_static).mkDerivation {
            #in stdenv.mkDerivation {
            hardeningDisable = [ "all" ];
            patchPhase = ''
              patchShebangs --build .
              substituteInPlace \
              common.mak --replace-fail "override SHELL := /bin/bash" "override SHELL := bash"

              substituteInPlace Makefile \
              --replace-fail "LIB_DIRS = libvtoc libzds libdasd libccw libvmcp libekmfweb \\" "LIB_DIRS = #\\" \
              --replace-fail "TOOL_DIRS = zipl zdump fdasd dasdfmt dasdview tunedasd \\" "TOOL_DIRS = zipl dasdfmt zfcpdump netboot zdev#\\"
            '';
            name = "zfcpdump";
            # TODO unless we no longer need this hack-drv
            # what would be the best version string to set?
            # that of s390-tools? This would make sense i guess
            version = "0.0.1";
            src = fetchFromGitHub {
              owner = "ibm-s390-linux";
              repo = pname;
              rev = "v${version}";
              hash = "sha256-flH2v1z7wpDqGV2R/uS4aBKxdtGtEgO03UjbSA+sBWQ=";
            };
            buildInputs = [
              musl.dev
            ];
            nativeBuildInputs = [
              patchelf
            ];
            # TODO zfcpdump somehow can't build with the standard
            # stdenv and -static thus currently i sort of build it
            # as its own drv and copy over the binary artifcats but thats
            # obviously hacky and wrong
            #
            # also TODO maybe setting the interpreter is no longer needed in this drv
            # V as cpioinit is used in make all and executed it until the patchelf
            # is no longer required needs to be build before zfcpdump_part
            buildPhase = "
make V=1 -C zfcpdump cpioinit 
patchelf --set-interpreter ${musl}/lib/ld-musl-s390x.so.1 ./zfcpdump/cpioinit
make V=1 -C zfcpdump zfcpdump_part
make V=1 -C zfcpdump  all
";
            # unless this hack is no longer needed at least only copy the things requride
            # /used in the s390-tools makefile
            installPhase =
              /*
                "
                #make V=1 -C zfcpdump cpioinit \
                #      INSTALLDIR=$out
                #cp -r zfcpdump $out
              */
              "
mkdir -p $out/bin
cp zfcpdump/* $out/bin
";
          };
      in
      # TODO why is zfcpdump rebuild eventhough we supply it trough the zfcpdump drv?
      # as for now im disabling that
      #
      # TODO why is pkg-config not providing json_c properly?
        # cp ${zfcpdump}/bin/* zfcpdump
      ''
            substituteInPlace zfcpdump/Makefile \
            --replace-fail "all: check_dep \$(ZFCPDUMP_INITRD) scripts" "all: $(ZFCPDUMP_INITRD) scripts"

            make V=1 -j $(nproc) ${makeFlags} LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${json_c.dev}/
              INSTALLDIR=$out \
              HAVE_OPENSSL=0 \
              HAVE_CURL=0 \
            	HAVE_CARGO=0 \
            	HAVE_GLIB=0 \
            	HAVE_GLIB2=0 \
            	HAVE_PFM=0
      '';
    # TODO re-use the params make and make install get as they need to be identical
    # so no reubild is issued
    installPhase = ''
      mkdir -p $out
      make install V=1 -j $(nproc) ${makeFlags} \
        INSTALLDIR=$out \
        HAVE_OPENSSL=0 \
        HAVE_CURL=0 \
      	HAVE_CARGO=0 \
      	HAVE_GLIB=0 \
      	HAVE_GLIB2=0 \
      	HAVE_PFM=0

    '';
    #dontFixup = true;
    meta = {
      # TODO etc
      # at the moment except very few utilities s390-tools can
      # only be build for s390 / s390x
      # TODO maintainers = [ maintainers.bl0v3 ]; ... 
      platforms = [
        "s390x-linux" # "s390-linux"
      ];
    };
  }
