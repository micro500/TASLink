-- Filters out any very short pulses on the signal in
-- Pulses must be at least 6/32,000,000 s ~= 187ns

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity filter is
    Port ( signal_in : in  STD_LOGIC;
           clk : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
end filter;

architecture Behavioral of filter is
  signal counter : integer range 0 to 6 := 0;
  signal current_output : std_logic := '0';
begin

  process(clk)
    
  begin
    if (rising_edge(clk)) then
      if (signal_in = current_output) then
        counter <= 0;
      else
        counter <= counter + 1;
        if (counter = 6) then
          current_output <= not(current_output);
          counter <= 0;
        end if;
      end if;
    end if;
  end process;

signal_out <= current_output;

end Behavioral;

