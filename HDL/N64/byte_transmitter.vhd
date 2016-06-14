library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

entity byte_transmitter is
    Port ( data_signal_out : out  STD_LOGIC;
           data_to_send : in STD_LOGIC_VECTOR(7 downto 0);
           need_stop_bit : in STD_LOGIC;
           stop_bit : in STD_LOGIC;
           tx_write : in  STD_LOGIC;
           tx_write_ack : out STD_LOGIC;
           tx_busy : out STD_LOGIC;
           CLK : in  STD_LOGIC);
end byte_transmitter;

architecture Behavioral of byte_transmitter is
  component bit_transmitter is
    Port ( bit_value : in  STD_LOGIC_VECTOR (1 downto 0);
           new_bit : in  STD_LOGIC;
           new_bit_ack : out  STD_LOGIC;
           transmitting : out  STD_LOGIC;
           data_out : out STD_LOGIC;
           CLK : in  STD_LOGIC);
  end component;

  signal latched_data : std_logic_vector(7 downto 0) := (others => '0');
  signal latched_need_stop_bit : std_logic := '0';
  signal latched_stop_bit : std_logic := '0';
  
  signal bit_id_in_progress : integer range 0 to 8 := 0;

  signal data_signal : std_logic := '1';

  signal tx_write_ack_signal : std_logic := '0';
  
  signal new_bit_value : std_logic_vector(1 downto 0) := "00";
  signal new_bit_signal : std_logic := '0';
  signal new_bit_ack_signal : std_logic;
  signal bit_transmitting_signal : std_logic;
  
  signal byte_transmitting_signal : std_logic;
begin
  bit_tx: bit_transmitter port map ( bit_value => new_bit_value,
                                     new_bit => new_bit_signal,
                                     new_bit_ack => new_bit_ack_signal,
                                     transmitting => bit_transmitting_signal,
                                     data_out => data_signal,
                                     CLK => CLK);

process (clk)
begin
  if (rising_edge(clk)) then
    if (byte_transmitting_signal = '1') then
      if (new_bit_ack_signal = '1' and new_bit_signal = '1') then
        new_bit_signal <= '0';
        
        -- If we're out of bits, go to idle
        if (bit_id_in_progress = 8 or (bit_id_in_progress = 7 and latched_need_stop_bit = '0')) then
          byte_transmitting_signal <= '0';
        end if;
      elsif (new_bit_ack_signal = '0' and new_bit_signal = '0') then
        -- Go to the next bit
        if (bit_id_in_progress = 7) then
          if (latched_need_stop_bit = '1') then
            new_bit_value <= "1" & latched_stop_bit;
            new_bit_signal <= '1';
            bit_id_in_progress <= bit_id_in_progress + 1;
          else
            -- We shouldn't end up here. This should have been dealt with earlier
            byte_transmitting_signal <= '0';
          end if;
        else
          new_bit_value <= "0" & latched_data(7 - (bit_id_in_progress + 1));
          new_bit_signal <= '1';
          bit_id_in_progress <= bit_id_in_progress + 1;
        end if;
      end if;
      
    else
      if (tx_write_ack_signal = '0' and tx_write = '1' and new_bit_ack_signal = '0') then
        byte_transmitting_signal <= '1';
        tx_write_ack_signal <= '1';
        
        -- Latch the data
        latched_data <= data_to_send;
        latched_need_stop_bit <= need_stop_bit;
        latched_stop_bit <= stop_bit;
        
        -- Write out the first bit
        new_bit_value <= "0" & data_to_send(7);
        new_bit_signal <= '1';
        bit_id_in_progress <= 0;
        
        
      end if;
    end if;
  
    -- Lower ack when new bit goes low
    if (tx_write_ack_signal = '1' and tx_write = '0') then
      tx_write_ack_signal <= '0';
    end if;

  end if;
end process;
  
data_signal_out <= data_signal;
tx_busy <= bit_transmitting_signal;
tx_write_ack <= tx_write_ack_signal;

end Behavioral;

