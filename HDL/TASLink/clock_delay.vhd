library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity clock_delay is
    Port ( signal_in : in  STD_LOGIC;
           signal_delayed : out  STD_LOGIC;
           CLK : in  STD_LOGIC);
end clock_delay;

architecture Behavioral of clock_delay is
  signal prev_signal_in : std_logic := '0';
  
  signal timer_active : std_logic := '0';
  signal timer : integer range 0 to 192 := 0;
  
  signal data : std_logic := '0';
begin
delay: process(clk)
  begin
    if (rising_edge(clk)) then
      if (signal_in = '1') then
        -- On rising edge
        if (prev_signal_in = '0') then
          -- Start the timer
          timer <= 0;
          timer_active <= '1';
        -- Timer is finished. Write out a 1
        elsif (timer_active = '1') then
          if (timer = 192) then
            data <= '1';
            timer_active <= '0';
          
          -- Otherwise increment the timer
          else
            timer <= timer + 1;
          end if;
        end if;
      
      -- Immediately pass a 0 through and reset the timer
      elsif (signal_in = '0') then
        data <= '0';
        timer_active <= '0';
      end if;
      
      prev_signal_in <= signal_in;
    end if;
  end process;

signal_delayed <= data;


end Behavioral;

