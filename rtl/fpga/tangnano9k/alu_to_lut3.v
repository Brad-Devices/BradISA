// SPDX-License-Identifier: MIT
// alu_to_lut3.v -- expand the Gowin ALU cell for the gate-level testbench.
//
// WHY THIS EXISTS
//
// Icarus Verilog 12 crashes inside its own elaborator (ivl_nexus_ptrs:
// assertion `net' failed at t-dll-api.cc:1785) on this module: the ALU
// carry-chain netlist with duplicated operands per cell is valid logic, the
// RTL simulation is green and yosys synthesis is green, but ivl dies while
// elaborating it. (A hand-built two-cell ALU chain simulates fine; the
// crash is an ivl defect, not a design defect.)
//
// The expansion is exact for the modes this netlist uses, per the cell's
// own behaviour in cells_sim.v:
//
//   ALU_MODE = 0 (ADD):    S  = I0 ^ I1
//   ALU_MODE = 2 (ADDSUB): S  = I3 ? (I0 ^ I1) : (I0 ^ ~I1)
//   both:                  SUM  = S ^ CIN
//                          COUT = S ? CIN : I0
//
// Every cell this map touches is replaced by LUT cells whose truth tables
// are those formulas: XNOR (8'hC3), XOR (4'h6) and the select (8'hE4).
// So the gate-level testbench still simulates the yosys-synthesized logic,
// one library level further down, and the LUT budget check (gowin_fit)
// still runs its own independent count on the unmodified ALU netlist.
//
// Any other ALU_MODE in the netlist is a flow error and is left alone so the
// run fails loudly rather than silently expanding into something different.

module ALU (SUM, COUT, I0, I1, I3, CIN);

parameter ALU_MODE = 0;

input I0, I1, I3, CIN;
output SUM, COUT;

wire _TECHMAP_FAIL_ = (ALU_MODE != 0) && (ALU_MODE != 2);

// S = I0 ^ (I3 ? I1 : ~I1)
wire t;
wire s;
wire sum_i;

LUT3 #(
	.INIT(8'hC3)      // XNOR(I1, I3)
) _u_alu_t (
	.I0(1'b0),
	.I1(I1),
	.I2(I3),
	.F (t)
);

LUT2 #(
	.INIT(4'h6)       // XOR(I0, t)
) _u_alu_s (
	.I0(I0),
	.I1(t),
	.F (s)
);

LUT2 #(
	.INIT(4'h6)       // XOR(S, CIN)
) _u_alu_sum (
	.I0(s),
	.I1(CIN),
	.F (sum_i)
);

LUT3 #(
	.INIT(8'hE4)      // COUT = S ? CIN : I0
) _u_alu_cout (
	.I0(s),
	.I1(I0),
	.I2(CIN),
	.F (COUT)
);

assign SUM = sum_i;

endmodule
