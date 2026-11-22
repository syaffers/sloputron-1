-- Leros (original 16-bit VHDL) baseline harness: core (unmodified except IM_BITS=11)
-- + 4 KB instruction ROM + 512 B data memory (in core) + 5-bit LED port on io write.
library ieee;
use ieee.std_logic_1164.all;
use work.leros_types.all;
entity top is
  port (clk : in std_logic; rst : in std_logic; led : out std_logic_vector(4 downto 0));
end top;
architecture rtl of top is
  signal ioout : io_out_type;
  signal ioin  : io_in_type;
  signal led_r : std_logic_vector(4 downto 0) := (others => '0');
begin
  cpu: entity work.leros port map (clk, rst, ioout, ioin);
  ioin.rddata <= "00000000000" & led_r;
  process(clk) begin
    if rising_edge(clk) then
      if ioout.wr = '1' then led_r <= ioout.wrdata(4 downto 0); end if;
    end if;
  end process;
  led <= led_r;
end rtl;
