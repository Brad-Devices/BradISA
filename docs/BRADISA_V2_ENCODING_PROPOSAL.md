# BradISA V2 — Encoding Growth Proposal

**Status: PROPOSAL. Nothing in this document has been applied.**
**Date: Oct 2026**
**Scope: `src/spec/bradisa_spec.tex` §2 (Register File), §3 (Instruction Formats), §4 (Instruction Set), and the `BRADISA_VS_RISCV.md` §2.1 decode claim.**

---

## 1. The problem, stated precisely

BradISA V1 cannot address more than 64 KB from any base register.

```
RI = { op[3:0], rd[3:0], rs1[3:0], imm[15:0] }      imm sign-extended to 32
```

`LDW` therefore reaches `rs1 ± 32767`, and no instruction loads a 32-bit
constant. Consequences, in order of severity:

- **no data segment beyond 64 KB, no heap** — no linked executable, therefore no libc
- **no function pointers, no vtables, no callbacks** — `CALL` is direct-only
- **no array over 16,384 elements**
- **16 GPRs** (`r0`–`r15`), of which `r0` is hardwired zero and `r15` is the read-only PC

This is not a missing feature list. It is a functional ceiling, and it is why
LLVM cannot target V1 — not "compiles badly", **cannot compile**.

The three gaps `TOOLCHAIN_STRATEGY.md` §2.2 names (atomics, compare-branches,
LUI/AUIPC+JALR) are the visible symptoms of it.

## 2. Why "just add three instructions" is not available

The V1 opcode space is **completely full**:

```
0x0 ADD  0x8 ADDI   0x1 SUB  0x9 LDW    0x2 MUL  0xA STW
0x3 AND  0xB BZ     0x4 OR   0xC BNZ    0x5 XOR  0xD JMP
0x6 SHL  0xE CALL   0x7 SHR  0xF RET
```

Sixteen opcodes, sixteen allocated, zero free.

And `BRADISA_VS_RISCV.md` §2.1 sells exactly this as the design win:

> *"The entire scalar decoder is 16 cases. Decode state — **zero** — 16 cases."*

**The property the ISA is proudest of is the property that prevents it growing.**
Any added instruction costs the claim. An ISA cannot both have a 4-bit
exhaustive opcode space and address memory.

Option A — grow the opcode field — was approved. This document specifies it.

## 3. Correction: 5 bits is not enough

An earlier recommendation in this review proposed **5 bits / 32 opcodes**. That
number is wrong, and the arithmetic is worth recording because it changes the
answer.

What Clang's integer subset actually emits:

| Group | Count | Instructions |
|---|---|---|
| ALU reg-reg | 12 | ADD SUB MUL DIV REM SREM AND OR XOR SHL SHR SAR |
| ALU reg-imm | 6 | ADDI ANDI ORI XORI SHLI SARI |
| Load / store | 6 | LDW STW LBU LHU SB SH |
| Upper immediate | 2 | LUI AUIPC |
| Control | 4 | JALR JMP CALL RET |
| Branches | 8 | BZ BNZ BEQ BNE BLT BGE BLTU BGEU |
| Ordering | 1 | FENCE |
| Atomics | 4 | LR.W SC.W AMOADD.W AMOSWAP.W |
| **Total** | **43** | |

```
4-bit -> 16 slots : SHORT BY 27
5-bit -> 32 slots : SHORT BY 11
6-bit -> 64 slots : fits, with room for NOP and a reserved vector range
```

Two ways to close an 11-instruction gap at 5 bits: fold the reg-imm ALU
variants into the reg-reg opcodes behind a `funct` field, or push atomics to a
later version. Both work. Both cost something real:

- **Folding** reintroduces the `funct3`/`funct7` sub-hierarchy that §2.1
  explicitly names as the RISC-V property BradISA exists to avoid. The decoder
  stops being 32 flat cases and starts being a table of tables.
- **Deferring atomics** means the backend ships without working
  `std::atomic`, and the ISA has to be re-broken a third time to add them.

There is a third factor that decides it. **Nothing has ever executed on BradISA
silicon.** There are no V1 binaries, no deployed toolchain, no customers. Every
encoding break today is free. In three years, when `bradasm` has users and
boot ROMs exist in the field, a break costs a migration. **A re-break is cheap
now and expensive later, so the correct move is to pick a width that does not
need re-breaking.**

### Recommendation

> **V2 uses a 6-bit opcode field — `op[5:0]`, 64 slots — and 5-bit register
> fields, `rd[4:0]`, `rs1[4:0]`, `rs2[4:0]`, for 32 registers.**

The decode stage stays a **single flat exhaustive table of 64 cases**. It stays
zero-hierarchy. The only thing that changes is the number in a sentence: 16
becomes 64.

**This is not a new idea for this repository.** `src/rtl/bradvector_core.v`
already ships exactly this configuration:

```
src/rtl/bradvector_core.v:27   localparam REG_ADDR_W = 5
src/rtl/bradvector_core.v:28   localparam NUM_REGS     = 32
src/rtl/bradvector_core.v:41   wire [4:0] slot0_opcode
```

The vector core already has a 5-bit opcode, a 5-bit register address width and
32 registers, verified in CI. **The scalar ISA is the outlier that never grew.**
V2 ports the vector core's proven encoding to the scalar side, and the argument
becomes consistency rather than novelty.

## 4. Proposed V2 opcode map

64 slots. Reserved ranges are stated, not left blank.

```
0x00-0x0F  ALU, register-register        (12 used, 4 reserved)
0x10-0x1F  ALU, register-immediate      ( 6 used, 10 reserved)
0x20-0x27  Load / store                 ( 6 used, 2 reserved)
0x28-0x2F  Upper immediate              ( 2 used, 6 reserved)
0x30-0x3F  Control transfer             ( 4 used, 12 reserved)
0x40-0x4F  Branches                     ( 8 used, 8 reserved)
0x50-0x5F  Atomics and memory ordering  ( 5 used, 11 reserved)
0x60-0x63  Vector escape                (4 reserved — see §7)
```

Control transfer keeps twelve spare slots deliberately. It is the group that
grows: `CALL` variants, indirect tail calls, and link-register handling all land
there without another break.

## 5. Format changes

All four V1 formats are re-cut for a 6-bit opcode and 5-bit register fields.
Two of them must change width regardless of opcode size.

| Format | V1 | V2 | Change |
|---|---|---|---|
| RRR | `{op[3:0], rd[3:0], rs1[3:0], rs2[3:0], 16'b0}` | `{op[5:0], rd[4:0], rs1[4:0], rs2[4:0], 11'b0}` | fields widen, pad shrinks |
| RI | `{op[3:0], rd[3:0], rs1[3:0], imm[15:0]}` | `{op[5:0], rd[4:0], rs1[4:0], 6'b0, imm[16:0]}` | **imm widens** |
| BR | `{op[3:0], 4'b0, rs1[3:0], 4'b0, offset[15:0]}` | `{op[5:0], rs2[4:0], rs1[4:0], cond[4:0], offset[16:0]}` | **gains rs2 for compare-branches** |
| JMP | `{op[3:0], 8'b0, offset[19:0]}` | `{op[5:0], 8'b0, offset[18:0]}` | offset narrows one bit |
| **U** | — | `{op[5:0], rd[4:0], imm[20:0]}` | **new — LUI/AUIPC** |
| **IJ** | — | `{op[5:0], rd[4:0], rs1[4:0], 6'b0, imm[16:0]}` | **new — JALR** |

Notes:

- **BR gains `rs2`.** `BZ`/`BNZ` test one register against zero; `BEQ`/`BLT`
  and their friends need two. Without `rs2` in the format, every `if (a < b)`
  compiles to a `SUB` plus a `BNZ`, and the backend's job gets strictly harder.
- **JMP offset narrows 20→19 bits.** Six opcode bits and one fewer offset bit
  is the cheapest place to pay for the growth: it costs `±4 MiB` of unconditional
  jump range, which is more than `LUI`+`ADDI` can address anyway once the new
  upper-immediate path exists.
- **U and IJ are new formats, not new opcodes.** The decoder still sees one flat
  64-entry table; formats are documentation of bit layout, not a decode level.

## 6. DECISION REQUIRED — the register file and the ABI

**This is not decided by this proposal and needs an explicit answer.**

Option A as originally framed was the opcode field. The register file is a
separate and larger decision, and the ABI as currently written is the more
serious problem.

V1 ABI register map, from `bradisa_spec.tex` §2:

```
r0  zero     r5  t0     r8  s0     r10 s2     r13 sp
r1  a0       r6  t1     r9  s1     r11 s3     r14 lr
r2  a1       r7  t2     r10 s2     r12 s4     r15 pc  (read-only)
r3  a2                         
r4  a3
```

Counting what is actually available to a register allocator:

| | BradISA V1 | RISC-V RV32I | x86-32 |
|---|---|---|---|
| General registers | 16 | 32 | 16 |
| Usable for computation | **~8** | 31 | ~13 |
| **Argument registers** | **4** (a0–a3) | 7 (a0–a6) | 8 |
| Temporaries | 3 (t0–t2) | 6 (t0–t5) | — |

**Four argument registers is the binding constraint.** Every call with a fifth
argument spills to the stack. Clang will emit it correctly, but struct returns,
variadics and any non-trivial signature generate heavy stack traffic — before a
single line of backend code exists.

Combined with `r15` being spent on a read-only PC, a register file that is
already small is allocated thinly enough that the allocator has almost nothing to
work with.

### Options

- **V2-A — 32 registers, RISC-V-style ABI (7 arguments).** 5-bit fields, matching
  `bradvector_core.v`'s existing `NUM_REGS = 32`. Cost: a new ABI, which is
  free today for the reason in §3.
- **V2-B — 32 registers, wider argument set (8+).** As above, plus `s5`–`s11`
  for callee-saved headroom. Slightly more die area on the register file.
- **V2-C — keep 16 registers.** Cheapest. Accepts structurally poor codegen for
  anything with more than four parameters, permanently, and makes the LLVM
  backend's job materially harder than it needs to be.

**Recommendation: V2-A.** The register file is the one piece of this ISA that
scales with process and costs almost nothing — 32 × 32-bit registers is a
rounding error against a core that already carries a 32 × 256-bit vector file.

## 7. Two defects found in the V1 spec while scoping this

Neither is introduced by V2. Both are in the current normative text and should
be fixed in the same pass.

**7.1 — The RI format array does not add to 32 bits.**

```
RRR = 4 + 4 + 4 + 4 + 16 = 32   ok
RI  = 4 + 4 + 4 + 16     = 28   SHORT BY 4
BR  = 4 + 4 + 4 + 4 + 16 = 32   ok
JMP = 4 + 8 + 20         = 32   ok
```

The RI diagram is worse than the array. `imm[15:0]` is drawn with
`\bwsliceh{16}{16}`, which places it at bits 31:16 — **overlapping `op`, `rd`
and `rs1`.** Two representations of the same format, disagreeing, one of them
not describing a 32-bit word. A normative encoding table has to be
unambiguous, because it is the thing a TableGen target is transcribed from.

**7.2 — Opcode `0xF` means two different things.**

The scalar table assigns `0xF = RET`. The vector section states that *all*
vector instructions use opcode `0xF`, disambiguated by a class field in bits
`[27:25]`, with `0xF0000000` pinned to RET. The whole vector ISA shares one
opcode with RET and is distinguished by everything else in the word.

It is coherent as written and it is fragile — the entire vector extension depends
on `RET` having exactly one encoding, and any second 32-bit pattern that collides
silently becomes a vector instruction. §4's reserved vector range removes this.

## 8. What breaks

| Artefact | Impact | Recovery |
|---|---|---|
| `bradisa_spec.tex` §3, §4 | every field shifts | rewritten wholesale |
| `BRADISA_VS_RISCV.md` §2.1 | "16 cases" → "64 cases"; the comparison table's headline | reworded, claim preserved in substance |
| Falcon RTL | decode ROM/case statement, register file ports | 64-case table; reg file 16→32 if V2-A/B |
| `bradasm` assembler | encoder + 102-check self-test | self-test regenerates the reference encodings |
| behavioral testbench | every hand-written instruction word | regenerate from assembly, never hand-typed |
| boot ROM | re-assembled | already assembler-produced, so mechanical |
| any V1 binary | **none exist** | — |

The register file is the only row with a real risk: widening ports touches the
pipeline's read/write bandwidth assumptions, and `Performance Characteristics`
§7 will need re-measuring rather than re-reading.

## 9. Regression plan

The existing gates carry the ISA. All three must be re-run after the change,
and the second one must be extended, not merely satisfied.

1. **Behavioural testbench (Verilog + VHDL).** Both trees, both must agree.
2. **`bradasm` self-test, 102 checks.** Regenerates reference encodings from
   assembly sources and fails on any diff — this is the encoding tripwire.
3. **Boot ROM and testbench image diff.** Any change here is an unannounced
   encoding change.
4. **NEW — a decode-coverage assertion.** Every one of the 64 slots must be
   explicitly assigned or explicitly marked reserved. An unassigned slot in a
   flat table is a silent hole, and a silent hole in a decoder is how you get an
   instruction that executes as something else. This gate does not exist today
   because a 16-case table was small enough to read by hand; a 64-case table is
   not.

## 10. Reopening conditions

- If the ABI decision (§6) lands on **V2-C, keep 16 registers**, then the opcode
  growth is still required but the register fields stay 4-bit, and every V1
  format above keeps its register widths. The opcode map is unaffected.
- If atomics are deferred past V2, the `0x50` range absorbs them and 6 bits
  remains the right width.
- Nothing in this proposal should be applied to `bradisa_spec.tex` without §6
  answered first, because the register-width answer changes the format table.

---

## What this is, and what it is not

This is a **DESIGNED** proposal. It changes a published ISA encoding, so it is
a bigger commitment than dropping a memory tier.

What it buys, stated honestly: **an ISA that LLVM can target at all.** Right now
the toolchain strategy's headline claim — that the LLVM backend is the moat — is
gated on an ISA that cannot address its own heap. Closing that is the difference
between a plan and a precondition.

What it does not buy: a working backend. That remains roughly a one-to-two
engineer-year effort for the integer subset alone, followed by the vector
selection problem, which is the hardest part and is deliberately not in scope
here.

The next receipt after this one is not a TableGen target. It is the RTL
implementing `LUI`, `AUIPC` and `JALR`, passing the behavioural testbench, with
`bradasm` regenerating every encoding from assembly. Only after that does
TableGen make sense.