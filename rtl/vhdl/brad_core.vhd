-- SPDX-License-Identifier: MIT
-- BradISA V2 -- BradCore (Falcon pipeline, VHDL)
-- Stages: F -> D -> EX -> WB.
--
-- In-order, single-issue, no stalls.  RAW hazards are covered by forwarding
-- from the EX and WB stages into the decode operand capture, which is sound
-- here because the data memory returns in the same cycle (the single-cycle
-- memory contract this core is specified against).  A multi-cycle memory
-- would need a stall path.
--
-- This is the VHDL half of the same design as rtl/verilog/brad_core.v +
-- brad_decode.v + brad_execute.v.  The two trees are kept as one design: a
-- change to the ISA in one is a change in the other, and the shared
-- full-ISA program (rtl/asm/tb_brad_isa.s) executes on both.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.bradisa_pkg.all;

entity brad_core is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        -- Instruction memory port (single-cycle, combinational read)
        imem_addr   : out std_logic_vector(31 downto 0);
        imem_rdata  : in  std_logic_vector(31 downto 0);
        -- Data memory port (single-cycle, combinational read)
        dmem_addr   : out std_logic_vector(31 downto 0);
        dmem_req    : out std_logic;
        dmem_we     : out std_logic;
        dmem_be     : out std_logic_vector(3 downto 0);
        dmem_wdata  : out std_logic_vector(31 downto 0);
        dmem_rdata  : in  std_logic_vector(31 downto 0);
        -- One-cycle fault: undefined opcode or divide by zero in EX
        fault       : out std_logic
    );
end entity brad_core;

architecture rtl of brad_core is

    -- ─── Fetch stage ────────────────────────────────────────────
    signal f_valid : std_logic := '0';
    signal f_pc    : std_logic_vector(31 downto 0) := (others => '0');
    signal f_insn  : std_logic_vector(31 downto 0) := (others => '0');

    -- ─── Decode stage registers ─────────────────────────────────
    signal d_valid   : std_logic := '0';
    signal d_opcode  : std_logic_vector(5 downto 0) := (others => '0');
    signal d_rd      : std_logic_vector(4 downto 0) := (others => '0');
    signal d_rs1     : std_logic_vector(4 downto 0) := (others => '0');
    signal d_rs2     : std_logic_vector(4 downto 0) := (others => '0');
    signal d_rs1_val : std_logic_vector(31 downto 0) := (others => '0');
    signal d_rs2_val : std_logic_vector(31 downto 0) := (others => '0');
    signal d_pc      : std_logic_vector(31 downto 0) := (others => '0');
    signal d_imm     : std_logic_vector(31 downto 0) := (others => '0');
    signal d_reg_we  : std_logic := '0';
    signal d_undef   : std_logic := '0';

    -- ─── Writeback stage ────────────────────────────────────────
    signal w_valid  : std_logic := '0';
    signal w_rd     : std_logic_vector(4 downto 0) := (others => '0');
    signal w_result : std_logic_vector(31 downto 0) := (others => '0');
    signal w_reg_we : std_logic := '0';

    -- ─── PC ─────────────────────────────────────────────────────
    signal pc           : std_logic_vector(31 downto 0) := (others => '0');
    signal branch_taken : std_logic := '0';
    signal branch_target : std_logic_vector(31 downto 0) := (others => '0');

    -- ─── Decode / register file wiring ──────────────────────────
    signal id_raddr1 : std_logic_vector(4 downto 0);
    signal id_raddr2 : std_logic_vector(4 downto 0);
    signal rf_rdata1 : std_logic_vector(31 downto 0);
    signal rf_rdata2 : std_logic_vector(31 downto 0);
    signal id_rdata1 : std_logic_vector(31 downto 0);
    signal id_rdata2 : std_logic_vector(31 downto 0);

    -- ─── Execute outputs ────────────────────────────────────────
    signal ex_rd         : std_logic_vector(4 downto 0);
    signal ex_result     : std_logic_vector(31 downto 0);
    signal ex_reg_we     : std_logic;
    signal ex_illegal    : std_logic;
    signal ex_addr       : std_logic_vector(31 downto 0);
    signal ex_mem_req    : std_logic;
    signal ex_mem_we     : std_logic;
    signal ex_mem_be     : std_logic_vector(3 downto 0);
    signal ex_store_data : std_logic_vector(31 downto 0);

    -- ─── Decode raw fields ──────────────────────────────────────
    signal opcode : std_logic_vector(5 downto 0);
    signal f_rd   : std_logic_vector(4 downto 0);
    signal f_rs1  : std_logic_vector(4 downto 0);
    signal f_rs2  : std_logic_vector(4 downto 0);
    signal imm16  : std_logic_vector(15 downto 0);
    signal imm21  : std_logic_vector(20 downto 0);

    -- ─── Decode format detection ────────────────────────────────
    signal fmt_rrr  : std_logic;
    signal fmt_ri   : std_logic;
    signal fmt_si   : std_logic;
    signal fmt_u    : std_logic;
    signal fmt_jmp  : std_logic;
    signal fmt_ij   : std_logic;
    signal fmt_br   : std_logic;
    signal fmt_amo  : std_logic;
    signal is_ret   : std_logic;   -- fetch stage: drives the read-address mux
    signal is_ret_d : std_logic;   -- decode stage: drives execute/redirect
    signal is_fence : std_logic;
    signal is_nop   : std_logic;
    signal is_undef : std_logic;
    signal reg_we   : std_logic;

    -- ─── Execute groups ─────────────────────────────────────────
    signal op_rrr      : std_logic;
    signal op_br       : std_logic;
    signal op_ij       : std_logic;
    signal op_jump      : std_logic;
    signal is_amo      : std_logic;
    signal is_load     : std_logic;
    signal is_store    : std_logic;
    signal is_amo_load : std_logic;
    signal is_amo_store : std_logic;
    signal is_mem      : std_logic;
    signal is_jmp_op   : std_logic;
    signal alu_result  : std_logic_vector(31 downto 0);
    signal alu_div_zero : std_logic;
    signal br_cond     : std_logic;
    signal pc_rel      : std_logic_vector(31 downto 0);
    signal jalr_tgt     : std_logic_vector(31 downto 0);

begin

    -- ─── Raw fields ─────────────────────────────────────────────
    opcode <= f_insn(31 downto 26);
    f_rd   <= f_insn(25 downto 21);
    f_rs1  <= f_insn(20 downto 16);
    f_rs2  <= f_insn(15 downto 11);
    imm16  <= f_insn(15 downto 0);
    imm21  <= f_insn(20 downto 0);

    -- ─── Format detection from opcode range ─────────────────────
    -- Chips, not one inline conditional chain: GHDL rejects inline
    -- conditionals mixed with and/or, and each of these is used in several
    -- places below.
    fmt_rrr <= '1' when unsigned(f_insn(31 downto 26)) <= 14 else '0';
    fmt_ri  <= '1' when unsigned(f_insn(31 downto 26)) >= 16 and unsigned(f_insn(31 downto 26)) <= 34 else '0';
    fmt_si  <= '1' when unsigned(f_insn(31 downto 26)) >= 35 and unsigned(f_insn(31 downto 26)) <= 37 else '0';
    fmt_u   <= '1' when unsigned(f_insn(31 downto 26)) >= 40 and unsigned(f_insn(31 downto 26)) <= 41 else '0';
    fmt_jmp <= '1' when unsigned(f_insn(31 downto 26)) >= 42 and unsigned(f_insn(31 downto 26)) <= 44 else '0';
    fmt_ij  <= '1' when unsigned(f_insn(31 downto 26)) = 45 else '0';
    fmt_br  <= '1' when unsigned(f_insn(31 downto 26)) >= 48 and unsigned(f_insn(31 downto 26)) <= 55 else '0';
    fmt_amo <= '1' when unsigned(f_insn(31 downto 26)) >= 56 and unsigned(f_insn(31 downto 26)) <= 59 else '0';
    is_ret   <= '1' when unsigned(f_insn(31 downto 26)) = 46 else '0';
    is_ret_d <= '1' when unsigned(d_opcode) = 46 else '0';
    is_fence <= '1' when unsigned(f_insn(31 downto 26)) = 47 else '0';
    is_nop   <= '1' when unsigned(f_insn(31 downto 26)) = 0 else '0';

    -- Undef detection: 14 reserved slots (0x0F, 0x19-0x1F, 0x26-0x27, 0x3C-0x3F)
    is_undef <= '1' when (unsigned(f_insn(31 downto 26)) = 15)
                          or (unsigned(f_insn(31 downto 26)) >= 25 and unsigned(f_insn(31 downto 26)) <= 31)
                          or (unsigned(f_insn(31 downto 26)) >= 38 and unsigned(f_insn(31 downto 26)) <= 39)
                          or (unsigned(f_insn(31 downto 26)) >= 60 and unsigned(f_insn(31 downto 26)) <= 63)
                    else '0';

    -- Register write enable.  NOP, stores, branches, JMP, RET and FENCE
    -- write no register.  CALL writes the link register (r15) regardless.
    reg_we <= '1' when (((fmt_rrr = '1' or fmt_ri = '1' or fmt_u = '1' or fmt_amo = '1')
                          and is_nop = '0')
                        or unsigned(f_insn(31 downto 26)) = 43      -- JAL
                        or unsigned(f_insn(31 downto 26)) = 44      -- CALL
                        or unsigned(f_insn(31 downto 26)) = 45)     -- JALR
                    else '0';

    -- ─── Register file read addresses ───────────────────────────
    id_raddr1 <= f_rd when fmt_br = '1' else
                 REG_LR when is_ret = '1' else
                 f_rs1 when (fmt_rrr = '1' or fmt_ri = '1' or fmt_si = '1'
                             or fmt_ij = '1' or fmt_amo = '1') else
                 (others => '0');

    id_raddr2 <= f_rs2 when (fmt_rrr = '1' or fmt_amo = '1') else
                 f_rd  when fmt_si = '1' else
                 f_rs1 when fmt_br = '1' else
                 (others => '0');

    -- ─── Forwarding ─────────────────────────────────────────────
    -- EX beats WB: it is the younger writer and holds the value the consumer
    -- would otherwise have to wait a cycle for.
    id_rdata1 <= ex_result when (d_valid = '1' and d_reg_we = '1'
                                 and unsigned(d_rd) /= 0
                                 and d_rd = id_raddr1)
                else w_result when (w_valid = '1' and w_reg_we = '1'
                                    and unsigned(w_rd) /= 0
                                    and w_rd = id_raddr1)
                else rf_rdata1;

    id_rdata2 <= ex_result when (d_valid = '1' and d_reg_we = '1'
                                 and unsigned(d_rd) /= 0
                                 and d_rd = id_raddr2)
                else w_result when (w_valid = '1' and w_reg_we = '1'
                                    and unsigned(w_rd) /= 0
                                    and w_rd = id_raddr2)
                else rf_rdata2;

    -- ─── Register file instance ─────────────────────────────────
    regfile_inst : entity work.brad_regfile
        port map (
            clk    => clk,
            rst_n  => rst_n,
            raddr1 => id_raddr1,
            rdata1 => rf_rdata1,
            raddr2 => id_raddr2,
            rdata2 => rf_rdata2,
            we     => w_valid and w_reg_we,
            waddr  => w_rd,
            wdata  => w_result
        );

    -- ─── Decode stage (registered) ──────────────────────────────
    process(clk, rst_n) begin
        if rst_n = '0' then
            d_valid   <= '0';
            d_opcode  <= (others => '0');
            d_rd      <= (others => '0');
            d_rs1     <= (others => '0');
            d_rs2     <= (others => '0');
            d_rs1_val <= (others => '0');
            d_rs2_val <= (others => '0');
            d_pc      <= (others => '0');
            d_imm     <= (others => '0');
            d_reg_we  <= '0';
            d_undef   <= '0';
        elsif rising_edge(clk) then
            if branch_taken = '1' then
                d_valid <= '0';
            else
                d_valid  <= f_valid;
                d_opcode <= opcode;
                d_pc     <= f_pc;
                d_undef  <= is_undef;
                d_rs1_val <= id_rdata1;
                d_rs2_val <= id_rdata2;
                d_reg_we  <= reg_we and not is_undef;

                -- Field extraction.  Roles, not slices.
                if (fmt_rrr = '1' or fmt_amo = '1') then
                    d_rd  <= (others => '0') when is_nop = '1' else f_rd;
                    d_rs1 <= f_rs1;
                    d_rs2 <= f_rs2;
                    d_imm <= (others => '0');
                elsif fmt_ri = '1' then
                    d_rd  <= f_rd;
                    d_rs1 <= f_rs1;
                    d_rs2 <= (others => '0');
                    d_imm <= sext16(imm16);
                elsif fmt_si = '1' then
                    d_rd  <= (others => '0');
                    d_rs1 <= f_rs1;
                    d_rs2 <= f_rd;   -- [25:21] holds the store source
                    d_imm <= sext16(imm16);
                elsif fmt_br = '1' then
                    d_rd  <= (others => '0');
                    d_rs1 <= f_rd;
                    d_rs2 <= f_rs1;
                    d_imm <= std_logic_vector(shift_left(unsigned(sext16(imm16)), 2));
                elsif fmt_ij = '1' then
                    d_rd  <= f_rd;
                    d_rs1 <= f_rs1;
                    d_rs2 <= (others => '0');
                    d_imm <= sext16(imm16);
                elsif fmt_jmp = '1' then
                    d_rd  <= REG_LR when unsigned(opcode) = 44 else f_rd;  -- CALL -> lr
                    d_rs1 <= (others => '0');
                    d_rs2 <= (others => '0');
                    d_imm <= std_logic_vector(shift_left(unsigned(sext21(imm21)), 2));
                elsif fmt_u = '1' then
                    d_rd  <= f_rd;
                    d_rs1 <= (others => '0');
                    d_rs2 <= (others => '0');
                    d_imm <= sext21(imm21);
                else
                    -- RET, FENCE, NOP
                    d_rd  <= (others => '0');
                    d_rs1 <= (others => '0');
                    d_rs2 <= (others => '0');
                    d_imm <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- ─── ALU instance ───────────────────────────────────────────
    alu_inst : entity work.brad_alu
        port map (
            a        => d_rs1_val,
            b        => d_rs2_val,
            op       => d_opcode,
            result   => alu_result,
            div_zero => alu_div_zero
        );

    -- ─── Execute opcode groups ───────────────────────────────────
    -- Format is a pure function of the opcode, so the execute stage derives
    -- its group signals from d_opcode exactly as the decode stage derived
    -- them from the fetch-stage opcode.  RRR covers the ALU group and the
    -- AMO opcodes (which reuse the RRR field shape).
    op_rrr <= '1' when (unsigned(d_opcode) <= 14)
                        or (unsigned(d_opcode) >= 56 and unsigned(d_opcode) <= 59)
              else '0';
    op_br  <= '1' when d_opcode >= OP_BEQ and d_opcode <= OP_BNZ else '0';
    op_ij  <= '1' when d_opcode = OP_JALR else '0';
    op_jump <= '1' when d_opcode = OP_JMP or d_opcode = OP_JAL or d_opcode = OP_CALL else '0';

    is_amo      <= '1' when d_opcode >= OP_LR_W and d_opcode <= OP_AMOADD_W else '0';
    is_load     <= '1' when d_opcode = OP_LDW or d_opcode = OP_LHU or d_opcode = OP_LHBU else '0';
    is_store    <= '1' when d_opcode = OP_STW or d_opcode = OP_SH or d_opcode = OP_SB else '0';
    is_amo_load <= '1' when d_opcode = OP_LR_W else '0';
    is_amo_store <= '1' when d_opcode = OP_SC_W or d_opcode = OP_AMOSWAP_W
                              or d_opcode = OP_AMOADD_W else '0';
    is_mem      <= '1' when (is_load = '1' or is_store = '1' or is_amo = '1') else '0';
    is_jmp_op   <= '1' when (d_opcode = OP_JMP or d_opcode = OP_JAL or d_opcode = OP_CALL) else '0';

    -- ─── Branch resolution ──────────────────────────────────────
    process(d_opcode, d_rs1_val, d_rs2_val) begin
        br_cond <= '0';
        case d_opcode is
            when OP_BEQ  => br_cond <= '1' when d_rs1_val = d_rs2_val else '0';
            when OP_BNE  => br_cond <= '1' when d_rs1_val /= d_rs2_val else '0';
            when OP_BLT  => br_cond <= '1' when signed(d_rs1_val) < signed(d_rs2_val) else '0';
            when OP_BGE  => br_cond <= '1' when signed(d_rs1_val) >= signed(d_rs2_val) else '0';
            when OP_BLTU => br_cond <= '1' when unsigned(d_rs1_val) < unsigned(d_rs2_val) else '0';
            when OP_BGEU => br_cond <= '1' when unsigned(d_rs1_val) >= unsigned(d_rs2_val) else '0';
            when OP_BZ   => br_cond <= '1' when unsigned(d_rs1_val) = 0 else '0';
            when OP_BNZ  => br_cond <= '1' when unsigned(d_rs1_val) /= 0 else '0';
            when others  => br_cond <= '0';
        end case;
    end process;

    pc_rel  <= std_logic_vector(unsigned(d_pc) + 4 + unsigned(d_imm));
    jalr_tgt <= std_logic_vector((unsigned(d_rs1_val) + unsigned(d_imm)) and x"FFFFFFFE");

    -- ─── Execute + writeback datapath ───────────────────────────
    process(d_valid, d_opcode, d_rd, d_rs1, d_rs2, d_rs1_val, d_rs2_val,
            d_pc, d_imm, d_reg_we, d_undef, alu_result, alu_div_zero,
            dmem_rdata, br_cond, is_load, is_store, is_amo, is_amo_load,
            is_amo_store, is_mem, op_rrr, op_br, op_ij, is_jmp_op, is_ret_d,
            pc_rel, jalr_tgt)
        variable v_result : std_logic_vector(31 downto 0);
        variable v_reg_we : std_logic;
        variable v_illegal : std_logic;
        variable v_mem_req, v_mem_we : std_logic;
        variable v_mem_be : std_logic_vector(3 downto 0);
        variable v_store_data : std_logic_vector(31 downto 0);
        variable v_branch_taken : std_logic := '0';
    begin
        -- Defaults: no write, no memory, no branch, no trap.
        v_result      := (others => '0');
        v_reg_we      := d_reg_we and d_valid and not d_undef;
        v_illegal     := d_undef;
        v_mem_req     := '0';
        v_mem_we      := '0';
        v_mem_be      := (others => '0');
        v_store_data  := d_rs2_val;
        v_branch_taken := '0';
        ex_addr       <= std_logic_vector(unsigned(d_rs1_val) + unsigned(d_imm));

        -- Result select.
        if (op_rrr = '1' and is_amo = '0') then
            v_result := alu_result;
            if alu_div_zero = '1' then
                v_illegal := '1';
            end if;
        elsif d_opcode = OP_ADDI then
            v_result := std_logic_vector(unsigned(d_rs1_val) + unsigned(d_imm));
        elsif d_opcode = OP_ANDI then
            v_result := d_rs1_val and (x"0000" & d_imm(15 downto 0));
        elsif d_opcode = OP_ORI then
            v_result := d_rs1_val or (x"0000" & d_imm(15 downto 0));
        elsif d_opcode = OP_XORI then
            v_result := d_rs1_val xor (x"0000" & d_imm(15 downto 0));
        elsif d_opcode = OP_SLLI then
            v_result := std_logic_vector(shift_left(unsigned(d_rs1_val), to_integer(unsigned(d_imm(4 downto 0)))));
        elsif d_opcode = OP_SRLI then
            v_result := std_logic_vector(shift_right(unsigned(d_rs1_val), to_integer(unsigned(d_imm(4 downto 0)))));
        elsif d_opcode = OP_SRAI then
            v_result := std_logic_vector(shift_right(signed(d_rs1_val), to_integer(unsigned(d_imm(4 downto 0)))));
        elsif d_opcode = OP_SLTI then
            v_result := x"00000001" when signed(d_rs1_val) < signed(d_imm) else x"00000000";
        elsif d_opcode = OP_SLTIU then
            v_result := x"00000001" when unsigned(d_rs1_val) < unsigned(x"0000" & d_imm(15 downto 0)) else x"00000000";
        elsif d_opcode = OP_LUI then
            v_result := std_logic_vector(shift_left(unsigned(d_imm), 11));
        elsif d_opcode = OP_AUIPC then
            v_result := std_logic_vector(unsigned(d_pc) + shift_left(unsigned(d_imm), 11));
        elsif d_opcode = OP_JAL or d_opcode = OP_CALL or d_opcode = OP_JALR then
            v_result := std_logic_vector(unsigned(d_pc) + 4);   -- link value
        elsif is_load = '1' then
            if d_opcode = OP_LDW then
                v_result := dmem_rdata;
            elsif d_opcode = OP_LHU then
                v_result := x"0000" & dmem_rdata(15 downto 0);
            else
                v_result := x"000000" & dmem_rdata(7 downto 0);
            end if;
        elsif is_amo_load = '1' or d_opcode = OP_AMOSWAP_W or d_opcode = OP_AMOADD_W then
            v_result := dmem_rdata;   -- old memory value
        elsif d_opcode = OP_SC_W then
            v_result := x"00000000";  -- 0 = success
        end if;

        -- Memory request.
        if is_mem = '1' then
            v_mem_req := '1';
            if is_store = '1' or is_amo_store = '1' then
                v_mem_we := '1';
            end if;
            if d_opcode = OP_SH then
                v_store_data := x"0000" & d_rs2_val(15 downto 0);
                v_mem_be     := "0011";
            elsif d_opcode = OP_SB then
                v_store_data := x"000000" & d_rs2_val(7 downto 0);
                v_mem_be     := "0001";
            elsif d_opcode = OP_AMOADD_W then
                v_store_data := std_logic_vector(unsigned(dmem_rdata) + unsigned(d_rs2_val));
                v_mem_be     := "1111";
            elsif v_mem_we = '1' then
                v_mem_be     := "1111";
            end if;
        end if;

        -- Branch / jump.
        if op_br = '1' then
            v_branch_taken := br_cond;
            branch_target  <= pc_rel;
        elsif is_jmp_op = '1' then
            v_branch_taken := '1';
            branch_target  <= pc_rel;
        elsif op_ij = '1' then
            v_branch_taken := '1';
            branch_target  <= jalr_tgt;
        elsif is_ret_d = '1' then
            v_branch_taken := '1';
            branch_target  <= d_rs1_val;   -- link register, read as rs1
        end if;

        -- A non-valid slot issues nothing.
        if d_valid = '0' then
            v_reg_we  := '0';
            v_mem_req := '0';
            v_mem_we  := '0';
            v_branch_taken := '0';
            v_illegal := '0';
        end if;

        ex_rd         <= d_rd;
        ex_result     <= v_result;
        ex_reg_we     <= v_reg_we;
        ex_illegal    <= v_illegal;
        ex_mem_req    <= v_mem_req;
        ex_mem_we     <= v_mem_we;
        ex_mem_be     <= v_mem_be;
        ex_store_data <= v_store_data;
        branch_taken  <= v_branch_taken;
    end process;

    -- ─── Fetch ───────────────────────────────────────────────────
    imem_addr <= pc;

    process(clk, rst_n) begin
        if rst_n = '0' then
            pc      <= (others => '0');
            f_valid <= '0';
            f_pc    <= (others => '0');
            f_insn  <= (others => '0');
        elsif rising_edge(clk) then
            if branch_taken = '1' then
                -- The instruction being fetched and the one in decode are
                -- both wrong-path.  Redirect, and spend one cycle refilling.
                pc      <= branch_target;
                f_valid <= '0';
            else
                f_valid <= '1';
                f_pc    <= pc;
                f_insn  <= imem_rdata;
                pc      <= std_logic_vector(unsigned(pc) + 4);
            end if;
        end if;
    end process;

    -- ─── Writeback ──────────────────────────────────────────────
    process(clk, rst_n) begin
        if rst_n = '0' then
            w_valid  <= '0';
            w_rd     <= (others => '0');
            w_result <= (others => '0');
            w_reg_we <= '0';
        elsif rising_edge(clk) then
            w_valid  <= d_valid;
            w_rd     <= ex_rd;
            w_result <= ex_result;
            w_reg_we <= ex_reg_we;
        end if;
    end process;

    -- ─── Memory port ─────────────────────────────────────────────
    dmem_addr  <= ex_addr;
    dmem_req   <= ex_mem_req;
    dmem_we    <= ex_mem_we;
    dmem_be    <= ex_mem_be;
    dmem_wdata <= ex_store_data;

    -- ─── Fault ───────────────────────────────────────────────────
    fault <= ex_illegal;

end architecture rtl;
