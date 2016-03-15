library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity main is
    Port ( CLK : in std_logic;
           RX : in std_logic;
           TX : out std_logic;
           console_latch : in  STD_LOGIC_VECTOR(1 to 2);
           console_clock : in  STD_LOGIC_VECTOR(1 to 2);
           console_d0 : out STD_LOGIC_VECTOR(1 to 2);
           console_d1 : out STD_LOGIC_VECTOR(1 to 2);
           console_io : in STD_LOGIC_VECTOR(1 to 2);
           console_d0_oe : out std_logic_VECTOR(1 to 2);
           console_d1_oe : out std_logic_VECTOR(1 to 2);
           debug : out STD_LOGIC_VECTOR (7 downto 0));
end main;

architecture Behavioral of main is 
  component filter is
    Port ( signal_in : in  STD_LOGIC;
           clk : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
  end component;
  
  component toggle is
    Port ( signal_in : in  STD_LOGIC;
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
  
  component controller is
    Port ( console_clock : in  STD_LOGIC;
           console_latch : in  STD_LOGIC;
           console_io : in  STD_LOGIC;
           console_d0 : out  STD_LOGIC;
           console_d1 : out  STD_LOGIC;
           console_d0_oe : out  STD_LOGIC;
           console_d1_oe : out  STD_LOGIC;
           data : in  STD_LOGIC_VECTOR (31 downto 0);
           overread_value : in  STD_LOGIC;
           size : in  STD_LOGIC_VECTOR (1 downto 0);
           connected : in  STD_LOGIC;
           clk : STD_LOGIC);
  end component;
  
  component snes_multitap is
    Port ( console_clock : in  STD_LOGIC;
           console_latch : in  STD_LOGIC;
           console_io : in  STD_LOGIC;
           console_d0 : out  STD_LOGIC;
           console_d1 : out  STD_LOGIC;
           console_d0_oe : out  STD_LOGIC;
           console_d1_oe : out  STD_LOGIC;
           
           clk : in  STD_LOGIC;
           sw : in  STD_LOGIC;
           
           port_latch : out STD_LOGIC_VECTOR(1 to 4);
           port_clock : out STD_LOGIC_VECTOR(1 to 4);
           port_io : out STD_LOGIC_VECTOR(1 to 4);
           port_d0 : in STD_LOGIC_VECTOR(1 to 4);
           port_d1 : in STD_LOGIC_VECTOR(1 to 4);
           port_d0_oe : in STD_LOGIC_VECTOR(1 to 4);
           port_d1_oe : in STD_LOGIC_VECTOR(1 to 4));
  end component;

  -- Filtered signals coming from the console
  signal console_clock_f : std_logic_vector(1 to 2);
  signal console_latch_f : std_logic_vector(1 to 2);
  signal console_io_f : std_logic_vector(1 to 2);
  
  -- Toggle signals, useful for monitoring when the FPGA detects a rising edge
  signal console_clock_toggle : std_logic_vector(1 to 2);
  signal console_latch_toggle : std_logic_vector(1 to 2);
  signal console_clock_f_toggle : std_logic_vector(1 to 2);
  signal console_latch_f_toggle : std_logic_vector(1 to 2);
  
  signal data_from_uart : STD_LOGIC_VECTOR (7 downto 0);
  signal uart_data_recieved : STD_LOGIC := '0';
  signal uart_byte_waiting : STD_LOGIC := '0';
  
  signal data_to_uart : STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
  signal uart_buffer_full : STD_LOGIC;
  signal uart_write : STD_LOGIC := '0';
  
  signal serial_receive_mode : std_logic_vector (2 downto 0) := (others => '0');
  signal uart_buffer_ptr : integer range 0 to 16 := 0;
  
  type vector32 is array (natural range <>) of std_logic_vector(31 downto 0);
  signal buffer_new_data : vector32(1 to 8);
  signal buffer_write : std_logic_vector(1 to 8);
  signal buffer_data : vector32(1 to 8);
  signal buffer_read : std_logic_vector(1 to 8);
  signal buffer_empty : std_logic_vector(1 to 8);
  signal buffer_full : std_logic_vector(1 to 8);
  signal buffer_clear : std_logic_vector(1 to 8);
  
  signal prev_latch : std_logic := '0';
  
  signal frame_timer_active : std_logic := '0';
  signal frame_timer : integer range 0 to 160000 := 0;
  
  signal windowed_mode : std_logic := '0';
  
  signal uart_data_temp : std_logic_vector(7 downto 0);
  
  signal controller_size : std_logic_vector(1 downto 0) := "00";
  
  type logic_array is array (natural range <>) of std_logic;
  signal controller_clock : logic_array(8 downto 1);
  signal controller_latch : logic_array(8 downto 1);
  signal controller_io : logic_array(8 downto 1);
  signal controller_d0 : logic_array(8 downto 1);
  signal controller_d1 : logic_array(8 downto 1);
  signal controller_d0_oe : logic_array(8 downto 1);
  signal controller_d1_oe : logic_array(8 downto 1);
  signal controller_overread_value : logic_array(8 downto 1);
  signal controller_connected : logic_array(8 downto 1);
  
  signal controller_data : vector32(8 downto 1);


  type vector4 is array (natural range <>) of std_logic_vector(1 to 4);
  
  signal multitap_clock : std_logic_vector(1 to 2);
  signal multitap_latch : std_logic_vector(1 to 2);
  signal multitap_io : std_logic_vector(1 to 2);
  signal multitap_d0 : std_logic_vector(1 to 2);
  signal multitap_d1 : std_logic_vector(1 to 2);
  signal multitap_d0_oe : std_logic_vector(1 to 2);
  signal multitap_d1_oe : std_logic_vector(1 to 2);

  signal multitap_port_latch : vector4(1 to 2);
  signal multitap_port_clock : vector4(1 to 2);
  signal multitap_port_io : vector4(1 to 2);
  signal multitap_port_d0 : vector4(1 to 2);
  signal multitap_port_d1 : vector4(1 to 2);
  signal multitap_port_d0_oe : vector4(1 to 2);
  signal multitap_port_d1_oe : vector4(1 to 2);
    
  signal use_multitap1 : std_logic := '0';
  signal use_multitap2 : std_logic := '0';

  
  signal address_to_use : integer range 0 to 63;
begin

  GENERATE_FILTERS:
  for I in 1 to 2 generate
    latch_filters: filter port map (signal_in => console_latch(I),
                                    clk => CLK,
                                    signal_out => console_latch_f(I));
                                 
    clock_filters: filter port map (signal_in => console_clock(I),
                                    clk => CLK,
                                    signal_out => console_clock_f(I));
    
    io_filters: filter port map (signal_in => console_io(I),
                                 clk => CLK,
                                 signal_out => console_io_f(I));
  end generate GENERATE_FILTERS;
  
  GENERATE_TOGGLES:
  for I in 1 to 2 generate
    latch_toggles: toggle port map (signal_in => console_latch(I),
                                    signal_out => console_latch_toggle(I));
                                 
    latch_f_toggles: toggle port map (signal_in => console_latch_f(I),
                                      signal_out => console_latch_f_toggle(I));
    
    clock_toggles: toggle port map (signal_in => console_clock(I),
                                    signal_out => console_clock_toggle(I));
    
    clock_f_toggles: toggle port map (signal_in => console_clock_f(I),
                                      signal_out => console_clock_f_toggle(I));
  end generate GENERATE_TOGGLES;
                                    
                                     
  uart1: UART port map (rx_data_out => data_from_uart,
                        rx_data_was_recieved => uart_data_recieved,
                        rx_byte_waiting => uart_byte_waiting,
                        clk => CLK,
                        rx_in => RX,
                        tx_data_in => data_to_uart,
                        tx_buffer_full => uart_buffer_full,
                        tx_write => uart_write,
                        tx_out => TX);
 
  GENERATE_CONTROLLERS:
  for I in 1 to 8 generate
    controllers: controller port map (console_clock => controller_clock(I),
                                     console_latch => controller_latch(I),
                                     console_io => controller_io(I),
                                     console_d0 => controller_d0(I),
                                     console_d1 => controller_d1(I),
                                     console_d0_oe => controller_d0_oe(I),
                                     console_d1_oe => controller_d1_oe(I),
                                     data => controller_data(I),
                                     overread_value => controller_overread_value(I),
                                     size => controller_size,
                                     connected => controller_connected(I),
                                     clk => clk);

    buffers: fifo port map ( data_in => buffer_new_data(I),
                             write_en => buffer_write(I),
                             data_out => buffer_data(I),
                             read_en => buffer_read(I),
                             clk => clk,
                             empty => buffer_empty(I),
                             full => buffer_full(I),
                             clear => buffer_clear(I));
                             
  end generate GENERATE_CONTROLLERS;
  
  GENERATE_MULTITAPS:
  for I in 1 to 2 generate
  multitaps: snes_multitap port map ( console_clock => multitap_clock(I),
                                      console_latch => multitap_latch(I),
                                      console_io => multitap_io(I),
                                      console_d0 => multitap_d0(I),
                                      console_d1 => multitap_d1(I),
                                      console_d0_oe => multitap_d0_oe(I),
                                      console_d1_oe => multitap_d1_oe(I),
                                       
                                      clk => clk,
                                      sw => '1',
                                      
                                      port_latch => multitap_port_latch(I),
                                      port_clock => multitap_port_clock(I),
                                      port_io => multitap_port_io(I),
                                      port_d0 => multitap_port_d0(I),
                                      port_d1 => multitap_port_d1(I),
                                      port_d0_oe => multitap_port_d0_oe(I),
                                      port_d1_oe => multitap_port_d1_oe(I)); 
  end generate GENERATE_MULTITAPS;
                                      
uart_recieve_btye: process(CLK)
	begin
		if (rising_edge(CLK)) then
      buffer_clear <= "00000000";
      buffer_write <= "00000000";
    
			if (uart_byte_waiting = '1' and uart_data_recieved = '0') then
        case uart_buffer_ptr is
          when 0 =>
            case data_from_uart is
              when x"66" => -- 'f'
                
                uart_buffer_ptr <= 1;
                serial_receive_mode <= "000";
              
              when x"63" => -- 'c'
                buffer_clear <= "11111111";
                uart_buffer_ptr <= 0;  
              
              when x"77" => -- 'w'
                windowed_mode <= '1';
                
              when x"6C" => -- 'l'
                windowed_mode <= '0';
              
              when x"6E" => -- 'n'
                controller_size <= "00";
                uart_buffer_ptr <= 1;
                serial_receive_mode <= "001";
              
              when x"73" => -- 's'
                controller_size <= "01";
                uart_buffer_ptr <= 1;
                serial_receive_mode <= "010";
              
              when others =>
              
            end case;
            
          when 1 =>
            case serial_receive_mode is
              when "000" =>
                buffer_new_data(1) <= "111111111111111111111111" & data_from_uart;
                if (controller_size = "00") then
                  buffer_write(1) <= '1';
                end if;
                
                uart_buffer_ptr <= 2;
              
              when "001" =>
                case data_from_uart is
                  when x"30" => -- '0'
                    controller_connected(1) <= '0';
                    controller_connected(2) <= '0';
                    controller_connected(3) <= '0';
                    controller_connected(4) <= '0';
                    controller_connected(5) <= '0';
                    controller_connected(6) <= '0';
                    controller_connected(7) <= '0';
                    controller_connected(8) <= '0';
                    
                    use_multitap1 <= '0';
                    use_multitap2 <= '0';
                  
                  when x"31" => -- '1'
                    controller_connected(1) <= '1';
                    controller_connected(2) <= '0';
                    controller_connected(3) <= '0';
                    controller_connected(4) <= '0';
                    controller_connected(5) <= '0';
                    controller_connected(6) <= '0';
                    controller_connected(7) <= '0';
                    controller_connected(8) <= '0';
                    
                    use_multitap1 <= '0';
                    use_multitap2 <= '0';

                  when x"32" => -- '2'
                    controller_connected(1) <= '1';
                    controller_connected(2) <= '1';
                    controller_connected(3) <= '0';
                    controller_connected(4) <= '0';
                    controller_connected(5) <= '0';
                    controller_connected(6) <= '0';
                    controller_connected(7) <= '0';
                    controller_connected(8) <= '0';
                    
                    use_multitap1 <= '0';
                    use_multitap2 <= '0';
                  
                  when others =>
                  
                end case;
                
                uart_buffer_ptr <= 0;

              when "010" =>
                case data_from_uart is
                  when x"30" => -- '0'
                    controller_connected(1) <= '0';
                    controller_connected(2) <= '0';
                    controller_connected(3) <= '0';
                    controller_connected(4) <= '0';
                    controller_connected(5) <= '0';
                    controller_connected(6) <= '0';
                    controller_connected(7) <= '0';
                    controller_connected(8) <= '0';
                    
                    use_multitap1 <= '0';
                    use_multitap2 <= '0';
                  
                  when x"31" => -- '1'
                    controller_connected(1) <= '1';
                    controller_connected(2) <= '0';
                    controller_connected(3) <= '0';
                    controller_connected(4) <= '0';
                    controller_connected(5) <= '0';
                    controller_connected(6) <= '0';
                    controller_connected(7) <= '0';
                    controller_connected(8) <= '0';
                    
                    use_multitap1 <= '0';
                    use_multitap2 <= '0';

                  when x"32" => -- '2'
                    controller_connected(1) <= '1';
                    controller_connected(2) <= '1';
                    controller_connected(3) <= '0';
                    controller_connected(4) <= '0';
                    controller_connected(5) <= '0';
                    controller_connected(6) <= '0';
                    controller_connected(7) <= '0';
                    controller_connected(8) <= '0';
                    
                    use_multitap1 <= '0';
                    use_multitap2 <= '0';
                    
                  when x"38" => -- '8'
                    controller_connected(1) <= '1';
                    controller_connected(2) <= '1';
                    controller_connected(3) <= '1';
                    controller_connected(4) <= '1';
                    controller_connected(5) <= '1';
                    controller_connected(6) <= '1';
                    controller_connected(7) <= '1';
                    controller_connected(8) <= '1';
                    
                    use_multitap1 <= '1';
                    use_multitap2 <= '1';
                  
                  when others =>
                  
                end case;
                
                uart_buffer_ptr <= 0;
              
              when others =>
                uart_buffer_ptr <= 0;
                
            end case;
            
          when 2 =>
            if (controller_size = "00") then
              -- add it to the next spot
              buffer_new_data(2) <= "111111111111111111111111" & data_from_uart;
              buffer_write(2) <= '1';
              uart_buffer_ptr <= 0;
              
            elsif (controller_size = "01") then
              buffer_new_data(1) <= "1111111111111111" & data_from_uart & buffer_new_data(1)(7 downto 0);
              buffer_write(1) <= '1';
              uart_buffer_ptr <= 3;
            else
              uart_buffer_ptr <= 0;
            end if;
            
          when 3 =>
            buffer_new_data(2) <= "111111111111111111111111" & data_from_uart;
            uart_buffer_ptr <= 4;
          
          when 4 =>
            buffer_new_data(2) <= "1111111111111111" & data_from_uart & buffer_new_data(2)(7 downto 0);
            buffer_write(2) <= '1';
            uart_buffer_ptr <= 5;

          when 5 =>
            buffer_new_data(3) <= "111111111111111111111111" & data_from_uart;
            uart_buffer_ptr <= 6;
          
          when 6 =>
            buffer_new_data(3) <= "1111111111111111" & data_from_uart & buffer_new_data(3)(7 downto 0);
            buffer_write(3) <= '1';
            uart_buffer_ptr <= 7;
          
          when 7 =>
            buffer_new_data(4) <= "111111111111111111111111" & data_from_uart;
            uart_buffer_ptr <= 8;
          
          when 8 =>
            buffer_new_data(4) <= "1111111111111111" & data_from_uart & buffer_new_data(4)(7 downto 0);
            buffer_write(4) <= '1';
            uart_buffer_ptr <= 9;

          when 9 =>
            buffer_new_data(5) <= "111111111111111111111111" & data_from_uart;
            uart_buffer_ptr <= 10;
          
          when 10 =>
            buffer_new_data(5) <= "1111111111111111" & data_from_uart & buffer_new_data(5)(7 downto 0);
            buffer_write(5) <= '1';
            uart_buffer_ptr <= 11;
          
          when 11 =>
            buffer_new_data(6) <= "111111111111111111111111" & data_from_uart;
            uart_buffer_ptr <= 12;
          
          when 12 =>
            buffer_new_data(6) <= "1111111111111111" & data_from_uart & buffer_new_data(6)(7 downto 0);
            buffer_write(6) <= '1';
            uart_buffer_ptr <= 13;

          when 13 =>
            buffer_new_data(7) <= "111111111111111111111111" & data_from_uart;
            uart_buffer_ptr <= 14;
          
          when 14 =>
            buffer_new_data(7) <= "1111111111111111" & data_from_uart & buffer_new_data(7)(7 downto 0);
            buffer_write(7) <= '1';
            uart_buffer_ptr <= 15;
          
          when 15 =>
            buffer_new_data(8) <= "111111111111111111111111" & data_from_uart;
            uart_buffer_ptr <= 16;
          
          when 16 =>
            buffer_new_data(8) <= "1111111111111111" & data_from_uart & buffer_new_data(8)(7 downto 0);
            buffer_write(8) <= '1';

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
      buffer_read <= "00000000";
      
      if (windowed_mode = '1' and frame_timer_active = '1') then
        if (frame_timer = 96000) then
          frame_timer <= 0;
          frame_timer_active <= '0';
        
          buffer_read <= "11111111";
          
          -- Send feedback that a frame was consumed
          if (uart_buffer_full = '0') then
            uart_write <= '1';
            data_to_uart <= x"66";
          end if;
          
        else
          frame_timer <= frame_timer + 1;
        end if;
      end if;

      if (console_latch_f(1) /= prev_latch) then
        if (console_latch_f(1) = '1') then
          if (windowed_mode = '1') then
            frame_timer <= 0;
            frame_timer_active <= '1';
          else
            buffer_read <= "11111111";
            
            -- Send feedback that a frame was consumed
            if (uart_buffer_full = '0') then
              uart_write <= '1';
              data_to_uart <= x"66";
            end if;
          end if;
        end if;
        prev_latch <= console_latch_f(1);
      end if;
    end if;
  end process;
  
  controller_data(1) <= buffer_data(1);
  controller_data(2) <= buffer_data(2);
  controller_data(3) <= buffer_data(3);
  controller_data(4) <= buffer_data(4);
  controller_data(5) <= buffer_data(5);
  controller_data(6) <= buffer_data(6);
  controller_data(7) <= buffer_data(7);
  controller_data(8) <= buffer_data(8);

  console_d0(1) <= multitap_d0(1) when use_multitap1 = '1' else
                   controller_d0(1);
  console_d1(1) <= multitap_d1(1) when use_multitap1 = '1' else
                   controller_d1(1);
  console_d0(2) <= multitap_d0(2) when use_multitap2 = '1' else
                   controller_d0(2);
  console_d1(2) <= multitap_d1(2) when use_multitap2 = '1' else
                   controller_d1(2);
  
  console_d0_oe(1) <= multitap_d0_oe(1) when use_multitap1 = '1' else
                      controller_d0_oe(1);
  console_d1_oe(1) <= multitap_d1_oe(1) when use_multitap1 = '1' else
                      controller_d1_oe(1);
  console_d0_oe(2) <= multitap_d0_oe(2) when use_multitap2 = '1' else
                      controller_d0_oe(2);
  console_d1_oe(2) <= multitap_d1_oe(2) when use_multitap2 = '1' else
                      controller_d1_oe(2);
  
  controller_clock(1) <= multitap_port_clock(1)(1) when use_multitap1 = '1' else
                         console_clock_f(1);
  controller_clock(2) <= multitap_port_clock(1)(2) when use_multitap1 = '1' else
                         console_clock_f(2);
  controller_clock(3) <= multitap_port_clock(1)(3) when use_multitap1 = '1' else
                         console_clock_f(2);
  controller_clock(4) <= multitap_port_clock(1)(4) when use_multitap1 = '1' else
                         console_clock_f(2);
  controller_clock(5) <= multitap_port_clock(2)(1) when use_multitap2 = '1' else
                         console_clock_f(2);
  controller_clock(6) <= multitap_port_clock(2)(2) when use_multitap2 = '1' else
                         console_clock_f(2);
  controller_clock(7) <= multitap_port_clock(2)(3) when use_multitap2 = '1' else
                         console_clock_f(2);
  controller_clock(8) <= multitap_port_clock(2)(4) when use_multitap2 = '1' else
                         console_clock_f(2);
  
  controller_latch(1) <= multitap_port_latch(1)(1) when use_multitap1 = '1' else
                         console_latch_f(1);
  controller_latch(2) <= multitap_port_latch(1)(2) when use_multitap1 = '1' else
                         console_latch_f(2);
  controller_latch(3) <= multitap_port_latch(1)(3) when use_multitap1 = '1' else
                         console_latch_f(2);
  controller_latch(4) <= multitap_port_latch(1)(4) when use_multitap1 = '1' else
                         console_latch_f(2);
  controller_latch(5) <= multitap_port_latch(2)(1) when use_multitap2 = '1' else
                         console_latch_f(2);
  controller_latch(6) <= multitap_port_latch(2)(2) when use_multitap2 = '1' else
                         console_latch_f(2);
  controller_latch(7) <= multitap_port_latch(2)(3) when use_multitap2 = '1' else
                         console_latch_f(2);
  controller_latch(8) <= multitap_port_latch(2)(4) when use_multitap2 = '1' else
                         console_latch_f(2);
  
  controller_io(1) <= '1';
  controller_io(2) <= '1';
  controller_io(3) <= '1';
  controller_io(4) <= '1';
  controller_io(5) <= '1';
  controller_io(6) <= '1';
  controller_io(7) <= '1';
  controller_io(8) <= '1';
  
  controller_overread_value(1) <= '1';
  controller_overread_value(2) <= '1';
  controller_overread_value(3) <= '1';
  controller_overread_value(4) <= '1';
  controller_overread_value(5) <= '1';
  controller_overread_value(6) <= '1';
  controller_overread_value(7) <= '1';
  controller_overread_value(8) <= '1';
  
  
  multitap_clock(1) <= console_clock_f(1);
  multitap_latch(1) <= console_latch_f(1);
  multitap_io(1) <= console_io_f(1);
  
  multitap_clock(2) <= console_clock_f(2);
  multitap_latch(2) <= console_latch_f(2);
  multitap_io(2) <= console_io_f(2);
  
  multitap_port_d0(1)(1) <= controller_d0(1);
  multitap_port_d0(1)(2) <= controller_d0(2);
  multitap_port_d0(1)(3) <= controller_d0(3);
  multitap_port_d0(1)(4) <= controller_d0(4);
  
  multitap_port_d1(1)(1) <= controller_d1(1);
  multitap_port_d1(1)(2) <= controller_d1(2);
  multitap_port_d1(1)(3) <= controller_d1(3);
  multitap_port_d1(1)(4) <= controller_d1(4);
  
  multitap_port_d0_oe(1)(1) <= controller_d0_oe(1);
  multitap_port_d0_oe(1)(2) <= controller_d0_oe(2);
  multitap_port_d0_oe(1)(3) <= controller_d0_oe(3);
  multitap_port_d0_oe(1)(4) <= controller_d0_oe(4);

  multitap_port_d1_oe(1)(1) <= controller_d1_oe(1);
  multitap_port_d1_oe(1)(2) <= controller_d1_oe(2);
  multitap_port_d1_oe(1)(3) <= controller_d1_oe(3);
  multitap_port_d1_oe(1)(4) <= controller_d1_oe(4);
  
  
  multitap_port_d0(2)(1) <= controller_d0(5);
  multitap_port_d0(2)(2) <= controller_d0(6);
  multitap_port_d0(2)(3) <= controller_d0(7);
  multitap_port_d0(2)(4) <= controller_d0(8);
  
  multitap_port_d1(2)(1) <= controller_d1(5);
  multitap_port_d1(2)(2) <= controller_d1(6);
  multitap_port_d1(2)(3) <= controller_d1(7);
  multitap_port_d1(2)(4) <= controller_d1(8);
  
  multitap_port_d0_oe(2)(1) <= controller_d0_oe(5);
  multitap_port_d0_oe(2)(2) <= controller_d0_oe(6);
  multitap_port_d0_oe(2)(3) <= controller_d0_oe(7);
  multitap_port_d0_oe(2)(4) <= controller_d0_oe(8);

  multitap_port_d1_oe(2)(1) <= controller_d1_oe(5);
  multitap_port_d1_oe(2)(2) <= controller_d1_oe(6);
  multitap_port_d1_oe(2)(3) <= controller_d1_oe(7);
  multitap_port_d1_oe(2)(4) <= controller_d1_oe(8);

  debug(0) <= console_latch_toggle(1);
  debug(1) <= console_latch_f(2);
  debug(2) <= console_clock_toggle(1);
  debug(3) <= console_clock_f(2);
  debug(4) <= '1';
  debug(5) <= '1';
  debug(6) <= '1';
  debug(7) <= '1';

end Behavioral;

