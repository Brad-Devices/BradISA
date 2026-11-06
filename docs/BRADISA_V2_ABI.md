# BradISA V2 — ABI and Register File (normative)

> *Kinetic V2 scalar ABI. Normative for the compiler, the kernel's
> `bradk_arch_v2` adapter, and every driver compiled against V2. V1 is
> documented in `ARCHITECTURE_REFERENCE_MODEL.md` §5 and is what runs on
> the FPGA today; this document is the target V2 does not yet ship on silicon.*

---

## 1. Register file

| | |
|---|---|
| General registers | **32 × 32-bit**, r0–r31, r0 hardwired zero |
| Vector registers | **32 × 256-bit**, VSET |
| Lane count | 8 × int32/FP32 · 16 × int16 · 32 × int8 · 4 × int64/FP64 |
| PC | 32-bit, 4-byte aligned, **not** a general register |

The PC is lifted out of the register file in V2. A saved context does not
contain a PC slot in the GPR bank; the resume address is carried in the
trap frame (`EPC`) and restored by `RFE`.

## 2. Scalar ABI

| Role | Registers | Notes |
|---|---|---|
| Zero | r0 | hardwired |
| Arguments | r1–r8 (a0–a7) | 8 arguments |
| Temporaries | r9–r14 | caller-saved |
| Link | r15 (ra) | return address |
| Callee-saved | r16–r26 | 11 registers |
| Stack pointer | r27 (sp) | 16-byte aligned |
| Global pointer | r28 (gp) | |
| Thread pointer | r29 (tp) | |
| Reserved | r30–r31 | kernel / reserved |

**Floating point:** there are no scalar FP registers. Every float lives in
lane 0 of a 256-bit vector register. FP scalars are passed in lane 0 of
v1–v4; v8–v15 are callee-saved.

**Stack:** grows down; 16-byte aligned (vector safety).

## 3. Vector ABI

- Arguments: v1–v4.
- Callee-saved: v8–v15.
- FP scalars: lane 0 of v1–v4.
- Reductions land in v-lane 0; read scalars from there, not the GPRs.

## 4. Calling convention

- Caller-saved: r9–r14, v1–v7.
- Callee-saved: r16–r26, v8–v15.
- Arguments: r1–r8, v1–v4.
- Return value: r1 (scalar), v1 lane 0 (FP).
- Stack: 16-byte aligned at every call boundary.

## 5. Atomics (V2 only)

Spec only today; the RTL is the gate (I-10, fence G2). V2 opcodes:

| Opcode | Mnemonic | Semantics |
|---|---|---|
| `0x2F` | `FENCE` | memory ordering barrier |
| `0x38` | `LR.W` | load-reserved word |
| `0x39` | `SC.W` | store-conditional word |
| `0x3A` | `AMOSWAP.W` | atomic swap |
| `0x3B` | `AMOADD.W` | atomic add |

V1 has zero ISA-level atomics; the fabric provides them and software cannot
emit them. The kernel's spinlock needs these before SMP is safe.

## 6. Trap and system-call entry

- **ECALL**: system call entry. **No opcode is assigned in V2** (I-09 / D1).
  The opcode at `0x14` is `SLLI`; `0x14` is the exception-vector table address
  for a syscall, not an opcode. The kernel's seed uses a software-injected trap
  (a `CALL` to a fixed entry point) until an opcode is assigned.
- **RFE**: trap return. **No opcode is assigned in V2.** It belongs in the
  reserved extension escape range `0x3C–0x3F`. It atomically restores
  `PC ← EPC`, `STATUS.IE ← 1`, `STATUS.SVC ← 0`. **Not** at opcode `0xF`
  funct `0x11` — that placement is wrong and was corrected in the BradISA repo
  (commit `90bd110`).

Trap delivery (R3) — what the kernel needs the RTL to write:

1. `EPC ← PC`
2. `STATUS.IE ← 0`
3. `STATUS.SVC ← 1`
4. `CAUSE ← cause`
5. `PC ← vector_table[cause]` (the 11 fixed words at `0x00–0x2C`)

## 7. Privilege levels (V2)

Three modes: User / Supervisor / Machine. Machine mode is a V2 addition
(`STATUS.M`, bit 7) for the secure monitor. V1 defines User/Supervisor only.

## 8. Compatibility

The kernel does not change the ISA. `bradk_arch_v1` and `bradk_arch_v2` map
the same roles to the two register files. A kernel written against roles runs
on both; the adapter is the only place that knows register numbers.

---

*Companion: `BRADKERNEL_ABI.md` (roles and adapters), `KINETIC_MICROARCHITECTURE.md`
§1 (microarchitecture), `BRADISA_VS_RISCV.md` (fence G2 — atomics).*