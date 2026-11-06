// SPDX-License-Identifier: MIT
// BradISA V2 -- Decode Stage
// Decodes 6-bit opcodes into 7 formats, reads 32-register file.
// All 64 opcode slots are decoded; 50 assigned, 14 reserved (undef insn).
//
// Two conventions the execute stage relies on:
//   * Branch and jump offsets arrive here as a word offset and are shifted
//     left by two, so dec_imm is already a byte displacement.
//   * LUI/AUIPC leaves the 21-bit immediate unshifted; execute applies the
//     << 11.  Every other immediate is sign-extended to 32 bits.

`include "bradisa_defines.v"

module brad_decode (
    input  wire         clk,
    input  wire         rst_n,
    // From fetch
    input  wire         fetch_valid,
    input  wire [31:0]  fetch_pc,
    input  wire [31:0]  fetch_insn,
    // Pipeline control
    input  wire         stall,
    input  wire         flush,
    // Register file read ports
    output wire [4:0]   rf_raddr1,
    input  wire [31:0]  rf_rdata1,
    output wire [4:0]   rf_raddr2,
    input  wire [31:0]  rf_rdata2,
    // Output to execute stage
    output reg          dec_valid,
    output reg  [5:0]   dec_opcode,
    output reg  [4:0]   dec_rd,
    output reg  [4:0]   dec_rs1,
    output reg  [4:0]   dec_rs2,
    output reg  [31:0]  dec_rs1_val,
    output reg  [31:0]  dec_rs2_val,
    output reg  [31:0]  dec_pc,
    output reg  [31:0]  dec_imm,
    output reg          dec_reg_we,
    output reg          dec_undef,      // 1 = reserved/unknown opcode
    output reg  [2:0]   dec_fmt         // see BRAD_FMT_* in bradisa_defines.v
);

    // ─── Raw fields ────────────────────────────────────────────
    // The bit position of "rs1" and "rs2" moves with the format, so these
    // names describe the fixed slices, not the roles.  The per-format block
    // below assigns the roles.
    wire [5:0]  opcode = fetch_insn[31:26];
    wire [4:0]  f_rd   = fetch_insn[25:21];   // RRR/RI/IJ/U rd, SI/BR rs1
    wire [4:0]  f_rs1  = fetch_insn[20:16];   // RRR/RI/IJ rs1, SI/BR rs2
    wire [4:0]  f_rs2  = fetch_insn[15:11];   // RRR rs2
    wire [15:0] imm16  = fetch_insn[15:0];    // RI/SI/BR/IJ immediate
    wire [20:0] imm21  = fetch_insn[20:0];    // JMP/U immediate

    // ─── Format detection from opcode range ────────────────────
    wire fmt_rrr = (opcode <= 6'd14);                     // 0x00-0x0E
    wire fmt_ri  = (opcode >= 6'd16 && opcode <= 6'd34);  // 0x10-0x22
    wire fmt_si  = (opcode >= 6'd35 && opcode <= 6'd37);  // 0x23-0x25
    wire fmt_u   = (opcode >= 6'd40 && opcode <= 6'd41);  // 0x28-0x29
    wire fmt_jmp = (opcode >= 6'd42 && opcode <= 6'd44);  // 0x2A-0x2C
    wire fmt_ij  = (opcode == 6'd45);                     // 0x2D JALR
    wire fmt_br  = (opcode >= 6'd48 && opcode <= 6'd55);  // 0x30-0x37
    wire fmt_amo = (opcode >= 6'd56 && opcode <= 6'd59);  // 0x38-0x3B
    wire is_ret  = (opcode == 6'd46);                     // 0x2E
    wire is_fence = (opcode == 6'd47);                    // 0x2F
    wire is_nop  = (opcode == 6'd0);                      // 0x00

    // ─── Undef detection ──────────────────────────────────────
    // 14 reserved slots: 0x0F, 0x19-0x1F (7), 0x26-0x27 (2), 0x3C-0x3F (4).
    wire is_undef = (opcode == 6'd15) ||
                    (opcode >= 6'd25 && opcode <= 6'd31) ||
                    (opcode >= 6'd38 && opcode <= 6'd39) ||
                    (opcode >= 6'd60 && opcode <= 6'd63);

    // ─── Register write enable ────────────────────────────────
    // NOP, stores, branches, JMP, RET and FENCE write no register.
    // CALL writes the link register (r15) regardless of its rd field.
    wire reg_we = ((fmt_rrr || fmt_ri || fmt_u || fmt_amo) && !is_nop) ||
                  (opcode == 6'd43) ||   // JAL
                  (opcode == 6'd44) ||   // CALL
                  (opcode == 6'd45);     // JALR

    // ─── Register file read addresses ─────────────────────────
    // RRR/AMO : rs1 = [20:16], rs2 = [15:11]
    // RI/IJ   : rs1 = [20:16]
    // SI      : rs1 = [20:16], rs2 (store data) = [25:21]
    // BR      : rs1 = [25:21], rs2 = [20:16]
    // RET     : reads the link register r15
    // JMP/U   : no register read
    assign rf_raddr1 = fmt_br     ? f_rd  :
                       is_ret     ? BRAD_LR :
                       (fmt_rrr || fmt_ri || fmt_si || fmt_ij || fmt_amo) ? f_rs1 :
                       5'd0;
    assign rf_raddr2 = fmt_rrr ? f_rs2 :
                       fmt_amo ? f_rs2 :
                       fmt_si  ? f_rd  :
                       fmt_br  ? f_rs1 :
                       5'd0;

    // ─── Format code for the execute stage ────────────────────
    // AMO reuses the RRR field shape; brad_execute distinguishes it by opcode.
    wire [2:0] fmt_code = (fmt_rrr || fmt_amo) ? BRAD_FMT_RRR :
                          fmt_ri  ? BRAD_FMT_RI  :
                          fmt_si  ? BRAD_FMT_SI  :
                          fmt_br  ? BRAD_FMT_BR  :
                          fmt_ij  ? BRAD_FMT_IJ  :
                          fmt_jmp ? BRAD_FMT_JMP :
                          fmt_u   ? BRAD_FMT_U   : BRAD_FMT_SP;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_valid   <= 1'b0;
            dec_opcode  <= 6'd0;
            dec_rd      <= 5'd0;
            dec_rs1     <= 5'd0;
            dec_rs2     <= 5'd0;
            dec_rs1_val <= 32'd0;
            dec_rs2_val <= 32'd0;
            dec_pc      <= 32'd0;
            dec_imm     <= 32'd0;
            dec_reg_we  <= 1'b0;
            dec_undef   <= 1'b0;
            dec_fmt     <= BRAD_FMT_SP;
        end else if (flush) begin
            dec_valid <= 1'b0;
        end else if (!stall) begin
            dec_valid   <= fetch_valid;
            dec_opcode  <= opcode;
            dec_pc      <= fetch_pc;
            dec_undef   <= is_undef;
            dec_fmt     <= fmt_code;

            // Field extraction.  Roles, not slices:
            //   RRR/AMO : rd, rs1, rs2
            //   RI/IJ   : rd, rs1, sext(imm16)
            //   SI      : rs1, rs2 (from [25:21]), sext(imm16)
            //   BR      : rs1 (from [25:21]), rs2 (from [20:16]), sext(imm16)<<2
            //   JMP     : rd, sext(imm21)<<2   (CALL overrides rd with lr)
            //   U       : rd, sext(imm21)      (execute shifts by 11)
            if (fmt_rrr || fmt_amo) begin
                dec_rd   <= is_nop ? 5'd0 : f_rd;
                dec_rs1  <= f_rs1;
                dec_rs2  <= f_rs2;
                dec_imm  <= 32'd0;
            end else if (fmt_ri) begin
                dec_rd   <= f_rd;
                dec_rs1  <= f_rs1;
                dec_rs2  <= 5'd0;
                dec_imm  <= { {16{imm16[15]}}, imm16 };
            end else if (fmt_si) begin
                dec_rd   <= 5'd0;   // stores have no destination
                dec_rs1  <= f_rs1;
                dec_rs2  <= f_rd;   // [25:21] holds the store source
                dec_imm  <= { {16{imm16[15]}}, imm16 };
            end else if (fmt_br) begin
                dec_rd   <= 5'd0;
                dec_rs1  <= f_rd;   // [25:21]
                dec_rs2  <= f_rs1;  // [20:16]
                dec_imm  <= { {14{imm16[15]}}, imm16, 2'b00 };  // bytes
            end else if (fmt_ij) begin
                dec_rd   <= f_rd;
                dec_rs1  <= f_rs1;
                dec_rs2  <= 5'd0;
                dec_imm  <= { {16{imm16[15]}}, imm16 };
            end else if (fmt_jmp) begin
                dec_rd   <= (opcode == 6'd44) ? BRAD_LR : f_rd;  // CALL -> lr
                dec_rs1  <= 5'd0;
                dec_rs2  <= 5'd0;
                dec_imm  <= { {9{imm21[20]}}, imm21, 2'b00 };    // bytes
            end else if (fmt_u) begin
                dec_rd   <= f_rd;
                dec_rs1  <= 5'd0;
                dec_rs2  <= 5'd0;
                dec_imm  <= { {11{imm21[20]}}, imm21 };
            end else begin
                // RET, FENCE, NOP
                dec_rd   <= 5'd0;
                dec_rs1  <= 5'd0;
                dec_rs2  <= 5'd0;
                dec_imm  <= 32'd0;
            end

            dec_rs1_val <= rf_rdata1;
            dec_rs2_val <= rf_rdata2;
            dec_reg_we  <= reg_we && !is_undef;
        end
    end

endmodule
