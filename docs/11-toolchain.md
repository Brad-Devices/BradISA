# Toolchain and Reference Implementations

This repository bundles **one toolchain component that this repository itself
runs on**: the `bradasm` assembler under `tools/bradasm/`. It builds with
nothing but a C99 compiler, and the same executable that assembles the board's
boot program is exercised by CI on every change. It ships no cross
compilers, emulators, or debuggers.

## What ships in this repository

| Component | Status |
|---|---|
| `spec/bradisa_spec.tex`, `spec/bradisa_v2_ext.tex` | normative ISA specification |
| `rtl/verilog/`, `rtl/vhdl/` | reference core RTL |
| `rtl/fpga/` | FPGA constraints and build scripts |
| `rtl/asm/` | the full-ISA program both testbenches load (assembled with bradasm) |
| `tools/bradasm/` | the bundled assembler (C99 source, Makefile, self-test) |
| `docs/` | programmer-visible guides |

There is no `bradc`, `bradvm`, `bradgdb`, or `braddev` in this repository.
`bradasm` is the only tool.

## bradasm (bundled)

`tools/bradasm/` is a two-pass assembler for BradISA V1. It resolves labels
(including forward references), validates operand widths, and computes the
16-bit word offsets for branches and jumps so that nobody has to hand-decode
`(target − pc − 4) / 4` again. Hand-encoding words is how `0x82000007`
quietly meant "ADDI r2" while someone believed it meant "ADDI r1, r0, 7" —
this tool exists to end that.

    make -C tools/bradasm          # builds build/bradasm and build/test_brad_as
    make -C tools/bradasm test     # 102-check self-test, incl. RTL drift guard

The self-test parses `rtl/verilog/bradisa_defines.v` and fails if the
assembler's opcode table has drifted from the RTL, and it asserts the board
boot ROM and its encodings word for word.

### Command line

    bradasm [options] <source.s>

| Option | Effect |
|---|---|
| `-o FILE` | write the flat little-endian binary image (default `a.bin`) |
| `-V FILE` | write a Verilog boot-ROM include: an `initial begin` block that fills `imem[addr>>2]` (what the Tang Nano 9K top `include`s) |
| `-m FILE` | write one `%08X` word per line, in address order — the format `$readmemh` and GHDL textio read |
| `-e ADDR` | override the entry point |
| `-l` | print a listing: address, encoded word, source line |
| `-s` | print the symbol table |
| `-S` | print symbols and exit without writing an image |
| `-q` | quiet |

`-V` and `-m` are how this repository turns one source of truth into images
the RTL actually consumes: `rtl/fpga/tangnano9k/boot.s` becomes the board ROM
include, and `rtl/asm/tb_brad_isa.s` becomes the program both ISA regression
testbenches load. Both generated files are checked in so the trees simulate
without a C compiler; CI regenerates each and fails on a diff
(`make -C rtl/fpga boot_rom_check`, `make -C rtl/asm check`), so a stale
image cannot survive a commit. "The program is written in assembly" is
enforced, not assumed.

### Assembly syntax

| Syntax | Meaning |
|---|---|
| `; …` | comment to end of line |
| `name:` | label (defines the current address) |
| `.org N` | set the current address; must keep it word-aligned |
| `.word expr, …` | emit 32-bit words |
| `.half expr, …` | emit 16-bit halfwords |
| `.byte expr, …` | emit bytes |
| `.entry expr` | set the entry point (defaults to `0x00000000`, the reset vector) |
| `.equ name, expr` | define a numeric constant |
| `.fill count, value` | emit `count` copies of `value`, e.g. `.fill 11, 0x81000000` |
| `.align N` | pad with zeros up to the next `N`-byte boundary (power of two) |
| `$` | the current address (`$` = `.`, the program counter) |

Registers are `r0`–`r15`, with the aliases `zero` (r0), `sp` (r13), `lr`
(r14), and `pc` (r15). Mnemonics and register names are case-insensitive.

### Instructions

| Form | Example | Notes |
|---|---|---|
| RRR | `ADD r1, r2, r3` | also `SUB`, `MUL`, `AND`, `OR`, `XOR`, `SHL`, `SHR` |
| RI | `ADDI r1, r2, 8` | also accepts negative immediates |
| load | `LDW r1, [r2 + 4]` | or `LDW r1, r2, 4` |
| store | `STW r3, [r2 + 4]` | or `STW r3, r2, 4` |
| branch | `BZ r1, label` / `BNZ r1, label` | PC-relative in word units |
| jump / call | `JMP label` / `CALL label` | |
| return | `RET` | returns through lr (r14) |
| aliases | `NOP` (= `ADDI zero, zero, 0`), `MV rd, rs` (= `ADD rd, rs, zero`) | |

`CALL` always writes the link register r14; naming any other register as the
link is an error rather than a silently ignored operand. The branch/jump
immediate is a 16-bit *word* offset, matching the RTL's
`target = pc + 4 + sext(imm) × 4`, so branches and calls span ±128 KiB.

BradISA V1's compressed forms (`C.ADD`, `C.ADDI`, `C.LDW`, `C.STW`, `C.BZ`,
`C.BNZ`, `C.MV`, `C.NOP`, `C.JMP`, `C.CALL`) are **rejected with a clear
error**. There is no compressed decode path in the shipped core, and silently
reinterpreting a 16-bit form as 32-bit garbage is worse than refusing it.

### Assembler API

The assembler is a C library as well as a command line tool:

```
int brad_as_assemble(const char *source, struct brad_as_output *out);
size_t brad_as_assemble_listing(const char *source, struct brad_as_output *out,
                                struct brad_as_listing *listing, size_t cap);
int brad_as_byte(const struct brad_as_output *out, uint32_t addr, uint8_t *byte);
int brad_as_lookup(const struct brad_as_output *out, const char *name,
                   uint32_t *addr);
```

`struct brad_as_output` carries the emitted `code[]` (a 256 KiB image whose
`.org` gaps are zero), the `base_addr`/`limit_addr` span, the `entry_point`,
a symbol table (`name` + `addr`), and a line-level `error`. The listing API
records what the assembler itself produced — one row per emitted word plus
one row per label — because a listing that is parsed out of the source text
afterwards is a second, weaker parser that will disagree with the first one.

## Reference emulator (source kit, not bundled)

The Brad Devices source kit contains a second reference implementation, the
`brad_core_emu` cycle-approximate core and SoC emulator. It is not part of
this repository.

| Function | Description |
|---|---|
| `brad_soc_emu_init(soc, clusters, phoenix, falcon)` | initialise a heterogeneous SoC |
| `brad_soc_emu_init_ex(…, kestrel, falcon_lite)` | include the additional core models |
| `brad_core_emu_init(core, model, entry_pc, sp)` | initialise one core |
| `brad_core_emu_load(soc, program, words, addr)` | load a program image |
| `brad_core_emu_step(soc, cluster, core)` | execute one instruction |
| `brad_core_emu_run(soc, cluster, core, max_cycles)` | run one core |
| `brad_core_emu_run_all(soc, max_cycles)` | run every core |
| `brad_core_read_reg` / `brad_core_write_reg` | architectural register access |
| `brad_core_read_msr` / `brad_core_write_msr` | MSR access |
| `brad_core_emu_disasm(insn, buf, size)` | disassemble one instruction |

The core state tracks the pipeline model (Falcon-Lite, Falcon, Kestrel,
Phoenix), stall counters, branch statistics, cache hits/misses, compressed
mode, and the MSR set documented in [MSR reference](07-msr-reference.md).

## Scope and authority

- `bradasm` is bundled and is the tool this repository's own CI, testbenches,
  and board boot ROM depend on, but it remains a reference assembler.
- The emulator is cycle-approximate; it is a software model, not a performance
  claim.
- The normative specification is the LaTeX source under `spec/`. Where a
  guide or model disagrees with it, the spec wins — except where the RTL and
  the spec disagree, in which case the RTL wins and the prose gets corrected.

See also: [FPGA](12-fpga.md) for simulating the RTL, and the
[BradVector repository](https://github.com/Brad-Devices/BradVector)
for the separate GPU/accelerator ISA and its shipped toolchain.