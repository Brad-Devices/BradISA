// SPDX-License-Identifier: MIT
// BradISA V2 -- ALU
// Combinational, 6-bit opcode.  Covers the fifteen register-register
// operations in the 0x00-0x0E group.  Loads, immediates and branches are
// handled in brad_execute, which owns the memory and control paths.

`include "bradisa_defines.v"

module brad_alu (
    input  wire [31:0]  a,
    input  wire [31:0]  b,
    input  wire [5:0]   op,       // BRAD_OP_NOP .. BRAD_OP_SAR
    output reg  [31:0]  result,
    output reg          div_zero  // 1 = divide by zero (DIV/DIVU/REM/REMU)
);

    wire signed [31:0] a_s = a;
    wire signed [31:0] b_s = b;
    wire        [63:0] mul64 = {32'd0, a} * {32'd0, b};

    always @(*) begin
        result   = 32'd0;
        div_zero = 1'b0;
        case (op)
            BRAD_OP_NOP:   result = 32'd0;
            BRAD_OP_ADD:   result = a + b;
            BRAD_OP_SUB:   result = a - b;
            BRAD_OP_MUL:   result = mul64[31:0];
            BRAD_OP_MULHU: result = mul64[63:32];
            BRAD_OP_DIV: begin
                if (b == 32'd0) begin
                    div_zero = 1'b1;
                    result   = 32'd0;
                end else begin
                    result = a_s / b_s;
                end
            end
            BRAD_OP_DIVU: begin
                if (b == 32'd0) begin
                    div_zero = 1'b1;
                    result   = 32'd0;
                end else begin
                    result = a / b;
                end
            end
            BRAD_OP_REM: begin
                if (b == 32'd0) begin
                    div_zero = 1'b1;
                    result   = 32'd0;
                end else begin
                    result = a_s % b_s;
                end
            end
            BRAD_OP_REMU: begin
                if (b == 32'd0) begin
                    div_zero = 1'b1;
                    result   = 32'd0;
                end else begin
                    result = a % b;
                end
            end
            BRAD_OP_AND:   result = a & b;
            BRAD_OP_OR:    result = a | b;
            BRAD_OP_XOR:   result = a ^ b;
            BRAD_OP_SHL:   result = a << b[4:0];
            BRAD_OP_SHR:   result = a >> b[4:0];
            BRAD_OP_SAR:   result = a_s >>> b[4:0];
            default:       result = 32'd0;
        endcase
    end

endmodule
