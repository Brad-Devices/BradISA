# BradISA — Architecture Guide

> *The developer-facing guide to programming BradISA. Companion to the
> Architecture Reference Model (ARM) and the normative specs.*
> *Target: OS/kernel engineers, compiler/toolchain teams, firmware, and
> performance engineers writing for BradCore/HyperCore and the Torox G1
> GPU family.*

---

## 1. The Big Picture

Brad is a **big-little, one-ISA** ecosystem: the same instructions run on
Phoenix (performance) and Falcon (efficiency) cores, so a single binary
runs across BradPhone through BradCube X. Don't code to a core — code to the
ISA and let the scheduler put you where you belong.

**The scalar core is an integer/control engine.** There are no scalar FP
registers. Floating-point, ML, DSP, and media are *vector* work (VSET).
If you reach for `float`, you are really reaching for a vector register.

## 2. Getting Started (First Program)

```text
# add v1 = v2 + v3  (256-bit vector, 8×FP32)
V.FADD  v1, v2, v3      # v1[i] = v2[i] + v3[i], 0 <= i < 8
V.EXT   r1, v1          # read the lane-0 result into a scalar GPR
```

`VSTATUS.VE` (MSR 23) must be set — by the OS at context switch — before any
vector instruction commits; otherwise it traps as undefined (cause 1). On
Gen1 the vector length is fixed 256-bit; use the full register or the lane
count implied by the element width (8×FP32, 4×FP64, 16×int16, 32×int8).

## 3. Stack & ABI Rules

- **Args**: first 4 scalars in r1–r4 (return value in r1), first 4 vectors in v1–v4.
- **FP scalars**: pass in lane 0 of an arg vector (v1–v4).
- **Callee-saved**: r8–r12, v8–v15. Preserve or be prepared for bugs.
- **Stack**: grows down; 16-byte align (vector safety).

## 4. Exceptions & Syscalls

- User code traps via a software-injected trap; the dispatch machinery (trap
  vector table, cause dispatch, syscall router) is built, and the hardware
  ECALL entry is an additive change when the ISA delivers it.
- There is no `MRET` in V1; trap return is software-driven until the ISA
  adds it.
- Misaligned access, illegal instruction, and privilege violations trap to
  the S-mode table (BradOS) or M-mode (BradSec firmware).

## 5. Performance Guidance

### 5.1 Phoenix (OoO) vs Falcon (in-order)

| | Phoenix | Falcon |
|--|---------|--------|
| Sustain | high IPC, OoO | low power, in-order |
| Branch pred | tournament (12-bit global) | static/BTFNT |
| Vector | 256-bit/cycle | 128-bit/cycle (Gen1) |
| Use for | hot loops, interactive | idle, background, NPU-fed |

### 5.2 Vector Performance

- Match element width (SEW) to the datapath: 8×FP32 / 4×FP64 / 16×int16.
- Avoid cross-lane ops on Gen1 (limited); Gen2 SVEXT adds predication.
- Reductions land in v-lane 0 — read scalars from there, not the GPRs.

### 5.3 Memory

- The BradFusion Fabric is the coherence point. Use non-temporal /
  streaming hints for large copies (avoid fabric-bounce).
- Unified memory (SPMP): GPU and CPU share physical memory. Zero-copy is
  real — don't DMA-copy what the fabric already coalesces.

## 6. GPU (Torox G1) Programming Notes

- BradVector is a 32-thread SIMT warp ISA (CUDA-style warp size for
  Brad-CVT compatibility). Not SPMD-on-your-vector-extension.
- The GPU lives on the same fabric as the CPU; shared memory is the
  *same* SPMP you see from CPU code.
- BA-ISA (BradApex) is a different, datacenter-oriented block+vector ISA —
  don't mix it with Torox G1 shader code.

## 7. Gen2 Headroom (What to Design For)

- **SVEXT**: variable-length vector (128–512-bit), vector-length-agnostic
  code, new `VSTATUS.SVL` / `ID_VECTOR` probing. Keep Gen1 vector loops
  VL-independent in style and they port cleanly.
- Predication (v0 as mask) becomes real in Gen2 — reserve v0 now.
- Compressed ISA: hot loops can be shepherded into 16-bit encoding
  automatically by the toolchain; design for it.

## 8. Tooling & Where Things Live

| Need | Go to |
|------|-------|
| Base ISA encoding | `src/spec/bradisa_spec.tex` |
| V2 (compressed/VSET/power/MSRs) | `src/spec/bradisa_v2_ext.tex` |
| GPU SIMT ISA | `Brad Silicon/GPU/GPU_ISA.md` |
| SoC (cores+NPU+fab) | `Brad Silicon/CPU/BRADCHIP.md` |
| Architectural model | `BradISA/ARCHITECTURE_REFERENCE_MODEL.md` |

---

*Keep the honesty guardrails: plan for Gen2/Gen2 intent, but only ship what
is tagged [Gen1]. See `ROADMAP.md` §Architecture Over the Node War for why
the ISA carries the performance weight.*