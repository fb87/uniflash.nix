# uniflash.nix

Nix packaging and board-specific UART flashing support for TI UniFlash on NixOS.

The SK-TDA4VM flow has been hardware-tested with its Cypress S28HS512 xSPI NOR. It loads a custom flash writer through ROM UART, then programs and verifies the complete NOR boot layout without requiring software on the target.

## Build

TI UniFlash and the TI Arm compiler are unfree packages, so Nix evaluation must allow unfree software:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix build --impure
```

Useful packages:

```text
uniflash                    Repackaged TI processor serial flash CLI
ti-arm-clang                Repackaged TI Arm Clang compiler
sk-tda4vm-flash-writer      SK-TDA4VM S28HS512 RAM writer
tda4vm-boot-artifacts       Boot files extracted from TI's SK WIC
tda4vm                      Single-image processor flashing
tda4vm-flash-nor-boot       Complete SK-TDA4VM NOR boot layout
j784s4-evm-flash-writer     J784S4 EVM xSPI RAM writer (untested)
tda4vh-boot-artifacts       TI J784S4 EVM boot files
tda4vh                      Single-image J784S4 EVM flashing (untested)
tda4vh-flash-nor-boot       Complete J784S4 EVM NOR boot layout (untested)
```

The `uniflash` output intentionally excludes TI's NW.js GUI, generic DebugServer, and cloud-agent trees; J7 UART flashing uses the static `ProcessorSDKSerialFlash` tool.

## SK Boot Image

Download TI's official SK-TDA4VM Edge AI image with resume support:

```sh
nix shell nixpkgs#aria2 --command aria2c \
  --continue=true --max-connection-per-server=16 --split=16 \
  https://dr-download.ti.com/software-development/software-development-kit-sdk/MD-4K6R4tqhZI/11.00.00.08/tisdk-edgeai-image-j721e-evm.wic.xz
```

Expected SHA-256:

```text
7bebcff62930c93bc0d10462385a936305ffdfd2457c4bbd85c2b2f216076da0
```

Seed Nix from the verified offline download to avoid downloading it again:

```sh
nix store prefetch-file \
  --name tisdk-edgeai-image-j721e-evm.wic.xz \
  "file://$PWD/tisdk-edgeai-image-j721e-evm.wic.xz"
```

The `tda4vm-boot-artifacts` derivation extracts only the FAT boot partition. The local WIC remains ignored by Git.

## Board Setup

Connect SK-TDA4VM connector J4. Its CP2108 interfaces are:

```text
if00  WKUP UART
if01  MCU flash UART
if02  Main console
if03  UART1
```

Use the stable `if01` path under `/dev/serial/by-id/` for flashing.

SW1.1/SW1.2/SW1.3 boot settings:

```text
OFF/OFF/OFF  microSD
OFF/OFF/ON   xSPI NOR
ON/ON/OFF    USB Type-A
OFF/ON/OFF   USB-C
OFF/ON/ON    M.2
ON/OFF/ON    UART flashing
ON/OFF/OFF   No boot/JTAG
```

`SW1.4` independently selects the USB-C role: `OFF` for DFP, `ON` for UFP.

## Flash NOR Boot

1. Set UART flashing mode: `SW1.1/SW1.2/SW1.3 = ON/OFF/ON`.
2. Restart or power-cycle the board.
3. Run:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix run --impure .#tda4vm-flash-nor-boot -- \
  /dev/serial/by-id/usb-Silicon_Labs_CP2108_Quad_USB_to_UART_Bridge_Controller_*-if01-port0
```

The command asks for `READY`, loads one RAM writer, then programs and read-back verifies:

```text
0x000000  tiboot3.bin
0x080000  tispl.bin
0x280000  u-boot.img
0x6C0000  sysfw.itb
```

After all four stages report `Flash Programming Success!`, set xSPI mode `OFF/OFF/ON` and restart. The main console is on `if02` at 115200 baud.

The complete SK-TDA4VM flow has been hardware-tested with full-byte read-back verification for all four images.

## Timeouts

- `UNIFLASH_HANDSHAKE_TIMEOUT` defaults to 5 seconds and applies only before image transfer starts.
- `UNIFLASH_TIMEOUT` defaults to 240 seconds for the RAM-writer stage. Image operations are not killed after transfer starts.
- Writer and TIFS transfers are RAM-only. NOR programming starts only after `Flashing Image of size` appears.

## TDA4VH

TDA4VH uses the J784S4XEVM platform. A prepared, untested one-shot NOR target is available:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix run --impure .#tda4vh-flash-nor-boot -- /dev/ttyUSB0
```

The J784S4 boot files are provided by `.#tda4vh-boot-artifacts`, sourced from TI's `boot-adas-j784s4-evm.tar.gz` (SHA-256 `b8139d948a0d71dc6be16e176af4a6c2ee682e857eec9cd621c10947d7d0445d`). Its NOR layout has three images: `tiboot3.bin` at `0x0`, `tispl.bin` at `0x80000`, and `u-boot.img` at `0x280000`; TIFS/DM is embedded.

The flashing UART is J48 COM1; J784S4 uses FTDI bridges and does not use the SK-TDA4VM CP2108 `if01` path. UART boot uses `SW11=00000000`, `SW7=01110000`; OSPI boot uses `SW11=00000110`, `SW7=01000000`, with switch strings in `.1` through `.8` order. This target is untested until a J784S4XEVM is connected.
