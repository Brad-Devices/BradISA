// SPDX-License-Identifier: MIT
// BradISA V2 -- BradCore (Falcon pipeline)
// Synthesisable RTL for FPGA.  Stages: F -> D -> EX -> WB.
//
// In-order, single-issue, no stalls.  RAW hazards are covered by forwarding
// from the EX and WB stages into the decode operand capture, which is sound
// here because the data memory returns in the same cycle (the single-cycle
// memory contract this core is specified against).  A multi-cycle memory
// would need the stall path that brad_decode already exposes.

`include "bradisa_defines.v"

module brad_core (
    input  wire         clk,
    input  wire         rst_n,
    // Instruction memory port (single-cycle, combinational read)
    output wire [31:0]  imem_addr,
    input  wire [31:0]  imem_rdata,
    // Data memory port (single-cycle, combinational read)
    output wire [31:0]  dmem_addr,
    output wire         dmem_req,
    output wire         dmem_we,
    output wire [3:0]   dmem_be,
    output wire [31:0]  dmem_wdata,
    input  wire [31:0]  dmem_rdata,
    // One-cycle fault: undefined opcode or divide by zero in EX
    output wire         fault
);

    // ─── Fetch stage ────────────────────────────────────────────
    reg         f_valid;
    reg  [31:0] f_pc;
    reg  [31:0] f_insn;

    // ─── Decode stage (registered outputs of brad_decode) ──────
    wire        d_valid;
    wire [5:0]  d_opcode;
    wire [4:0]  d_rd;
    wire [4:0]  d_rs1;
    wire [4:0]  d_rs2;
    wire [31:0] d_rs1_val;
    wire [31:0] d_rs2_val;
    wire [31:0] d_pc;
    wire [31:0] d_imm;
    wire        d_reg_we;
    wire        d_undef;
    wire [2:0]  d_fmt;

    // ─── Writeback stage ────────────────────────────────────────
    reg         w_valid;
    reg  [4:0]  w_rd;
    reg  [31:0] w_result;
    reg         w_reg_we;

    // ─── PC ─────────────────────────────────────────────────────
    reg  [31:0] pc;
    wire        branch_taken;
    wire [31:0] branch_target;

    // ─── Decode / register file wiring ──────────────────────────
    wire [4:0]  id_raddr1;
    wire [4:0]  id_raddr2;
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;

    // ─── Execute outputs ────────────────────────────────────────
    wire [4:0]  ex_rd;
    wire [31:0] ex_result;
    wire        ex_reg_we;
    wire        ex_illegal;
    wire [31:0] ex_addr;
    wire        ex_mem_req;
    wire        ex_mem_we;
    wire [3:0]  ex_mem_be;
    wire [31:0] ex_store_data;

    // ─── Forwarding ─────────────────────────────────────────────
    // EX beats WB: it is the younger writer and holds the value the consumer
    // would otherwise have to wait a cycle for.
    wire [31:0] id_rdata1 =
        (d_valid && d_reg_we && (d_rd != BRAD_R0) && (d_rd == id_raddr1)) ? ex_result :
        (w_valid && w_reg_we && (w_rd != BRAD_R0) && (w_rd == id_raddr1)) ? w_result :
        rf_rdata1;

    wire [31:0] id_rdata2 =
        (d_valid && d_reg_we && (d_rd != BRAD_R0) && (d_rd == id_raddr2)) ? ex_result :
        (w_valid && w_reg_we && (w_rd != BRAD_R0) && (w_rd == id_raddr2)) ? w_result :
        rf_rdata2;

    // ─── Submodules ─────────────────────────────────────────────
    brad_decode decode (
        .clk(clk), .rst_n(rst_n),
        .fetch_valid(f_valid), .fetch_pc(f_pc), .fetch_insn(f_insn),
        .stall(1'b0), .flush(branch_taken),
        .rf_raddr1(id_raddr1), .rf_rdata1(id_rdata1),
        .rf_raddr2(id_raddr2), .rf_rdata2(id_rdata2),
        .dec_valid(d_valid), .dec_opcode(d_opcode), .dec_rd(d_rd),
        .dec_rs1(d_rs1), .dec_rs2(d_rs2),
        .dec_rs1_val(d_rs1_val), .dec_rs2_val(d_rs2_val),
        .dec_pc(d_pc), .dec_imm(d_imm), .dec_reg_we(d_reg_we),
        .dec_undef(d_undef), .dec_fmt(d_fmt)
    );

    brad_execute execute (
        .dec_valid(d_valid), .dec_opcode(d_opcode), .dec_rd(d_rd),
        .dec_rs1(d_rs1), .dec_rs2(d_rs2),
        .dec_rs1_val(d_rs1_val), .dec_rs2_val(d_rs2_val),
        .dec_pc(d_pc), .dec_imm(d_imm), .dec_reg_we(d_reg_we),
        .dec_undef(d_undef), .dec_fmt(d_fmt),
        .dmem_rdata(dmem_rdata),
        .ex_rd(ex_rd), .ex_result(ex_result), .ex_reg_we(ex_reg_we),
        .ex_illegal(ex_illegal),
        .ex_addr(ex_addr), .ex_mem_req(ex_mem_req), .ex_mem_we(ex_mem_we),
        .ex_mem_be(ex_mem_be), .ex_store_data(ex_store_data),
        .branch_taken(branch_taken), .branch_target(branch_target)
    );

    brad_regfile regfile (
        .clk(clk), .rst_n(rst_n),
        .raddr1(id_raddr1), .rdata1(rf_rdata1),
        .raddr2(id_raddr2), .rdata2(rf_rdata2),
        .we(w_valid && w_reg_we), .waddr(w_rd), .wdata(w_result)
    );

    // ─── Fetch ──────────────────────────────────────────────────
    assign imem_addr = pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc      <= 32'd0;
            f_valid <= 1'b0;
            f_pc    <= 32'd0;
            f_insn  <= 32'd0;
        end else if (branch_taken) begin
            // The instruction being fetched and the one in decode are both
            // wrong-path.  Redirect, and spend one cycle refilling.
            pc      <= branch_target;
            f_valid <= 1'b0;
        end else begin
            f_valid <= 1'b1;
            f_pc    <= pc;
            f_insn  <= imem_rdata;
            pc      <= pc + 32'd4;
        end
    end

    // ─── Writeback ──────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_valid  <= 1'b0;
            w_rd     <= 5'd0;
            w_result <= 32'd0;
            w_reg_we <= 1'b0;
        end else begin
            w_valid  <= d_valid;
            w_rd     <= ex_rd;
            w_result <= ex_result;
            w_reg_we <= ex_reg_we;
        end
    end

    // ─── Memory port ────────────────────────────────────────────
    assign dmem_addr  = ex_addr;
    assign dmem_req   = ex_mem_req;
    assign dmem_we    = ex_mem_we;
    assign dmem_be    = ex_mem_be;
    assign dmem_wdata = ex_store_data;

    // ─── Fault ──────────────────────────────────────────────────
    assign fault = ex_illegal;

endmodule
