// SPDX-License-Identifier: MIT
// BradISA V2 -- BradCore execution testbench
//
// Every program below is hand-encoded with the V2 field layout, run on the
// core, and checked against the value the instruction is defined to produce.
// This is the receipt the decode-coverage testbench cannot give: decode
// proves the ISA is parseable, this proves it computes.

`include "bradisa_defines.v"

module tb_brad_core;

    reg         clk;
    reg         rst_n;

    // Instruction memory (single-cycle, combinational read)
    reg  [31:0] imem [0:255];
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    assign imem_rdata = imem[imem_addr[9:2]];

    // Data memory (single-cycle, combinational read, synchronous write)
    reg  [31:0] dmem [0:255];
    wire [31:0] dmem_addr;
    wire        dmem_req;
    wire        dmem_we;
    wire [3:0]  dmem_be;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    assign dmem_rdata = dmem[dmem_addr[9:2]];

    always @(posedge clk)
        if (dmem_req && dmem_we) begin
            if (dmem_be[0]) dmem[dmem_addr[9:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_be[1]) dmem[dmem_addr[9:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_be[2]) dmem[dmem_addr[9:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_be[3]) dmem[dmem_addr[9:2]][31:24] <= dmem_wdata[31:24];
        end

    // DUT
    wire fault;

    brad_core dut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_be(dmem_be),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .fault(fault)
    );

    always #5 clk = ~clk;

    // ─── Encoders ───────────────────────────────────────────────
    // These mirror bradisa_spec.tex §3 exactly.  If a field moves in the
    // spec, it moves here in the same commit.
    function [31:0] RRR(input [5:0] op, input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        RRR = {op, rd, rs1, rs2, 11'b0};
    endfunction

    function [31:0] RI(input [5:0] op, input [4:0] rd, input [4:0] rs1, input [15:0] imm);
        RI = {op, rd, rs1, imm};
    endfunction

    function [31:0] SI(input [5:0] op, input [4:0] rs2, input [4:0] rs1, input [15:0] imm);
        SI = {op, rs2, rs1, imm};
    endfunction

    function [31:0] BR(input [5:0] op, input [4:0] rs1, input [4:0] rs2, input [15:0] off);
        BR = {op, rs1, rs2, off};
    endfunction

    function [31:0] JMPF(input [5:0] op, input [4:0] rd, input [20:0] off);
        JMPF = {op, rd, off};
    endfunction

    function [31:0] UF(input [5:0] op, input [4:0] rd, input [20:0] imm);
        UF = {op, rd, imm};
    endfunction

    // ─── Bookkeeping ────────────────────────────────────────────
    integer errors;
    integer checks;
    reg     fault_seen;

    always @(posedge clk)
        if (fault) fault_seen <= 1'b1;

    task check(input [8*24-1:0] name, input [31:0] got, input [31:0] want);
        begin
            checks = checks + 1;
            if (got !== want) begin
                $display("  FAIL  %0s: got 0x%08X, want 0x%08X", name, got, want);
                errors = errors + 1;
            end else begin
                $display("  ok    %0s = 0x%08X", name, got);
            end
        end
    endtask

    task clear_mem;
        integer k;
        begin
            for (k = 0; k < 256; k = k + 1) begin
                imem[k] = 32'd0;
                dmem[k] = 32'd0;
            end
        end
    endtask

    task reset_core;
        begin
            rst_n = 1'b0;
            #15;
            rst_n = 1'b1;
        end
    endtask

    task run(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge clk);
        end
    endtask

    // Halt: JMP with offset -1 lands on itself.
    function [31:0] HALT;
        HALT = JMPF(BRAD_OP_JMP, 5'd0, 21'h1FFFFF);
    endfunction

    // ─── Programs ───────────────────────────────────────────────
    task test_alu;
        begin
            $display("[1] register-register ALU");
            clear_mem;
            imem[0]  = RI(BRAD_OP_ADDI, 5'd1, 5'd0, 16'd10);
            imem[1]  = RI(BRAD_OP_ADDI, 5'd2, 5'd0, 16'd3);
            imem[2]  = RRR(BRAD_OP_ADD, 5'd3, 5'd1, 5'd2);
            imem[3]  = RRR(BRAD_OP_SUB, 5'd4, 5'd1, 5'd2);
            imem[4]  = RRR(BRAD_OP_MUL, 5'd5, 5'd1, 5'd2);
            imem[5]  = RRR(BRAD_OP_AND, 5'd6, 5'd1, 5'd2);
            imem[6]  = RRR(BRAD_OP_OR,  5'd7, 5'd1, 5'd2);
            imem[7]  = RRR(BRAD_OP_XOR, 5'd8, 5'd1, 5'd2);
            imem[8]  = RRR(BRAD_OP_SHL, 5'd9, 5'd1, 5'd2);
            imem[9]  = RRR(BRAD_OP_SHR, 5'd10, 5'd1, 5'd2);
            imem[10] = RRR(BRAD_OP_SAR, 5'd11, 5'd1, 5'd2);
            imem[11] = HALT();
            reset_core;
            run(80);
            check("r1  ADDI",  dut.regfile.regs[1],  32'd10);
            check("r2  ADDI",  dut.regfile.regs[2],  32'd3);
            check("r3  ADD",   dut.regfile.regs[3],  32'd13);
            check("r4  SUB",   dut.regfile.regs[4],  32'd7);
            check("r5  MUL",   dut.regfile.regs[5],  32'd30);
            check("r6  AND",   dut.regfile.regs[6],  32'd2);
            check("r7  OR",    dut.regfile.regs[7],  32'd11);
            check("r8  XOR",   dut.regfile.regs[8],  32'd9);
            check("r9  SHL",   dut.regfile.regs[9],  32'd80);
            check("r10 SHR",   dut.regfile.regs[10], 32'd1);
            check("r11 SAR",   dut.regfile.regs[11], 32'd1);
        end
    endtask

    task test_imm;
        begin
            $display("[2] immediates, upper immediate, set-less-than");
            clear_mem;
            imem[0]  = UF(BRAD_OP_LUI,   5'd1, 21'h00001);
            imem[1]  = RI(BRAD_OP_ADDI,  5'd1, 5'd1, 16'd25);
            imem[2]  = RI(BRAD_OP_ADDI,  5'd2, 5'd0, 16'hFFFB);  // -5
            imem[3]  = RI(BRAD_OP_ANDI,  5'd3, 5'd2, 16'h00FF);
            imem[4]  = RI(BRAD_OP_ORI,   5'd4, 5'd0, 16'h0F00);
            imem[5]  = RI(BRAD_OP_XORI,  5'd5, 5'd2, 16'h00FF);
            imem[6]  = RI(BRAD_OP_SLLI,  5'd6, 5'd1, 16'd4);
            imem[7]  = RI(BRAD_OP_SRLI,  5'd7, 5'd2, 16'd28);
            imem[8]  = RI(BRAD_OP_SRAI,  5'd8, 5'd2, 16'd28);
            imem[9]  = RI(BRAD_OP_SLTI,  5'd9, 5'd0, 16'd1);
            imem[10] = RI(BRAD_OP_SLTIU, 5'd10, 5'd0, 16'd1);
            imem[11] = UF(BRAD_OP_AUIPC, 5'd11, 21'h00001);   // pc + 0x800
            imem[12] = RI(BRAD_OP_ADDI,  5'd12, 5'd0,  16'd1);
            imem[13] = RI(BRAD_OP_SLLI,  5'd12, 5'd12, 16'd16); // 65536
            imem[14] = RI(BRAD_OP_SLTIU, 5'd13, 5'd12, 16'hFFFF); // zext, not sext
            imem[15] = HALT();
            reset_core;
            run(80);
            check("r1  LUI+ADDI", dut.regfile.regs[1],  32'h00000819);
            check("r2  ADDI -5",  dut.regfile.regs[2],  32'hFFFFFFFB);
            check("r3  ANDI zext",dut.regfile.regs[3],  32'h000000FB);
            check("r4  ORI",      dut.regfile.regs[4],  32'h00000F00);
            check("r5  XORI zext",dut.regfile.regs[5],  32'hFFFFFF04);
            check("r6  SLLI",     dut.regfile.regs[6],  32'h00008190);
            check("r7  SRLI",     dut.regfile.regs[7],  32'h0000000F);
            check("r8  SRAI",     dut.regfile.regs[8],  32'hFFFFFFFF);
            check("r9  SLTI",     dut.regfile.regs[9],  32'd1);
            check("r10 SLTIU",    dut.regfile.regs[10], 32'd1);
            check("r11 AUIPC",    dut.regfile.regs[11], 32'h0000082C);
            check("r13 SLTIU zext", dut.regfile.regs[13], 32'd0);
        end
    endtask

    task test_mem;
        begin
            $display("[3] loads, stores, sub-word access");
            clear_mem;
            imem[0]  = RI(BRAD_OP_ADDI, 5'd1, 5'd0, 16'd64);
            imem[1]  = RI(BRAD_OP_ADDI, 5'd2, 5'd0, 16'h1234);
            imem[2]  = SI(BRAD_OP_STW,  5'd2, 5'd1, 16'd0);
            imem[3]  = SI(BRAD_OP_STW,  5'd2, 5'd1, 16'd4);
            imem[4]  = RI(BRAD_OP_LDW,  5'd3, 5'd1, 16'd0);
            imem[5]  = RI(BRAD_OP_ADDI, 5'd4, 5'd0, 16'h5678);
            imem[6]  = SI(BRAD_OP_STW,  5'd4, 5'd1, 16'd8);
            imem[7]  = RI(BRAD_OP_LDW,  5'd5, 5'd1, 16'd8);
            // 0x12345678 via LUI+ADDI, then verify SH/SB merge instead of clobber
            imem[8]  = UF(BRAD_OP_LUI,  5'd10, 21'h24680);     // 0x12340000
            imem[9]  = RI(BRAD_OP_ADDI, 5'd10, 5'd10, 16'h5678);
            imem[10] = SI(BRAD_OP_STW,  5'd10, 5'd1, 16'd12);
            imem[11] = RI(BRAD_OP_ADDI, 5'd6, 5'd0, 16'hABCD);
            imem[12] = SI(BRAD_OP_SH,   5'd6, 5'd1, 16'd12);
            imem[13] = RI(BRAD_OP_LDW,  5'd7, 5'd1, 16'd12);
            imem[14] = RI(BRAD_OP_LHU,  5'd8, 5'd1, 16'd12);
            imem[15] = SI(BRAD_OP_SB,   5'd6, 5'd1, 16'd16);
            imem[16] = RI(BRAD_OP_LHBU, 5'd9, 5'd1, 16'd16);
            imem[17] = SI(BRAD_OP_STW,  5'd10, 5'd1, 16'd16);
            imem[18] = SI(BRAD_OP_SB,   5'd6, 5'd1, 16'd16);
            imem[19] = RI(BRAD_OP_LDW,  5'd15, 5'd1, 16'd16);
            imem[20] = HALT();
            reset_core;
            run(100);
            check("r3  LDW after STW",  dut.regfile.regs[3], 32'h00001234);
            check("r5  LDW after STW",  dut.regfile.regs[5], 32'h00005678);
            check("r7  SH preserves hi",dut.regfile.regs[7], 32'h1234ABCD);
            check("r8  LHU",            dut.regfile.regs[8], 32'h0000ABCD);
            check("r9  LHBU",           dut.regfile.regs[9], 32'h000000CD);
            check("r15 SB preserves",   dut.regfile.regs[15],32'h123456CD);
        end
    endtask

    task test_loop;
        begin
            $display("[4] signed branch loop");
            clear_mem;
            imem[0] = RI(BRAD_OP_ADDI, 5'd1, 5'd0, 16'd0);    // i = 0
            imem[1] = RI(BRAD_OP_ADDI, 5'd2, 5'd0, 16'd0);    // sum = 0
            imem[2] = RI(BRAD_OP_ADDI, 5'd3, 5'd0, 16'd5);    // n = 5
            imem[3] = RI(BRAD_OP_ADDI, 5'd1, 5'd1, 16'd1);    // loop: i++
            imem[4] = RRR(BRAD_OP_ADD, 5'd2, 5'd2, 5'd1);     // sum += i
            imem[5] = BR(BRAD_OP_BLT, 5'd1, 5'd3, 16'hFFFD);  // -3
            imem[6] = HALT();
            reset_core;
            run(120);
            check("r1  loop counter", dut.regfile.regs[1], 32'd5);
            check("r2  sum 1..5",     dut.regfile.regs[2], 32'd15);

            $display("[4b] BNZ countdown");
            clear_mem;
            imem[0] = RI(BRAD_OP_ADDI, 5'd4, 5'd0, 16'd4);
            imem[1] = RI(BRAD_OP_ADDI, 5'd5, 5'd0, 16'd0);
            imem[2] = RI(BRAD_OP_ADDI, 5'd5, 5'd5, 16'd2);    // loop
            imem[3] = RI(BRAD_OP_ADDI, 5'd4, 5'd4, 16'hFFFF); // -1
            imem[4] = BR(BRAD_OP_BNZ, 5'd4, 5'd0, 16'hFFFD);  // -3
            imem[5] = HALT();
            reset_core;
            run(100);
            check("r5  doubled 4x", dut.regfile.regs[5], 32'd8);
            check("r4  counted to 0", dut.regfile.regs[4], 32'd0);

            $display("[4c] unsigned comparisons");
            clear_mem;
            imem[0] = RI(BRAD_OP_ADDI, 5'd1, 5'd0, 16'hFFFF);  // 0xFFFFFFFF
            imem[1] = RI(BRAD_OP_ADDI, 5'd2, 5'd0, 16'd1);
            imem[2] = BR(BRAD_OP_BLTU, 5'd1, 5'd2, 16'd1);     // not taken
            imem[3] = RI(BRAD_OP_ADDI, 5'd3, 5'd0, 16'd10);
            imem[4] = BR(BRAD_OP_BGEU, 5'd1, 5'd2, 16'd1);     // taken
            imem[5] = RI(BRAD_OP_ADDI, 5'd4, 5'd0, 16'd20);    // skipped
            imem[6] = RI(BRAD_OP_ADDI, 5'd5, 5'd0, 16'd30);
            imem[7] = HALT();
            reset_core;
            run(80);
            check("r3  BLTU not taken", dut.regfile.regs[3], 32'd10);
            check("r4  BGEU skipped",   dut.regfile.regs[4], 32'd0);
            check("r5  BGEU target",    dut.regfile.regs[5], 32'd30);
        end
    endtask

    task test_call;
        begin
            $display("[5] CALL / RET");
            clear_mem;
            imem[0] = RI(BRAD_OP_ADDI, 5'd5, 5'd0, 16'd7);
            imem[1] = JMPF(BRAD_OP_CALL, 5'd1, 21'd2);        // -> index 4
            imem[2] = RI(BRAD_OP_ADDI, 5'd2, 5'd0, 16'd1);    // after RET
            imem[3] = JMPF(BRAD_OP_JMP,  5'd0, 21'd2);        // -> index 6
            imem[4] = RI(BRAD_OP_ADDI, 5'd3, 5'd0, 16'd99);   // fn
            imem[5] = {BRAD_OP_RET, 26'd0};
            imem[6] = HALT();
            reset_core;
            run(80);
            check("r15 link from CALL", dut.regfile.regs[15], 32'd8);
            check("r2  after RET",      dut.regfile.regs[2], 32'd1);
            check("r3  function body",  dut.regfile.regs[3], 32'd99);
            check("r5  preserved",      dut.regfile.regs[5], 32'd7);
        end
    endtask

    task test_jalr;
        begin
            $display("[6] JALR indirect jump");
            clear_mem;
            imem[0] = RI(BRAD_OP_ADDI, 5'd5, 5'd0, 16'd20);   // target = 20
            imem[1] = RI(BRAD_OP_JALR, 5'd6, 5'd5, 16'd0);
            imem[2] = RI(BRAD_OP_ADDI, 5'd7, 5'd0, 16'd1);    // skipped
            imem[3] = RI(BRAD_OP_ADDI, 5'd8, 5'd0, 16'd2);    // skipped
            imem[4] = RI(BRAD_OP_ADDI, 5'd9, 5'd0, 16'd3);    // skipped
            imem[5] = RI(BRAD_OP_ADDI, 5'd10, 5'd0, 16'd42);  // target
            imem[6] = HALT();
            reset_core;
            run(80);
            check("r6  link from JALR", dut.regfile.regs[6], 32'd8);
            check("r10 target reached", dut.regfile.regs[10], 32'd42);
            check("r7  not executed",   dut.regfile.regs[7], 32'd0);
            check("r8  not executed",   dut.regfile.regs[8], 32'd0);
            check("r9  not executed",   dut.regfile.regs[9], 32'd0);

            $display("[6b] JAL direct jump with link");
            clear_mem;
            imem[0] = JMPF(BRAD_OP_JAL, 5'd7, 21'd3);         // -> index 4
            imem[1] = RI(BRAD_OP_ADDI, 5'd8, 5'd0, 16'd1);    // skipped
            imem[2] = RI(BRAD_OP_ADDI, 5'd8, 5'd0, 16'd2);    // skipped
            imem[3] = RI(BRAD_OP_ADDI, 5'd8, 5'd0, 16'd3);    // skipped
            imem[4] = RI(BRAD_OP_ADDI, 5'd9, 5'd0, 16'd55);
            imem[5] = HALT();
            reset_core;
            run(80);
            check("r7  link from JAL",  dut.regfile.regs[7], 32'd4);
            check("r9  target reached", dut.regfile.regs[9], 32'd55);
            check("r8  not executed",   dut.regfile.regs[8], 32'd0);
        end
    endtask

    task test_fwd;
        begin
            $display("[7] forwarding (RAW distance 1 and 2)");
            clear_mem;
            imem[0] = RI(BRAD_OP_ADDI, 5'd1, 5'd0, 16'd5);
            imem[1] = RRR(BRAD_OP_ADD, 5'd2, 5'd1, 5'd1);
            imem[2] = RRR(BRAD_OP_ADD, 5'd3, 5'd2, 5'd1);
            imem[3] = RI(BRAD_OP_ADDI, 5'd4, 5'd0, 16'd100);
            imem[4] = SI(BRAD_OP_STW,  5'd3, 5'd4, 16'd0);
            imem[5] = RI(BRAD_OP_LDW,  5'd5, 5'd4, 16'd0);
            imem[6] = RRR(BRAD_OP_ADD, 5'd6, 5'd5, 5'd1);
            imem[7] = HALT();
            reset_core;
            run(80);
            check("r2  distance 1", dut.regfile.regs[2], 32'd10);
            check("r3  chain",      dut.regfile.regs[3], 32'd15);
            check("r5  store/load", dut.regfile.regs[5], 32'd15);
            check("r6  load-use",   dut.regfile.regs[6], 32'd20);
        end
    endtask

    task test_div;
        begin
            $display("[8] divide and remainder");
            clear_mem;
            imem[0] = RI(BRAD_OP_ADDI, 5'd1, 5'd0, 16'd100);
            imem[1] = RI(BRAD_OP_ADDI, 5'd2, 5'd0, 16'd7);
            imem[2] = RRR(BRAD_OP_DIV,  5'd3, 5'd1, 5'd2);
            imem[3] = RRR(BRAD_OP_REM,  5'd4, 5'd1, 5'd2);
            imem[4] = RRR(BRAD_OP_DIVU, 5'd5, 5'd1, 5'd2);
            imem[5] = RRR(BRAD_OP_REMU, 5'd6, 5'd1, 5'd2);
            imem[6] = RI(BRAD_OP_ADDI, 5'd7, 5'd0, 16'hFF9C); // -100
            imem[7] = RRR(BRAD_OP_DIV,  5'd8, 5'd7, 5'd2);
            imem[8] = HALT();
            reset_core;
            run(80);
            check("r3  DIV",     dut.regfile.regs[3], 32'd14);
            check("r4  REM",     dut.regfile.regs[4], 32'd2);
            check("r5  DIVU",    dut.regfile.regs[5], 32'd14);
            check("r6  REMU",    dut.regfile.regs[6], 32'd2);
            check("r8  DIV neg", dut.regfile.regs[8], 32'hFFFFFFF2);
        end
    endtask

    task test_fault;
        begin
            $display("[9] undefined opcode faults");
            clear_mem;
            imem[0] = {6'h3F, 26'd0};   // reserved slot
            imem[1] = HALT();
            fault_seen = 1'b0;
            reset_core;
            run(40);
            check("fault on 0x3F", fault_seen, 32'd1);

            $display("[10] divide by zero faults");
            clear_mem;
            imem[0] = RI(BRAD_OP_ADDI, 5'd1, 5'd0, 16'd5);
            imem[1] = RI(BRAD_OP_ADDI, 5'd2, 5'd0, 16'd0);
            imem[2] = RRR(BRAD_OP_DIV, 5'd3, 5'd1, 5'd2);
            imem[3] = HALT();
            fault_seen = 1'b0;
            reset_core;
            run(40);
            check("fault on DIV/0", fault_seen, 32'd1);
            check("r3  DIV/0 result", dut.regfile.regs[3], 32'd0);
        end
    endtask

    // ─── Run ────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_brad_core.vcd");
        $dumpvars(0, tb_brad_core);

        clk = 1'b0;
        rst_n = 1'b0;
        errors = 0;
        checks = 0;
        fault_seen = 1'b0;

        test_alu;
        test_imm;
        test_mem;
        test_loop;
        test_call;
        test_jalr;
        test_fwd;
        test_div;
        test_fault;

        $display("");
        $display("=== BRADCORE EXECUTION SUMMARY ===");
        $display("  checks: %0d", checks);
        $display("  errors: %0d", errors);
        if (errors == 0)
            $display("  RESULT: PASS -- every instruction produced its defined value");
        else
            $display("  RESULT: FAIL -- %0d mismatches", errors);
        if (errors == 0)
            $display("PASS");
        $finish;
    end

endmodule
