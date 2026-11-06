# BradISA — Quick Reference Card

> **Encoding changed in V2.** The opcode and register tables below this
> line are **V1** and describe a superseded encoding: 16 GPRs, 4-bit
> opcode, 16 opcodes, no `LUI`/`AUIPC`/`JALR`, and therefore an ISA that
> cannot address memory beyond 64 KB. The normative encoding is
> `src/spec/bradisa_spec.pdf` (V2, 6-bit opcode, 32 registers, 50
> instructions). This page has not been rewritten yet and is retained
> as the V1 record.


> Everything you need to write and read BradISA assembly, on one page.
> *Source of truth: `bradisa_spec.tex` (V1) + `bradisa_v2_ext.tex` (V2).*

---

## Data Model

| Parameter | Value |
|-----------|-------|
| Word size | 32 bits (4 bytes) |
| Address space | 32-bit byte-addressed, little-endian |
| Instruction length | 32 bits fixed (Gen1); 16-bit compressed mode available (V2) |
| Page size | 4 KiB |

---

## Registers

### Scalar GPRs (16 × 32-bit)

| Reg | ABI | Purpose |
|-----|-----|---------|
| r0 | zero | Hardwired zero — writes discarded |
| r1 | a0 | Argument 0 / return value |
| r2 | a1 | Argument 1 |
| r3 | a2 | Argument 2 |
| r4 | a3 | Argument 3 |
| r5 | t0 | Temporary 0 |
| r6 | t1 | Temporary 1 |
| r7 | t2 | Temporary 2 |
| r8 | s0 | Callee-saved 0 |
| r9 | s1 | Callee-saved 1 |
| r10 | s2 | Callee-saved 2 |
| r11 | s3 | Callee-saved 3 |
| r12 | s4 | Callee-saved 4 |
| r13 | sp | Stack pointer |
| r14 | lr | Link register |
| r15 | pc | Program counter (read-only) |

### Vector Registers (32 × 256-bit, VSET)

| Reg | ABI | Purpose |
|-----|-----|---------|
| v0 | vm | Mask / zero-vector (Gen2 predication reserved) |
| v1 | va0 | Vector arg 0 / return value |
| v2 | va1 | Vector arg 1 |
| v3 | va2 | Vector arg 2 |
| v4 | va3 | Vector arg 3 |
| v5–v7 | vt0–vt2 | Caller-saved temporaries |
| v8–v15 | vs0–vs7 | Callee-saved |
| v16–v31 | vt3–vt18 | Caller-saved temporaries |

---

## Instruction Formats

### RRR — ALU (register-to-register)

```
31   28 27   24 23   20 19   16 15                  0
+--------+--------+--------+--------+-----------------+
| op     | rd     | rs1    | rs2    |    0 (unused)   |
+--------+--------+--------+--------+-----------------+
  4-bit    4-bit    4-bit    4-bit    16 bits reserved
```

### RI — Register-Immediate

```
31   28 27   24 23   20 19                               0
+--------+--------+--------+-------------------------------+
| op     | rd     | rs1    |    signed imm16                |
+--------+--------+--------+-------------------------------+
  4-bit    4-bit    4-bit    sign-extended to 32 bits
```

> **STW note:** rs2 (store data) occupies the `rd` field; the actual `rd` field is ignored.

### BR — Branch

```
31   28 27   24 23   20 19   16 15                       0
+--------+--------+--------+--------+----------------------+
| op     |   0    | rs1    |   0    |  offset (×4 words)  |
+--------+--------+--------+--------+----------------------+
```

Target: `PC = insn_pc + 4 + sext(offset × 4)` — range ±128 KiB.

### JMP / CALL

```
31   28 27                              20 19                0
+--------+--------------------------------+--------------------+
| op     |           0 (reserved)         |  offset (×4 words) |
+--------+--------------------------------+--------------------+
```

Target: `PC = insn_pc + 4 + sext(offset × 4)` — range ±4 MiB.

### RET

```
31                                                         0
+-----------------------------------------------------------+
|                    0xF0000000                             |
+-----------------------------------------------------------+
```

Branches to `lr` (r14). Does not modify lr.

---

## Instruction Set — V1 Base

| Op | Mnemonic | Format | Semantics |
|----|----------|--------|-----------|
| 0x0 | ADD | RRR | rd = rs1 + rs2 |
| 0x1 | SUB | RRR | rd = rs1 − rs2 |
| 0x2 | MUL | RRR | rd = rs1 × rs2 (low 32 bits) |
| 0x3 | AND | RRR | rd = rs1 & rs2 |
| 0x4 | OR | RRR | rd = rs1 \| rs2 |
| 0x5 | XOR | RRR | rd = rs1 ^ rs2 |
| 0x6 | SHL | RRR | rd = rs1 << rs2[4:0] |
| 0x7 | SHR | RRR | rd = rs1 >> rs2[4:0] (logical) |
| 0x8 | ADDI | RI | rd = rs1 + sext(imm16) |
| 0x9 | LDW | RI | rd = mem[rs1 + sext(imm16)] |
| 0xA | STW | RI | mem[rs1 + sext(imm16)] = rs2 |
| 0xB | BZ | BR | if rs1 == 0: branch |
| 0xC | BNZ | BR | if rs1 != 0: branch |
| 0xD | JMP | JMP | Unconditional jump |
| 0xE | CALL | JMP | lr = insn_pc + 4; jump |
| 0xF | — | — | *Vector (VSET) or RET* (see below) |

---

## Calling Convention

| Rule | Detail |
|------|--------|
| Args (scalar) | r1–r4 (return value in r1) |
| Args (vector) | v1–v4; FP scalars in lane 0 of v1–v4 |
| Callee-saved (scalar) | r8–r12 |
| Callee-saved (vector) | v8–v15 |
| Stack | Grows down; 16-byte aligned; r13 = sp |

---

## Exceptions

| Vector | Exception | Cause |
|--------|-----------|-------|
| 0x00 | Reset / cold boot | — |
| 0x04 | Undefined instruction | 1 |
| 0x08 | Page fault | 2 |
| 0x0C | Unaligned access | 3 |
| 0x10 | Privilege violation | 4 |
| 0x14 | System call (ECALL) | 5 |
| 0x18 | Timer interrupt | 6 |
| 0x20–0x2C | External IRQ 0–3 | 7 |

---

## MSR Map

### V1 MSRs

| Idx | Name | Description |
|-----|------|-------------|
| 0 | STATUS | Processor status flags (IE, SVC, HALTED, WFE, EXC_PEND) |
| 1 | CAUSE | Cause of last exception |
| 2 | EPC | Exception program counter |
| 3 | EAR | Exception address register |
| 4 | PAGE_BASE | Page table base address |
| 5 | TICK | Cycle count timer |
| 6 | CORE_ID | Core identifier |
| 7 | CLUSTER_ID | Cluster identifier |

### V2 MSRs (additions)

| Idx | Name | Description |
|-----|------|-------------|
| 8 | PM_CTRL | Power management control |
| 9 | PSTATE | Current P-state |
| 10 | PSTATES | Available P-states bitmap |
| 11 | VOLTAGE | Core voltage (mV) |
| 12 | FREQ | Core frequency (MHz) |
| 13 | ENERGY | Accumulated energy (µJ) |
| 14 | PWR_CAP | Power cap (mW) |
| 15 | TEMP | Die temperature (°C) |
| 16 | PERF_CNT0 | Performance counter 0 |
| 17 | PERF_CNT1 | Performance counter 1 |
| 18 | PERF_CNT_CTRL | Perf counter control |
| 19 | L2_PART | L2 cache partitioning |
| 20 | L3_PART | L3 cache partitioning |
| 21 | CG_MASK | Clock-gating unit mask |
| 22 | DBG_CTRL | Debug control |
| 23 | VSTATUS | Vector unit status |

### VSTATUS (MSR 23) Flags

| Bit | Name | Description |
|-----|------|-------------|
| 0 | VE | Vector unit enable (0 → trap on any vector insn) |
| 1–4 | resv | Reserved |
| 5 | VILL | Sticky: illegal vector encoding executed |
| 6 | VFP | Sticky: FP exception flag (write-1 to clear) |

---

## Vector Extension (VSET) — Quick Summary

**Registers:** 32 × 256-bit; SEW selects lane width: 32×int8 / 16×int16 / 8×int32 or FP32 / 4×int64 or FP64.

**Encoding:** all instructions use opcode 0xF (bits [31:28] = 0xF); class field in bits [27:25]. `0xF0000000` always = RET.

| Class | Format | Operations |
|-------|--------|-----------|
| 000 | VV | V.ADD, V.SUB, V.MUL, V.AND, V.OR, V.XOR, V.SHL, V.SHR, V.MIN, V.MAX, V.CMPEQ, V.CMPLT, V.ABS, V.MOV |
| 001 | VV | V.FADD, V.FSUB, V.FMUL, V.FMADD, V.FMIN, V.FMAX, V.FCMPEQ, V.FCMPLT, V.FABS, V.FNEG, V.FSQRT |
| 010 | VM | V.LW (vector load), V.SW (vector store) |
| 011 | VV | V.SUM, V.FSUM, V.MAX, V.MIN, V.FMAX, V.FMIN, V.DOT, V.FDOT |
| 100 | VV | V.CVT.SF, V.CVT.FS, V.CVT.UF, V.CVT.FU, V.WIDEN, V.NARROW |
| 101 | VX | V.BCAST, V.ADDX, V.SUBX, V.MULX, V.FADDX, V.FMULX, V.INS |
| 110 | VSC | V.EXT (read lane 0 to scalar GPR) |

---

## Compressed 16-bit Encoding (V2)

Enabled via STATUS bit 4 (C). PC advances 2 bytes; two 16-bit insns pack per 32-bit word.

### Formats

| Format | Bits [15:12] | Bits [11:8] | Bits [7:0] |
|--------|-------------|-------------|------------|
| CRRR | op | rd | {rs1, rs2} |
| CRI | op | rd | {rs1, imm4} |
| CBR | op | rs1 | offset8 |
| CMV | 0xC | rd | imm8 |

### Compressed Opcode Map

| Cop | Mnemonic | Format | Semantics |
|-----|----------|--------|-----------|
| 0x0 | C.ADD | CRRR | rd = rs1 + rs2 |
| 0x1 | C.SUB | CRRR | rd = rs1 − rs2 |
| 0x2 | C.AND | CRRR | rd = rs1 & rs2 |
| 0x3 | C.OR | CRRR | rd = rs1 \| rs2 |
| 0x4 | C.XOR | CRRR | rd = rs1 ^ rs2 |
| 0x5 | C.SHL | CRRR | rd = rs1 << rs2[4:0] |
| 0x6 | C.SHR | CRRR | rd = rs1 >> rs2[4:0] |
| 0x7 | C.ADDI | CRI | rd = rs1 + zext(imm4) |
| 0x8 | C.LDW | CRI | rd = mem[rs1 + zext(imm4)×4] |
| 0x9 | C.STW | CRI | mem[rs1 + zext(imm4)×4] = rd |
| 0xA | C.BZ | CBR | if rs1 == 0: PC += sext(off8)×4 |
| 0xB | C.BNZ | CBR | if rs1 != 0: PC += sext(off8)×4 |
| 0xC | C.MV | CMV | rd = zext(imm8) |
| 0xD | C.NOP | — | No-op |
| 0xE | C.JMP | CBR | PC += sext(off8)×4 |
| 0xF | C.CALL | CBR | lr = PC + 2; PC += sext(off8)×4 |

---

## Example — SAXPY (vectorized)

```asm
; r1 = &x, r2 = &y, r3 = n, r4 = &a   (8×FP32 per 256-bit register)
saxpy:
    V.BCAST v2,  --, r4      ; v2 = a broadcast to all 8 lanes
    V.LW    v3,  r1, 0       ; v3 = x[0..7]
    V.FMUL  v3,  v3, v2      ; v3 = a * x
    V.LW    v4,  r2, 0       ; v4 = y[0..7]
    V.FADD  v3,  v3, v4      ; v3 = a*x + y
    V.SW    r2,  v3, 0       ; y[0..7] = v3
    ADDI    r1, r1, 32       ; advance 8 floats (32 bytes)
    ADDI    r2, r2, 32
    ADDI    r3, r3, -8       ; n -= 8
    BNZ     r3, saxpy
    RET
```

---

*Normative sources: `bradisa_spec.tex` (V1), `bradisa_v2_ext.tex` (V2). This card is a convenience reference; the specs define the ISA.*
