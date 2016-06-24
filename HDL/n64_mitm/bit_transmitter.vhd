library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

entity bit_transmitter is
    Port ( bit_value : in  STD_LOGIC_VECTOR (1 downto 0);
           new_bit : in  STD_LOGIC;
           new_bit_ack : out  STD_LOGIC;
           transmitting : out  STD_LOGIC;
           data_out : out STD_LOGIC;
           CLK : in  STD_LOGIC);
end bit_transmitter;

architecture Behavioral of bit_transmitter is
  constant one_us_exact : integer := 32;
  constant two_us_exact : integer := 64;
  constant three_us_exact : integer := 96;

  signal data_signal : std_logic := '1';

  signal transmitting_signal : std_logic := '0';
  signal new_bit_ack_signal : std_logic := '0';
  
  signal bit_in_progress : std_logic_vector(1 downto 0) := "00";
  
  signal bit_timer : integer range 0 to 104 := 0;
  
  type modes is (idle_mode, high_mode, low_mode);
  signal tx_mode : modes := idle_mode;
begin

process (clk)
begin
  if (rising_edge(clk)) then
    if (transmitting_signal = '1') then
      if (tx_mode = low_mode) then
        if ((bit_in_progress = "01" and bit_timer = one_us_exact) or (bit_in_progress = "00" and bit_timer = three_us_exact)) then
          -- Switch to high mode 
          data_signal <= '1';
          bit_timer <= 0;
          tx_mode <= high_mode;
        elsif ((bit_in_progress = "11" and bit_timer = one_us_exact) or (bit_in_progress = "10" and bit_timer = two_us_exact)) then
          -- We're done transmitting this bit
          -- Check if there is a new bit waiting
          if (new_bit_ack_signal = '0' and new_bit = '1') then
            transmitting_signal <= '1';
            new_bit_ack_signal <= '1';
            
            bit_in_progress <= bit_value;
            data_signal <= '0';
            bit_timer <= 0;
            
            tx_mode <= low_mode;
          else
            data_signal <= '1';
            tx_mode <= idle_mode;
            transmitting_signal <= '0';
          end if;
        else
          bit_timer <= bit_timer + 1;
        end if;
      elsif (tx_mode = high_mode) then
        if ((bit_in_progress = "01" and bit_timer = three_us_exact) or (bit_in_progress = "00" and bit_timer = one_us_exact)) then  
          -- We're done transmitting this bit
          -- Check if there is a new bit waiting
          if (new_bit_ack_signal = '0' and new_bit = '1') then
            transmitting_signal <= '1';
            new_bit_ack_signal <= '1';
            
            bit_in_progress <= bit_value;
            data_signal <= '0';
            bit_timer <= 0;
            
            tx_mode <= low_mode;
          else
            data_signal <= '1';
            tx_mode <= idle_mode;
            transmitting_signal <= '0';
          end if;
        else
          bit_timer <= bit_timer + 1;
        end if;
      else
        -- We should never end up here
        transmitting_signal <= '0';
      end if;
    else
      if (new_bit_ack_signal = '0' and new_bit = '1') then
        transmitting_signal <= '1';
        new_bit_ack_signal <= '1';
        
        bit_in_progress <= bit_value;
        data_signal <= '0';
        bit_timer <= 0;
        
        tx_mode <= low_mode;
      end if;
    end if;
    
    -- Lower ack when new bit goes low
    if (new_bit_ack_signal = '1' and new_bit = '0') then
      new_bit_ack_signal <= '0';
    end if;
  end if;
end process;

transmitting <= transmitting_signal;
data_out <= data_signal;
new_bit_ack <= new_bit_ack_signal;

end Behavioral;

