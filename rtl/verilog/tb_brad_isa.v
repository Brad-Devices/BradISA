// SPDX-License-Identifier: MIT
// BradISA V1 -- full-ISA regression for brad_core
//
// The original testbench (tb_brad_core.v) runs ADDI, BNZ and JMP and nothing
// else, which is how ADD/SUB/MUL/AND/OR/XOR/SHL/SHR shipped broken: the
// register-file read port for rs2 was gated to r0 for every opcode except
// STW, so all eight RRR ops quietly computed rd = rs1 op r0.  A green gate
// was telling the truth about the three instructions it actually ran and
// nothing about the other thirteen.
//
// This testbench runs every opcode the core implements and checks each
// result, so "CI is green" now means the whole ISA works.
//
// The program under test is NOT encoded here.  It lives in
// rtl/asm/tb_brad_isa.s, is assembled by bradasm into
// rtl/asm/tb_brad_isa_prog.mem, and this testbench loads those words with
// $readmemh.  The old version hand-encoded every instruction with helper
// functions -- writing 0x82000007 believing it meant "ADDI r1, r0, 7"
// actually encodes rd=2 and the core dutifully writes r2.  Hand-encoding
// words is a trap, so now an assembler does it and CI regenerates the .mem
// and fails on a diff (`make -C rtl/asm check`).  bradasm's own self-test
// checks every opcode's encoding against the RTL's opcode table and the
// board boot ROM byte for byte, so the words this testbench executes are
// produced by the same assembler the rest of the project trusts.
//
// The program stores each observable result to its own data-memory slot
// (dmem[addr>>2]); the slots are named in rtl/asm/tb_brad_isa.s.  Register
// checks below are on top: several results survive in registers until the
// program parks, so the testbench can observe the register file directly
// without trusting the store path.

`timescale 1ns / 1ps

module tb_brad_isa;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;

    reg  [31:0] imem [0:255];
    wire [31:0] imem_addr, imem_rdata;
    assign imem_rdata = imem[imem_addr[9:2]];

    reg  [31:0] dmem [0:255];
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_req, dmem_we;
    assign dmem_rdata = dmem_req ? dmem[dmem_addr[9:2]] : 32'd0;

    // Single-cycle data memory write port.
    always @(posedge clk) begin
        if (dmem_we)
            dmem[dmem_addr[9:2]] <= dmem_wdata;
    end

    integer i;
    integer checks = 0;
    integer failed = 0;

    brad_core dut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata)
    );

    always #5 clk = ~clk;

    // dmem slots the program stores its results to.  Must stay in lockstep
    // with the addresses in rtl/asm/tb_brad_isa.s -- dmem[addr>>2].
    localparam S_ADD  = 0,  S_SUB  = 1,  S_MUL  = 2,  S_AND  = 3,
               S_OR   = 4,  S_XOR  = 5,  S_SHL  = 6,  S_SHR  = 7,
               S_NEG  = 8,  S_RSUM = 9,  S_R0WR = 10, S_42   = 11,
               S_STWL = 12, S_STWB = 13,
               S_BZT  = 14, S_BZNT = 15, S_BNZT = 16, S_JMP  = 17,
               S_CAL1 = 18, S_CAL2 = 19, S_CALL = 20,
               S_LSUM = 21, S_LCNT = 22;

    // CALL sits at 0x128 in tb_brad_isa.s; ra (r15, the V2 link register)
    // must hold pc+4 = 0x12C, the return point (the ADDI right after the
    // CALL). V1 named it lr = r14; V2 renamed the ABI and r14 became a
    // caller-saved temporary.
    localparam [31:0] CALL_PC = 32'h00000128;

    // Fill imem with a NOP (V2: opcode 0) so a runaway fetch spins in
    // place instead of executing whatever garbage follows the program.
    task clear_mem;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                imem[i] = 32'h00000000;
                dmem[i] = 32'd0;
            end
        end
    endtask

    task boot;
        input integer ns;
        begin
            clk = 1'b0; rst_n = 1'b0;
            #15 rst_n = 1'b1;
            #(ns);
        end
    endtask

    task expect_r;
        input [8*12-1:0] name;
        input integer      rn;
        input [31:0]       want;
        begin
            checks = checks + 1;
            if (dut.regfile.regs[rn] !== want) begin
                failed = failed + 1;
                $display("FAIL %0s: r%0d = 0x%08x (%0d)  want 0x%08x (%0d)",
                         name, rn, dut.regfile.regs[rn], dut.regfile.regs[rn],
                         want, want);
            end
        end
    endtask

    task expect_m;
        input [8*12-1:0] name;
        input integer      slot;
        input [31:0]       want;
        begin
            checks = checks + 1;
            if (dmem[slot] !== want) begin
                failed = failed + 1;
                $display("FAIL %0s: dmem[%0d] = 0x%08x (%0d)  want 0x%08x (%0d)",
                         name, slot, dmem[slot], dmem[slot], want, want);
            end
        end
    endtask

    initial begin
        // Load the words bradasm assembled from rtl/asm/tb_brad_isa.s and
        // run the whole program to the JMP self at the end.
        clear_mem;
        $readmemh("../asm/tb_brad_isa_prog.mem", imem, 0, 89);
        // 90 instructions, the loop alone is 10 iterations; give the pipe
        // room rather than racing it.
        boot(6000);

        // ── The eight RRR ops (7 op 5, result in r1) ───────────────
        expect_m("ADD",  S_ADD,  32'd12);    // 7 + 5
        expect_m("SUB",  S_SUB,  32'd2);     // 7 - 5
        expect_m("MUL",  S_MUL,  32'd35);    // 7 * 5
        expect_m("AND",  S_AND,  32'd5);     // 7 & 5
        expect_m("OR",   S_OR,   32'd7);     // 7 | 5
        expect_m("XOR",  S_XOR,  32'd2);     // 7 ^ 5
        expect_m("SHL",  S_SHL,  32'd224);   // 7 << (5 & 31)
        expect_m("SHR",  S_SHR,  32'd0);     // 7 >> (5 & 31)

        // ── ADDI: negative immediate, same-register form, r0 ──────
        expect_m("ADDI-neg",  S_NEG,  32'hFFFFFFF9);   // r2 = -7
        expect_m("ADDI-rsum", S_RSUM, 32'd0);          // r1 = 7 + -7
        expect_m("r0-wrwb",   S_R0WR, 32'd0);          // write to r0 discarded
        expect_m("r0-const",  S_42,   32'd42);

        // ── STW / LDW round trip ─────────────────────────────────
        expect_m("STW/LDW",   S_STWL, 32'd42);
        expect_m("STW-base",  S_STWB, 32'h40);

        // ── Branches ─────────────────────────────────────────────
        expect_m("BZ-taken",  S_BZT,  32'd7);
        expect_m("BZ-notaken",S_BZNT, 32'd99);
        expect_m("BNZ-taken", S_BNZT, 32'd7);
        expect_m("JMP",       S_JMP,  32'd7);

        // ── CALL / RET ───────────────────────────────────────────
        expect_m("CALL/RET",    S_CAL1, 32'd1);       // return point, r1
        expect_m("CALL/RET-sub",S_CAL2, 32'd7);       // subroutine wrote r2
        expect_m("CALL/RET-lr", S_CALL, CALL_PC + 4); // lr = CALL's pc + 4

        // ── The loop: r2 = sum(10..1) = 55 ───────────────────────
        expect_m("loop-sum", S_LSUM, 32'd55);
        expect_m("loop-cnt", S_LCNT, 32'd0);

        // ── Register-file checks, on top of the stored results ────
        // The final state at the park: r2/r3 are the loop's, r4 the
        // round trip's, lr the CALL's, r1 the return point's.
        expect_r("CALL-ret",   1, 32'd1);
        expect_r("loop-acc",   2, 32'd55);
        expect_r("loop-cnt",   3, 32'd0);
        expect_r("round-trip", 4, 32'd42);
        expect_r("lr (ra)",   15, CALL_PC + 4);

        // ── Summary ─────────────────────────────────────────────────
        $display("ISA checks run   : %0d", checks);
        $display("ISA checks failed : %0d", failed);
        $display("%0s", (failed == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule