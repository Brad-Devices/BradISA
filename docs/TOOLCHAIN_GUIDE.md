# BradISA Toolchain Guide

This repository bundles the **bradasm** assembler (`tools/bradasm/`) and runs
on it: the board's boot ROM and the full-ISA regression programs are written
in assembly and assembled by the bundled tool. It does not bundle a bigger
toolchain or ship prebuilt binaries.

- For instruction encodings, see [Instruction formats](03-instruction-formats.md) and the normative LaTeX under `spec/`.
- For the bundled assembler (`bradasm`) and the source-kit emulator (`brad_core_emu`) interfaces, see [Toolchain and Reference Implementations](11-toolchain.md).
- For simulating the CPU RTL, see [FPGA](12-fpga.md).

The BradVector **GPU/accelerator** toolchain (`bradc`, BVRT, `bradgdb`, BradTimeline, `braddev`) is a separate ISA and is documented in the [BradVector repository](https://github.com/Brad-Devices/BradVector).