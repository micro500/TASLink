-- Toggles signal_out on every rising edge of signal_in

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity toggle is
    Port ( signal_in : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
end toggle;

architecture Behavioral of toggle is
signal toggle : std_logic := '0';
begin

  process(signal_in)
  begin
    if (rising_edge(signal_in)) then
      toggle <= not(toggle);
    end if;
  end process;

signal_out <= toggle;
end Behavioral;

