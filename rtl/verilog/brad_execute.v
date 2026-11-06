// SPDX-License-Identifier: MIT
// BradISA V2 -- Execute Stage
// Combinational ALU, address generation, branch resolution and single-cycle
// memory access.  The register file and the WB stage live in brad_core.
//
// Scope note: LR.W/SC.W execute as a single-cycle load/store.  Reservation
// tracking for SC.W is not implemented yet -- SC.W always reports success.
// That is a real gap, recorded here rather than hidden in a comment elsewhere.

`include "bradisa_defines.v"

module brad_execute (
    // From the ID/EX register
    input  wire         dec_valid,
    input  wire [5:0]   dec_opcode,
    input  wire [4:0]   dec_rd,
    input  wire [4:0]   dec_rs1,
    input  wire [4:0]   dec_rs2,
    input  wire [31:0]  dec_rs1_val,
    input  wire [31:0]  dec_rs2_val,
    input  wire [31:0]  dec_pc,
    input  wire [31:0]  dec_imm,      // branch/jump offsets already in bytes
    input  wire         dec_reg_we,
    input  wire         dec_undef,
    input  wire [2:0]   dec_fmt,
    // Data memory (single-cycle, combinational read)
    input  wire [31:0]  dmem_rdata,
    // To the EX/WB register
    output reg  [4:0]   ex_rd,
    output reg  [31:0]  ex_result,
    output reg          ex_reg_we,
    output reg          ex_illegal,
    // Data memory request
    output reg  [31:0]  ex_addr,
    output reg          ex_mem_req,
    output reg          ex_mem_we,
    output reg  [3:0]   ex_mem_be,     // byte enables for SH/SB
    output reg  [31:0]  ex_store_data,
    // Branch redirect to fetch
    output reg          branch_taken,
    output reg  [31:0]  branch_target
);

    // ─── Opcode groups ────────────────────────────────────────────────────
    wire op_rrr   = (dec_fmt == BRAD_FMT_RRR);
    wire op_br    = (dec_fmt == BRAD_FMT_BR);
    wire op_ij    = (dec_fmt == BRAD_FMT_IJ);
    wire op_jmp   = (dec_fmt == BRAD_FMT_JMP);

    wire is_amo   = (dec_opcode >= BRAD_OP_LR_W) && (dec_opcode <= BRAD_OP_AMOADD_W);
    wire is_load  = (dec_opcode == BRAD_OP_LDW) || (dec_opcode == BRAD_OP_LHU) ||
                    (dec_opcode == BRAD_OP_LHBU);
    wire is_store = (dec_opcode == BRAD_OP_STW) || (dec_opcode == BRAD_OP_SH) ||
                    (dec_opcode == BRAD_OP_SB);
    wire is_amo_load  = (dec_opcode == BRAD_OP_LR_W);
    wire is_amo_store = (dec_opcode == BRAD_OP_SC_W) ||
                        (dec_opcode == BRAD_OP_AMOSWAP_W) ||
                        (dec_opcode == BRAD_OP_AMOADD_W);
    wire is_mem = is_load || is_store || is_amo;

    // ─── ALU ──────────────────────────────────────────────────────────────
    wire [31:0] alu_result;
    wire        alu_div_zero;

    brad_alu alu_inst (
        .a(dec_rs1_val),
        .b(dec_rs2_val),
        .op(dec_opcode),
        .result(alu_result),
        .div_zero(alu_div_zero)
    );

    wire signed [31:0] rs1_s = dec_rs1_val;
    wire signed [31:0] rs2_s = dec_rs2_val;

    // ─── Branch resolution ───────────────────────────────────────────────
    reg br_cond;
    always @(*) begin
        br_cond = 1'b0;
        case (dec_opcode)
            BRAD_OP_BEQ:  br_cond = (dec_rs1_val == dec_rs2_val);
            BRAD_OP_BNE:  br_cond = (dec_rs1_val != dec_rs2_val);
            BRAD_OP_BLT:  br_cond = (rs1_s < rs2_s);
            BRAD_OP_BGE:  br_cond = (rs1_s >= rs2_s);
            BRAD_OP_BLTU: br_cond = (dec_rs1_val < dec_rs2_val);
            BRAD_OP_BGEU: br_cond = (dec_rs1_val >= dec_rs2_val);
            BRAD_OP_BZ:   br_cond = (dec_rs1_val == 32'd0);
            BRAD_OP_BNZ:  br_cond = (dec_rs1_val != 32'd0);
            default:      br_cond = 1'b0;
        endcase
    end

    wire        is_jmp  = (dec_opcode == BRAD_OP_JMP) ||
                          (dec_opcode == BRAD_OP_JAL) ||
                          (dec_opcode == BRAD_OP_CALL);
    wire        is_ret  = (dec_opcode == BRAD_OP_RET);
    wire [31:0] pc_rel   = dec_pc + 32'd4 + dec_imm;
    wire [31:0] jalr_tgt = (dec_rs1_val + dec_imm) & ~32'd1;

    // ─── Datapath ────────────────────────────────────────────────────────
    always @(*) begin
        // Defaults: no write, no memory, no branch, no trap.
        ex_rd         = dec_rd;
        ex_result     = 32'd0;
        ex_reg_we     = dec_reg_we && dec_valid && !dec_undef;
        ex_illegal    = dec_undef;
        ex_addr       = dec_rs1_val + dec_imm;
        ex_mem_req    = 1'b0;
        ex_mem_we     = 1'b0;
        ex_mem_be     = 4'b0000;
        ex_store_data = dec_rs2_val;
        branch_taken  = 1'b0;
        branch_target = 32'd0;

        // Result select
        if (op_rrr && !is_amo) begin
            ex_result = alu_result;
            if (alu_div_zero)
                ex_illegal = 1'b1;
        end else if (dec_opcode == BRAD_OP_ADDI) begin
            ex_result = dec_rs1_val + dec_imm;
        end else if (dec_opcode == BRAD_OP_ANDI) begin
            ex_result = dec_rs1_val & {16'd0, dec_imm[15:0]};
        end else if (dec_opcode == BRAD_OP_ORI) begin
            ex_result = dec_rs1_val | {16'd0, dec_imm[15:0]};
        end else if (dec_opcode == BRAD_OP_XORI) begin
            ex_result = dec_rs1_val ^ {16'd0, dec_imm[15:0]};
        end else if (dec_opcode == BRAD_OP_SLLI) begin
            ex_result = dec_rs1_val << dec_imm[4:0];
        end else if (dec_opcode == BRAD_OP_SRLI) begin
            ex_result = dec_rs1_val >> dec_imm[4:0];
        end else if (dec_opcode == BRAD_OP_SRAI) begin
            ex_result = rs1_s >>> dec_imm[4:0];
        end else if (dec_opcode == BRAD_OP_SLTI) begin
            ex_result = (rs1_s < $signed(dec_imm)) ? 32'd1 : 32'd0;
        end else if (dec_opcode == BRAD_OP_SLTIU) begin
            ex_result = (dec_rs1_val < {16'd0, dec_imm[15:0]}) ? 32'd1 : 32'd0;
        end else if (dec_opcode == BRAD_OP_LUI) begin
            ex_result = dec_imm << 11;
        end else if (dec_opcode == BRAD_OP_AUIPC) begin
            ex_result = dec_pc + (dec_imm << 11);
        end else if ((dec_opcode == BRAD_OP_JAL) ||
                     (dec_opcode == BRAD_OP_CALL) ||
                     (dec_opcode == BRAD_OP_JALR)) begin
            ex_result = dec_pc + 32'd4;         // link value
        end else if (is_load) begin
            ex_result = (dec_opcode == BRAD_OP_LDW)  ? dmem_rdata :
                        (dec_opcode == BRAD_OP_LHU)  ? {16'd0, dmem_rdata[15:0]} :
                                                       {24'd0, dmem_rdata[7:0]};
        end else if (is_amo_load || (dec_opcode == BRAD_OP_AMOSWAP_W) ||
                     (dec_opcode == BRAD_OP_AMOADD_W)) begin
            ex_result = dmem_rdata;             // old memory value
        end else if (dec_opcode == BRAD_OP_SC_W) begin
            ex_result = 32'd0;                  // 0 = success
        end

        // Memory request
        if (is_mem) begin
            ex_mem_req = 1'b1;
            ex_mem_we  = is_store || is_amo_store;
            if (dec_opcode == BRAD_OP_SH) begin
                ex_store_data = {16'd0, dec_rs2_val[15:0]};
                ex_mem_be     = 4'b0011;
            end else if (dec_opcode == BRAD_OP_SB) begin
                ex_store_data = {24'd0, dec_rs2_val[7:0]};
                ex_mem_be     = 4'b0001;
            end else if (dec_opcode == BRAD_OP_AMOADD_W) begin
                ex_store_data = dmem_rdata + dec_rs2_val;
                ex_mem_be     = 4'b1111;
            end else if (ex_mem_we) begin
                ex_mem_be     = 4'b1111;
            end
        end

        // Branch / jump
        if (op_br) begin
            branch_taken  = br_cond;
            branch_target = pc_rel;
        end else if (is_jmp) begin
            branch_taken  = 1'b1;
            branch_target = pc_rel;
        end else if (op_ij) begin
            branch_taken  = 1'b1;
            branch_target = jalr_tgt;
        end else if (is_ret) begin
            branch_taken  = 1'b1;
            branch_target = dec_rs1_val;        // link register, read as rs1
        end

        // A non-valid slot issues nothing.
        if (!dec_valid) begin
            ex_reg_we     = 1'b0;
            ex_mem_req    = 1'b0;
            ex_mem_we     = 1'b0;
            branch_taken  = 1'b0;
            ex_illegal    = 1'b0;
        end
    end

endmodule
