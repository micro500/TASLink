library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

entity main is
    Port ( data_signal_in : in  STD_LOGIC;
           data_signal_out : out STD_LOGIC;
           debug : out  STD_LOGIC_VECTOR(3 downto 0);
           data_signal_oe : out std_logic;
           RX : in std_logic;
           TX_raw : out std_logic;
           CLK : in  STD_LOGIC);
end main;

architecture Behavioral of main is
  component toggle is
    Port ( signal_in : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
  end component;

  component bit_detector is
    Port ( data_signal : in  STD_LOGIC;
           new_bit : out  STD_LOGIC;
           bit_val : out  STD_LOGIC_VECTOR (1 downto 0);
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

  component fifo is
    Port ( data_in : in  STD_LOGIC_VECTOR (31 downto 0);
           write_en : in  STD_LOGIC;
           data_out : out  STD_LOGIC_VECTOR (31 downto 0);
           read_en : in  STD_LOGIC;
           clk : in  STD_LOGIC;
           empty : out  STD_LOGIC;
           full : out  STD_LOGIC;
           clear : in  STD_LOGIC);
  end component;
  
  component UART is
    Port ( rx_data_out : out STD_LOGIC_VECTOR (7 downto 0);
           rx_data_was_recieved : in STD_LOGIC;
           rx_byte_waiting : out STD_LOGIC;
           clk : in  STD_LOGIC;

           rx_in : in STD_LOGIC;
           tx_data_in : in STD_LOGIC_VECTOR (7 downto 0);
           tx_buffer_full : out STD_LOGIC;
           tx_write : in STD_LOGIC;
           tx_out : out STD_LOGIC);
  end component;


  
  signal new_bit_flag : std_logic;
  
  signal data_in_f : std_logic;
  
  type rx_modes is (idle_mode, receive_mode);
  signal rx_mode : rx_modes := idle_mode;
  
  signal new_bit_val : std_logic_vector(1 downto 0);
  
  signal rx_data : std_logic_vector(7 downto 0);
  signal rx_timer : integer range 0 to 160 := 0;
  signal bit_count : integer range 0 to 7 := 0;
  
  signal new_byte : std_logic := '0';
  
  signal data_to_send : std_logic_vector(31 downto 0) := (others => '0');
  signal latched_data_to_send : std_logic_vector(31 downto 0) := (others => '0');
  signal tx_byte_id : integer range 0 to 3 := 0;
  signal transmit_new_data : std_logic := '0';
  signal transmitting : std_logic := '0';
  signal data_length : integer range 0 to 3 := 0;
  
  signal data_signal_from_tx : std_logic;
  signal data_to_tx : std_logic_vector(7 downto 0) := (others => '0');
  signal need_stop_bit : std_logic := '0';
  signal stop_bit : std_logic := '0';
  
  signal tx_busy : std_logic;
  signal tx_write : std_logic := '0';
  
  signal reply_delay_active : std_logic := '0';
  signal reply_delay_timer : integer range 0 to 96 := 0;
  
  signal latched_rx_data : std_logic_vector(7 downto 0) := (others => '0');
  
  signal oe_signal : std_logic := '1';
  
  
  
  signal buffer_new_data : std_logic_vector(31 downto 0);
  signal buffer_write : std_logic;
  signal buffer_data : std_logic_vector(31 downto 0);
  signal buffer_read : std_logic;
  signal buffer_empty : std_logic;
  signal buffer_full : std_logic;
  signal buffer_clear : std_logic;

  signal tx : std_logic := '0';
  
  
  signal data_from_uart : STD_LOGIC_VECTOR (7 downto 0);
  signal uart_data_recieved : STD_LOGIC := '0';
  signal uart_byte_waiting : STD_LOGIC := '0';
  
  signal data_to_uart : STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
  signal uart_buffer_full : STD_LOGIC;
  signal uart_write : STD_LOGIC := '0';
  
  type uart_states is (main_cmd, button_data_cmd);
  signal uart_state : uart_states := main_cmd;
  signal data_byte_id : integer range 1 to 4;
  type vector8 is array (natural range <>) of std_logic_vector(7 downto 0);
  signal setup_cmd_data : vector8(1 to 3) := (others => (others => '0'));

  signal bit_tog : std_logic := '0';
begin

  data_filter: filter port map (signal_in => data_signal_in,
                                clk => CLK,
                                signal_out => data_in_f);

  detector: bit_detector port map (data_signal => data_in_f,
                                   bit_val => new_bit_val,
                                   new_bit => new_bit_flag,
                                   clk => clk);
                                   
  bit_toggle: toggle port map (signal_in => new_bit_flag,
                               signal_out => bit_tog);
                               
                               
  tx1: bit_transmitter port map ( data_signal_out => data_signal_from_tx,
                                 data_to_send => data_to_tx,
                                 need_stop_bit => need_stop_bit,
                                 stop_bit => stop_bit,
                                 tx_busy => tx_busy,
                                 tx_write => tx_write,
                                 CLK => clk);
                               
  buffers: fifo port map ( data_in => buffer_new_data,
                           write_en => buffer_write,
                           data_out => buffer_data,
                           read_en => buffer_read,
                           clk => clk,
                           empty => buffer_empty,
                           full => buffer_full,
                           clear => buffer_clear);

  uart1: UART port map (rx_data_out => data_from_uart,
                        rx_data_was_recieved => uart_data_recieved,
                        rx_byte_waiting => uart_byte_waiting,
                        clk => CLK,
                        rx_in => RX,
                        tx_data_in => data_to_uart,
                        tx_buffer_full => uart_buffer_full,
                        tx_write => uart_write,
                        tx_out => TX);  
  

uart_recieve_btye: process(CLK)
	begin
		if (rising_edge(CLK)) then
      uart_data_recieved <= '0';
      buffer_clear <= '0';
      buffer_write <= '0';
    
			if (uart_byte_waiting = '1' and uart_data_recieved = '0') then
        case uart_state is
          when main_cmd =>
            case data_from_uart is
              when x"66" => -- 'f'
                
                data_byte_id <= 1;
                uart_state <= button_data_cmd;
                            
              when x"52" => -- 'R'
                buffer_clear <= '1';
                --uart_state <= main_cmd;
                
              when others =>
              
            end case;
                    
          when button_data_cmd =>
            -- Store this byte of data in the right spot
            if (data_byte_id = 1) then
              buffer_new_data <= "111111111111111111111111" & data_from_uart;
            elsif (data_byte_id = 2) then
              buffer_new_data <= "1111111111111111" & data_from_uart & buffer_new_data(7 downto 0);
            elsif (data_byte_id = 3) then
              buffer_new_data <= "11111111" & data_from_uart & buffer_new_data(15 downto 0);
            else
              buffer_new_data <= data_from_uart & buffer_new_data(23 downto 0);
            end if;
            
            -- Do we need to go to the next controller?
            if (data_byte_id = 4) then
              -- Store the data in the fifo
              buffer_write <= '1';
              uart_state <= main_cmd;
            else
              -- Go to the next byte
              data_byte_id <= data_byte_id + 1;
            end if;
         
        end case;
      	uart_data_recieved <= '1';
			end if;
    end if;
	end process;
  
  
  
  
  
  process (clk)
  begin
    if (rising_edge(clk)) then
      new_byte <= '0';
      if (rx_mode = idle_mode) then
        if (new_bit_flag = '1' and (new_bit_val = "00" or new_bit_val = "01")) then
          rx_data <= "0000000" & new_bit_val(0);
          rx_timer <= 0;
          rx_mode <= receive_mode;
          bit_count <= 1;
        end if;
      else
        if (new_bit_flag = '1' and (new_bit_val = "00" or new_bit_val = "01")) then
          rx_data <= rx_data(6 downto 0) & new_bit_val(0);
          if (bit_count = 7) then
            rx_mode <= idle_mode;
            new_byte <= '1';
          else
            bit_count <= bit_count + 1;
            rx_timer <= 0;
            rx_mode <= receive_mode;
          end if;
        else
          if (rx_timer = 160) then
            rx_mode <= idle_mode;
          else
            rx_timer <= rx_timer + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  process (clk)
  begin
    if (rising_edge(clk)) then
      transmit_new_data <= '0';
      uart_write <= '0';
      buffer_read <= '0';
      if (reply_delay_active = '1') then
        if (reply_delay_timer = 96) then
          if (rx_data = "00000000") then
            transmit_new_data <= '1';
            data_to_send <= "00000101000000000000001000000000";
            data_length <= 2;
            reply_delay_active <= '0';
          elsif (rx_data = "11111111") then
            transmit_new_data <= '1';
            data_to_send <= "10000010100000000000000100000000";
            data_length <= 2;
            reply_delay_active <= '0';
          elsif (rx_data = "00000001") then
            transmit_new_data <= '1';
            data_to_send <= buffer_data;
            data_length <= 3;
            reply_delay_active <= '0';
            buffer_read <= '1';
            uart_write <= '1';
            data_to_uart <= x"66"; -- "f"
          end if;
        else
          reply_delay_timer <= reply_delay_timer + 1;
        end if;
      elsif (transmitting = '0' and new_byte = '1') then
        reply_delay_timer <= 0;
        reply_delay_active <= '1';
      end if;
    end if;
  end process;
  
  process (clk)
  begin
    if (rising_edge(clk)) then
      --tx_write <= '0';
      
      if (transmitting = '1') then
        if (tx_write = '0' and tx_busy = '0') then
          if (tx_byte_id = 0) then
            data_to_tx <= latched_data_to_send(23 downto 16);
            need_stop_bit <= '0';
            tx_write <= '1';
            
            tx_byte_id <= 1;
          elsif (tx_byte_id = 1) then
            data_to_tx <= latched_data_to_send(15 downto 8);
            if (data_length = 2) then
              need_stop_bit <= '1';
              stop_bit <= '0';
            else
              need_stop_bit <= '0';
            end if;
            
            tx_write <= '1';
            
            tx_byte_id <= 2;
          elsif (tx_byte_id = 2 and data_length = 3) then
            data_to_tx <= latched_data_to_send(7 downto 0);
            need_stop_bit <= '1';
            stop_bit <= '0';
            tx_write <= '1';
            
            tx_byte_id <= 3;
          elsif ((tx_byte_id = 2 and data_length = 2) or tx_byte_id = 3) then
            -- stop tx
            transmitting <= '0';
          end if;
        end if;
      elsif (transmit_new_data = '1') then
        latched_data_to_send <= data_to_send;
        
        data_to_tx <= data_to_send(31 downto 24);
        need_stop_bit <= '0';
        tx_write <= '1';
        
        tx_byte_id <= 0;
        
        transmitting <= '1';
      end if;
      
      if (tx_write = '1' and tx_busy = '1') then
          tx_write <= '0';
        end if;
    end if;
  end process;

  debug(0) <= tx;
  debug(1) <= rx;
  debug(2) <= new_bit_val(0);
  debug(3) <= data_signal_from_tx;
  
  data_signal_oe <= oe_signal;
  
  data_signal_out <= data_signal_from_tx;
  oe_signal <= not transmitting;
  
  TX_raw <= tx;

end Behavioral;

