library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

entity bit_transmitter is
    Port ( data_out : out  STD_LOGIC;
           data_to_send : in STD_LOGIC_VECTOR(7 downto 0);
           need_stop_bit : in STD_LOGIC;
           stop_bit : in STD_LOGIC;
           tx_busy : out STD_LOGIC;
           tx_write : in  STD_LOGIC;
           CLK : in  STD_LOGIC);
end bit_transmitter;

architecture Behavioral of bit_transmitter is
  constant one_us_exact : integer := 32;
  constant two_us_exact : integer := 64;
  constant three_us_exact : integer := 96;

  signal latched_data : std_logic_vector(7 downto 0) := (others => '0');
  signal latched_need_stop_bit : std_logic := '0';
  signal latched_stop_bit : std_logic := '0';
  
  signal transmitting : std_logic := '0';
  
  signal bit_timer : integer range 0 to 104 := 0;
  
  signal bit_id_in_progress : integer range 0 to 8 := 0;
  signal bit_in_progress : std_logic_vector(1 downto 0) := "00";
  
  signal data_signal : std_logic := '1';
  
  type modes is (idle_mode, high_mode, low_mode);
  signal tx_mode : modes := idle_mode;
  
  signal prev_tx_write : std_logic := '0';
begin
  
process (clk)
begin
  if (rising_edge(clk)) then
    if (transmitting = '1') then
      if (tx_mode = low_mode) then
        if ((bit_in_progress = "01" and bit_timer = one_us_exact) or (bit_in_progress = "00" and bit_timer = three_us_exact)) then
          -- Switch to high mode 
          data_signal <= '1';
          bit_timer <= 0;
          tx_mode <= high_mode;
        elsif ((bit_in_progress = "11" and bit_timer = one_us_exact) or (bit_in_progress = "10" and bit_timer = two_us_exact)) then
          -- We're done transmitting
          data_signal <= '1';
          tx_mode <= idle_mode;
          transmitting <= '0';
        else
          bit_timer <= bit_timer + 1;
        end if;
      elsif (tx_mode = high_mode) then
        if ((bit_in_progress = "01" and bit_timer = three_us_exact) or (bit_in_progress = "00" and bit_timer = one_us_exact)) then  
          -- Go to the next bit
          if (bit_id_in_progress = 7) then
            if (latched_need_stop_bit = '1') then
              data_signal <= '0';
              bit_timer <= 0;
              
              bit_in_progress <= "1" & latched_stop_bit;
              bit_id_in_progress <= 8;
              tx_mode <= low_mode;
            else
              -- We're done transmitting
              data_signal <= '1';
              tx_mode <= idle_mode;
              transmitting <= '0';
            end if;
          else
            data_signal <= '0';
            bit_timer <= 0;

            bit_in_progress <= "0" & latched_data(7 - (bit_id_in_progress + 1));
            bit_id_in_progress <= bit_id_in_progress + 1;
            tx_mode <= low_mode;
          end if;
        else
           bit_timer <= bit_timer + 1;
        end if;
      end if;
    else
      if (prev_tx_write = '0' and tx_write = '1') then
        latched_data <= data_to_send;
        latched_need_stop_bit <= need_stop_bit;
        latched_stop_bit <= stop_bit;
        
        transmitting <= '1';
        
        -- Start sending first bit
        data_signal <= '0';
        bit_timer <= 0;
        
        bit_in_progress <= "0" & data_to_send(7);
        bit_id_in_progress <= 0;
        tx_mode <= low_mode;
        
        prev_tx_write <= tx_write;
      end if;
    end if;
    
    if (tx_write = '0') then
      prev_tx_write <= tx_write;
    end if;
  end if;
end process;

data_out <= data_signal;
tx_busy <= transmitting;

end Behavioral;

