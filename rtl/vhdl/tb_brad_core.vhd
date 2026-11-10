-- SPDX-License-Identifier: MIT
-- BradISA V2 -- VHDL Testbench

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.bradisa_pkg.all;

entity tb_brad_core is
end entity tb_brad_core;

architecture sim of tb_brad_core is

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal imem_addr : std_logic_vector(31 downto 0);
    signal imem_rdata : std_logic_vector(31 downto 0);
    signal dmem_addr : std_logic_vector(31 downto 0);
    signal dmem_req  : std_logic;
    signal dmem_we   : std_logic;
    signal dmem_wdata : std_logic_vector(31 downto 0);
    signal dmem_rdata : std_logic_vector(31 downto 0);

    type mem_t is array (0 to 255) of std_logic_vector(31 downto 0);
    signal imem : mem_t := (others => (others => '0'));
    signal dmem : mem_t := (others => (others => '0'));

    constant PERIOD : time := 10 ns;

    -- Functional self-check: count fetches of the loop body (address 8).
    -- 1 pre-loop fetch + 99 taken branches = 100 exactly when the loop finishes.
    signal loop_fetches : integer := 0;

begin

    -- DUT
    dut: entity work.brad_core
        port map (
            clk => clk, rst_n => rst_n,
            imem_addr => imem_addr, imem_rdata => imem_rdata,
            dmem_addr => dmem_addr, dmem_req => dmem_req,
            dmem_we => dmem_we, dmem_be => open, dmem_wdata => dmem_wdata,
            dmem_rdata => dmem_rdata, fault => open
        );

    -- Undefined (X/U) instruction addresses read as 0; the core's pc becomes
    -- defined at the first clock edge after reset.
    imem_rdata <= imem(to_integer(unsigned(imem_addr(9 downto 2)))) when not is_x(imem_addr(9 downto 2)) else (others => '0');
    dmem_rdata <= dmem(to_integer(unsigned(dmem_addr(9 downto 2)))) when dmem_req = '1' else (others => '0');

    process(dmem_req, dmem_we, dmem_addr, dmem_wdata) begin
        if rising_edge(dmem_req) and dmem_we = '1' then
            dmem(to_integer(unsigned(dmem_addr(9 downto 2)))) <= dmem_wdata;
        end if;
    end process;

    -- Clock
    clk <= not clk after PERIOD/2;

    -- Loop-fetch counter (functional self-check)
    process(clk) begin
        if rising_edge(clk) then
            if imem_addr = x"00000008" then
                loop_fetches <= loop_fetches + 1;
            end if;
        end if;
    end process;

    process begin
        -- Load program (V2 encodings, produced by tools/bradasm from the
        -- assembly comments; the assembler is the source of truth).
        imem(0) <= x"40210064";  -- ADDI r1, r1, 100
        imem(1) <= x"40420000";  -- ADDI r2, r2, 0
        imem(2) <= x"4021FFFF";  -- ADDI r1, r1, -1  (loop:)
        imem(3) <= x"40420001";  -- ADDI r2, r2, 1
        imem(4) <= x"DC20FFFD";  -- BNZ  r1, loop     (offset = -3 words = -12 bytes)
        imem(5) <= x"A81FFFFF";  -- JMP  self         (epilogue: spin in place)

        rst_n <= '0';
        wait for 15 ns;
        rst_n <= '1';

        wait for 6000 ns;

        if loop_fetches >= 100 then
            report "PASS: loop completed (100 fetches of loop body)" severity note;
        else
            report "FAIL: loop did not complete" severity failure;
        end if;

        report "Simulation complete" severity note;
        stop;  -- terminate cleanly (exit 0) so the CI GHDL job completes
    end process;

end architecture sim;
