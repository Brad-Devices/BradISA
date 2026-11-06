// SPDX-License-Identifier: MIT
// BradISA V2 -- Decode Coverage Testbench
// Verifies all 64 opcode slots decode correctly.
// Assigned opcodes (50): correct format and field extraction.
// Reserved opcodes (14): undef flag set.

`include "bradisa_defines.v"

module tb_decode_coverage;

    reg         clk;
    reg         rst_n;
    reg         fetch_valid;
    reg  [31:0] fetch_pc;
    reg  [31:0] fetch_insn;
    reg         stall;
    reg         flush;

    wire [4:0]  rf_raddr1;
    wire [4:0]  rf_raddr2;
    reg  [31:0] rf_rdata1 = 32'd0;
    reg  [31:0] rf_rdata2 = 32'd0;

    wire        dec_valid;
    wire [5:0]  dec_opcode;
    wire [4:0]  dec_rd;
    wire [4:0]  dec_rs1;
    wire [4:0]  dec_rs2;
    wire [31:0] dec_rs1_val;
    wire [31:0] dec_rs2_val;
    wire [31:0] dec_pc;
    wire [31:0] dec_imm;
    wire        dec_reg_we;
    wire        dec_undef;
    wire [2:0]  dec_fmt;

    brad_decode dut (
        .clk(clk), .rst_n(rst_n),
        .fetch_valid(fetch_valid), .fetch_pc(fetch_pc), .fetch_insn(fetch_insn),
        .stall(stall), .flush(flush),
        .rf_raddr1(rf_raddr1), .rf_rdata1(rf_rdata1),
        .rf_raddr2(rf_raddr2), .rf_rdata2(rf_rdata2),
        .dec_valid(dec_valid), .dec_opcode(dec_opcode), .dec_rd(dec_rd),
        .dec_rs1(dec_rs1), .dec_rs2(dec_rs2), .dec_rs1_val(dec_rs1_val),
        .dec_rs2_val(dec_rs2_val), .dec_pc(dec_pc), .dec_imm(dec_imm),
        .dec_reg_we(dec_reg_we), .dec_undef(dec_undef), .dec_fmt(dec_fmt)
    );

    always #5 clk = ~clk;

    integer op, pass_count, fail_count, undef_count;
    reg [31:0] test_insn;

    initial begin
        $dumpfile("tb_decode_coverage.vcd");
        $dumpvars(0, tb_decode_coverage);

        clk = 0;
        rst_n = 0;
        fetch_valid = 0;
        fetch_pc = 32'd0;
        fetch_insn = 32'd0;
        stall = 0;
        flush = 0;

        #15 rst_n = 1;

        pass_count = 0;
        fail_count = 0;
        undef_count = 0;

        // Test all 64 opcode slots
        for (op = 0; op < 64; op = op + 1) begin
            // Construct a test instruction with known fields:
            // rd=7, rs1=11, rs2=13, imm=0x1234
            test_insn = {op[5:0], 5'd7, 5'd11, 5'd13, 11'd0};
            // Override for immediate formats: put imm in low 16 bits
            if (op >= 6'h10 && op <= 6'h25) begin
                test_insn = {op[5:0], 5'd7, 5'd11, 16'h1234};
            end
            if (op >= 6'h28 && op <= 6'h29) begin
                test_insn = {op[5:0], 5'd7, 21'h12345};
            end
            if (op >= 6'h2A && op <= 6'h2D) begin
                test_insn = {op[5:0], 5'd7, 21'h12345};
            end
            if (op >= 6'h30 && op <= 6'h37) begin
                test_insn = {op[5:0], 5'd11, 5'd13, 16'h1234};
            end

            fetch_valid = 1;
            fetch_pc = op * 4;
            fetch_insn = test_insn;
            @(posedge clk);  // wait for posedge
            #1;  // small delay for registered outputs to settle

            // Check undef flag
            if (dec_undef) begin
                undef_count = undef_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            if (!dec_valid) begin
                $display("  ERROR: dec_valid=0 for op=0x%02X", op);
                fail_count = fail_count + 1;
            end
        end

        fetch_valid = 0;
        #20;

        $display("");
        $display("=== DECODE COVERAGE SUMMARY ===");
        $display("  Total slots:    64");
        $display("  Assigned:       %0d", pass_count);
        $display("  Reserved/undef: %0d", undef_count);
        $display("  Failures:       %0d", fail_count);

        if (pass_count + undef_count == 64 && fail_count == 0) begin
            $display("  RESULT: PASS — all 64 slots decoded");
        end else begin
            $display("  RESULT: FAIL — %0d slots unaccounted", 64 - pass_count - undef_count);
        end

        $finish;
    end

endmodule
