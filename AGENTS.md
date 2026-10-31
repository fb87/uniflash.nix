# Repository Guidance

## Nix Commands

- This flake contains unfree TI software. Build or run with `NIXPKGS_ALLOW_UNFREE=1` and `--impure`, for example `NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#tda4vm`.
- Validate evaluation without rebuilding large artifacts: `NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure --no-build`.
- Key packages are `uniflash` (default), `ti-arm-clang`, `processor-sdk-serial-flash`, `sk-tda4vm-flash-writer`, `tda4vm-boot-artifacts`, `tda4vm`, `tda4vm-flash-nor-boot`, and `tda4vh`.
- The TDA4VM writer build is expensive. Build `.#processor-sdk-serial-flash` separately when changing only host protocol code; build `.#sk-tda4vm-flash-writer` when changing target/flash code.

## Source Composition

- `flake.nix` repackages the official UniFlash `.run`; do not commit downloaded installers. `.gitignore` excludes them.
- `tda4vm-boot-artifacts` extracts the boot partition from TI's official SK-TDA4VM Edge AI WIC image; use these board-specific files for NOR boot.
- SK WIC source: `https://dr-download.ti.com/software-development/software-development-kit-sdk/MD-4K6R4tqhZI/11.00.00.08/tisdk-edgeai-image-j721e-evm.wic.xz`, SHA-256 `7bebcff62930c93bc0d10462385a936305ffdfd2457c4bbd85c2b2f216076da0`. Local `.wic.xz` files are ignored; use `aria2c` for an offline/resumable download and seed Nix from the verified file when needed.
- The custom SK-TDA4VM writer composes pinned TI PDK, `common-csl-ip`, and `mcupsdk-rm-pm-hal` sources. Standalone PDK Git omits CSL and RM/PM HAL, so all three are required.
- `sk-tda4vm-xspi.patch` converts the J721E EVM writer from Micron OSPI to the SK board's Cypress S28HS512 on `MCU_OSPI0`.
- `uniflash-host-writer-exit.patch` fixes TI host sequencing/exit behavior and keeps image transfer at 115200 baud. Preserve the two-phase writer-then-image flow.
- TI PDK files have mixed CRLF endings and hard-code `/bin/` utilities. The derivation normalizes only patched files and clears `UTILSPATH`; do not remove these build fixes.

## Hardware And Flashing

- SK-TDA4VM J4 exposes CP2108 interfaces in order: `if00` WKUP UART, `if01` MCU flash UART, `if02` main console, `if03` UART1. Prefer `/dev/serial/by-id/...-if01-port0` over `/dev/ttyUSB1`.
- SK-TDA4VM boot modes use `SW1.1/SW1.2/SW1.3`: microSD `OFF/OFF/OFF`; xSPI `OFF/OFF/ON`; USB Type-A `ON/ON/OFF`; USB-C `OFF/ON/OFF`; M.2 `OFF/ON/ON`; UART flashing `ON/OFF/ON`; no-boot/JTAG `ON/OFF/OFF`. `SW1.4` independently selects USB-C role: `OFF` DFP, `ON` UFP.
- Ask the user to restart or power-cycle after changing SW1 and before every new UniFlash RAM-writer session; wait for explicit confirmation before contacting the board.
- A normal session first transfers the writer, then TIFS; both are RAM-only. NOR transfer starts only when output contains `Flashing Image of size` or `Transferring File of size` in the image stage.
- The wrapper intentionally aborts an image-stage handshake after `UNIFLASH_HANDSHAKE_TIMEOUT` (default 5 seconds) if no transfer marker appears. After transfer starts, only `UNIFLASH_TIMEOUT` applies; never kill a progressing write.
- TI's documented J721E OSPI layout is: `tiboot3.bin` at `0x0`, `tispl.bin` at `0x80000`, `u-boot.img` at `0x280000`, and `sysfw.itb` at `0x6C0000`.
- Flash that complete layout in one RAM-writer session with `NIXPKGS_ALLOW_UNFREE=1 nix run --impure .#tda4vm-flash-nor-boot -- /dev/serial/by-id/...-if01-port0`.
- The connected SK-TDA4VM follows the GP flow. Use GP `tifs.bin`, `tiboot3.bin`, and `sysfw.itb`; HS-FS TIFS leaves the writer unresponsive.
- The `tda4vh` app currently wraps stock processor flashing only. Do not claim it has a board-specific custom writer until one is implemented and tested.

## Safety And Verification

- Never infer success from writer/TIFS reaching 100%. Require image transfer plus UniFlash's final success/read-back result.
- Do not erase or write offsets not documented above. Start with only `tiboot3.bin` at `0x0`; add later images only after that operation verifies.
- If J4 disappears, verify CP2108 USB ID `10c4:ea71` and all four serial interfaces before running UniFlash. A missing port means no board contact occurred.
