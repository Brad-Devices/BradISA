-- SPDX-License-Identifier: MIT
-- BradISA V2 VHDL Package
-- 6-bit opcode, 32 registers, 7 formats, 50 instructions.
-- Every instruction is exactly 32 bits.
--
-- Field layout (all formats):
--   [31:26]  op    (6 bits)
--   [25:21]  rd    (5 bits)  -- or rs2 for SI/BR
--   [20:16]  rs1   (5 bits)  -- or rd for JMP/U
--   [15:0]   imm/offset (16 bits) -- or rs2 for RRR/BR

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package bradisa_pkg is

    -- Opcodes (6-bit, 64 slots)
    constant OP_NOP    : std_logic_vector(5 downto 0) := "000000";
    constant OP_ADD    : std_logic_vector(5 downto 0) := "000001";
    constant OP_SUB    : std_logic_vector(5 downto 0) := "000010";
    constant OP_MUL    : std_logic_vector(5 downto 0) := "000011";
    constant OP_MULHU  : std_logic_vector(5 downto 0) := "000100";
    constant OP_DIV    : std_logic_vector(5 downto 0) := "000101";
    constant OP_DIVU   : std_logic_vector(5 downto 0) := "000110";
    constant OP_REM    : std_logic_vector(5 downto 0) := "000111";
    constant OP_REMU   : std_logic_vector(5 downto 0) := "001000";
    constant OP_AND    : std_logic_vector(5 downto 0) := "001001";
    constant OP_OR     : std_logic_vector(5 downto 0) := "001010";
    constant OP_XOR    : std_logic_vector(5 downto 0) := "001011";
    constant OP_SHL    : std_logic_vector(5 downto 0) := "001100";
    constant OP_SHR    : std_logic_vector(5 downto 0) := "001101";
    constant OP_SAR    : std_logic_vector(5 downto 0) := "001110";
    -- 0x0F reserved

    constant OP_ADDI   : std_logic_vector(5 downto 0) := "010000";
    constant OP_ANDI   : std_logic_vector(5 downto 0) := "010001";
    constant OP_ORI    : std_logic_vector(5 downto 0) := "010010";
    constant OP_XORI   : std_logic_vector(5 downto 0) := "010011";
    constant OP_SLLI   : std_logic_vector(5 downto 0) := "010100";
    constant OP_SRLI   : std_logic_vector(5 downto 0) := "010101";
    constant OP_SRAI   : std_logic_vector(5 downto 0) := "010110";
    constant OP_SLTI   : std_logic_vector(5 downto 0) := "010111";
    constant OP_SLTIU  : std_logic_vector(5 downto 0) := "011000";
    -- 0x19-0x1F reserved

    constant OP_LDW    : std_logic_vector(5 downto 0) := "100000";
    constant OP_LHU    : std_logic_vector(5 downto 0) := "100001";
    constant OP_LHBU   : std_logic_vector(5 downto 0) := "100010";
    constant OP_STW    : std_logic_vector(5 downto 0) := "100011";
    constant OP_SH     : std_logic_vector(5 downto 0) := "100100";
    constant OP_SB     : std_logic_vector(5 downto 0) := "100101";
    -- 0x26-0x27 reserved

    constant OP_LUI    : std_logic_vector(5 downto 0) := "101000";
    constant OP_AUIPC  : std_logic_vector(5 downto 0) := "101001";
    constant OP_JMP    : std_logic_vector(5 downto 0) := "101010";
    constant OP_JAL    : std_logic_vector(5 downto 0) := "101011";
    constant OP_CALL   : std_logic_vector(5 downto 0) := "101100";
    constant OP_JALR   : std_logic_vector(5 downto 0) := "101101";
    constant OP_RET    : std_logic_vector(5 downto 0) := "101110";
    constant OP_FENCE  : std_logic_vector(5 downto 0) := "101111";

    constant OP_BEQ    : std_logic_vector(5 downto 0) := "110000";
    constant OP_BNE    : std_logic_vector(5 downto 0) := "110001";
    constant OP_BLT    : std_logic_vector(5 downto 0) := "110010";
    constant OP_BGE    : std_logic_vector(5 downto 0) := "110011";
    constant OP_BLTU   : std_logic_vector(5 downto 0) := "110100";
    constant OP_BGEU   : std_logic_vector(5 downto 0) := "110101";
    constant OP_BZ     : std_logic_vector(5 downto 0) := "110110";
    constant OP_BNZ    : std_logic_vector(5 downto 0) := "110111";

    -- Atomics (0x38-0x3B; 0x3C-0x3F reserved as extension escape)

    constant OP_LR_W      : std_logic_vector(5 downto 0) := "111000";
    constant OP_SC_W      : std_logic_vector(5 downto 0) := "111001";
    constant OP_AMOSWAP_W : std_logic_vector(5 downto 0) := "111010";
    constant OP_AMOADD_W  : std_logic_vector(5 downto 0) := "111011";

    -- Register numbers (5-bit, 32 registers; ABI per bradisa_spec.tex 3.2)
    constant REG_R0 : std_logic_vector(4 downto 0) := "00000";
    constant REG_A0 : std_logic_vector(4 downto 0) := "00001";
    constant REG_T5 : std_logic_vector(4 downto 0) := "01110";
    constant REG_LR : std_logic_vector(4 downto 0) := "01111";  -- link register
    constant REG_SP : std_logic_vector(4 downto 0) := "11011";
    constant NUM_REGS : integer := 32;

    -- Instruction field positions (V2)
    constant OPCODE_SHIFT : integer := 26;
    constant RD_SHIFT     : integer := 21;
    constant RS1_SHIFT    : integer := 16;
    constant RS2_SHIFT    : integer := 11;

    -- Pipeline model constants
    constant PHOENIX_DEPTH      : integer := 10;
    constant PHOENIX_EXEC_STAGE : integer := 6;
    constant FALCON_DEPTH       : integer := 5;
    constant FALCON_EXEC_STAGE  : integer := 3;

    -- RET fixed encoding: opcode 0x2E at [31:26] => 0xB8000000
    constant RET_RAW : std_logic_vector(31 downto 0) := x"B8000000";

    -- Helper: sign-extend 16-bit to 32-bit
    function sext16(v : std_logic_vector(15 downto 0)) return std_logic_vector;

    -- Helper: sign-extend 21-bit to 32-bit
    function sext21(v : std_logic_vector(20 downto 0)) return std_logic_vector;

end package bradisa_pkg;

package body bradisa_pkg is
    function sext16(v : std_logic_vector(15 downto 0)) return std_logic_vector is
    begin
        return (31 downto 16 => v(15)) & v;
    end function;
    function sext21(v : std_logic_vector(20 downto 0)) return std_logic_vector is
    begin
        return (31 downto 21 => v(20)) & v;
    end function;
end package body bradisa_pkg;
