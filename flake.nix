{
  description = "TI UniFlash repackaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs-gconf.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs, nixpkgs-gconf }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      packages = forAllSystems (pkgs:
        let
          legacyPkgs = import nixpkgs-gconf { system = pkgs.stdenv.hostPlatform.system; };
          gconf = legacyPkgs.gnome2.GConf;
          runtimeLibs = with pkgs; [
            alsa-lib atk at-spi2-atk cairo cups dbus expat fontconfig freetype glib
            gtk3
            libdrm libgbm libusb1 libusb-compat-0_1
            libxcrypt-legacy libxkbcommon nspr nss pango
            libX11 libxcb libXcomposite libXcursor libXdamage libXext libXfixes
            libXi libXrandr libXrender libXtst mesa
          ] ++ [ gconf ];
          tiArmClang = pkgs.stdenvNoCC.mkDerivation {
            pname = "ti-cgt-armllvm";
            version = "4.0.4.LTS";

            src = pkgs.fetchurl {
              url = "https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-ayxs93eZNN/4.0.4.LTS/ti_cgt_armllvm_4.0.4.LTS_linux-x64_installer.bin";
              hash = "sha256-mMYOzCWaB6VL5vzA9VmQMy9JO/5drUYMC6g5Y/XcsG8=";
            };

            nativeBuildInputs = with pkgs; [ file findutils patchelf ];
            dontUnpack = true;
            installPhase = ''
              runHook preInstall
              ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 "$src" \
                --mode unattended --prefix "$out"

              interpreter="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
              rpath="${pkgs.lib.makeLibraryPath [ pkgs.glibc pkgs.stdenv.cc.cc.lib pkgs.ncurses pkgs.zlib ]}"
              while IFS= read -r -d "" binary; do
                if ${pkgs.file}/bin/file "$binary" | ${pkgs.gnugrep}/bin/grep -q "ELF"; then
                  chmod u+w "$binary"
                  patchelf --set-interpreter "$interpreter" --set-rpath "$rpath" "$binary" 2>/dev/null || true
                fi
              done < <(${pkgs.findutils}/bin/find "$out" -type f -print0)
              runHook postInstall
            '';

            meta = {
              homepage = "https://www.ti.com/tool/ARM-CGT-CLANG";
              license = pkgs.lib.licenses.unfree;
              platforms = [ "x86_64-linux" ];
            };
          };
          cslSrc = pkgs.fetchgit {
            url = "https://git.ti.com/git/keystone-rtos/common-csl-ip.git";
            rev = "36ff9f2d02a5a282cb0c7128a5957168900fe744";
            hash = "sha256-LGHi48i5aU/P0KrfhM/TNCUzSK6HpzHj+DKjqzIzqW8=";
          };
          rmPmHalSrc = pkgs.fetchgit {
            url = "https://github.com/TexasInstruments/mcupsdk-rm-pm-hal.git";
            rev = "d9dce67aca0c098e5426d3b9d86dd9b057bbdfd4";
            hash = "sha256-T49mqZuq3eHsLFqr5GsgN7dmBv+LQsLavuMARNHJruQ=";
          };
          processorSerialFlash = pkgs.stdenv.mkDerivation {
            pname = "processor-sdk-serial-flash";
            version = "1.10.0.0-sk";
            src = pkgs.fetchgit {
              url = "https://git.ti.com/git/processor-sdk/pdk.git";
              rev = "ec9f41cb291c53365fd8b64632beaf7ecfbc0828";
              hash = "sha256-otZYtO55iERzzSKsTFwkbE/r6IkztCHMuVHmWAOj5Ic=";
            };
            patches = [ ./uniflash-host-writer-exit.patch ];
            hardeningDisable = [ "all" ];
            nativeBuildInputs = with pkgs; [ dos2unix gnumake ];
            prePatch = ''
              dos2unix \
                packages/ti/board/utils/uniflash/host/source/ProcessorSDKSerialFlash.cpp \
                packages/ti/board/utils/uniflash/host/source/main.cpp
            '';
            postPatch = ''
              substituteInPlace packages/ti/board/utils/uniflash/host/source/ProcessorSDKSerialFlash.cpp \
                --replace-fail 'exit(0);' 'exit(1);' \
                --replace-fail 'if(!(strcmp( ext,".appimage_xip" )))' \
                  'if((ext != NULL) && !(strcmp( ext,".appimage_xip" )))'
              substituteInPlace packages/ti/board/utils/uniflash/host/source/main.cpp \
                --replace-fail 'LoadImage( argv[i+1], &argv[1], &argv[2], argc );' \
                  'return LoadImage( argv[i+1], &argv[1], &argv[2], argc );' \
                --replace-fail 'return(1);' '/* Return handled above. */'
            '';
            buildPhase = ''
              runHook preBuild
              make -C packages/ti/board/utils/uniflash/host CPPFLAG=
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin"
              cp packages/ti/board/utils/uniflash/host/bin/ProcessorSDKSerialFlash "$out/bin/"
              runHook postInstall
            '';
          };
          tda4vmBootArtifacts = pkgs.stdenvNoCC.mkDerivation {
            pname = "tda4vm-boot-artifacts";
            version = "11.00.00.08-sk";
            src = pkgs.fetchurl {
              url = "https://dr-download.ti.com/software-development/software-development-kit-sdk/MD-4K6R4tqhZI/11.00.00.08/tisdk-edgeai-image-j721e-evm.wic.xz";
              hash = "sha256-e+vP9ikwyTvA0QRiOFqTYwX/39JFfEu9hcKy8hYHbaA=";
            };
            nativeBuildInputs = with pkgs; [ mtools parted xz ];
            dontUnpack = true;
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              xz -dc "$src" > image.wic
              boot_offset="$(parted -sm image.wic unit B print | grep '^1:' | cut -d: -f2 | tr -d B)"
              if [ -z "$boot_offset" ]; then
                printf 'Unable to locate the SK boot partition.\n' >&2
                exit 1
              fi
              mcopy -s -i "image.wic@@$boot_offset" '::*' "$out/"
              for image in tiboot3.bin tispl.bin u-boot.img sysfw.itb; do
                test -s "$out/$image" || { printf 'Missing required SK image: %s\n' "$image" >&2; exit 1; }
              done
              runHook postInstall
            '';
            meta = {
              description = "TI SK-TDA4VM boot firmware artifacts";
              license = pkgs.lib.licenses.unfree;
              platforms = pkgs.lib.platforms.all;
            };
          };
          tda4vhBootArtifacts = pkgs.stdenvNoCC.mkDerivation {
            pname = "tda4vh-boot-artifacts";
            version = "11.02.02.05-j784s4";
            src = pkgs.fetchurl {
              url = "https://dr-download.ti.com/software-development/software-development-kit-sdk/MD-lOshtRwR8P/11.02.02.05/boot-adas-j784s4-evm.tar.gz";
              hash = "sha256-uBOdlIoNcdxr4W4XavSmwu5oLoV+7JzWIcEJR9fQRF0=";
            };
            dontUnpack = true;
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              tar -xzf "$src" -C "$out"
              for image in tiboot3.bin tispl.bin u-boot.img; do
                test -s "$out/$image" || { printf 'Missing required J784S4 image: %s\n' "$image" >&2; exit 1; }
              done
              runHook postInstall
            '';
            meta = {
              description = "TI J784S4/TDA4VH EVM boot firmware artifacts";
              license = pkgs.lib.licenses.unfree;
              platforms = pkgs.lib.platforms.all;
            };
          };
          skTda4vmFlashWriter = pkgs.stdenvNoCC.mkDerivation {
            pname = "sk-tda4vm-uniflash-writer";
            version = "11.02.00";

            src = pkgs.fetchgit {
              url = "https://git.ti.com/git/processor-sdk/pdk.git";
              rev = "ec9f41cb291c53365fd8b64632beaf7ecfbc0828";
              hash = "sha256-otZYtO55iERzzSKsTFwkbE/r6IkztCHMuVHmWAOj5Ic=";
            };
            patches = [ ./sk-tda4vm-xspi.patch ];

            nativeBuildInputs = with pkgs; [
              bash coreutils dos2unix gnumake openssl perl python3
              pkgsCross.aarch64-embedded.buildPackages.binutils
            ];
            prePatch = ''
              dos2unix \
                packages/ti/board/utils/uniflash/target/src/ospi/ospi.h \
                packages/ti/board/utils/uniflash/target/src/ospi/ospi.c \
                packages/ti/board/src/flash/src_files_flash.mk \
                packages/ti/board/src/flash/nor/ospi/nor_xspi.h \
                packages/ti/board/src/flash/nor/ospi/nor_xspi.c \
                packages/ti/board/src/flash/nor/nor.c \
                packages/ti/board/utils/uniflash/target/src/xmodem.c \
                packages/ti/build/makerules/env.mk
            '';
            postPatch = ''
              substituteInPlace packages/ti/board/src/flash/nor/ospi/nor_xspi.c \
                --replace-fail \
                  '                /* Reset device memory for all the other lines */' \
                  '                /* Defer device access until verified programming. */' \
                --replace-fail '                Nor_xspiResetMemory(hwHandle);' \
                  '                /* Reset deferred. */' \
                --replace-fail '                Nor_xspiWaitReady(hwHandle, NOR_WRR_WRITE_TIMEOUT);' \
                  '                /* Status read deferred. */' \
                --replace-fail $'                if(NOR_PASS != retVal)\n                {\n                    return (NOR_HANDLE)NOR_FAIL;\n                }' \
                  '                /* No pre-transfer device transaction. */' \
                --replace-fail $'            if (NOR_PASS == Nor_xspiReadId(hwHandle))\n            {\n                Nor_xspiInfo.hwHandle = (uintptr_t)hwHandle;\n                norHandle = (NOR_HANDLE)(&Nor_xspiInfo);\n            }' \
                  $'            Nor_xspiInfo.manufacturerId = NOR_MANF_ID;\n            Nor_xspiInfo.deviceId = NOR_DEVICE_ID;\n            Nor_xspiInfo.hwHandle = (uintptr_t)hwHandle;\n            norHandle = (NOR_HANDLE)(&Nor_xspiInfo);'
              cp -r ${cslSrc} packages/ti/csl
              chmod -R u+w packages/ti/csl
              cp -r ${rmPmHalSrc} packages/ti/drv/sciclient/src/rm_pm_hal
              chmod -R u+w packages/ti/drv/sciclient/src/rm_pm_hal
              patchShebangs packages/ti
            '';

            enableParallelBuilding = true;
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              export OS=linux
              export SDK_INSTALL_PATH="$PWD"
              export PDK_INSTALL_PATH="$PWD/packages"
              export TOOLS_INSTALL_PATH="$PWD"
              export TOOLCHAIN_PATH_R5="${tiArmClang}/ti-cgt-armllvm_4.0.4.LTS"
              export TOOLCHAIN_PATH_GCC_ARCH64="${pkgs.pkgsCross.aarch64-embedded.buildPackages.binutils}"
              export GCC_ARCH64_BIN_PREFIX=aarch64-none-elf

              make -C packages/ti/build -s \
                BOARD=j721e_evm SOC=j721e CORE=mcu1_0 \
                BUILD_PROFILE=release PROFILE=release \
                board_utils_uart_flash_programmer
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp packages/ti/board/utils/uniflash/target/bin/j721e_evm/uart_j721e_evm_flash_programmer_release.tiimage \
                "$out/uart_sk_tda4vm_flash_programmer_release.tiimage"
              cp packages/ti/drv/sciclient/soc/V1/tifs.bin "$out/tifs.bin"
              runHook postInstall
            '';

            meta = {
              description = "UniFlash UART writer for SK-TDA4VM S28HS512 xSPI NOR";
              license = pkgs.lib.licenses.bsd3;
              platforms = [ "x86_64-linux" ];
            };
          };
          j784s4FlashWriter = pkgs.stdenvNoCC.mkDerivation {
            pname = "j784s4-evm-uniflash-writer";
            version = "11.02.00";
            src = pkgs.fetchgit {
              url = "https://git.ti.com/git/processor-sdk/pdk.git";
              rev = "ec9f41cb291c53365fd8b64632beaf7ecfbc0828";
              hash = "sha256-otZYtO55iERzzSKsTFwkbE/r6IkztCHMuVHmWAOj5Ic=";
            };
            nativeBuildInputs = with pkgs; [
              bash coreutils dos2unix gnumake openssl perl python3
              pkgsCross.aarch64-embedded.buildPackages.binutils
            ];
            prePatch = ''
              dos2unix \
                packages/ti/board/utils/uniflash/target/src/xmodem.c \
                packages/ti/build/makerules/env.mk
            '';
            postPatch = ''
              substituteInPlace packages/ti/board/utils/uniflash/target/src/xmodem.c \
                --replace-fail 'for(i = 0U; i < size; i +=4U)' 'for(i = 0U; i < size; i++)'
              substituteInPlace packages/ti/build/makerules/env.mk \
                --replace-fail '  UTILSPATH = /bin/' '  UTILSPATH ='
              cp -r ${cslSrc} packages/ti/csl
              chmod -R u+w packages/ti/csl
              cp -r ${rmPmHalSrc} packages/ti/drv/sciclient/src/rm_pm_hal
              chmod -R u+w packages/ti/drv/sciclient/src/rm_pm_hal
              patchShebangs packages/ti
            '';
            enableParallelBuilding = true;
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              export OS=linux
              export SDK_INSTALL_PATH="$PWD"
              export PDK_INSTALL_PATH="$PWD/packages"
              export TOOLS_INSTALL_PATH="$PWD"
              export TOOLCHAIN_PATH_R5="${tiArmClang}/ti-cgt-armllvm_4.0.4.LTS"
              export TOOLCHAIN_PATH_GCC_ARCH64="${pkgs.pkgsCross.aarch64-embedded.buildPackages.binutils}"
              export GCC_ARCH64_BIN_PREFIX=aarch64-none-elf
              make -C packages/ti/build -s \
                BOARD=j784s4_evm SOC=j784s4 CORE=mcu1_0 \
                BUILD_PROFILE=release PROFILE=release \
                board_utils_uart_flash_programmer
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp packages/ti/board/utils/uniflash/target/bin/j784s4_evm/uart_j784s4_evm_flash_programmer_release.tiimage \
                "$out/uart_j784s4_evm_flash_programmer_release.tiimage"
              cp packages/ti/drv/sciclient/soc/V6/tifs.bin "$out/tifs.bin"
              runHook postInstall
            '';
            meta = {
              description = "UniFlash UART writer for J784S4 EVM xSPI NOR";
              license = pkgs.lib.licenses.bsd3;
              platforms = [ "x86_64-linux" ];
            };
          };
          uniflash = pkgs.stdenv.mkDerivation {
            pname = "uniflash";
            version = "9.7.0.5873";

            src = pkgs.fetchurl {
              url = "https://dr-download.ti.com/software-development/software-programming-tool/MD-QeJBJLj8gq/9.7.0/uniflash_sl.9.7.0.5873.run";
              sha256 = "3d1788cd1ce413acf2b3927834288213bf9751100ff256687440e3a32c97b1a1";
            };

            nativeBuildInputs = with pkgs; [ bash patchelf ];
            dontUnpack = true;

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp "$src" ./uniflash-installer.run
              chmod u+wx ./uniflash-installer.run
              patchelf --set-interpreter "${pkgs.glibc}/lib/ld-linux-x86-64.so.2" ./uniflash-installer.run
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}"
              printf 'y\n' | ./uniflash-installer.run --mode unattended --prefix "$out"

              mv "$out/processors" ./processors
              rm -rf "$out"/*
              mv ./processors "$out/processors"
              cp "${processorSerialFlash}/bin/ProcessorSDKSerialFlash" \
                "$out/processors/ProcessorSDKSerialFlash"
              mkdir -p "$out/bin"
              ln -s "$out/processors/ProcessorSDKSerialFlash" "$out/bin/uniflash-processors"

              runHook postInstall
            '';

            meta = {
              homepage = "https://www.ti.com/tool/UNIFLASH";
              description = "TI UniFlash processor serial programming tool";
              license = pkgs.lib.licenses.unfree;
              platforms = [ "x86_64-linux" ];
              mainProgram = "uniflash-processors";
            };
          };

          flashTarget = target: writerImage: pkgs.writeShellApplication {
            name = "${pkgs.lib.toLower target}-flash";
            runtimeInputs = [ processorSerialFlash pkgs.coreutils pkgs.gnugrep ];
            text = ''
              if [ "$#" -eq 0 ]; then
                printf '%s\n' \
                  "Usage: ${pkgs.lib.toLower target}-flash -c /dev/ttyUSBx -f image -i image_type -o offset" \
                  "  image_type: 0=flash, 1=MLO, 2=U-Boot, 3=UImage, 4=firmware, 5=custom" \
                  "  This target selects OSPI/xSPI NOR (device type 3) for ${target}."
                exit 2
              fi

              printf 'Restart or power-cycle the board, keep UART boot enabled, then type READY: '
              read -r restart_confirmation
              if [ "$restart_confirmation" != "READY" ]; then
                printf 'Expected READY; aborting without contacting the board.\n' >&2
                exit 2
              fi

              timeout_seconds="''${UNIFLASH_TIMEOUT:-120}"
              ${pkgs.lib.optionalString (writerImage != null) ''
                port=""
                previous=""
                for argument in "$@"; do
                  if [ "$previous" = "-c" ]; then
                    port="$argument"
                    break
                  fi
                  previous="$argument"
                done
                if [ -z "$port" ]; then
                  printf 'A UART port must be supplied with -c.\n' >&2
                  exit 2
                fi

                set +e
                timeout --foreground --kill-after=5s "$timeout_seconds" \
                  ProcessorSDKSerialFlash -d 3 -c "$port" \
                  -f "${writerImage}" -i 0
                writer_status="$?"
                set -e
                if [ "$writer_status" -ne 0 ] && [ "$writer_status" -ne 1 ]; then
                  exit "$writer_status"
                fi
                printf 'Writer stage returned %s; attaching image stage immediately.\n' "$writer_status"
              ''}
              handshake_seconds="''${UNIFLASH_HANDSHAKE_TIMEOUT:-5}"
              image_log="$(mktemp)"
              cleanup() {
                rm -f "$image_log"
              }
              trap cleanup EXIT

              stdbuf -o0 ProcessorSDKSerialFlash -d 3 "$@" \
                > >(tee "$image_log") 2>&1 &
              image_pid="$!"
              elapsed=0
              transfer_started=0
              while kill -0 "$image_pid" 2>/dev/null; do
                if grep -qE 'Flashing Image|Transferring File of size' "$image_log"; then
                  transfer_started=1
                fi
                if [ "$transfer_started" -eq 0 ] && [ "$elapsed" -ge "$handshake_seconds" ]; then
                  printf 'No image-transfer progress after %s seconds; terminating.\n' "$handshake_seconds" >&2
                  kill "$image_pid" 2>/dev/null || true
                  sleep 1
                  kill -9 "$image_pid" 2>/dev/null || true
                  wait "$image_pid" || true
                  exit 124
                fi
                sleep 1
                elapsed=$((elapsed + 1))
              done
              set +e
              wait "$image_pid"
              image_status="$?"
              set -e
              if [ "$image_status" -ne 0 ] || \
                 ! grep -qE 'Flashing Image|Transferring File of size' "$image_log" || \
                 ! grep -q 'Flash Programming Success!' "$image_log"; then
                printf 'Image operation did not report transfer plus verified success.\n' >&2
                exit 1
              fi
            '';
          };
          tda4vmFlashNorBoot = pkgs.writeShellApplication {
            name = "tda4vm-flash-nor-boot";
            runtimeInputs = [ processorSerialFlash pkgs.coreutils pkgs.gnugrep ];
            text = ''
              port="''${1:-''${UNIFLASH_PORT:-/dev/ttyUSB1}}"
              timeout_seconds="''${UNIFLASH_TIMEOUT:-240}"
              handshake_seconds="''${UNIFLASH_HANDSHAKE_TIMEOUT:-5}"

              if [ ! -e "$port" ]; then
                printf 'UART port does not exist: %s\n' "$port" >&2
                exit 2
              fi

              printf 'Restart or power-cycle the board, keep UART boot enabled, then type READY: '
              read -r restart_confirmation
              if [ "$restart_confirmation" != "READY" ]; then
                printf 'Expected READY; aborting without contacting the board.\n' >&2
                exit 2
              fi

              set +e
              timeout --foreground --kill-after=5s "$timeout_seconds" \
                ProcessorSDKSerialFlash -d 3 -c "$port" \
                -f "${skTda4vmFlashWriter}/uart_sk_tda4vm_flash_programmer_release.tiimage" -i 0
              writer_status="$?"
              set -e
              if [ "$writer_status" -ne 0 ] && [ "$writer_status" -ne 1 ]; then
                exit "$writer_status"
              fi

              run_image() {
                image="$1"
                image_type="$2"
                offset="$3"
                image_log="$(mktemp)"

                printf '\nFlashing %s at 0x%s\n' "$(basename "$image")" "$offset"
                stdbuf -o0 ProcessorSDKSerialFlash -d 3 -c "$port" \
                  -f "$image" -i "$image_type" -o "$offset" \
                  > >(tee "$image_log") 2>&1 &
                image_pid="$!"
                elapsed=0
                transfer_started=0
                while kill -0 "$image_pid" 2>/dev/null; do
                  if grep -qE 'Flashing Image|Transferring File of size' "$image_log"; then
                    transfer_started=1
                  fi
                  if [ "$transfer_started" -eq 0 ] && [ "$elapsed" -ge "$handshake_seconds" ]; then
                    printf 'No image-transfer progress after %s seconds; terminating.\n' "$handshake_seconds" >&2
                    kill "$image_pid" 2>/dev/null || true
                    sleep 1
                    kill -9 "$image_pid" 2>/dev/null || true
                    wait "$image_pid" || true
                    rm -f "$image_log"
                    return 124
                  fi
                  sleep 1
                  elapsed=$((elapsed + 1))
                done
                set +e
                wait "$image_pid"
                status="$?"
                set -e
                if [ "$status" -ne 0 ] || \
                   ! grep -qE 'Flashing Image|Transferring File of size' "$image_log" || \
                   ! grep -q 'Flash Programming Success!' "$image_log"; then
                  printf 'Image operation did not report transfer plus verified success.\n' >&2
                  rm -f "$image_log"
                  return 1
                fi
                rm -f "$image_log"
                return 0
              }

              run_image "${tda4vmBootArtifacts}/tiboot3.bin" 1 0
              run_image "${tda4vmBootArtifacts}/tispl.bin" 2 80000
              run_image "${tda4vmBootArtifacts}/u-boot.img" 2 280000
              run_image "${tda4vmBootArtifacts}/sysfw.itb" 5 6C0000
              printf '\nAll TDA4VM NOR boot images flashed and verified.\n'
            '';
          };
          tda4vhFlashNorBoot = pkgs.writeShellApplication {
            name = "tda4vh-flash-nor-boot";
            runtimeInputs = [ processorSerialFlash pkgs.coreutils pkgs.gnugrep ];
            text = ''
              port="''${1:-''${UNIFLASH_PORT:-/dev/ttyUSB0}}"
              timeout_seconds="''${UNIFLASH_TIMEOUT:-240}"
              handshake_seconds="''${UNIFLASH_HANDSHAKE_TIMEOUT:-5}"

              if [ ! -e "$port" ]; then
                printf 'UART port does not exist: %s\n' "$port" >&2
                exit 2
              fi
              printf 'Restart or power-cycle the J784S4 EVM, keep UART boot enabled, then type READY: '
              read -r restart_confirmation
              if [ "$restart_confirmation" != "READY" ]; then
                printf 'Expected READY; aborting without contacting the board.\n' >&2
                exit 2
              fi

              set +e
              timeout --foreground --kill-after=5s "$timeout_seconds" \
                ProcessorSDKSerialFlash -d 3 -c "$port" \
                -f "${j784s4FlashWriter}/uart_j784s4_evm_flash_programmer_release.tiimage" -i 0
              writer_status="$?"
              set -e
              if [ "$writer_status" -ne 0 ] && [ "$writer_status" -ne 1 ]; then
                exit "$writer_status"
              fi

              run_image() {
                image="$1"
                image_type="$2"
                offset="$3"
                image_log="$(mktemp)"
                printf '\nFlashing %s at 0x%s\n' "$(basename "$image")" "$offset"
                stdbuf -o0 ProcessorSDKSerialFlash -d 3 -c "$port" -f "$image" -i "$image_type" -o "$offset" \
                  > >(tee "$image_log") 2>&1 &
                image_pid="$!"
                elapsed=0
                transfer_started=0
                while kill -0 "$image_pid" 2>/dev/null; do
                  if grep -qE 'Flashing Image|Transferring File of size' "$image_log"; then transfer_started=1; fi
                  if [ "$transfer_started" -eq 0 ] && [ "$elapsed" -ge "$handshake_seconds" ]; then
                    kill "$image_pid" 2>/dev/null || true
                    sleep 1
                    kill -9 "$image_pid" 2>/dev/null || true
                    wait "$image_pid" || true
                    rm -f "$image_log"
                    return 124
                  fi
                  sleep 1
                  elapsed=$((elapsed + 1))
                done
                set +e
                wait "$image_pid"
                status="$?"
                set -e
                if [ "$status" -ne 0 ] || \
                   ! grep -qE 'Flashing Image|Transferring File of size' "$image_log" || \
                   ! grep -q 'Flash Programming Success!' "$image_log"; then
                  printf 'Image operation did not report transfer plus verified success.\n' >&2
                  rm -f "$image_log"
                  return 1
                fi
                rm -f "$image_log"
                return 0
              }

              run_image "${tda4vhBootArtifacts}/tiboot3.bin" 1 0
              run_image "${tda4vhBootArtifacts}/tispl.bin" 2 80000
              run_image "${tda4vhBootArtifacts}/u-boot.img" 2 280000
              printf '\nAll TDA4VH/J784S4 NOR boot images flashed and verified.\n'
            '';
          };
        in {
          default = uniflash;
          uniflash = uniflash;
          ti-arm-clang = tiArmClang;
          sk-tda4vm-flash-writer = skTda4vmFlashWriter;
          j784s4-evm-flash-writer = j784s4FlashWriter;
          processor-sdk-serial-flash = processorSerialFlash;
          tda4vm-boot-artifacts = tda4vmBootArtifacts;
          tda4vm = flashTarget "TDA4VM" "${skTda4vmFlashWriter}/uart_sk_tda4vm_flash_programmer_release.tiimage";
          tda4vm-flash-nor-boot = tda4vmFlashNorBoot;
          tda4vh-boot-artifacts = tda4vhBootArtifacts;
          tda4vh-flash-nor-boot = tda4vhFlashNorBoot;
          tda4vh = flashTarget "TDA4VH" "${j784s4FlashWriter}/uart_j784s4_evm_flash_programmer_release.tiimage";
        });

      apps = forAllSystems (pkgs:
        let
          packages = self.packages.${pkgs.stdenv.hostPlatform.system};
        in {
          tda4vm = {
            type = "app";
            program = "${packages.tda4vm}/bin/tda4vm-flash";
          };
          tda4vm-flash-nor-boot = {
            type = "app";
            program = "${packages.tda4vm-flash-nor-boot}/bin/tda4vm-flash-nor-boot";
          };
          tda4vh = {
            type = "app";
            program = "${packages.tda4vh}/bin/tda4vh-flash";
          };
          tda4vh-flash-nor-boot = {
            type = "app";
            program = "${packages.tda4vh-flash-nor-boot}/bin/tda4vh-flash-nor-boot";
          };
        });
    };
}
