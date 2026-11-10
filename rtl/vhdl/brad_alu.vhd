-- SPDX-License-Identifier: MIT
-- BradISA V2 -- ALU (VHDL)
-- Combinational, 6-bit opcode.  Covers the fifteen register-register
-- operations in the 0x00-0x0E group.  Loads, immediates and branches are
-- handled by the execute stage, which owns the memory and control paths.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.bradisa_pkg.all;

entity brad_alu is
    port (
        a        : in  std_logic_vector(31 downto 0);
        b        : in  std_logic_vector(31 downto 0);
        op       : in  std_logic_vector(5 downto 0);
        result   : out std_logic_vector(31 downto 0);
        div_zero : out std_logic
    );
end entity brad_alu;

architecture rtl of brad_alu is
    signal a_s, b_s : signed(31 downto 0);
    signal a_u, b_u : unsigned(31 downto 0);

    -- GHDL's numeric_std "*" range-checks and aborts the simulation when the
    -- product does not fit the operand width, so it cannot express "the low
    -- 32 bits of a 32x32 product" -- which is what the ISA specifies and what
    -- the Verilog tree's 32-bit `*` computes.  (This only surfaced because
    -- MUL had never been executed by any testbench; the ALU reported a bound
    -- check failure the first time the regression reached it.)
    -- Shift-and-add reproduces the truncation explicitly: unsigned "+" wraps
    -- rather than asserting, so each partial product folds into the low word.
    function mul_low32(x, y : unsigned(31 downto 0)) return unsigned is
        variable acc : unsigned(31 downto 0);
        variable msk : unsigned(31 downto 0);
    begin
        acc := (others => '0');
        msk := y;
        for i in 0 to 31 loop
            if x(i) = '1' then
                acc := acc + msk;
            end if;
            msk := shift_left(msk, 1);
        end loop;
        return acc;
    end function;

    -- The high half needs the carries the low half discards, so it accumulates
    -- into a 64-bit word and returns bits [63:32].  Same shift-and-add shape.
    function mul_high32(x, y : unsigned(31 downto 0)) return unsigned is
        variable acc : unsigned(63 downto 0);
        variable msk : unsigned(63 downto 0);
    begin
        acc := (others => '0');
        msk := resize(y, 64);
        for i in 0 to 31 loop
            if x(i) = '1' then
                acc := acc + msk;
            end if;
            msk := shift_left(msk, 1);
        end loop;
        return acc(63 downto 32);
    end function;

    signal b_nz : std_logic;
begin
    a_s <= signed(a); b_s <= signed(b);
    a_u <= unsigned(a); b_u <= unsigned(b);

    -- Divide-by-zero is a chip, not an inline conditional: GHDL refuses
    -- inline conditional-expression chains mixed with and/or, and the ALU
    -- needs the zero flag in four places.  The comparison runs on the port
    -- `b` itself, not on the converted signal b_u: at time zero b_u is still
    -- unpropagated and a numeric_std comparison against it would trap on a
    -- metavalue.  (std_logic_vector "=" has no such assertion.)
    b_nz <= '0' when b = x"00000000" else '1';

    process(a, b, op, a_s, b_s, a_u, b_u, b_nz) begin
        result   <= (others => '0');
        div_zero <= '0';
        case op is
            when OP_NOP   => result <= (others => '0');
            when OP_ADD   => result <= std_logic_vector(a_u + b_u);
            when OP_SUB   => result <= std_logic_vector(a_u - b_u);
            when OP_MUL   => result <= std_logic_vector(mul_low32(a_u, b_u));
            when OP_MULHU => result <= std_logic_vector(mul_high32(a_u, b_u));
            when OP_DIV   =>
                if b_nz = '0' then
                    div_zero <= '1';
                    result   <= (others => '0');
                else
                    result <= std_logic_vector(a_s / b_s);
                end if;
            when OP_DIVU  =>
                if b_nz = '0' then
                    div_zero <= '1';
                    result   <= (others => '0');
                else
                    result <= std_logic_vector(a_u / b_u);
                end if;
            when OP_REM   =>
                if b_nz = '0' then
                    div_zero <= '1';
                    result   <= (others => '0');
                else
                    -- "rem" keeps the dividend's sign, matching Verilog's "%".
                    result <= std_logic_vector(a_s rem b_s);
                end if;
            when OP_REMU  =>
                if b_nz = '0' then
                    div_zero <= '1';
                    result   <= (others => '0');
                else
                    result <= std_logic_vector(a_u rem b_u);
                end if;
            when OP_AND   => result <= a and b;
            when OP_OR    => result <= a or b;
            when OP_XOR   => result <= a xor b;
            when OP_SHL   => result <= std_logic_vector(shift_left(a_u, to_integer(b_u(4 downto 0))));
            when OP_SHR   => result <= std_logic_vector(shift_right(a_u, to_integer(b_u(4 downto 0))));
            when OP_SAR   => result <= std_logic_vector(shift_right(a_s, to_integer(b_u(4 downto 0))));
            when others   => result <= (others => '0');
        end case;
    end process;

end architecture rtl;
