-- SPDX-License-Identifier: MIT
-- BradISA V2 -- full-ISA regression for brad_core (VHDL)
--
-- Mirrors rtl/verilog/tb_brad_isa.v: both load the words that bradasm
-- assembles from rtl/asm/tb_brad_isa.s and check what the core did with
-- them.  The program stores every observable result to its own data-memory
-- slot, so both simulators execute the same bytes and inspect the same
-- picture.  Until rtl/asm/tb_brad_isa.s existed, each tree hand-encoded its
-- own copy of every instruction and the trees could drift apart while both
-- stayed green.
--
-- GHDL offers no dut.regfile.regs[n] peek, so the checker inspects the
-- dmem slots only (the Verilog tree checks a few registers on top).  That is
-- a weaker observation -- it trusts the store path -- but it tests the same
-- instruction semantics and it keeps the two trees honest about each other.
--
-- The same bug is what made this file necessary: the rs2 read port was gated
-- to r0 for every opcode except STW, so all eight RRR ops computed
-- rd = rs1 op r0, and the original testbench -- ADDI, BNZ, JMP only -- stayed
-- green the whole time.
--
-- Encoding (authoritative: the RTL, not docs/04-base-isa.md):
--   word = (op << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (imm16)
--   branch/jump target = pc + 4 + sext(offset) * 4
-- None of the words below are written here; they come from the assembler.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.bradisa_pkg.all;

entity tb_brad_isa is
end entity tb_brad_isa;

architecture sim of tb_brad_isa is

    signal clk        : std_logic := '0';
    signal rst_n      : std_logic := '0';
    signal imem_addr  : std_logic_vector(31 downto 0);
    signal imem_rdata : std_logic_vector(31 downto 0);
    signal dmem_addr  : std_logic_vector(31 downto 0);
    signal dmem_req   : std_logic;
    signal dmem_we    : std_logic;
    signal dmem_wdata : std_logic_vector(31 downto 0);
    signal dmem_rdata : std_logic_vector(31 downto 0);

    type mem_t is array (0 to 255) of std_logic_vector(31 downto 0);
    signal imem : mem_t := (others => (others => '0'));
    signal dmem : mem_t := (others => (others => '0'));

    constant PERIOD : time := 10 ns;

    -- dmem word slots the program stores its results to (dmem[addr>>2]).
    -- Must stay in lockstep with the addresses in rtl/asm/tb_brad_isa.s.
    constant S_ADD  : integer := 0;
    constant S_SUB  : integer := 1;
    constant S_MUL  : integer := 2;
    constant S_AND  : integer := 3;
    constant S_OR   : integer := 4;
    constant S_XOR  : integer := 5;
    constant S_SHL  : integer := 6;
    constant S_SHR  : integer := 7;
    constant S_NEG  : integer := 8;
    constant S_RSUM : integer := 9;
    constant S_R0WR : integer := 10;
    constant S_42   : integer := 11;
    constant S_STWL : integer := 12;
    constant S_STWB : integer := 13;
    constant S_BZT  : integer := 14;
    constant S_BZNT : integer := 15;
    constant S_BNZT : integer := 16;
    constant S_JMP  : integer := 17;
    constant S_CAL1 : integer := 18;
    constant S_CAL2 : integer := 19;
    constant S_CALL : integer := 20;
    constant S_LSUM : integer := 21;
    constant S_LCNT : integer := 22;

    -- The CALL sits at 0x128 in tb_brad_isa.s; lr must hold pc+4 = 0x12C.
    constant CALL_PC : std_logic_vector(31 downto 0) := x"00000128";

begin

    dut: entity work.brad_core
        port map (
            clk => clk, rst_n => rst_n,
            imem_addr => imem_addr, imem_rdata => imem_rdata,
            dmem_addr => dmem_addr, dmem_req => dmem_req,
            dmem_we => dmem_we, dmem_be => open, dmem_wdata => dmem_wdata,
            dmem_rdata => dmem_rdata, fault => open
        );

    -- Index reads are guarded with is_x: the address buses are undefined
    -- until the first clock edge after reset, and indexing an array with a
    -- metavalue is a simulation-fatal range error.
    imem_rdata <= imem(to_integer(unsigned(imem_addr(9 downto 2))))
                  when not is_x(imem_addr(9 downto 2)) else (others => '0');
    dmem_rdata <= dmem(to_integer(unsigned(dmem_addr(9 downto 2))))
                  when dmem_req = '1' and not is_x(dmem_addr(9 downto 2))
                  else (others => '0');

    -- ONE driver for dmem, and it clears itself on reset.
    --
    -- mem_t is an array of std_logic_vector, which is a *resolved* type, so
    -- every process that writes dmem contributes a driver and the effective
    -- value is the per-bit resolution of all of them.  std_logic's resolution
    -- table has no entry for 'C' against '0', so a scenario reset holding '0'
    -- plus a store port holding 0x0000000C resolves to 0000000X -- and the
    -- checker then reports a bad load for a store that actually landed.  Not
    -- a core bug and not a memory bug: two drivers writing one resolved
    -- signal.  Clearing on rst_n keeps the reset-between-scenarios behaviour
    -- while leaving exactly one driver.
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            for i in dmem'range loop
                dmem(i) <= (others => '0');
            end loop;
        elsif rising_edge(clk) then
            if dmem_req = '1' and dmem_we = '1' and not is_x(dmem_addr(9 downto 2)) then
                dmem(to_integer(unsigned(dmem_addr(9 downto 2)))) <= dmem_wdata;
            end if;
        end if;
    end process;

    clk <= not clk after PERIOD/2;

    stim: process

        -- Variables, not signals: the procedures below increment them several
        -- times inside one delta cycle, where signal assignment would collapse
        -- the repeated increments into a single deferred update.
        variable checks : integer := 0;
        variable failed : integer := 0;

        -- The words bradasm produced.  A file object lives in the process
        -- declarative part and is opened here, so the testbench executes
        -- exactly the assembler's output -- no hand-written literals.
        file prog_file : text;
        variable l  : line;
        variable w  : std_logic_vector(31 downto 0);
        variable idx : integer := 0;

        procedure clear_mem is
        begin
            for i in 0 to 255 loop
                imem(i) <= x"00000000";   -- NOP (V2 opcode 0)
            end loop;
        end procedure;

        procedure load_prog is
        begin
            idx := 0;
            file_open(prog_file, "../asm/tb_brad_isa_prog.mem", read_mode);
            while not endfile(prog_file) loop
                readline(prog_file, l);
                hread(l, w);
                imem(idx) <= w;
                idx := idx + 1;
            end loop;
            file_close(prog_file);
        end procedure;

        -- Note: rst_n only.  clk already has a concurrent driver, and adding
        -- a second driver that resolves against it pins the clock at '0' --
        -- the core then never sees an edge and every check reads zero.
        procedure boot(constant dur : in time) is
        begin
            rst_n <= '0';
            wait for 15 ns;
            rst_n <= '1';
            wait for dur;
        end procedure;

        procedure chk(constant slot : in integer;
                      constant want : in std_logic_vector(31 downto 0);
                      constant name : in string) is
        begin
            checks := checks + 1;
            if dmem(slot) /= want then
                failed := failed + 1;
                report "FAIL " & name & ": dmem[" & integer'image(slot) &
                       "] = " & to_hstring(dmem(slot)) & " want " &
                       to_hstring(want)
                severity note;
            end if;
        end procedure;

    begin
        clear_mem;
        load_prog;

        -- Run the whole program: tb_brad_isa.s fills imem from 0, everything
        -- is sequential, and the last instruction parks at JMP self.  Give
        -- the pipe room rather than racing it.
        boot(6000 ns);

        -- ── The eight RRR ops (7 op 5, result in r1) ───────────────
        chk(S_ADD,  x"0000000C", "ADD");   -- 7 + 5
        chk(S_SUB,  x"00000002", "SUB");   -- 7 - 5
        chk(S_MUL,  x"00000023", "MUL");   -- 7 * 5
        chk(S_AND,  x"00000005", "AND");   -- 7 and 5
        chk(S_OR,   x"00000007", "OR");    -- 7 or 5
        chk(S_XOR,  x"00000002", "XOR");   -- 7 xor 5
        chk(S_SHL,  x"000000E0", "SHL");   -- 7 << (5 and 31)
        chk(S_SHR,  x"00000000", "SHR");   -- 7 >> (5 and 31)

        -- ── ADDI: negative immediate, same-register form, r0 ──────
        chk(S_NEG,  x"FFFFFFF9", "ADDI-neg");   -- r2 = -7
        chk(S_RSUM, x"00000000", "ADDI-rsum");  -- r1 = 7 + -7
        chk(S_R0WR, x"00000000", "r0-wrwb");    -- write to r0 discarded
        chk(S_42,   x"0000002A", "r0-const");   -- r2 = 42

        -- ── STW / LDW round trip ─────────────────────────────────
        chk(S_STWL, x"0000002A", "STW/LDW");
        chk(S_STWB, x"00000040", "STW-base");

        -- ── Branches ─────────────────────────────────────────────
        chk(S_BZT,  x"00000007", "BZ-taken");
        chk(S_BZNT, x"00000063", "BZ-notaken");
        chk(S_BNZT, x"00000007", "BNZ-taken");
        chk(S_JMP,  x"00000007", "JMP");

        -- ── CALL / RET ───────────────────────────────────────────
        chk(S_CAL1, x"00000001", "CALL/RET");      -- return point, r1
        chk(S_CAL2, x"00000007", "CALL/RET-sub");  -- subroutine wrote r2
        chk(S_CALL, std_logic_vector(unsigned(CALL_PC) + 4),
            "CALL/RET-lr");                        -- lr = CALL's pc + 4

        -- ── The loop: r2 = sum(10..1) = 55 ───────────────────────
        chk(S_LSUM, x"00000037", "loop-sum");
        chk(S_LCNT, x"00000000", "loop-cnt");

        -- ── Summary ──────────────────────────────────────────────
        report "ISA checks run   : " & integer'image(checks) severity note;
        if failed = 0 then
            report "PASS" severity note;
        else
            -- severity failure halts ghdl with a non-zero exit code, so a
            -- failing run cannot masquerade as a green one downstream.
            assert false
                report "FAIL: " & integer'image(failed) & " of " &
                       integer'image(checks) & " checks failed"
                severity failure;
        end if;
        stop;
        wait;
    end process;

end architecture sim;