# BradISA — Shipped Reference Toolchain Guide

> The BradVector toolchain ships *before* the silicon: everything below runs
> today, unattended in CI, hosted on any POSIX system and in the browser via
> WASM. All binaries are stdlib-only; no external dependencies.

---

## Overview

| Tool | What it is | Input → Output |
|------|-----------|---------------|
| **bradc** | BradVector assembler | `.basm` source → `.bvbc` bytecode image |
| **BVRT** | 32-lane SIMT virtual machine | `.bvbc` → runs vector ops, checks results |
| **bradgdb** | symbol-aware debugger | attaches to BVRT; breakpoints by instruction index |
| **BradTimeline** | cycle-level profiler | BVRT execution → CSV trace + per-opcode histogram |
| **braddev** | one-binary dev CLI | wraps all of the above; `cvt / run / dbg / timeline / gpu` |
| **bradlib.h** | stable host API | compile → pack → session → launch → run → inspect → breakpoints |
| **WASM** | browser build | `bradlib.h` API → `js/bradvector.js` (in-browser assemble/run/debug) |

---

## File Formats

### `.basm` — source format

Plain-text BradVector assembly. Mnemonics are case-insensitive; line comments
use `;`. Labels use `:` suffix. The assembler resolves labels, validates
operand widths, and rejects ill-formed instructions with a line-level error.

### `.bvbc` — BradVector Bytecode

Portable bytecode image: a flat array of 32-bit instructions with a compact
header (entry point, section offsets, symbol table). The format is designed
for round-trip fidelity: `bradc` emits a `.bvbc` that `bradgdb` can load
and symbol-resolve without reassembly.

---

## Quick Start

### Assemble + run

```bash
braddev cvt  saxpy.basm            # → saxpy.bvbc
braddev run  saxpy.bvbc            # runs across all 32 lanes; exits 0 on success
```

### Debug interactively

```bash
braddev dbg  saxpy.bvbc
> break 4                          # break at instruction index 4
> run                              # stops at breakpoint 4
> regs                             # show all 16 GPRs + PC
> step 2                           # single-step 2 instructions
> quit
```

### Profile execution

```bash
braddev timeline  saxpy.bvbc       # runs, emits saxpy_trace.csv + summary
```

### GPU info (on hardware or simulated fabric)

```bash
braddev gpu info                    # device topology, VRAM, fabric lanes
braddev gpu top                     # live lane utilization (in-app)
```

### Run full test suite

```bash
braddev test                        # 11/11 green; round-trip + saxpy + fib
```

---

## bradc — Assembler Internals

`bradc_assemble()` takes a source string and fills a `bvbc_image` struct
with the bytecode payload and a symbol table. If assembly fails, the error
struct carries the failing line number and a human-readable message.

The symbol table (`bradc_symbols()`) is loaded into `bradgdb` so breakpoints
can be set by address with symbolic context (function name, label offset).

**Round-trip invariant:** `bradc` → `.bvbc` → disassemble → reassemble →
`.bvbc` produces an identical bytecode image (verified in CI).

---

## BVRT — SIMT Virtual Machine

BVRT is a 32-lane scalar-relaxed SIMT interpreter. Each instruction executes
in lockstep across all enabled lanes; lane masks track divergence. The VM
exposes a flat register file (16 × 32-bit GPRs) plus 32 × 256-bit vector
registers, matching the architectural state.

The host communicates through `bradlib.h`: compile → pack → session →
launch → run → inspect registers → set breakpoints → continue → read results.

---

## bradgdb — Debugger

Attaches to a running BVRT device. Capabilities:

- **Breakpoints:** up to 64 instruction-index breakpoints; enable/disable by ID.
- **Single-step:** advance one or N instructions; each step echoes the
  executed instruction and the lane mask.
- **Register inspect:** dump all 16 GPRs + PC at the current stop point.
- **Tracing mode:** optional echo of every instruction as it executes.

Breakpoint IDs are stable across a debug session; disabling a breakpoint
does not reclaim its slot.

---

## BradTimeline — Profiler

Wraps BVRT execution and records a per-instruction event trace:

| Field | Meaning |
|-------|---------|
| `cycle` | cumulative instruction count at this event |
| `pc` | instruction index |
| `op` | opcode retired |
| `active_lanes` | number of lanes active before this instruction |

Post-run, the summary includes:

- **Total instructions retired** and **total lanes executed** (aggregate)
- **Per-opcode retire histogram** (256 entries)
- **Trap count**
- **Per-kernel stats** (when running multiple kernels)

Output: CSV trace file + terminal summary.

---

## bradlib.h — Host API

The stable, versioned interface between user code and the BradVector
platform. The pipeline:

```
compile (.basm → .bvbc)  →  pack (image)  →  session  →  launch
     →  run  →  inspect (regs/mem)  →  breakpoints  →  continue
```

Exposed 1:1 to the browser via WASM — the same API runs in a native CLI
tool and in a browser tab (`site/js/bradvector.js`).

---

## WASM Browser Build

The `.o` objects for `bradc`, `BVRT`, `bradgdb`, and `bradlib` are compiled
to WASM and wired into the site. Users can assemble, run, and debug BradVector
code directly in the browser — no install required. The in-browser build is
part of CI and is verified on every push.

---

## What this toolchain proves

This is not a stub. The assembler rejects bad code with line-level errors;
the VM runs real vector kernels across 32 lanes; the debugger sets real
breakpoints; the profiler produces real instruction traces. All of it runs
unattended in CI on every push, and the browser build runs in production.

The shipped toolchain is the moat: the silicon comes later; the software
ecosystem already works.

---

*Source: `src/bradvector/` (bradc, bvrt, bradgdb, bradtimeline, bradlib); `src/bradvector/tools/bradc-cli.c` (braddev); `src/wasm/` (browser build). All ships first.*
