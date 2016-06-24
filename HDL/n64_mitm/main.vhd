library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

entity main is
    Port ( console_signal_in : in  STD_LOGIC;
           console_signal_out : out STD_LOGIC;
           debug : out  STD_LOGIC_VECTOR(3 downto 0);
           console_signal_oe : out std_logic;
           controller_signal_in : in STD_LOGIC;
           controller_signal_out : out STD_LOGIC;
           controller_signal_oe : out STD_LOGIC;
           CLK : in  STD_LOGIC);
end main;

architecture Behavioral of main is
  component bit_detector is
    Port ( data_signal : in  STD_LOGIC;
           new_bit : out  STD_LOGIC;
           bit_val : out  STD_LOGIC_VECTOR (1 downto 0);
           CLK : in  STD_LOGIC);
  end component;
  
  component byte_receiver is
    Port ( new_bit : in  STD_LOGIC;
           bit_val : in  STD_LOGIC_VECTOR (1 downto 0);
           new_byte : out  STD_LOGIC;
           byte_val : out  STD_LOGIC_VECTOR (7 downto 0);
           CLK : in  STD_LOGIC);
  end component;
  
  component filter is
    Port ( signal_in : in  STD_LOGIC;
           clk : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
  end component;
  
  component n64_data_transmitter is
    Port ( data_to_send : in  STD_LOGIC_VECTOR (263 downto 0);
           data_length : in STD_LOGIC_VECTOR (5 downto 0);
           tx_write : in  STD_LOGIC;
           tx_write_ack : out  STD_LOGIC;
           need_crc : in  STD_LOGIC;
           need_stop_bit : in  STD_LOGIC;
           stop_bit : in  STD_LOGIC;
           data_out : out STD_LOGIC;
           tx_busy : out STD_LOGIC;
           CLK : in  STD_LOGIC);
  end component;

  
  signal console_new_bit : std_logic;
  signal console_new_bit_val : std_logic_vector(1 downto 0);
  
  signal console_signal_in_f : std_logic;
  signal controller_signal_in_f : std_logic;
    
    
  signal console_new_byte : std_logic := '0';
  signal console_rx_data : std_logic_vector (7 downto 0) := (others => '0');
--  
--  signal data_to_send : std_logic_vector(31 downto 0) := (others => '0');
--  signal latched_data_to_send : std_logic_vector(31 downto 0) := (others => '0');
--  signal tx_byte_id : integer range 0 to 3 := 0;
--  signal transmit_new_data : std_logic := '0';
--  signal transmitting : std_logic := '0';
  
  signal console_signal_from_tx : std_logic;
  signal console_data_to_tx : std_logic_vector(7 downto 0) := (others => '0');
  signal console_need_stop_bit : std_logic := '0';
  signal console_stop_bit : std_logic := '0';
  signal console_tx_busy : std_logic;
  signal console_tx_write : std_logic := '0';
  
  signal reply_delay_timer : integer range 0 to 37000 := 0;
  
  signal latched_rx_data : std_logic_vector(7 downto 0) := (others => '0');
  
  signal console_oe_signal : std_logic := '1';
  
  signal timer_max : integer range 0 to 50000 := 0;
  signal switch_timer_max : integer range 0 to 50000 := 0;
  
  signal tx : std_logic := '0';
  
  type broadcast_modes is (idle_mode, rx_cmd_bytes, broadcast_delay, broadcast_begin_wait, broadcast_override, preswitch, controller_to_console);
  signal broadcast_mode : broadcast_modes := idle_mode;

  type vector8 is array (natural range <>) of std_logic_vector(7 downto 0);
  signal cmd_data : vector8(1 to 5) := (others => (others => '0'));
  
  signal cmd_byte_id : integer range 0 to 5 := 1;
  
  signal data_to_tx : std_logic_vector(263 downto 0) := (others => '0');
  signal data_length : std_logic_vector(5 downto 0) := "000000";
  signal tx_busy : std_logic;
  signal tx_write : std_logic := '0';
  signal tx_write_ack : std_logic;
  signal need_crc : std_logic := '0';
  signal need_stop_bit : std_logic := '0';
  signal stop_bit : std_logic := '0';
  signal data_signal_from_tx : std_logic;

  signal override_count : integer range 0 to 5 := 0;
  signal override_count2 : integer range 0 to 10 := 0;
  signal override_count3 : integer range 0 to 10 := 0;
  signal override_count4 : integer range 0 to 10 := 0;


  
begin

  console_data_filter: filter port map (signal_in => console_signal_in,
                                        clk => CLK,
                                        signal_out => console_signal_in_f);
                                        
  controller_data_filter: filter port map (signal_in => controller_signal_in,
                                           clk => CLK,
                                           signal_out => controller_signal_in_f);

  console_bit_detector: bit_detector port map (data_signal => console_signal_in_f,
                                               bit_val => console_new_bit_val,
                                               new_bit => console_new_bit,
                                               clk => clk);
                                               
  console_byte_rx: byte_receiver port map ( new_bit => console_new_bit,
                                            bit_val => console_new_bit_val,
                                            new_byte => console_new_byte,
                                            byte_val => console_rx_data,
                                            CLK => CLK);
                                   
                               
  datatx: n64_data_transmitter port map ( data_to_send => data_to_tx,
                                          data_length => data_length,
                                          tx_write => tx_write,
                                          tx_write_ack => tx_write_ack,
                                          need_crc => need_crc,
                                          need_stop_bit => need_stop_bit,
                                          stop_bit => stop_bit,
                                          data_out => data_signal_from_tx,
                                          tx_busy => tx_busy,
                                          CLK => CLK);
                                 
    
  process (clk)
  begin
    if (rising_edge(clk)) then
      tx_write <= '0';
      if (broadcast_mode = preswitch) then
        if (reply_delay_timer = switch_timer_max) then
          reply_delay_timer <= 0;
          broadcast_mode <= controller_to_console;
        else
          reply_delay_timer <= reply_delay_timer + 1;
        end if;
        
      elsif (broadcast_mode = controller_to_console) then
        if (reply_delay_timer = timer_max) then
          broadcast_mode <= idle_mode;
        else
          reply_delay_timer <= reply_delay_timer + 1;
        end if;
      
      elsif (broadcast_mode = rx_cmd_bytes) then
        if (cmd_data(1) = "00000010") then
          if (console_new_byte = '1') then
            if (cmd_byte_id = 2) then
--              if (cmd_data(2) = "11100101" and console_rx_data = "10001100" and override_count < 2) then
--                reply_delay_timer <= 0;
--                broadcast_mode <= broadcast_delay;
--                override_count <= override_count + 1;
--                data_to_tx <= (others => '0');
--                data_to_tx(263 downto 0) <= "000001100000011000000110000001100000011000000110000001100000011000000110000001100000011000000110000001100000011000000110000001100000011000000110000001100000011000000110000001100000011000000110100000011000100010000100100001001001001010000100010100000000000000011111";
              --els
              if (cmd_data(2) = "11000001" and console_rx_data = "00111000" and override_count2 < 2) then
                reply_delay_timer <= 0;
                broadcast_mode <= broadcast_delay;
                data_to_tx <= (others => '0');
                data_to_tx(263 downto 0) <= "110111011101110111011001100110011011101110111011011001110110001101101110000011101110110011001100110111011101110010011001100111111011101110111001001100110011111001010000010011110100101101000101010011010100111101001110001000000101001001000101010001000000000000100001";
                override_count2 <= override_count2 + 1;
              elsif (cmd_data(2) = "11000001" and console_rx_data = "01010010" and override_count3 < 2) then
                reply_delay_timer <= 0;
                broadcast_mode <= broadcast_delay;
                data_to_tx <= (others => '0');
                data_to_tx(263 downto 0) <= "000000000000000000000000000000000011000000110001000000110001001100000101000000110000000100110011000000000010000000100100110001111111111000010001001000000001101011110000010011011110011010000000001000000000110100111110001100001110000000000000001111100000000101010011";
                override_count3 <= override_count3 + 1;
--              elsif (cmd_data(2) = "11011010" and console_rx_data = "01001111" and override_count4 < 1) then
--                reply_delay_timer <= 0;
--                broadcast_mode <= broadcast_delay;
--                data_to_tx <= (others => '0');
--                data_to_tx(263 downto 0) <= "000100010111001000011010110011010101010100011001011000000110100100010001110110101100111111001101010101010001100101100000011010011101000100010011110000110101011000011001100100111000110001010000100001011000001010000000100010001000110110000100100100010101000011111010";
--                override_count4 <= override_count4 + 1;
              else
                switch_timer_max <= 24;
                timer_max <= 33920;
                reply_delay_timer <= 0;
                broadcast_mode <= preswitch;
              end if;
            else
              cmd_data(cmd_byte_id+1) <= console_rx_data;
              cmd_byte_id <= cmd_byte_id + 1;
            end if;
          end if;
        else
          broadcast_mode <= idle_mode;
        end if;
      
      elsif (broadcast_mode = broadcast_delay) then
        if (reply_delay_timer = 96) then
          tx_write <= '1';
          data_length <= "100001";
          need_stop_bit <= '1';
          stop_bit <= '0';
          broadcast_mode <= broadcast_begin_wait;
        else
          reply_delay_timer <= reply_delay_timer + 1;
        end if;
        
      elsif (broadcast_mode = broadcast_begin_wait) then
        if (tx_busy = '1') then
          broadcast_mode <= broadcast_override;
        end if;
       
      elsif (broadcast_mode = broadcast_override) then
        if (tx_busy = '0') then
          broadcast_mode <= idle_mode;
        end if;
        
      elsif (broadcast_mode = idle_mode and console_new_byte = '1') then
        if (console_rx_data = "00000000") then
          switch_timer_max <= 16;
          timer_max <= 3200;
          reply_delay_timer <= 0;
          broadcast_mode <= preswitch;
          
        elsif (console_rx_data = "00000001") then
          switch_timer_max <= 16;
          timer_max <= 4224;
          reply_delay_timer <= 0;
          broadcast_mode <= preswitch;
          
        elsif (console_rx_data = "00000010") then
          cmd_data(1) <= console_rx_data;
          cmd_byte_id <= 1;
          broadcast_mode <= rx_cmd_bytes;
          
          
--          switch_timer_max <= 2224;
--          timer_max <= 33920;
--          reply_delay_timer <= 0;
--          broadcast_mode <= preswitch;

        elsif (console_rx_data = "00000011") then
          switch_timer_max <= 35764;
          timer_max <= 1152;
          reply_delay_timer <= 0;
          broadcast_mode <= preswitch;
          
        end if;
      end if;
    end if;
  end process;

  debug(0) <= '1';
  debug(1) <= '1';
  debug(2) <= console_new_bit_val(0);
  debug(3) <= data_signal_from_tx;
  
  console_signal_out <= controller_signal_in_f when (broadcast_mode = controller_to_console) else
                        data_signal_from_tx when (broadcast_mode = broadcast_begin_wait or broadcast_mode = broadcast_override) else
                        '1';
  console_signal_oe <= '0' when (broadcast_mode = controller_to_console or broadcast_mode = broadcast_begin_wait or broadcast_mode = broadcast_override) else
                       '1';

  
  controller_signal_out <= console_signal_in_f when (broadcast_mode = idle_mode or broadcast_mode = preswitch or broadcast_mode = rx_cmd_bytes) else
                        '1';
  controller_signal_oe <= '1' when (broadcast_mode = controller_to_console) else
                          '0';
                           

end Behavioral;

