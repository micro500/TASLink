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
  
  component n64_data_transmitter is
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
  end component;

  signal new_bit : std_logic;
  
  signal data_in_f : std_logic;
    
  signal new_bit_val : std_logic_vector(1 downto 0);
    
  signal new_byte : std_logic := '0';
  signal rx_data : std_logic_vector (7 downto 0) := (others => '0');
  
  signal data_length : std_logic_vector(5 downto 0) := "000000";
  
  signal data_signal_from_tx : std_logic;
  signal data_to_tx : std_logic_vector(255 downto 0) := (others => '0');
  signal need_stop_bit : std_logic := '0';
  signal stop_bit : std_logic := '0';
  
  signal tx_busy : std_logic;
  signal tx_write : std_logic := '0';
  signal tx_write_ack : std_logic;
  
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
  
  signal need_crc : std_logic := '0';
begin

  data_filter: filter port map (signal_in => data_signal_in,
                                clk => CLK,
                                signal_out => data_in_f);

  detector: bit_detector port map (data_signal => data_in_f,
                                   bit_val => new_bit_val,
                                   new_bit => new_bit,
                                   clk => clk);
  byte_rx: byte_receiver port map ( new_bit => new_bit,
                                    bit_val => new_bit_val,
                                    new_byte => new_byte,
                                    byte_val => rx_data,
                                    CLK => CLK);
                                   
  bit_toggle: toggle port map (signal_in => new_bit,
                               signal_out => bit_tog);
                               
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
      tx_write <= '0';
      uart_write <= '0';
      buffer_read <= '0';
      if (reply_delay_active = '1') then
        if (reply_delay_timer = 96) then
          if (rx_data = "00000000") then
            tx_write <= '1';
            data_to_tx <= (others => '0');
            data_to_tx(255 downto 232) <= "000001010000000000000010";
            data_length <= "000011";
            need_stop_bit <= '1';
            stop_bit <= '0';
            reply_delay_active <= '0';
          elsif (rx_data = "11111111") then
            tx_write <= '1';
            data_to_tx <= (others => '0');
            data_to_tx(255 downto 232) <= "100000101000000000000001";
            data_length <= "000011";
            need_stop_bit <= '1';
            stop_bit <= '0';
            reply_delay_active <= '0';
          elsif (rx_data = "00000001") then
            tx_write <= '1';
            data_to_tx <= (others => '0');
            data_to_tx(255 downto 224) <= buffer_data;
            data_length <= "000100";
            need_stop_bit <= '1';
            stop_bit <= '0';
            reply_delay_active <= '0';
            buffer_read <= '1';
            uart_write <= '1';
            data_to_uart <= x"66"; -- "f"
          end if;
        else
          reply_delay_timer <= reply_delay_timer + 1;
        end if;
      elsif (tx_busy = '0' and new_byte = '1') then
        reply_delay_timer <= 0;
        reply_delay_active <= '1';
      end if;
    end if;
  end process;
  
  debug(0) <= tx;
  debug(1) <= rx;
  debug(2) <= new_bit_val(0);
  debug(3) <= data_signal_from_tx;
  
  data_signal_oe <= oe_signal;
  
  data_signal_out <= data_signal_from_tx;
  oe_signal <= not tx_busy;
  
  TX_raw <= tx;

end Behavioral;

