library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

entity n64_data_transmitter is
    Port ( data_to_send : in  STD_LOGIC_VECTOR (255 downto 0);
           data_length : in STD_LOGIC_VECTOR (5 downto 0);
           tx_write : in  STD_LOGIC;
           tx_write_ack : out  STD_LOGIC;
           need_crc : in  STD_LOGIC;
           need_stop_bit : in  STD_LOGIC;
           stop_bit : in  STD_LOGIC;
           data_out : out STD_LOGIC;
           tx_busy : out STD_LOGIC;
           CLK : in  STD_LOGIC);
end n64_data_transmitter;

architecture Behavioral of n64_data_transmitter is
  component byte_transmitter is
    Port ( data_signal_out : out  STD_LOGIC;
           data_to_send : in STD_LOGIC_VECTOR(7 downto 0);
           need_stop_bit : in STD_LOGIC;
           stop_bit : in STD_LOGIC;
           tx_write : in  STD_LOGIC;
           tx_write_ack : out STD_LOGIC;
           tx_busy : out STD_LOGIC;
           CLK : in  STD_LOGIC);
  end component;


  signal byte_id_in_progress : integer range 1 to 33 := 1;
  
  signal transmitting_signal : std_logic := '0';
  signal tx_write_ack_signal : std_logic := '0';
  
  signal latched_data : std_logic_vector (255 downto 0) := (others => '0');
  signal latched_data_length : integer range 1 to 32 := 1;
  signal latched_need_crc : std_logic := '0';
  signal latched_need_stop_bit : std_logic := '0';
  signal latched_stop_bit : std_logic := '0';
  
  signal data_signal : std_logic;
  signal byte_to_send : std_logic_vector(7 downto 0) := "00000000";
  signal need_stop_bit_signal : std_logic := '0';
  signal stop_bit_signal : std_logic := '0';
  signal byte_tx_write_signal : std_logic := '0';
  signal byte_tx_write_ack_signal : std_logic;
  signal byte_tx_busy : std_logic;
  
begin
  
  byte_tx : byte_transmitter port map ( data_signal_out => data_signal,
                                        data_to_send => byte_to_send,
                                        need_stop_bit => need_stop_bit_signal,
                                        stop_bit => stop_bit_signal,
                                        tx_write => byte_tx_write_signal,
                                        tx_write_ack => byte_tx_write_ack_signal,
                                        tx_busy => byte_tx_busy,
                                        CLK => CLK);


process(clk)
  variable new_data_length : integer range 0 to 63 := 0;
begin
  if (rising_edge(clk)) then
    if (transmitting_signal = '1') then
      if (byte_tx_write_ack_signal = '1' and byte_tx_write_signal = '1') then
        byte_tx_write_signal <= '0';
        
        -- If we're out of bytes, go to idle
        if (byte_id_in_progress = latched_data_length) then
          transmitting_signal <= '0';
        end if;
      elsif (byte_tx_write_ack_signal = '0' and byte_tx_write_signal = '0') then
        -- Go to the next byte
        if (byte_id_in_progress < latched_data_length and byte_id_in_progress < 32) then
          -- Set up the next byte of data
          case byte_id_in_progress is
            when 1 =>
              byte_to_send <= latched_data(247 downto 240);
            when 2 =>
              byte_to_send <= latched_data(239 downto 232);
            when 3 =>
              byte_to_send <= latched_data(231 downto 224);
            when 4 =>
              byte_to_send <= latched_data(223 downto 216);
            when 5 =>
              byte_to_send <= latched_data(215 downto 208);
            when 6 =>
              byte_to_send <= latched_data(207 downto 200);
            when 7 =>
              byte_to_send <= latched_data(199 downto 192);
            when 8 =>
              byte_to_send <= latched_data(191 downto 184);
            when 9 =>
              byte_to_send <= latched_data(183 downto 176);
            when 10 =>
              byte_to_send <= latched_data(175 downto 168);
            when 11 =>
              byte_to_send <= latched_data(167 downto 160);
            when 12 =>
              byte_to_send <= latched_data(159 downto 152);
            when 13 =>
              byte_to_send <= latched_data(151 downto 144);
            when 14 =>
              byte_to_send <= latched_data(143 downto 136);
            when 15 =>
              byte_to_send <= latched_data(135 downto 128);
            when 16 =>
              byte_to_send <= latched_data(127 downto 120);
            when 17 =>
              byte_to_send <= latched_data(119 downto 112);
            when 18 =>
              byte_to_send <= latched_data(111 downto 104);
            when 19 =>
              byte_to_send <= latched_data(103 downto 96);
            when 20 =>
              byte_to_send <= latched_data(95 downto 88);
            when 21 =>
              byte_to_send <= latched_data(87 downto 80);
            when 22 =>
              byte_to_send <= latched_data(79 downto 72);
            when 23 =>
              byte_to_send <= latched_data(71 downto 64);
            when 24 =>
              byte_to_send <= latched_data(63 downto 56);
            when 25 =>
              byte_to_send <= latched_data(55 downto 48);
            when 26 =>
              byte_to_send <= latched_data(47 downto 40);
            when 27 =>
              byte_to_send <= latched_data(39 downto 32);
            when 28 =>
              byte_to_send <= latched_data(31 downto 24);
            when 29 =>
              byte_to_send <= latched_data(23 downto 16);
            when 30 =>
              byte_to_send <= latched_data(15 downto 8);
            when 31 =>
              byte_to_send <= latched_data(7 downto 0);
            when others =>
              byte_to_send <= latched_data(7 downto 0);
          end case;
          
          byte_id_in_progress <= byte_id_in_progress + 1;

          -- Check if we need to send a stop bit after this byte
          if ((byte_id_in_progress + 1) = latched_data_length) then
            need_stop_bit_signal <= latched_need_stop_bit;
            stop_bit_signal <= latched_stop_bit;
          else
            need_stop_bit_signal <= '0';
            stop_bit_signal <= '0';
          end if;
          
          byte_tx_write_signal <= '1';
        else
          transmitting_signal <= '0';
        end if;
      end if;

    else
      if (tx_write = '1' and tx_write_ack_signal = '0') then
        -- Get and check the new data length
        new_data_length := to_integer(unsigned(data_length));
        
        if (new_data_length > 0) then
          -- Limit the data length
          if (new_data_length > 32) then
            new_data_length := 32;
          end if;
          
          latched_data_length <= new_data_length;
          latched_data <= data_to_send;
          latched_need_stop_bit <= need_stop_bit;
          latched_stop_bit <= stop_bit;
          byte_id_in_progress <= 1;
          
          -- Send the first byte of this data
          byte_to_send <= data_to_send(255 downto 248);
          -- Check if we need to send a stop bit after this byte
          if (new_data_length = 1) then
            need_stop_bit_signal <= need_stop_bit;
            stop_bit_signal <= stop_bit;
          else
            need_stop_bit_signal <= '0';
            stop_bit_signal <= '0';
          end if;
          byte_tx_write_signal <= '1';
          
          transmitting_signal <= '1';
        end if;
        
        -- Even if 0 bytes were requested, ack this request
        tx_write_ack_signal <= '1';
      end if;
    end if;
    
    -- Lower ack when new bit goes low
    if (tx_write_ack_signal = '1' and tx_write = '0') then
      tx_write_ack_signal <= '0';
    end if;
  end if;
end process;

tx_busy <= byte_tx_busy;
tx_write_ack <= tx_write_ack_signal;
data_out <= data_signal;

end Behavioral;

