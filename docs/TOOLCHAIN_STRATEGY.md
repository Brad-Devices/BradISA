# Brad Toolchain Strategy — Assembler, Compiler, and Ecosystem

> *The standing plan for BradISA/BradVector tooling: what exists, what is missing,
> the three-layer compiler ladder (L0–L2), and the honest ordering rules.*
> *Companion to `TOOLCHAIN_GUIDE.md`, `BRADOS_KERNEL_STRATEGY.md`,
> `BRADISA_VS_RISCV.md` (fence G5), and `BRADSILICON_STRATEGY.md`.*

---

## 1. What Ships Today (claim vs reality)

| Piece | What it is | Input → Output | Status |
|---|---|---|---|
| **bradc** | **BradVector assembler** | `.basm` → `.bvbc` | **SHIPPED** — CLI + wasm, 11/11 tests |
| **BVRT** | 32-lane SIMT virtual machine | `.bvbc` → runs vector ops | **SHIPPED** |
| **bradgdb** | symbol-aware debugger | attaches to BVRT, 64 breakpoints | **SHIPPED** |
| **BradTimeline** | cycle-level profiler | BVRT trace → CSV + histogram | **SHIPPED** |
| **braddev** | one-binary dev kit | wraps cvt/run/dbg/timeline/gpu | **SHIPPED** |
| **bradlib.h** | stable host API | compile→pack→launch→inspect | **SHIPPED** |
| **WASM** | browser build | in-browser assemble/run/debug | **SHIPPED** |
| **BradISA CPU assembler** | — | `.basm`-style → CPU image | EXISTS — bradasm ships in the BradISA repo (`tools/bradasm`, 102 CI checks) and here (`src/asm/bradasm.c`, not wired into CMake) |
| **C compiler (either ISA)** | — | C → machine code | **PARTIAL — bradc-mini** (L2 C subset for BradISA V2, runs its own output in ctest); an LLVM/GCC-class compiler (L1) **does not exist** |

**The remaining hole this document plans:** the L1 *C compiler*, with LLVM
first. The L0 BradISA assembler exists, and bradc-mini covers L2 under the
policy in §2.1. L1 is the same class of missing work as the G5 fence in
`BRADISA_VS_RISCV.md` — for general-purpose code the toolchain is still
*only* our toolchain.

---

## 2. The Compiler Decision — LLVM First, GCC Only on Demand

There are three roads to a C compiler for a new ISA. We pick by honest engineering
weight, not marketing:

| Path | What you get | True cost | Verdict |
|---|---|---|---|
| **A. LLVM backend** | Clang C/C++ front end, optimizer, LTO, sanitizers, ASan, whole LLVM ecosystem — all inherited | A real-but-bounded project; simple 16-register RISC is the *easiest* ISA class for LLVM (Cpu0-class) | **RECOMMENDED — the moat** |
| **B. GCC backend** | Mature optimizer, huge legacy mindshare | RTL backend is gnarly, slow to port, newer ISAs all chose LLVM first; porting both from day one burns two years | **DEFERRED — partner-demand only** |
| **C. Own C-subset compiler** | Total control, small, wasm-able | No optimizer worth the name, no C++, everyone pays your compiler's tax; fine *targeted* but never the general tool | **TARGETED USE ONLY (L2)** |

### 2.1 Policy (the standing answer)

> **LLVM backend for BradISA is the development toolchain. GCC is not a goal —
> it only becomes one if a real partner's build chain demands it. A small
> C-subset compiler (bradc-mini) exists only for kernel bring-up and the
> in-browser compile receipt — never the general compiler.**

Why this wins for us specifically:

- **"Borrow the ocean" becomes literal.** The moment `clang -target brad` exists,
  the software universe opens — BradLibc, ports, and eventually the browser/TLS
  stacks become compile-able, not re-writable. The G5 fence flips from weakness
  to moat: *our* assembler + *our* simulator + LLVM's codegen + *our* BradOS =
  the RISC-V story with the co-design intact.
- **Iteration at our speed.** We control the backend; Clang's upstream evolution
  is inherited for free. One commit line from ISA decision → spec → backend →
  toolchain → CI, exactly like the VHDL chip-fix war taught us to work.
- **The ISA philosophy gets enforced by the toolchain.** No scalar FP registers
  means LLVM's legalizer maps scalar `float` onto the vector file (VSET) — the
  "if you reach for `float`, you've grabbed a vector register" rule becomes
  *obligatory*, not advisory.

### 2.2 The ISA gaps that gate the backend

LLVM needs three things our V1 spec does not have yet (the fences G2/G3/G4):

| Gap | What LLVM needs it for | Move |
|---|---|---|
| **Atomics (AMO/LRSC-equivalent)** | spinlocks, memory ordering, SMP correctness | V2 spec addition, before backend matures |
| **Compare-branches (BGE/BLT)** | high-level `if`/`for` without SUB+BNZ pairs | V2 spec addition, before backend matures |
| **LUI/AUIPC + JALR** | 32-bit address/immediate building, indirect calls | V2 spec addition, before backend matures |

**Order rule:** the V2 ISA growth **lands before** the LLVM backend matures — a
backend targeting a spec that cannot build addresses or lock memory would produce
code nobody wants to run. (This is the same honesty sequencing as everywhere else:
receipts in the ISA first.)

---

## 3. The Three-Layer Ladder

```
Layer 0 — BradISA CPU assembler        (the missing bridge)
    bradas (or bradc --cpu): .basm-style source → CPU instruction image
    replaces the hand-assembled test words in the CI tb
    runs in Icarus + GHDL + FPGA immediately
    UNBLOCKS: BradKernel bring-up, driver code, real tests
    THIS IS THE NEXT ACTUAL WORK — cheap, testable, unblocks everything

Layer 1 — LLVM backend ("Brad" target) (the moat)
    TableGen: 32 GPRs, 5-bit fields, 7 formats (V2), BR/JMP offsets ×4, MSRs via intrinsics
    legalization: scalar float → VSET vector file (ISA philosophy, enforced)
    gates: V2 atomics/branches/immediates landed FIRST (see §2.2)
    win: clang -target brad → the ocean opens, G5 flips from weakness to moat

Layer 2 — bradc-mini (TCC-class C-subset)   (targeted, optional)
    ~2–5k LOC subset: ints, pointers, structs; no FP by default
    uses: BradKernel bring-up, embedded, the in-browser compile receipt
    NEVER the general compiler — that is LLVM's job
```

---

## 4. Sequencing (the ordering rule)

```
[done] CI sim gate                   ← GREEN both HDLs, run 36510059775 (r1=0, r2=100)
    → Tang Nano 9K board top        [done] DESIGNED+SYNTHESIZED+GATE-LEVEL VERIFIED — a775f91, run 36527852382
    → Place-and-route + bitstream     ← the live head — fits the part (21% of LUTs), never routed
    → Bitstream + board boot        ← needs nextpnr-himbaechel/Apicula + a human + a board
    → BradISA CPU assembler (L0)   ← the missing bridge — replace hand-assembled tb words
    → BradKernel boot on FPGA      ← in asm first (BRADOS_KERNEL_STRATEGY step 3)
    → V2 ISA gaps (atomics, compare-branches, LUI/AUIPC/JALR)
    → LLVM backend (L1)            ← clang -target brad — the ocean opens
    → BradOS core + BradLibc       ← syscall ABI, scheduler (step 5)
    → bradc-mini (L2, as demand appears)
    → BradUI on top (step 6)
GCC: OFF THE TABLE until a partner demands it.
```

## 5. Claim vs Reality (VISION-style)

| Item | Claim | Reality | Tag |
|------|-------|---------|-----|
| bradc / BVRT / bradgdb / BradTimeline / braddev | Shipped toolchain | **REAL** — CLI + wasm, 11/11 tests | [Gen1] |
| BradISA CPU assembler | Bridges the CPU | **EXISTS** — bradasm ships in the BradISA repo and here (not wired into CMake) | [Gen1] |
| `clang -target brad` | Production compiler | **PLANNED** — gated on V2 ISA gaps | [Gen1/Gen2] |
| LLVM backend | The dev toolchain | **PLANNED** — the moat, after L0 + V2 | [Gen2] |
| GCC backend | Second compiler | **NOT A GOAL** — partner-demand only | [Policy] |
| bradc-mini | C-subset for kernel/wasm | **PLANNED, targeted** — not the general compiler | [Gen2] |

---

## 6. Bottom Line

1. **The next actual work is the BradISA CPU assembler (L0)** — it replaces
   hand-assembled test words, unblocks the kernel, and is cheap + CI-testable now.
2. **The production compiler is LLVM** — one TableGen target buys Clang, the
   optimizer, LTO, sanitizers, and the whole ecosystem. It is the G5-moat flip.
3. **GCC is a partner-demanded exception, not a plan.**
4. **bradc-mini is targeted (kernel + wasm), never the general compiler.**
5. **V2 ISA gaps (atomics/branches/immediates) land before the backend** — same
   honesty sequencing as everywhere: receipts in the ISA first, then tooling.

---

*Honesty guardrails: everything in this document is tagged [Gen1]/[Gen2]/[Policy] per
VISION.md. Nothing promoted from PLANNED to SHIPPED without `clang -target brad` output
in CI and a CPU assembler green in both HDLs. See also `TOOLCHAIN_GUIDE.md` (what ships
today), `BRADISA_VS_RISCV.md` §G5, and `BRADOS_KERNEL_STRATEGY.md` step 4.*