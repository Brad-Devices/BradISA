# Tang Nano 9K board build (Gowin GW1NR-9C)

First physical target for BradCore (Falcon). This directory holds the board
top-level, its pin constraints, a yosys `synth_gowin` script, and two
testbenches — one for the RTL, one for the synthesized netlist.

**Status: DESIGNED + SYNTHESIZED + GATE-LEVEL VERIFIED. Not yet
`RUNS_ON_REAL_GATES`.** Synthesis onto Gowin primitives succeeds, the netlist
simulates correctly against yosys's own cell models, and the design fits the
part with ~80% of its LUTs free — but no bitstream has been generated and no
board has been plugged in. See [What is still missing](#what-is-still-missing).

## Files

| File | What it is |
|------|------------|
| `top_tangnano9k.v` | Board top: power-on reset, core clock divider, boot ROM, data RAM, LED latch, core instance |
| `tangnano9k.cst` | Gowin pin constraints |
| `synth_gowin.ys` | yosys `synth_gowin` script — the synthesis receipt |
| `synth_gate.ys` | synthesis to a Verilog netlist, for gate-level simulation |
| `tb_top_tangnano9k.v` | RTL testbench: proves the boot program drives the LEDs |
| `tb_gl_tangnano9k.v` | Gate-level testbench: proves the *synthesized* netlist still counts |

## Board facts

From Sipeed's own `TangNano-9K-example` constraints, cross-checked against
independent references:

| Signal | Pin | Notes |
|--------|-----|-------|
| `sys_clk` | 52 | 27 MHz onboard oscillator |
| `sys_rst_n` | 4 | button S1, active-LOW |
| `led[5:0]` | 10, 11, 13, 14, 15, 16 | **active-LOW**, common anode — invert once at the pin |

The LEDs being active-low is why the top ends with `assign led = ~led_r;`.

## The boot program

Real BradISA machine code in an on-chip ROM — the same encodings the CI
testbench runs, so the board is executing the proved CPU, not a stub:

```
0x00  ADDI r1, r0, 0     0x40200000   init counter
0x04  ADDI r1, r1, 1     0x40210001   loop: r1++
0x08  ADDI r2, r0, 0x04  0x40400004   r2 = data address
0x0C  STW  r1, [r2 + 0]  0x8C220000   publish the counter
0x10  JMP  0x04          0xA81FFFFC   back to the loop
```

(words are the V2 assembler's output; `boot_rom.vh` is generated from this
file and CI re-generates it byte-for-byte on every run)

The core publishes the counter by storing it to data memory; the top-level
latches `dmem_wdata` on a write and shows the low six bits on the LEDs. So the
visible count is the CPU's register value travelling out through a real memory
write, not a pattern generator pretending to be a CPU.

At 27 MHz this loop would run ~13 million times a second, so `core_clk` is
divided down to one cycle per 0.5 s. Each pass of the loop lands about every
2 seconds: a counter you can actually read with your eyes.

## Running it

```sh
# Board-level simulation (seconds, not minutes)
make sim_board        # from rtl/fpga/ — needs iverilog

# Gowin synthesis (real cell counts)
make gowin            # from rtl/fpga/ — needs yosys
```

`make sim_board` builds with `-DBRAD_FAST_SIM`, which shrinks only the clock
divider constant. The shipped design keeps the real 0.5 s divider, because that
is correct for the board and no simulation can wait for it.

The testbench does not just check "the LEDs moved". It checks that the
published sequence is exactly `1, 2, 3, …` with zero errors, so a core that
stopped counting, published garbage, or never published at all would all fail.

## Measured synthesis results

`yosys 0.52`, `synth_gowin`, yosys stat after mapping. Device is GW1NR-9C:
**8,640 LUT4, 6,480 FF, 26 BSRAM (468 Kb), 20 × 18×18 multipliers.**

Count LUT4s, not cells. The default flow emits `MUX2_LUT5..8` cells, which look
like fat multi-LUT4 consumers and are not — each is a wide-LUT optimisation that
still occupies exactly one LUT4. Adding `-nowidelut` forces the design down to
plain LUT4s, so the cell count *is* the fabric count:

| Design | LUT4 | FF | % of device LUTs |
|--------|------|----|------------------|
| Full board top, V2 design (2026-11-10, `-nowidelut`) | **1,250** | 374 | **14%** |

**The design fits the GW1NR-9C with ~86% of its LUTs unused.**

The V1-era probe table is kept for history: the 32×32 `MUL` on its own measured
1,330 LUT4 under the old core (78% of that design's logic), and the same V1
design with the multiply removed measured 507 LUT4 — the multiply was the
biggest single cost, and it was an optimisation target, not a blocker.

The top-level figure is a budget check, not a golden number: abc9's mapping is
not perfectly reproducible run to run, and `make gowin_fit` is what enforces
the budget on every run.

The one thing yosys's Gowin flow cannot do is infer a DSP. `*` becomes LUT logic
because `synth_gowin` has no multiplier mapping, even though the part carries 20
18×18 blocks. That is a missed optimisation, not a capacity problem.

Two honest caveats:

- These are for **this boot program**. The counter touches two registers, so
  yosys prunes the others — hence 374 FFs, not the full register file. A
  program using every register costs more, and a real one will also want more
  memory.
- Gate-level simulation below is proof the netlist *computes*, not proof it
  routes. Utilisation says there is room; only place-and-route and a board say
  it works.

## Gate-level verification

`make sim_gate` synthesises the design to Gowin primitives and then simulates
**that netlist** against yosys's own behavioural models of the Gowin cells
(`cells_sim.v`), checking the LED value walks 1, 2, 3, … with zero errors.

This is the step that catches a synthesis bug rather than an RTL bug. It runs
against a build whose divider constant is shrunk via `chparam` — same logic,
different timing constant — and currently reports **112 LED steps, 0 sequence
errors, final count 48**, identically to the RTL testbench.

So the design is no longer only "it elaborates". It is "the gates yosys produced
count correctly."

## CI gates for this board

Four, all in the `FPGA (Tang Nano 9K / yosys synth_gowin)` job:

| Step | What it refuses to let through |
|------|--------------------------------|
| `sim_board` | an RTL boot program that doesn't drive a correct counting sequence |
| `sim_gate` | a design that breaks when synthesized into gates |
| netlist check | a yosys run that produces no netlist at all |
| `gowin_fit` | a design that outgrows the GW1NR-9C's LUT4/FF budget |

`gowin_fit` is the one added in response to getting the fit estimate wrong by
roughly 5×. It is a real guard, not a decoration: run it with
`GOWIN_LUT_BUDGET=1000` and it fails.

## What is still missing

1. **A bitstream.** This is now the honest blocker. The design fits the part and
   the synthesized netlist computes correctly, but GW1N place-and-route needs
   nextpnr-himbaechel, Apicula, or Gowin EDA, and none is in CI. `synth_gowin`
   deliberately stops at synthesis.
2. **A board.** Until a bitstream is on real silicon and a person watches the
   LEDs count, the honest tag is DESIGNED + SYNTHESIZED + GATE-LEVEL VERIFIED.
   The `RUNS_ON_REAL_GATES` badge stays unflipped.
3. **A DSP-aware multiply.** An optimisation, not a blocker. The V1-era probe
   measured the 32×32 `MUL` alone at 1,330 LUT4 (78% of that design's logic),
   and `synth_gowin` still cannot infer a DSP — the part carries 20 18×18
   blocks. A hand-built 18×18 decomposition, or a `$mul` a
   prjtrellis-himbaechel flow claims as a hard block, would hand most of that
   back and free the LUTs for real program memory and a full register file.
4. **Real program memory.** The core reads instruction memory
   combinationally, so this build uses a small distributed ROM (16 words). Real
   program memory wants a synchronous BSRAM port, which means a matching core
   change — a design step, not a config tweak. Note this is the change most
   likely to be needed next, and the freed LUTs from (3) are what pay for it.
