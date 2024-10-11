{
  inputs.libfuse-fixes = {
    url = "github:bolives-hax/libfuse/s390x-fix";
    flake = false;
  };

  outputs =
    { self, libfuse-fixes }:
    {
      overlays.default = self: super: {
        python312 = super.python312.override {
          packageOverrides = pself: psuper: {
            psutil = psuper.psutil.overrideAttrs (old: {
              disabledTests = old.disabledTests ++ [
                # fails on IBM cloud s390x  (returns 1 core instead of 2)
                "cpu_count_cores"
              ];
            });
            # numpy 1 & 2 can't be fixed trough overrides thus
            numpy_1 = (pself.callPackage ./pkgs/numpy-1-fix.nix { }).overrideAttrs (old: {
              inherit (psuper.numpy_1) patches;
              #inherit (pself.numpy_1) patches;
            });
            numpy_2 = (pself.callPackage ./pkgs/numpy-2-fix.nix { }).overrideAttrs (old: {
              inherit (psuper.numpy_2) patches;
              #inherit (old) patches;
            });
          };
        };

        # my fix
        fuse = super.fuse.overrideAttrs {
          src = libfuse-fixes;
        };

        # https://github.com/NixOS/nixpkgs/pull/346408
        libuv = super.libuv.overrideAttrs (old: {
          postPatch = old.postPatch + "sed '/signal_multiple_loops/d' -i test/test-list.h";
        });

        /*
          by default it will select the linuxArch wthich would be "s390"
          		 not s390x  just like it would select x86 instead of x86_64. Though
          		 while it compiles without throwing an error it does seem to work like expected
          		 for example "ifconfig" as it is used when passing "ip=" kernel commandlines
          		 will thorw an obscure "parsing error" it won't throw on the 64bit 390x
          		 counterpart. While klibc claims to support s390 , ... dunno if this works it works
          		 and mainframes typically don't lack storage resources. This may be a little more
          		 relevant if it was common to use /boot/ partitions instead of /boot being on "/"
          		 but as long as the zipl bootloader is used its fine to just boot from "/"
          		 ( assuing your fs allows these old style bootloaders, ext4 does)
        */
        klibc = super.klibc.overrideAttrs {
          # using old: is not viable sadly
          makeFlags = with super; [
            "prefix=$(out)"
            "SHLIBDIR=$(out)/lib"
            "KLIBCARCH=${if stdenv.hostPlatform.isS390x then "s390x" else stdenv.hostPlatform.linuxArch}"
            "KLIBCKERNELSRC=${linuxHeaders}"
          ];
        };

        # spdlog-utests test fails
        spdlog = super.spdlog.overrideAttrs { doCheck = false; };

        /*
          luajit is still awaiting support for s390x, currently linux-on-ibm-z provides
          		the required patchset
        */
        luajit = super.luajit.overrideAttrs {
          src = super.fetchFromGitHub {
            owner = "linux-on-ibm-z";
            repo = "LuaJIT";
            rev = "9eaff286df941f645b31360093e181b967993695";
            hash = "sha256-4irOZ2m3k6Nz5rvvqN4DfAIQWCvIySSSC1MmzvA6GS8=";
          };
        };

        /*
          these tests seem to "TIMEOUT" rather than failing (may be the result of system overload)
          		 as the amount of tests timing out varies. (This may also just be slow on s390x) maybe
          		there is a way to crank up the timeout threshhold
          		 9/14 test_unit_cwrs32     TIMEOUT         30.06s   killed by signal 15 SIGTERM
          		12/14 test_opus_decode     TIMEOUT        120.09s   killed by signal 15 SIGTERM
          		13/14 test_opus_extensions TIMEOUT        120.02s   killed by signal 15 SIGTERM
          		14/14 test_opus_encode     TIMEOUT        240.09s   killed by signal 15 SIGTERM
        */
        libopus = super.libopus.overrideAttrs {
          doCheck = false;
        };

        # https://github.com/NixOS/nixpkgs/pull/346407
        aws-sdk-cpp = super.aws-sdk-cpp.overrideAttrs (old: {
          postPatch =
            old.postPatch
            + ''
              rm tests/aws-cpp-sdk-core-tests/utils/memory/AWSMemoryTest.cpp
              rm tests/aws-cpp-sdk-core-tests/utils/event/EventStreamDecoderTest.cpp
              rm tests/aws-cpp-sdk-core-tests/utils/event/EventStreamTest.cpp
              rm tests/aws-cpp-sdk-core-tests/utils/HashingUtilsTest.cpp
            '';
        });
        # TODO can we maybe patch the tests that fail rather than disabling them all?
        tpm2-tss = super.tpm2-tss.overrideAttrs (old: {
          configureFlags = builtins.filter (flag: flag != "--enable-integration") old.configureFlags;
        });

        # can't be fixed over just an override
        aws-c-common = (super.callPackage ./pkgs/aws-c-common-fix.nix { }).overrideAttrs {
          setupHook = super.aws-c-common.setupHook;
        };

        # https://github.com/NixOS/nixpkgs/pull/346406
        nsncd = super.nsncd.overrideAttrs (old: {
          checkFlags = old.checkFlags ++ [
            "--skip=handlers::test::test_hostent_serialization"
          ];
        });

        /*
          libresll straight up dropped s390x support, nc seets to by deafult be
          		taken from libresll though thus we use openssl in libressl's place
          		adding the nc attribute as thats used in some places. It does seem to work
        */
        libressl = super.openssl // ({ nc = super.netcat-gnu; });

        s390-tools = super.callPackage ./pkgs/zipl-package.nix { };
      };
      nixosModules = {
        zipl = ./modules/zipl.nix;
        iso = ./modules/iso-image-s390x.nix;
        allHardwareFixed = ./modules/all-hardware-s390x-fix.nix;
        default =
          { ... }:
          {
            imports = with self.nixosModules; [
              # zipl
              # allHardwareFixed	
              #iso
            ];
            boot.initrd = {
              /*
                the kernel module currently seems to be broken
                			figure out if tpm exists and if how it works on s390x
              */
              systemd.tpm2.enable = false;
              /*
                TODO fix the default modules to not include
                			kernel modules unavil on s390x
              */
              includeDefaultModules = false;
            };
            nixpkgs.overlays = [ self.overlays.default ];
          };
      };
    };
}
