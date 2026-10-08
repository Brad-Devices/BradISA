<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Brad-Devices/brad-devices/main/assets/brad-devices-wordmark/svg/brad-devices-wordmark-white.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/Brad-Devices/brad-devices/main/assets/brad-devices-wordmark/svg/brad-devices-wordmark-black.svg">
    <img alt="BRAD DEVICES" width="360">
  </picture>
</p>

<p align="center">
  <em>of</em>&nbsp;&nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Brad-Devices/brad-devices/main/assets/brad-verse-wordmark/svg/brad-verse-wordmark-flat-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/Brad-Devices/brad-devices/main/assets/brad-verse-wordmark/svg/brad-verse-wordmark-flat-light.svg">
    <img alt="BRADVERSE" width="190">
  </picture>
</p>

[![CI](https://github.com/Brad-Devices/BradISA/actions/workflows/ci.yml/badge.svg)](https://github.com/Brad-Devices/BradISA/actions/workflows/ci.yml)

<p align="center">
  <img alt="C" src="https://img.shields.io/badge/C-8A6D1F?style=for-the-badge">&nbsp;
  <img alt="Verilog" src="https://img.shields.io/badge/Verilog-8A6D1F?style=for-the-badge">&nbsp;
  <img alt="VHDL" src="https://img.shields.io/badge/VHDL-8A6D1F?style=for-the-badge">&nbsp;
  <img alt="Assembly" src="https://img.shields.io/badge/Assembly-8A6D1F?style=for-the-badge">&nbsp;
  <img alt="Linux" src="https://img.shields.io/badge/Linux-8A6D1F?style=for-the-badge">&nbsp;
  <img alt="LaTeX" src="https://img.shields.io/badge/LaTeX-8A6D1F?style=for-the-badge">
</p>

# BradISA

The Brad Devices CPU instruction set architecture — the shared software contract behind every BradCore processor.

```text
This is not a reference to some future silicon.
It is the spec the silicon is built from,
and the reference core that proves it fits on real fabric.
```

## What this repo contains

```
spec/                  normative ISA sources and built PDFs
  bradisa_spec.tex       V1 base ISA — encoding, exceptions, pipeline models
  bradisa_v2_ext.tex     V2 — compressed, VSET vector, power management
  *.pdf                  pre-built spec documents (11 pp V1, 16 pp V2)

docs/                  the full documentation tree
  00-index.md                   documentation index and reading order
  01-quickstart.md              orientation, first program, how to simulate
  02-data-model.md              words, bytes, address space, alignment
  03-instruction-formats.md     RRR / RI / BR / JMP / RET encodings
  04-base-isa.md                complete V1 opcode reference (16 instructions)
  05-abi.md                     calling convention, register map, stack
  06-exceptions.md              vector table, cause codes, trap flow
  07-msr-reference.md           every model-specific register (V1 + V2)
  08-vector.md                  VSET vector extension — full reference
  09-compressed.md              16-bit compressed instruction encoding
  10-power.md                   C-states, DVFS, clock-gating, perf counters
  11-toolchain.md               reference assembler (bradasm) + emulator (brad_core_emu)
  12-fpga.md                    Falcon RTL: pipeline, hazards, builds
  13-gen2.md                    SVEXT and future extensions (VISION)
  GLOSSARY.md                   every term, one line each
  ARCHITECTURE_GUIDE.md         developer-facing programming guide
  ARCHITECTURE_REFERENCE_MODEL.md   authoritative architecture model
  ISA_QUICK_REFERENCE.md        compact one-page reference card
  TOOLCHAIN_GUIDE.md            repo scope and pointers to reference implementations

rtl/                   synthesisable Falcon V1 core
  verilog/               Verilog 2001 RTL
  vhdl/                  VHDL-2008 RTL (same design)
  fpga/                  Vivado + Quartus build scripts and constraints
```

## The spec, briefly

BradISA V1 is a **32-bit fixed-width RISC ISA**:

- 16 general-purpose 32-bit registers (r0 = hardwired zero)
- 16 base opcodes; three primary instruction formats (RRR, RI, BR, JMP, RET)
- Two privilege levels (User, Supervisor); vectored exception model
- Vector extension (VSET) — 32 × 256-bit fixed-length SIMD, all FP lives here

The full architectural model (`ARCHITECTURE_REFERENCE_MODEL.md`) is the
normative companion to the LaTeX specs.

## The V2 extensions

- **Compressed 16-bit encoding** — two halfwords per 32-bit word, ~30–40% code-size reduction (STATUS.C bit)
- **VSET** — integer/FP elementwise ops, vector memory, reductions, conversions, VSTATUS MSR 23
- **Power management** — C-states, DVFS MSRs, performance counters, clock-gating mask
- **Kestrel** (8-stage dual-issue) and **Falcon-Lite** (3-stage ultra-tiny) pipeline models

## The RTL

A complete, synthesisable 5-stage **Falcon** core (single-issue, in-order) targeting:

- **Xilinx Artix-7** (Vivado, xc7a35ticsg324-1L) — ~300 LUTs, ~200 FFs, 1 DSP48E1, >200 MHz
- **Intel Cyclone V** (Quartus, 5CSXFC6D6F31C6ES)

Both Verilog 2001 and VHDL-2008 versions are provided with testbenches.
See `rtl/README.md` for build and simulation instructions.

## Links

- **Documentation:** [docs/00-index.md](docs/00-index.md) — the full reference tree
- **Live specs:** [BradISA V1](https://brad-devices.vercel.app/assets/specs/bradisa_spec.pdf) · [BradISA V2](https://brad-devices.vercel.app/assets/specs/bradisa_v2_ext.pdf)
- **Site:** [brad-devices.vercel.app](https://brad-devices.vercel.app)
- **Contact:** brad.devices.official@gmail.com
- **GitHub:** [Brad-Devices](https://github.com/Brad-Devices)

---

<p align="center"><em>One ISA, every core. Write it once; the scheduler decides where it runs. — The Architect</em></p>
