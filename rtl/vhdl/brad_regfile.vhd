-- SPDX-License-Identifier: MIT
-- BradISA V2 -- Register File (VHDL)
-- 32 x 32-bit general-purpose registers.  r0 is hardwired to zero.
-- Synchronous write, asynchronous read.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.bradisa_pkg.all;

entity brad_regfile is
    port (
        clk     : in  std_logic;
        rst_n   : in  std_logic;
        raddr1  : in  std_logic_vector(4 downto 0);
        rdata1  : out std_logic_vector(31 downto 0);
        raddr2  : in  std_logic_vector(4 downto 0);
        rdata2  : out std_logic_vector(31 downto 0);
        we      : in  std_logic;
        waddr   : in  std_logic_vector(4 downto 0);
        wdata   : in  std_logic_vector(31 downto 0)
    );
end entity brad_regfile;

architecture rtl of brad_regfile is
    type reg_array is array (0 to NUM_REGS-1) of std_logic_vector(31 downto 0);
    signal regs : reg_array := (others => (others => '0'));
begin

    process(clk, rst_n) begin
        if rst_n = '0' then
            regs <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if (we = '1') and (not is_x(waddr)) and (waddr /= REG_R0) then
                regs(to_integer(unsigned(waddr))) <= wdata;
            end if;
        end if;
    end process;

    -- Reads with an undefined (X/U) address return 0, mirroring an R0 read.
    rdata1 <= (others => '0') when (raddr1 = REG_R0) or is_x(raddr1) else regs(to_integer(unsigned(raddr1)));
    rdata2 <= (others => '0') when (raddr2 = REG_R0) or is_x(raddr2) else regs(to_integer(unsigned(raddr2)));

end architecture rtl;
