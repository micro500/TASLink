library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

entity bit_detector is
    Port ( data_signal : in  STD_LOGIC;
           new_bit : out  STD_LOGIC;
           bit_val : out  STD_LOGIC_VECTOR (1 downto 0);
           CLK : in  STD_LOGIC);
end bit_detector;

architecture Behavioral of bit_detector is
  constant one_us_min : integer := 24;
  constant two_us_min : integer := 56;
  constant three_us_min : integer := 88;

  constant one_us_exact : integer := 32;
  constant two_us_exact : integer := 64;
  constant three_us_exact : integer := 96;
  
  constant one_us_max : integer := 40;
  constant two_us_max : integer := 72;
  constant three_us_max : integer := 104;

  type modes is (idle_mode, wait1_mode, wait0_mode);
  signal detection_mode : modes := idle_mode;

  signal prev_data : std_logic := '1';

  signal bit_timer : integer range 0 to 105 := 0;
  
  signal new_bit_temp : std_logic := '0';
  signal bit_val_temp : std_logic_vector(1 downto 0) := "00";
begin
  
process (clk)
begin
  if (rising_edge(clk)) then
    new_bit_temp <= '0';
  
    if (data_signal = prev_data) then
      if (data_signal = '1') then
        if (detection_mode = wait1_mode) then
          if (bit_timer = three_us_exact) then
            -- output 1 
            bit_val_temp <= "01";
            new_bit_temp <= '1';
            
            -- go to idle
            detection_mode <= idle_mode;
          else
            bit_timer <= bit_timer + 1;
          end if;
        elsif (detection_mode = wait0_mode) then
          if (bit_timer = one_us_exact) then
            -- output 0 
            bit_val_temp <= "00";
            new_bit_temp <= '1';
            
            -- go to idle
            detection_mode <= idle_mode;
          else
            bit_timer <= bit_timer + 1;
          end if;
        end if;
      else -- data = '0'
        -- Increment the timer, maxing out at 105
        if (bit_timer /= 105) then
          bit_timer <= bit_timer + 1;
        end if;
      end if;
    else -- data /= prev_data
      -- Falling edge of data
      if (prev_data = '1' and data_signal = '0') then
        if (detection_mode = wait1_mode) then
          -- Did we get something close enough?
          if (bit_timer >= three_us_min) then
            -- output 1 
            bit_val_temp <= "01";
            new_bit_temp <= '1';
          else
            -- output 3 (console stop bit)
            bit_val_temp <= "11";
            new_bit_temp <= '1';
          end if;
        elsif (detection_mode = wait0_mode) then
          -- Did we get something close enough?
          if (bit_timer >= one_us_min) then
            -- output 0
            bit_val_temp <= "00";
            new_bit_temp <= '1';
          end if;
        end if;
        
        detection_mode <= idle_mode;
        bit_timer <= 0;
        
      -- Rising edge
      elsif (prev_data = '0' and data_signal = '1') then
        if (bit_timer >= one_us_min and bit_timer <= one_us_max) then
          detection_mode <= wait1_mode;
        elsif (bit_timer >= two_us_min and bit_timer <= two_us_max) then
          -- output 2 (controller stop bit)
            bit_val_temp <= "10";
            new_bit_temp <= '1';
          detection_mode <= idle_mode;
        elsif (bit_timer >= three_us_min and bit_timer <= three_us_max) then
          detection_mode <= wait0_mode;
        else
          -- Low pulse was outside acceptable ranges, ignore it
          detection_mode <= idle_mode;
        end if;
        
        bit_timer <= 0;
      end if;
      
      -- Remember this new data value
      prev_data <= data_signal;
    end if;
  end if;
end process;

new_bit <= new_bit_temp;
bit_val <= bit_val_temp;

end Behavioral;

