library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity main is
    Port ( CLK : in std_logic;
           RX : in std_logic;
           TX : out std_logic;
           btn : in  STD_LOGIC_VECTOR (3 downto 0);
           p1_latch : in  STD_LOGIC;
           p1_clock : in  STD_LOGIC;
           p1_d0 : out STD_LOGIC;
           p2_latch : in std_logic;
           p2_clock : in std_logic;
           p2_d0 : out std_logic;
           debug : out STD_LOGIC_VECTOR (3 downto 0);
           l: out STD_LOGIC_VECTOR(3 downto 0));
end main;

architecture Behavioral of main is
  component shift_register is
    Port ( latch : in  STD_LOGIC;
           clock : in  STD_LOGIC;
           din : in  STD_LOGIC_VECTOR (7 downto 0);
           dout : out  STD_LOGIC;
           clk : in std_logic);
  end component;
  
  component filter is
    Port ( signal_in : in  STD_LOGIC;
           clk : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
  end component;
  
  component toggle is
    Port ( signal_in : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
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

  -- Filtered signals coming from the console
  signal p1_clock_f : std_logic;
  signal p1_latch_f : std_logic;
  signal p2_clock_f : std_logic;
  signal p2_latch_f : std_logic;
  
  -- Toggle signals, useful for monitoring when the FPGA detects a rising edge
  signal p1_clock_toggle : std_logic;
  signal p1_latch_toggle : std_logic;
  signal p1_clock_f_toggle : std_logic;
  signal p1_latch_f_toggle : std_logic;
  signal p2_clock_toggle : std_logic;
  signal p2_latch_toggle : std_logic;
  signal p2_clock_f_toggle : std_logic;
  signal p2_latch_f_toggle : std_logic;

  signal button_data : std_logic_vector(7 downto 0) := "11111111";
  signal p2_button_data : std_logic_vector(7 downto 0) := "11111111";
  
  signal data_from_uart : STD_LOGIC_VECTOR (7 downto 0);
  signal uart_data_recieved : STD_LOGIC := '0';
  signal uart_byte_waiting : STD_LOGIC := '0';
  
  signal data_to_uart : STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
  signal uart_buffer_full : STD_LOGIC;
  signal uart_write : STD_LOGIC := '0';
  
  signal uart_buffer_ptr : integer range 0 to 2 := 0;
  
  type BUTTON_DATA_buffer is array(0 to 31) of std_logic_vector(15 downto 0);
  
  signal button_queue : BUTTON_DATA_BUFFER;
  
  signal buffer_tail : integer range 0 to 31 := 0;
  signal buffer_head : integer range 0 to 31 := 0;
  
  signal test_toggle : std_logic := '0';
  
  signal prev_latch : std_logic := '0';
  
  signal frame_timer_active : std_logic := '0';
  signal frame_timer : integer range 0 to 160000 := 0;
  
  signal windowed_mode : std_logic := '0';
  
  signal uart_data_temp : std_logic_vector(7 downto 0);
begin

  p1_latch_filter: filter port map (signal_in => p1_latch,
                                    clk => CLK,
                                    signal_out => p1_latch_f);
                                 
  p1_clock_filter: filter port map (signal_in => p1_clock,
                                    clk => CLK,
                                    signal_out => p1_clock_f);
                                 
  p2_latch_filter: filter port map (signal_in => p2_latch,
                                    clk => CLK,
                                    signal_out => p2_latch_f);
                                 
  p2_clock_filter: filter port map (signal_in => p2_clock,
                                    clk => CLK,
                                    signal_out => p2_clock_f);
                                    
  p1latch_toggle: toggle port map (signal_in => p1_latch,
                                   signal_out => p1_latch_toggle);
                                 
  p1latch_f_toggle: toggle port map (signal_in => p1_latch_f,
                                     signal_out => p1_latch_f_toggle);
  
  p1clk_toggle: toggle port map (signal_in => p1_clock,
                                 signal_out => p1_clock_toggle);
  
  p1clock_f_toggle: toggle port map (signal_in => p1_clock_f,
                                     signal_out => p1_clock_f_toggle);

  p2latch_toggle: toggle port map (signal_in => p2_latch,
                                   signal_out => p2_latch_toggle);
                                 
  p2latch_f_toggle: toggle port map (signal_in => p2_latch_f,
                                     signal_out => p2_latch_f_toggle);
  
  p2clk_toggle: toggle port map (signal_in => p2_clock,
                                 signal_out => p2_clock_toggle);
  
  p2clock_f_toggle: toggle port map (signal_in => p2_clock_f,
                                     signal_out => p2_clock_f_toggle);


  sr: shift_register port map (latch => p1_latch_f,
                               clock => p1_clock_f,
                               din => button_data,
                               dout => p1_d0,
                               clk => clk);
                               
  p2_sr: shift_register port map (latch => p1_latch_f,
                                  clock => p2_clock_f,
                                  din => p2_button_data,
                                  dout => p2_d0,
                                  clk => clk);
                                  
  button_data <= button_queue(buffer_tail)(7 downto 0) when buffer_head /= buffer_tail else
                 button_queue(31)(7 downto 0) when buffer_tail = 0 else
                 button_queue(buffer_tail-1)(7 downto 0);

  p2_button_data <= button_queue(buffer_tail)(15 downto 8) when buffer_head /= buffer_tail else
                    button_queue(31)(15 downto 8) when buffer_tail = 0 else
                    button_queue(buffer_tail-1)(15 downto 8);
                                   
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
			if (uart_byte_waiting = '1' and uart_data_recieved = '0') then
        test_toggle <= not(test_toggle);
        case uart_buffer_ptr is
          when 0 =>
            case data_from_uart is
              when x"66" => -- 'f'
                
                uart_buffer_ptr <= 1;
              
              when x"63" => -- 'c'
                buffer_head <= buffer_tail;
                
                uart_buffer_ptr <= 0;  
              
              when x"77" => -- 'w'
                windowed_mode <= '1';
                
              when x"6C" => -- 'l'
                windowed_mode <= '0';
              
              when others =>
              
            end case;
            
          when 1 =>
            if ((buffer_head = 31 and buffer_tail /= 0) or (buffer_head /= 31 and (buffer_head + 1) /= buffer_tail)) then
              -- add it to the next spot
              uart_data_temp <= data_from_uart;
            end if;
            
            uart_buffer_ptr <= 2;
              
          when 2 =>
            if ((buffer_head = 31 and buffer_tail /= 0) or (buffer_head /= 31 and (buffer_head + 1) /= buffer_tail)) then
              -- add it to the next spot
              button_queue(buffer_head) <= data_from_uart & uart_data_temp;

              -- move
              if (buffer_head = 31) then
                buffer_head <= 0;
              else
                buffer_head <= buffer_head + 1;
              end if;
            end if;
            
            uart_buffer_ptr <= 0;
            
          when others =>
        end case;
      	uart_data_recieved <= '1';
			else
				uart_data_recieved <= '0';
			end if;
    end if;
	end process;
  
  process (clk) is
  begin
    if (rising_edge(clk)) then
      uart_write <= '0';
      
      if (windowed_mode = '1' and frame_timer_active = '1') then
        if (frame_timer = 96000) then
          frame_timer <= 0;
          frame_timer_active <= '0';
        
          -- move tail pointer if possible
          if (buffer_tail /= buffer_head) then
            if (buffer_tail = 31) then
              buffer_tail <= 0;
            else
              buffer_tail <= buffer_tail + 1;
            end if;
          end if;
          
          -- Send feedback that a frame was consumed
          if (uart_buffer_full = '0') then
            uart_write <= '1';
            data_to_uart <= x"66";
          end if;
          
        else
          frame_timer <= frame_timer + 1;
        end if;
      end if;

      if (p1_latch_f /= prev_latch) then
        if (p1_latch_f = '1') then
          if (windowed_mode = '1') then
            frame_timer <= 0;
            frame_timer_active <= '1';
          else
            -- move tail pointer if possible
            if (buffer_tail /= buffer_head) then
              if (buffer_tail = 31) then
                buffer_tail <= 0;
              else
                buffer_tail <= buffer_tail + 1;
              end if;
            end if;
            
            -- Send feedback that a frame was consumed
            if (uart_buffer_full = '0') then
              uart_write <= '1';
              data_to_uart <= x"66";
            end if;
          end if;
        end if;
        prev_latch <= p1_latch_f;
      end if;
    end if;
  end process;


  l <= std_logic_vector(to_unsigned(buffer_tail, 4));
    
  debug(0) <= p1_latch_toggle;
  debug(1) <= p2_latch_f;
  debug(2) <= p1_clock_toggle;
  debug(3) <= p2_clock_f;

end Behavioral;

