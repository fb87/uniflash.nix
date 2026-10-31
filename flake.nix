{
  description = "TI UniFlash repackaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs-gconf.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs, nixpkgs-gconf }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      packages = forAllSystems (pkgs:
        let
          legacyPkgs = import nixpkgs-gconf { system = pkgs.system; };
          gconf = legacyPkgs.gnome2.GConf;
          runtimeLibs = with pkgs; [
            alsa-lib atk at-spi2-atk cairo cups dbus expat fontconfig freetype glib
            gtk3
            libdrm libgbm libusb1 libusb-compat-0_1
            libxcrypt-legacy libxkbcommon nspr nss pango
            libX11 libxcb libXcomposite libXcursor libXdamage libXext libXfixes
            libXi libXrandr libXrender libXtst mesa
          ] ++ [ gconf ];
        in {
          default = pkgs.stdenv.mkDerivation {
            pname = "uniflash";
            version = "9.7.0.5873";

            src = pkgs.fetchurl {
              url = "https://dr-download.ti.com/software-development/software-programming-tool/MD-QeJBJLj8gq/9.7.0/uniflash_sl.9.7.0.5873.run";
              sha256 = "3d1788cd1ce413acf2b3927834288213bf9751100ff256687440e3a32c97b1a1";
            };

            nativeBuildInputs = with pkgs; [ bash makeWrapper patchelf ];
            dontUnpack = true;

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp "$src" ./uniflash-installer.run
              chmod u+wx ./uniflash-installer.run
              patchelf --set-interpreter "${pkgs.glibc}/lib/ld-linux-x86-64.so.2" ./uniflash-installer.run
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}"
              printf 'y\n' | ./uniflash-installer.run --mode unattended --prefix "$out"

              patchShebangs "$out"

              # TI ships binaries built for a conventional FHS Linux layout.
              # Give every ELF object the Nix loader and shared-library RPATH.
              interpreter="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
              rpath="${pkgs.lib.makeLibraryPath runtimeLibs}:$out/deskdb/content/TICloudAgent/linux/ccs_base/DebugServer/bin:$out/node-webkit/lib"
              while IFS= read -r -d "" binary; do
                if ${pkgs.file}/bin/file "$binary" | ${pkgs.gnugrep}/bin/grep -q "ELF"; then
                  ${pkgs.patchelf}/bin/patchelf --set-interpreter "$interpreter" --set-rpath "$rpath" "$binary" 2>/dev/null || true
                fi
              done < <(${pkgs.findutils}/bin/find "$out" -type f -print0)

              chmod -R u+w "$out"
              wrapProgram "$out/dslite.sh" \
                --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"
              wrapProgram "$out/uniFlashGUI.sh" \
                --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"

              mkdir -p "$out/bin"
              ln -s "$out/dslite.sh" "$out/bin/dslite"
              ln -s "$out/uniFlashGUI.sh" "$out/bin/uniflash-gui"

              runHook postInstall
            '';

            meta = {
              homepage = "https://www.ti.com/tool/UNIFLASH";
              description = "TI CCStudio UniFlash flash programming tool";
              license = pkgs.lib.licenses.unfree;
              platforms = [ "x86_64-linux" ];
              mainProgram = "dslite.sh";
            };
          };
        });
    };
}
