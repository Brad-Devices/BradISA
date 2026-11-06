# Kinetic Microarchitecture

**Status: DESIGNED.** The architecture is specified; no silicon exists.
**ISA:** BradISA V2 · **Powers:** BradCore · BradXon · Atlas Core
**Related:** `Brad Silicon/ARCHITECTURES.md` · `Brad Silicon/BradISA/ARCHITECTURE_GUIDE.md`
· `Brad Silicon/BradISA/ARCHITECTURE_REFERENCE_MODEL.md` ·
`src/spec/bradisa_spec.tex` (normative) · `Brad Software/OS/BRADABI.md`

Every claim carries a tag: **[SPEC]** specified in a normative document,
**[DESIGNED]** decided but not written normatively, **[TARGET]** an aspiration
with no design behind it.

---

## 1. The machine

Kinetic is a general-purpose CPU architecture with **two core designs that run
the same binary** — Phoenix, out-of-order, for throughput; Falcon, in-order,
for efficiency — and **no scalar floating-point registers at all**. Every float
lives in lane 0 of a 256-bit vector register.

**The register file, authoritatively:**

| | |
|---|---|
| General registers | **32 × 32-bit**, r0–r31, r0 hardwired zero |
| Vector registers | **32 × 256-bit**, VSET |
| Lane count | 8 × int32/FP32 · 16 × int16 · 32 × int8 · 4 × int64/FP64 |
| PC | 32-bit, 4-byte aligned |
| Vector ABI | v1–v4 arguments, v8–v15 callee-saved, **FP scalars in lane 0 of v1–v4** |
| Scalar ABI | r1–r8 arguments (a0–a7), r9–r14 temporaries, r15 link, r16–r26 callee-saved, r27 stack pointer, r28 global pointer, r29 thread pointer |

> **Note.** `ARCHITECTURE_REFERENCE_MODEL.md` §5 still documents the **Gen 1**
> state: 16 GPRs, r1–r4 arguments, r13 stack, r14 link, r15 PC. That is
> correct for Gen 1 and **stale against the V2 spec**, which widened the
> register file to 32 and moved the ABI in `ARCHITECTURES.md` §5.2. The
> reference model needs a V2 revision; this document carries the current state
> in the meantime.

**Why no scalar FP is a feature, not a saving.** A conventional core carries a
scalar FPU *and* a vector unit. Kinetic carries one FP datapath, the vector
one, and every core from Falcon upward can do FP64. **That is why an
efficiency core can run scientific code at all**, and it is the reason
Phoenix and Falcon share so much machinery.

---

## 2. The P/E contract

**[SPEC]** One binary. Phoenix and Falcon are **the same ISA**; the scheduler
decides where code runs; **software is never core-model-specific.**

**[DESIGNED]** The two cores differ in width, not in language.

| | Phoenix | Falcon |
|---|---|---|
| Pipeline | 10 stages, octa-issue, out-of-order | 5 stages, in-order, single-issue |
| ROB | 128 entries | — |
| Branch prediction | tournament, 12-bit global | static / BTFNT |
| Vector throughput | 256-bit/cycle | 128-bit/cycle (Gen1) |
| Sustains | high IPC, hot loops, interactive | low power, idle, background, NPU-fed |
| Target IPC | 2.2 typical, 5.0 peak | 0.9 typical, 1.0 peak |
| Target DMIPS/MHz | 5.5 | 2.2 |
| Target frequency | 3.0–5.2 GHz | 2.4–3.6 GHz |

**This is rare and worth more than it looks.** ARM's big.LITTLE spans a much
narrower ISA gap, and the gap is what makes the portability story hard. Here
the gap is width and depth, and the binary is identical.

**The consequence for the compiler, and it is a real one:** a program that runs
on both must not assume either the vector width or the vector throughput. The
narrower Falcon path is **half the vector width**, so a reduction decomposed
for Phoenix's 8 lanes is a different sequence on Falcon's 4.

**Open:** how the scheduler chooses a core per thread of execution, and whether
it can migrate. This is an OS policy, and it interacts with the shared address
space in `BRADABI.md`.

---

## 3. Phoenix — out-of-order

**[SPEC]** 10 stages, octa-issue, ROB 128, tournament branch prediction with a
12-bit global history.

**[DESIGNED]** Pipeline stages: *Issue — wakeup, select, read physical
register file; Execute — ALU / AGU / branch resolution; Memory — data cache
access; Writeback — result write to the physical register file; Commit — retire
from the ROB, update architectural state.*

**A warning from the record, and it belongs in a specification.** The
behavioural testbench for this pipeline shipped with three subtle defects that
CI did not catch for a long time:

1. **Stale operand reads** — the register file was read with the *previous*
   instruction's field addresses, so every operand was one instruction old.
2. **A cycle-late writeback** with a hazard that never covered a
   Decode-resident producer, which meant the hazard unit and the writeback
   stage disagreed about what was in flight.
3. **A dropped branch scaling** — the target address omitted the spec's ×4
   word scaling.

**The lesson, and it is architectural rather than anecdotal:** an out-of-order
core with a wide issue width has a correctness surface that a single person
cannot hold in their head, and **a green testbench that does not exercise every
opcode is not evidence.** The corpus is blunt about it: ADD/SUB/MUL/AND/OR/XOR/
SHL/SHR all shipped broken while CI stayed green, because the only testbench
exercised ADDI, BNZ and JMP.

**Which is why the V2 work carries the decode-coverage assertion** — every one
of the 64 slots explicitly assigned or explicitly reserved. A 16-case table
could be read by hand; a 64-case one cannot.

**Open:** the physical register file sizing, the load-store queue depth, and
whether the ROB is shared between the scalar and vector issue paths. None is
written down normatively.

---

## 4. Falcon — in-order

**[SPEC]** 5 stages: *Decode — instruction decode, register file read; Execute
— ALU / AGU / branch resolution, writeback; Writeback — register file write.*
Single-issue.

**[DESIGNED]** Static / BTFNT branch prediction, 128-bit/cycle vector on Gen1.

**Falcon is not a cut-down Phoenix.** It is a different machine for a different
job, and the in-order pipeline is what makes the efficiency claim credible:
a wide OoO core does not become efficient by being clocked down.

---

## 5. The vector unit — the only floating-point path

**[SPEC]** There is **no scalar floating-point register file.** Floating point,
ML and DSP live entirely in VSET, and a scalar read of a float is `V.EXT` while
a scalar write is a broadcast to all lanes.

**[SPEC]** **Match the element width (SEW) to the datapath:** 8×FP32, 4×FP64,
16×int16 per cycle at Phoenix's 256-bit/cycle; half that at Falcon's
128-bit/cycle.

**[SPEC]** **Reductions land in lane 0** — read scalars from there, not from
the GPRs.

**[DESIGNED]** Cross-lane operations are limited on Gen1. Gen2 adds SVEXT
predication, and v0 becomes the predication mask.

### 5.1 The honest criticism

> **Scientific codes reduce constantly, and the lane model penalises exactly
> that.** A reduction across 8 lanes is not a first-class operation, and the
> fallback — decomposing it into a sequence — is a compiler problem.

**Two things make this a compiler problem rather than a silicon problem,** and
both belong in the plan rather than in the silicon:

1. **The legaliser** decomposes a cross-lane reduction into a sequence that
   completes in registers. `TOROX_COMPILER_PLAN.md` §2.2 has the lane model as
   the first thing built, precisely because it is shared with Torox and
   precisely because it is hard.
2. **The same decomposition is portable across Phoenix and Falcon** if it is
   written for the narrower width — which is a scheduling decision the compiler
   must make with knowledge of the target core, and therefore a reason the
   compiler needs to know which core it is targeting.

**Open:** whether the compiler targets one core or both, and how it is told.

---

## 6. Memory

**[SPEC]** The pool is SPMP — the unified logical pool over the BradRAM
subsystem, the NeuroSense AI memory controller and the fabric. `BRADRAM_SPMP_ARCH.md`
is canonical.

**[SPEC]** `SPMP` is formed by BradRAM, the NeuroSense AI memory controller and
fabric integration. It is a **logical pool, not a physical memory**, and the
fabric is the coherence point.

**Owned elsewhere, and deliberately:** the page-table format, the TLB model,
the access classes and the fabric ordering are **BradOS's**, in
`Brad Software/OS/BRADABI.md`. They are not ISA properties and this document
does not define them. Kinetic implements against them.

**Open:** the L1 and L2 organisation per core, and the DTLB structure.

---

## 7. Privilege and exceptions

**[SPEC]** Two privilege levels, plus machine mode:

| Level | Purpose | Entry |
|---|---|---|
| **Machine (M)** | reset, SBI/firmware, secure monitoring (BradSec) | vector table at fixed addresses |
| **Supervisor (S)** | BradOS kernel | MTVEC-style vectored table |

**[SPEC]** Vectored exception table:

| Vector | Exception | Cause |
|---|---|---|
| 0x00 | reset / cold boot | — |
| 0x04 | undefined instruction | 1 |
| 0x08 | page fault | 2 |
| 0x0C | unaligned access | 3 |
| 0x10 | privilege violation | 4 |
| 0x14 | system call (ECALL) | 5 |

**[SPEC]** A **user mode** is specified in the reference model's privilege
section.

**[DESIGNED]** VSTATUS carries the vector enable, power and thermal status;
VSTATUS.VE gates vector execution so a context switch can leave the vector
unit quiescent.

**Open:** the exact `BRADABI.md` access-class encoding has to reach the
Kinetic TLB, and the fault path for a vector unit that runs for millions of
cycles is a Torox addition that has no home inside the Kinetic ISA work.

---

## 8. The ISA

**[SPEC]** BradISA V2, normative in `src/spec/bradisa_spec.pdf`:

- 64 opcodes, 6-bit primary field
- 32 general registers, 5-bit fields
- Seven formats — RRR, RI, SI, BR, IJ, JMP, U — **each exactly 32 bits**
- 50 instructions assigned, 14 slots explicitly reserved
- LUI and AUIPC, so a 32-bit address is two instructions
- JALR, so indirect calls exist
- Compare-branches, so `if (a < b)` is one instruction

**[SPEC]** The ISA is **published**, and that is deliberate: a specification
nobody may build on is not a standard. The moat is not the encoding.

---

## 9. What is specified, and what is not

| Area | State |
|---|---|
| Register file, ABI map, privilege levels, exception table | **[SPEC]** |
| Phoenix and Falcon stage structure and issue widths | **[DESIGNED]** |
| The vector lane model and the SEW rule | **[SPEC]** |
| The ISA encoding and instruction set | **[SPEC]** — normative PDF |
| Physical register file sizing, ROB internals, LSQ depth | open |
| The P/E scheduling policy and migration | open |
| L1/L2 organisation, DTLB structure | open |
| Access classes and page-table format | owned by `BRADABI.md` |
| The cross-lane reduction decomposition | a compiler problem — `TOROX_COMPILER_PLAN.md` §2.2 |
| Absolute IPC and frequency | **[TARGET]** — no IPC may be claimed |

---

## 10. Open items

1. **The reference model needs a V2 revision.** It documents 16 GPRs and the
   Gen 1 ABI. §1.
2. **Physical register file sizing, ROB internals, LSQ depth.** §3. These are
   what the behavioural testbench will actually exercise, and the record says
   the last time they were under-specified, three bugs shipped.
3. **The P/E scheduling policy and whether migration is possible.** §2.
4. **L1/L2 and the DTLB.** §6.
5. **How the compiler targets one core or both.** §5.1. A binary that runs on
   both must not assume either vector width.
