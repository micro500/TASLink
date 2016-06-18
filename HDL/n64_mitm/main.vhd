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
  
  component bit_transmitter is
    Port ( data_signal_out : out  STD_LOGIC;
           data_to_send : in STD_LOGIC_VECTOR(7 downto 0);
           need_stop_bit : in STD_LOGIC;
           stop_bit : in STD_LOGIC;
           tx_busy : out STD_LOGIC;
           tx_write : in  STD_LOGIC;
           CLK : in  STD_LOGIC);
  end component;
  
  signal console_new_bit : std_logic;
  signal console_new_bit_val : std_logic_vector(1 downto 0);
  
  signal console_signal_in_f : std_logic;
  signal controller_signal_in_f : std_logic;
    
    
  signal console_new_byte : std_logic := '0';
  signal console_rx_data : std_logic_vector (7 downto 0) := (others => '0');
  
  signal data_to_send : std_logic_vector(31 downto 0) := (others => '0');
  signal latched_data_to_send : std_logic_vector(31 downto 0) := (others => '0');
  signal tx_byte_id : integer range 0 to 3 := 0;
  signal transmit_new_data : std_logic := '0';
  signal transmitting : std_logic := '0';
  signal data_length : integer range 0 to 3 := 0;
  
  signal console_signal_from_tx : std_logic;
  signal console_data_to_tx : std_logic_vector(7 downto 0) := (others => '0');
  signal console_need_stop_bit : std_logic := '0';
  signal console_stop_bit : std_logic := '0';
  signal console_tx_busy : std_logic;
  signal console_tx_write : std_logic := '0';
  
  signal reply_delay_active : std_logic := '0';
  signal reply_delay_timer : integer range 0 to 37000 := 0;
  
  signal latched_rx_data : std_logic_vector(7 downto 0) := (others => '0');
  
  signal console_oe_signal : std_logic := '1';
  
  signal timer_max : integer range 0 to 50000 := 0;
  signal switch_timer_max : integer range 0 to 50000 := 0;
  
  signal tx : std_logic := '0';
  
  type broadcast_modes is (idle_mode, preswitch, controller_to_console);
  signal broadcast_mode : broadcast_modes := idle_mode;

  
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
                                   
                               
  console_tx1: bit_transmitter port map ( data_signal_out => console_signal_from_tx,
                                          data_to_send => console_data_to_tx,
                                          need_stop_bit => console_need_stop_bit,
                                          stop_bit => console_stop_bit,
                                          tx_busy => console_tx_busy,
                                          tx_write => console_tx_write,
                                          CLK => clk);
                                 
    
--  process (clk)
--  begin
--    if (rising_edge(clk)) then
--      transmit_new_data <= '0';
--      if (reply_delay_active = '1') then
--        if (reply_delay_timer = 96) then
--          if (console_rx_data = "00000000") then
--            transmit_new_data <= '1';
--            data_to_send <= "00000101000000000000001000000000";
--            data_length <= 2;
--            reply_delay_active <= '0';
--          elsif (console_rx_data = "11111111") then
--            transmit_new_data <= '1';
--            data_to_send <= "10000010100000000000000100000000";
--            data_length <= 2;
--            reply_delay_active <= '0';
--          elsif (console_rx_data = "00000001") then
--            transmit_new_data <= '1';
--            data_to_send <= "10101010101010101010101010101010";
--            data_length <= 3;
--            reply_delay_active <= '0';
--          end if;
--        else
--          reply_delay_timer <= reply_delay_timer + 1;
--        end if;
--      elsif (transmitting = '0' and console_new_byte = '1') then
--        reply_delay_timer <= 0;
--        reply_delay_active <= '1';
--      end if;
--    end if;
--  end process;
--  
--  process (clk)
--  begin
--    if (rising_edge(clk)) then
--      --tx_write <= '0';
--      
--      if (transmitting = '1') then
--        if (console_tx_write = '0' and console_tx_busy = '0') then
--          if (tx_byte_id = 0) then
--            console_data_to_tx <= latched_data_to_send(23 downto 16);
--            console_need_stop_bit <= '0';
--            console_tx_write <= '1';
--            
--            tx_byte_id <= 1;
--          elsif (tx_byte_id = 1) then
--            console_data_to_tx <= latched_data_to_send(15 downto 8);
--            if (data_length = 2) then
--              console_need_stop_bit <= '1';
--              console_stop_bit <= '0';
--            else
--              console_need_stop_bit <= '0';
--            end if;
--            
--            console_tx_write <= '1';
--            
--            tx_byte_id <= 2;
--          elsif (tx_byte_id = 2 and data_length = 3) then
--            console_data_to_tx <= latched_data_to_send(7 downto 0);
--            console_need_stop_bit <= '1';
--            console_stop_bit <= '0';
--            console_tx_write <= '1';
--            
--            tx_byte_id <= 3;
--          elsif ((tx_byte_id = 2 and data_length = 2) or tx_byte_id = 3) then
--            -- stop tx
--            transmitting <= '0';
--          end if;
--        end if;
--      elsif (transmit_new_data = '1') then
--        latched_data_to_send <= data_to_send;
--        
--        console_data_to_tx <= data_to_send(31 downto 24);
--        console_need_stop_bit <= '0';
--        console_tx_write <= '1';
--        
--        tx_byte_id <= 0;
--        
--        transmitting <= '1';
--      end if;
--      
--      if (console_tx_write = '1' and console_tx_busy = '1') then
--          console_tx_write <= '0';
--        end if;
--    end if;
--  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      transmit_new_data <= '0';
      if (reply_delay_active = '1') then
        if (broadcast_mode = preswitch) then
          if (reply_delay_timer = switch_timer_max) then
            reply_delay_timer <= 0;
            broadcast_mode <= controller_to_console;
            reply_delay_active <= '1';
          else
            reply_delay_timer <= reply_delay_timer + 1;
          end if;
        else
          if (reply_delay_timer = timer_max) then
            broadcast_mode <= idle_mode;
            reply_delay_active <= '0';
          else
            reply_delay_timer <= reply_delay_timer + 1;
          end if;
        end if;
      elsif (transmitting = '0' and console_new_byte = '1') then
        if (console_rx_data = "00000000") then
          switch_timer_max <= 16;
          timer_max <= 3200;
          reply_delay_timer <= 0;
          broadcast_mode <= preswitch;
          reply_delay_active <= '1';
        elsif (console_rx_data = "00000001") then
          switch_timer_max <= 16;
          timer_max <= 4224;
          reply_delay_timer <= 0;
          broadcast_mode <= preswitch;
          reply_delay_active <= '1';
        elsif (console_rx_data = "00000010") then
          switch_timer_max <= 2224;
          timer_max <= 33920;
          reply_delay_timer <= 0;
          broadcast_mode <= preswitch;
          reply_delay_active <= '1';
        elsif (console_rx_data = "00000011") then
          switch_timer_max <= 35764;
          timer_max <= 1152;
          reply_delay_timer <= 0;
          broadcast_mode <= preswitch;
          reply_delay_active <= '1';
        end if;
      end if;
    end if;
  end process;

  debug(0) <= '1';
  debug(1) <= '1';
  debug(2) <= console_new_bit_val(0);
  debug(3) <= console_signal_from_tx;
  
  console_signal_out <= controller_signal_in_f when (broadcast_mode = controller_to_console) else
                        '1';
  console_signal_oe <= '0' when (broadcast_mode = controller_to_console) else
                       '1';

  
  controller_signal_out <= console_signal_in_f when (broadcast_mode = idle_mode or broadcast_mode = preswitch) else
                        '1';
  controller_signal_oe <= '1' when (broadcast_mode = controller_to_console) else
                          '0';
                           

end Behavioral;

