# BradISA vs RISC-V — The Honest Comparison

> *What BradISA genuinely gives over RISC-V — and the fences we do not claim yet.*
> *Grounded in `bradisa_spec.tex` (V1), `bradisa_v2_ext.tex` (V2), and the ARM.*
> *Style per VISION.md doctrine: every advantage has a receipt, every gap has a name.*

---

## 1. The Frame

This is not "Brad is better than RISC-V." That sentence is meaningless — RISC-V is a
specification *family* that spans 3-stage microcontrollers to 64-core OoO servers, and
its vendors (SiFive, Andes, T-Head, Rivos, Ventana) ship real silicon at every tier.

The meaningful question is: **for a vertically-integrated company building the Brad
ecosystem — cores, fabric, memory, OS, toolchain, all in-house — where does defining our
own ISA pay, and where does buying the RISC-V portability contract cost nothing?**

Two ways to lose this comparison: claim wins we don't have (the honesty rules forbid
it), and ignore wins we already built (the belief rules forbid that too).

## 2. What BradISA Genuinely Gives Over RISC-V

### 2.1 Decode: a 4-bit lookup, not a hierarchy  — [Gen1, RECEIPT]

RISC-V front-ends disambiguate a 2-bit prefix hierarchy, variable 16/32/48/64-bit
encodings, extension opcode spaces, and split `funct3`/`funct7` fields. BradISA is
**one flat opcode field, one table** — V1 is four formats, all 32-bit; V2 is seven
formats, all 32-bit. The entire scalar decoder is 64 cases either way.

| Property | RISC-V RV32I/C | BradISA (V1 / V2) |
|---|---|---|
| Instruction length | 16/32/48/64 variable | 32 fixed |
| Primary decode | 2-bit prefix + funct3/funct7 | 6-bit op[5:0], one table |
| Formats | ≥6 (R/I/S/B/U/J + C quartet) | V1: 4 (RRR/RI/BR/JMP) · V2: 7 |
| Decode state | length-decoder + csr/vector gates | zero — 64 cases |

**What it buys:** a smaller, exhaustively-verifiable decode stage; less front-end power
on Falcon/Falcon-Lite; a formal model we can prove. Real cost on real cores.

### 2.2 Vector is first-class *in the core* — RISC-V pays twice  — [Gen1 VSET, RECEIPT]

ARM principle 3: **no scalar FP registers**. FP/ML/DSP live entirely in the
32 × 256-bit VSET vector registers; the scalar core is integer + control.

RISC-V requires an F/D scalar FP datapath *and* register file on top of V (or you cut
FLEN and lose vector-FP compat). Brad builds **one** vector datapath that serves
everything, and "if you reach for `float`, you've already grabbed a vector register" is
the mental model the whole ABI (v1–v4 args, lane-0 scalars) is built on.

**What it buys:** the vector die-area/power budget is paid once on every core, from
Phoenix down to Falcon. Efficiency cores get SVE-style vectors without a scalar FPU.
Software inherits the *same* law on every core.

### 2.3 One ISA across asymmetric P/E cores, architected — [Gen1, RECEIPT]

RISC-V *can* ship big-little (it is an implementation choice, and its vendors do).
BradISA was *architected* for it (ARM principle 2): Phoenix (10-stage octa-issue OoO,
ROB 128) and Falcon (5-stage in-order) run **identical binaries**. The toolchain targets
the ISA, never a core.

**What it buys:** a single image from BradPhone to BradCube X; the scheduler decides
where you run — software is never core-model-specific. Ownership of the P/E split the
moment we tune a core, without asking an upstream committee.

### 2.4 Memory semantics defined against *our* fabric — [Gen1, RECEIPT]

RISC-V defines ordering/atomics against nothing in particular; each implementer picks.
BradISA's ARM defines ISA-visible memory semantics against the **BradFusion Fabric** as
the coherence point — which is exactly the SPMP unified-memory design (CPU and GPU share
physical memory; zero-copy is an architectural invariant, not a DMA hack).

**What it buys:** the ISA and the fabric are co-designed, so the memory model is cheap to
implement and cheap to verify. RISC-V's generality has no equivalent — it can't; it has
no fabric.

### 2.5 Iteration speed with zero committee debt — [RECEIPT: commit history]

RISC-V freezes ratified material and polities extend over years. Brad shipped
V1 → V2 (16-bit compressed mode, Kestrel dual-issue, Falcon-Lite 3-stage, 24 power
MSRs) → Gen2 SVEXT intent (128–512-bit VL-agnostic vectors, predication via v0) inside
one vertical stack. When we find a spec bug (the VHDL/GHDL CI war taught us this), we
fix the spec, the toolchain, and the RTL **in one commit line** — nobody to convene.

The receipts multiplied in the last pass: the V2 spec normatively grew to the 32-GPR
register file, LR/SC/AMO atomics, full compare-and-branch, `LUI`/`AUIPC`/`JALR`,
`FENCE`, the ECALL requirement (no opcode assigned yet), the RFE escape range, and the third privilege level — specified and
written into a normative ABI (`BRADISA_V2_ABI.md`), with the RTL still the gate
(a wrong-spec fix, the RFE opcode placement, was corrected in the BradISA repo,
`90bd110`). What used to take a committee cycle got specified between two gate runs.

**What it buys:** the freedom to evolve the ISA as the silicon learns, and the honesty
guardrail (every change tagged [Gen1]/[Gen2]/[Vision]) replaces ratification drama.

### 2.6 Compressed ISA as a *mode*, not a second kingdom — [Gen2, RECEIPT: v2_ext]

RISC-V `C` is a parallel instruction family the decoder must always disambiguate.
Brad's 16-bit compressed instructions pack **two per 32-bit word**, switched by one
STATUS bit (C=1). ~30–40% code-size win, and the decode stays simple when simplicity
matters — the mode is per-context opt-in.

### 2.7 Total toolchain ownership — [RECEIPT: braddev/BVRT/BVLibs]

We don't borrow a GNU toolchain and patch it. `braddev` (assembler → BVRT → bradgdb →
profile → test), the wasm bridge, and BVLibs are ours end-to-end. Cost and control at
once: any ISA evolution lands in the toolchain the same day, and the *entire* toolchain
is a SHIPPED receipt (site demo runs the real assembler+simulator in-browser).

### 2.8 Privilege levels small enough to verify — [Gen1, RECEIPT]

V1 defines User + Supervisor with MSR control and a fixed vectored exception
table. V2 adds a third level deliberately — a Machine mode for the secure
monitor (`STATUS.M`, bit 7) — because BradSec needs a root the supervisor
cannot reach. The principle does not change with the count: each level exists
because a named component needs it, so the kernel contract stays small enough
to verify — not a missing feature (C9 applied: `90bd110`).

### 2.9 The ISA hosts a kernel, in two HDL trees — [Gen1, RECEIPT]

The BradKernel seed (`rtl/kernel/bradkernel.s`) boots, dispatches a trap,
routes a syscall, saves/restores a context, and schedules three tasks
round-robin — the same program checkable in both RTL trees. It runs on the
Verilog testbench **and** the VHDL testbench (`iverilog` + GHDL), image
extraction from the assembler is drift-gated in `make check`, and the trace
`A1 B1 A2 B2 A3 B3 C1 C2 C3 D0` is asserted by both. V1's missing pieces are
honest in it: the trap is software-injected because the RTL has no ECALL yet
(I-09) — the seed exercises the dispatch logic the hardware trap will use,
and nothing pretends the hardware is there.

## 3. The Fences — What RISC-V Is Ahead On (do not claim these)

Honesty column. These are the gaps the company must close before "we beat RISC-V on
generality" can be said with anyone's hand on a Bible. Each has a name and a fix path;
none is "future fiction."

| # | Gap | RISC-V has | BradISA status | Fix path |
|---|---|---|---|---|
| G1 | **Register pressure** | 32 GPRs, 12 callee-saved | V1: 16 GPRs, 5 callee-saved (RTL today). V2 renames to **32 GPRs, 11 callee-saved** — spec landed, normative ABI written (`BRADISA_V2_ABI.md`) | Done normatively; the spill cost on heavy code was real and is the reason the count moved. `bradk_arch_v1`/`v2` adapters map the same roles so kernel code does not change. RTL remains the gate |
| G2 | **Atomics / SMP** | `A` extension (AMO/LRSC), ratified ~decade | V1 has **zero** ISA-level atomics; fabric provides them, SW can't emit them. V2 closes this normatively: `FENCE` `0x2F`, `LR.W` `0x38`, `SC.W` `0x39`, `AMOADD.W` `0x3A`, `AMOSWAP.W` `0x3B` — spec + ABI landed | Useful for SPMP completions; needed for a multicore BradOS spinlock. **RTL is the gate** (fence G2 / I-10) before the kernel's lock can be trusted |
| G3 | **Branch conditions** | 6 integer conds + C.BEQZ/C.BNEZ | V1: only `BZ`/`BNZ`. **V2 spec landed full compare-and-branch**: `BEQ`/`BNE`/`BLT`/`BGE`/`BLTU`/`BGEU` (`0x30–0x35`) | Spec + ABI landed; RTL is the gate. Hot loops stop paying `SUB`+`BNZ` once the core executes it |
| G4 | **Immediate/address build** | LUI/AUIPC + JALR + PC-relative | V1: 16-bit imm only. **V2 spec landed**: `LUI` `0x28`, `AUIPC` `0x29`, `JALR` `0x2D` (target computed before the link write) | Spec + ABI landed; RTL is the gate |
| G5 | **Toolchain/ecosystem** | production LLVM/GCC, Linux, decades of ports, third-party silicon everywhere | braddev/BVRT (ours — great, and also the only game in town). "Does it run Linux?" = no (by design). Do not dodge this | BradOS is the answer posture: we don't need Linux to win a vertical. Compiler plan: see `TOOLCHAIN_STRATEGY.md` (LLVM-first, GCC partner-demand-only) |
| G6 | **DMIPS claims are targets** | vendors *ship* measured Dhrystone | Phoenix 5.5 DMIPS/MHz, IPC 5.0 peak, 3.0–5.2 GHz are **spec targets, not measured silicon** | Optimistic for octa-issue + 16 GPRs | Tag clearly as targets until Falcon/Phoenix synthesis evidence (Tang Nano 9K + TinyTapeout are the first physical steps) |

## 4. The Scorecard That Matters

Don't count advantages; count *what the company is buying*.

| Purchase | BradISA | RISC-V |
|---|---|---|
| Front-end simplicity + verifiability | ✅ 6-bit, 64 cases, one table | variable, committee-grown |
| Vector die-budget once per core | ✅ in-core, no scalar FP | F/D + V two datapaths |
| Fabric-native memory semantics | ✅ co-designed | n/a (no fabric) |
| Iterate the ISA with the silicon | ✅ one commit line | years + freeze |
| P/E one-binary ownership | ✅ architected | vendor choice |
| Toolchain control | ✅ ours | borrowed |
| General-purpose portability (Linux, 3rd-party SW, silicon vendors) | ❌ by design | ✅ overwhelming |
| SMP/atomics, rich branches, immediate building | ❌ Gen1 RTL | ✅ ratified — **V2 closes these normatively** (32 GPRs, LR/SC/AMO, compare-and-branch, LUI/AUIPC/JALR, Machine mode); the RTL is the gate |
| Measured performance receipts | ❌ targets | ✅ shipped silicon |

## 5. Bottom Line

**BradISA wins the vertical: everything the Brad ecosystem needs is co-designed into the
ISA — decode, vector, fabric memory, P/E, toolchain — and nothing needs a committee.**

**RISC-V wins the horizontal: portability, proven silicon, mature SW, and SMP/atomics
today.**

Both statements are true, and the strategy is to be *honest about the second* while
*shipping the first*. The gap list in §3 doubled as the Gen1→Gen2 roadmap, and most
of the normative half of it has now been written: G1–G4 are specified (`bradisa_spec.tex`,
`BRADISA_V2_ABI.md`), and the receipt for hosting an actual kernel is in (§2.9). What is
left is not drafting — it is making the RTL execute what the spec already says (fences
G2/G3/G4 against the cores), then measuring, not estimating, against G6.

---

*Keep the guardrails: everything in §2 has a receipt tagged [Gen1]/[Gen2]; everything in
§3 is a named gap with a fix path, none dressed up as shipped. See `VISION.md`, `TASKS.md`,
and `HISTORY.md`.*