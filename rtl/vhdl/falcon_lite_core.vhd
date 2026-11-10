-- SPDX-License-Identifier: MIT
-- BradISA V2 -- Falcon-Lite 3-stage ultra-tiny core (VHDL)
-- Stages: F -> D -> EX (execute + writeback)
-- 8 registers (r0-r7), single-issue, in-order, no multiplier.
--
-- This is the compile-only teaching variant, the VHDL twin of
-- rtl/verilog/falcon_lite_core.v.  It uses the V2 instruction encoding
-- (6-bit opcode, 5-bit register fields) but implements nine opcodes and
-- an 8-entry register file, so it is not the reference core and no
-- testbench runs against it.  brad_core.vhd is the reference.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.bradisa_pkg.all;

entity falcon_lite_core is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        imem_addr   : out std_logic_vector(31 downto 0);
        imem_rdata  : in  std_logic_vector(31 downto 0);
        dmem_addr   : out std_logic_vector(31 downto 0);
        dmem_req    : out std_logic;
        dmem_we     : out std_logic;
        dmem_wdata  : out std_logic_vector(31 downto 0);
        dmem_rdata  : in  std_logic_vector(31 downto 0)
    );
end entity falcon_lite_core;

architecture rtl of falcon_lite_core is

    constant FALCON_NUM_REGS : integer := 8;

    -- ─── Register file (embedded, 8 x 32-bit) ──────────────
    type reg_array is array (0 to FALCON_NUM_REGS-1) of std_logic_vector(31 downto 0);
    signal regs : reg_array := (others => (others => '0'));

    -- ─── Fetch stage ────────────────────────────────────────
    signal f_pc    : std_logic_vector(31 downto 0) := (others => '0');
    signal f_insn  : std_logic_vector(31 downto 0) := (others => '0');
    signal f_valid : std_logic := '0';

    -- ─── Decode stage ───────────────────────────────────────
    signal d_valid   : std_logic := '0';
    signal d_pc      : std_logic_vector(31 downto 0) := (others => '0');
    signal d_opcode  : std_logic_vector(5 downto 0) := (others => '0');
    signal d_rd      : std_logic_vector(4 downto 0) := (others => '0');
    signal d_rs1     : std_logic_vector(4 downto 0) := (others => '0');
    signal d_rs2     : std_logic_vector(4 downto 0) := (others => '0');
    signal d_rs1_val : std_logic_vector(31 downto 0) := (others => '0');
    signal d_rs2_val : std_logic_vector(31 downto 0) := (others => '0');
    signal d_imm     : std_logic_vector(31 downto 0) := (others => '0');
    signal d_reg_we  : std_logic := '0';
    signal d_mem_req : std_logic := '0';
    signal d_mem_we  : std_logic := '0';

    -- ─── Execute stage ──────────────────────────────────────
    signal e_valid      : std_logic := '0';
    signal e_rd         : std_logic_vector(4 downto 0) := (others => '0');
    signal e_result     : std_logic_vector(31 downto 0) := (others => '0');
    signal e_addr       : std_logic_vector(31 downto 0) := (others => '0');
    signal e_reg_we     : std_logic := '0';
    signal e_mem_req    : std_logic := '0';
    signal e_mem_we     : std_logic := '0';
    signal e_store_data : std_logic_vector(31 downto 0) := (others => '0');

    -- ─── PC / branch ────────────────────────────────────────
    signal pc           : std_logic_vector(31 downto 0) := (others => '0');
    signal next_pc      : std_logic_vector(31 downto 0) := (others => '0');
    signal branch_taken : std_logic := '0';
    signal bz_taken     : std_logic := '0';
    signal bnz_taken    : std_logic := '0';
    signal jmp_taken    : std_logic := '0';
    signal call_taken   : std_logic := '0';
    signal ret_taken    : std_logic := '0';

    -- ─── ALU result ─────────────────────────────────────────
    signal alu_result : std_logic_vector(31 downto 0) := (others => '0');

    -- ─── Raw fields from the fetch-stage instruction ────────
    signal raw_op  : std_logic_vector(5 downto 0);
    signal raw_rd  : std_logic_vector(4 downto 0);
    signal raw_rs1 : std_logic_vector(4 downto 0);
    signal raw_rs2 : std_logic_vector(4 downto 0);
    signal raw_imm : std_logic_vector(15 downto 0);

    -- ─── Operand fetches from the embedded regfile ──────────
    signal rf_rdata1 : std_logic_vector(31 downto 0);
    signal rf_rdata2 : std_logic_vector(31 downto 0);

begin

    -- ─── Instruction field extraction (V2 layout) ───────────
    raw_op  <= f_insn(31 downto 26);
    raw_rd  <= f_insn(25 downto 21);
    raw_rs1 <= f_insn(20 downto 16);
    raw_rs2 <= f_insn(15 downto 11);
    raw_imm <= f_insn(15 downto 0);

    -- Eight registers: anything outside r0..r7 reads as zero, and r0 is
    -- hardwired to zero.
    rf_rdata1 <= (others => '0') when (unsigned(raw_rs1) = 0 or unsigned(raw_rs1) >= FALCON_NUM_REGS)
                 else regs(to_integer(unsigned(raw_rs1)));
    rf_rdata2 <= (others => '0') when (unsigned(raw_rs2) = 0 or unsigned(raw_rs2) >= FALCON_NUM_REGS)
                 else regs(to_integer(unsigned(raw_rs2)));

    -- ─── Fetch stage ────────────────────────────────────────
    imem_addr <= pc;

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            pc      <= (others => '0');
            f_valid <= '0';
            f_pc    <= (others => '0');
            f_insn  <= (others => '0');
        elsif rising_edge(clk) then
            if branch_taken = '1' then
                f_valid <= '0';
                pc      <= next_pc;
            else
                f_valid <= '1';
                f_pc    <= pc;
                f_insn  <= imem_rdata;
                pc      <= std_logic_vector(unsigned(pc) + 4);
            end if;
        end if;
    end process;

    -- ─── Decode stage ───────────────────────────────────────
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            d_valid   <= '0';
            d_pc      <= (others => '0');
            d_opcode  <= (others => '0');
            d_rd      <= (others => '0');
            d_rs1     <= (others => '0');
            d_rs2     <= (others => '0');
            d_rs1_val <= (others => '0');
            d_rs2_val <= (others => '0');
            d_imm     <= (others => '0');
            d_reg_we  <= '0';
            d_mem_req <= '0';
            d_mem_we  <= '0';
        elsif rising_edge(clk) then
            if branch_taken = '1' then
                d_valid <= '0';
            else
                d_valid   <= f_valid;
                d_pc      <= f_pc;
                d_opcode  <= raw_op;
                d_rd      <= raw_rd;
                d_rs1     <= raw_rs1;
                d_rs2     <= raw_rs2;
                d_rs1_val <= rf_rdata1;
                d_rs2_val <= rf_rdata2;
                d_imm     <= sext16(raw_imm);

                -- Writeback for the ALU group and ADDI, plus LDW.  MUL is
                -- in the ALU group but this variant has no multiplier, so
                -- the execute stage writes zero for it.
                d_reg_we  <= '1' when (unsigned(raw_op) >= 1 and unsigned(raw_op) <= 14)
                                       or raw_op = OP_ADDI
                                       or raw_op = OP_LDW
                             else '0';

                d_mem_req <= '1' when raw_op = OP_LDW or raw_op = OP_STW else '0';
                d_mem_we  <= '1' when raw_op = OP_STW else '0';
            end if;
        end if;
    end process;

    -- ─── ALU (combinational, no multiplier) ─────────────────
    process(d_opcode, d_rs1_val, d_rs2_val, d_imm)
        variable b_op : std_logic_vector(31 downto 0);
    begin
        b_op := d_rs2_val when d_opcode /= OP_ADDI else d_imm;
        case d_opcode is
            when OP_ADD    => alu_result <= std_logic_vector(unsigned(d_rs1_val) + unsigned(b_op));
            when OP_SUB    => alu_result <= std_logic_vector(unsigned(d_rs1_val) - unsigned(b_op));
            when OP_MUL    => alu_result <= (others => '0');   -- not implemented
            when OP_AND    => alu_result <= d_rs1_val and b_op;
            when OP_OR     => alu_result <= d_rs1_val or b_op;
            when OP_XOR    => alu_result <= d_rs1_val xor b_op;
            when OP_SHL    => alu_result <= std_logic_vector(shift_left(unsigned(d_rs1_val), to_integer(unsigned(b_op(4 downto 0)))));
            when OP_SHR    => alu_result <= std_logic_vector(shift_right(unsigned(d_rs1_val), to_integer(unsigned(b_op(4 downto 0)))));
            when OP_ADDI   => alu_result <= std_logic_vector(unsigned(d_rs1_val) + unsigned(d_imm));
            when others    => alu_result <= (others => '0');
        end case;
    end process;

    -- ─── Branch resolution ───────────────────────────────────
    bz_taken   <= '1' when (d_opcode = OP_BZ)  and (unsigned(d_rs1_val) = 0) else '0';
    bnz_taken  <= '1' when (d_opcode = OP_BNZ) and (unsigned(d_rs1_val) /= 0) else '0';
    jmp_taken  <= '1' when (d_opcode = OP_JMP)  else '0';
    call_taken <= '1' when (d_opcode = OP_CALL) else '0';
    ret_taken  <= '1' when (d_opcode = OP_RET)  else '0';
    branch_taken <= d_valid and (bz_taken or bnz_taken or jmp_taken or call_taken or ret_taken);

    -- Branch/jump displacements are word offsets in the encoding, so the
    -- byte target shifts left by two.
    next_pc <= d_rs1_val when d_opcode = OP_RET else
               std_logic_vector(unsigned(d_pc) + 4
                                + shift_left(unsigned(d_imm), 2));

    -- ─── Execute stage ──────────────────────────────────────
    process(clk, rst_n)
        variable ex_result : std_logic_vector(31 downto 0);
    begin
        if rst_n = '0' then
            e_valid      <= '0';
            e_rd         <= (others => '0');
            e_result     <= (others => '0');
            e_addr       <= (others => '0');
            e_reg_we     <= '0';
            e_mem_req    <= '0';
            e_mem_we     <= '0';
            e_store_data <= (others => '0');
        elsif rising_edge(clk) then
            e_valid   <= d_valid and not branch_taken;
            e_rd      <= d_rd;
            e_reg_we  <= d_reg_we;

            if unsigned(d_opcode) <= 14 or d_opcode = OP_ADDI then
                ex_result := alu_result;
            else
                ex_result := (others => '0');
            end if;

            if d_opcode = OP_CALL then
                ex_result := std_logic_vector(unsigned(d_pc) + 4);
                e_rd      <= REG_LR;
                e_reg_we  <= '1';
            end if;

            e_result     <= ex_result;
            e_addr       <= std_logic_vector(unsigned(d_rs1_val) + unsigned(d_imm));
            e_store_data <= d_rs2_val;
            e_mem_req    <= d_mem_req;
            e_mem_we     <= d_mem_we;
        end if;
    end process;

    -- ─── Writeback to the embedded regfile ───────────────────
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            regs <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if e_valid = '1' and e_reg_we = '1'
               and unsigned(e_rd) /= 0 and unsigned(e_rd) < FALCON_NUM_REGS then
                if e_mem_req = '1' and e_mem_we = '0' then
                    regs(to_integer(unsigned(e_rd))) <= dmem_rdata;
                else
                    regs(to_integer(unsigned(e_rd))) <= e_result;
                end if;
            end if;
        end if;
    end process;

    -- ─── Memory port outputs ─────────────────────────────────
    dmem_addr  <= e_addr;
    dmem_req   <= e_mem_req;
    dmem_we    <= e_mem_we;
    dmem_wdata <= e_store_data;

end architecture rtl;
