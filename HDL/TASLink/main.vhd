library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity main is
    Port ( CLK : in std_logic;
           RX : in std_logic;
           TX : out std_logic;
           console_latch : in  STD_LOGIC_VECTOR(1 to 4);
           console_clock : in  STD_LOGIC_VECTOR(1 to 4);
           console_d0 : out STD_LOGIC_VECTOR(1 to 4);
           console_d1 : out STD_LOGIC_VECTOR(1 to 4);
           --console_io : in STD_LOGIC_VECTOR(1 to 4);
           console_d0_oe : out std_logic_VECTOR(1 to 4);
           console_d1_oe : out std_logic_VECTOR(1 to 4);
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
  
  component clock_delay is
    Port ( signal_in : in  STD_LOGIC;
           signal_delayed : out  STD_LOGIC;
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
  signal console_clock_f : std_logic_vector(1 to 4);
  signal console_latch_f : std_logic_vector(1 to 4);
  signal console_io_f : std_logic_vector(1 to 4);
  
  -- Toggle signals, useful for monitoring when the FPGA detects a rising edge
  signal console_clock_toggle : std_logic_vector(1 to 4);
  signal console_latch_toggle : std_logic_vector(1 to 4);
  signal console_clock_f_toggle : std_logic_vector(1 to 4);
  signal console_latch_f_toggle : std_logic_vector(1 to 4);
  
  signal console_clock_f_delay : std_logic_vector(1 to 4);
  
  signal console_clock_final : std_logic_vector(1 to 4);
  
  signal data_from_uart : STD_LOGIC_VECTOR (7 downto 0);
  signal uart_data_recieved : STD_LOGIC := '0';
  signal uart_byte_waiting : STD_LOGIC := '0';
  
  signal data_to_uart : STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
  signal uart_buffer_full : STD_LOGIC;
  signal uart_write : STD_LOGIC := '0';
  
  signal data_receive_mask : std_logic_vector(8 downto 1) := (others => '0');
  signal active_setup_cmd : std_logic_vector(7 downto 0);
  
  type uart_states is (main_cmd, button_data_cmd, setup_cmd_data1, setup_cmd_data2, setup_cmd_data3, setup_cmd_data4);
  signal uart_state : uart_states := main_cmd;
  signal data_controller_id : integer range 1 to 8;
  signal data_byte_id : integer range 1 to 4;
  type vector8 is array (natural range <>) of std_logic_vector(7 downto 0);
  signal setup_cmd_data : vector8(1 to 3) := (others => (others => '0'));
  
  type vector32 is array (natural range <>) of std_logic_vector(31 downto 0);
  signal buffer_new_data : vector32(1 to 8);
  signal buffer_write : std_logic_vector(1 to 8);
  signal buffer_data : vector32(1 to 8);
  signal buffer_read : std_logic_vector(1 to 8);
  signal buffer_empty : std_logic_vector(1 to 8);
  signal buffer_full : std_logic_vector(1 to 8);
  signal buffer_clear : std_logic_vector(1 to 8);
  
  signal frame_timer_active : std_logic := '0';
  signal frame_timer : integer range 0 to 160000 := 0;
  
  signal uart_data_temp : std_logic_vector(7 downto 0);
  
  type logic_array is array (natural range <>) of std_logic;
  signal controller_clock : logic_array(8 downto 1);
  signal controller_latch : logic_array(8 downto 1);
  signal controller_io : logic_array(8 downto 1);
  signal controller_d0 : logic_array(8 downto 1);
  signal controller_d1 : logic_array(8 downto 1);
  signal controller_d0_oe : logic_array(8 downto 1);
  signal controller_d1_oe : logic_array(8 downto 1);
  signal controller_overread_value : logic_array(8 downto 1) := (others => '0');
  signal controller_connected : logic_array(8 downto 1);
  type vector2 is array (natural range <>) of std_logic_vector(1 downto 0);
  signal controller_size : vector2(1 to 8) := (others => "00");
  
  signal controller_data : vector32(8 downto 1);


  type vector4 is array (natural range <>) of std_logic_vector(1 to 4);
  
  signal multitap_sw : std_logic_vector(1 to 2);
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
  
  type port_config_type is (sr_controller, y_cable, multitap_2p, multitap_5p, fourscore);
  type port_config_arr is array (natural range <>) of port_config_type;
  signal port_config : port_config_arr(1 to 4) := (others => sr_controller);
  
  signal port_clock_delay : std_logic_vector(1 to 4) := (others => '0');

  signal custom_command_mask : vector8(1 to 8) := (others => (others => '0'));


  signal console_io : STD_LOGIC_VECTOR(1 to 4) := (others => '1');
  
  signal event_enabled : std_logic_vector(1 to 4) := (others => '0');
  signal event_signal : std_logic_vector(1 to 4) := (others => '0');
  signal event_received : std_logic_vector(1 to 4) := (others => '0');
  type timer_length_arr is array (natural range <>) of integer range 0 to 127;
  signal event_timer_length : timer_length_arr(1 to 4) := (20, 20, 0, 0);
  signal event_timer_restart : std_logic_vector(1 to 4) := (others => '0');
  type event_lane_mask_arr is array (natural range <>) of std_logic_vector(7 downto 0);
  signal event_buffer_read_mask : event_lane_mask_arr(1 to 4) := (others => (others => '0'));
  signal event_lane_mask : event_lane_mask_arr(1 to 4) := (others => (others => '1'));
  signal event_timer_active : std_logic_vector(1 to 4) := (others => '0');
  
begin

  GENERATE_FILTERS:
  for I in 1 to 4 generate
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
  for I in 1 to 4 generate
    latch_toggles: toggle port map (signal_in => console_latch(I),
                                    signal_out => console_latch_toggle(I));
                                 
    latch_f_toggles: toggle port map (signal_in => console_latch_f(I),
                                      signal_out => console_latch_f_toggle(I));
    
    clock_toggles: toggle port map (signal_in => console_clock(I),
                                    signal_out => console_clock_toggle(I));
    
    clock_f_toggles: toggle port map (signal_in => console_clock_f(I),
                                      signal_out => console_clock_f_toggle(I));
  end generate GENERATE_TOGGLES;
  
  GENERATE_DELAYS:
  for I in 1 to 4 generate
    clk_delay: clock_delay port map (signal_in => console_clock_f(I),
                                     signal_delayed => console_clock_f_delay(I),
                                     CLK => clk);
  end generate GENERATE_DELAYS; 
  
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
                                     size => controller_size(I),
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
                                      sw => multitap_sw(I),
                                      
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
      uart_data_recieved <= '0';
      buffer_clear <= "00000000";
      buffer_write <= "00000000";
    
			if (uart_byte_waiting = '1' and uart_data_recieved = '0') then
        case uart_state is
          when main_cmd =>
            case data_from_uart is
              when x"66" => -- 'f'
                
                data_receive_mask <= "11111111";
                data_controller_id <= 1;
                data_byte_id <= 1;
                uart_state <= button_data_cmd;
              
              when x"41" => -- 'A'
                
                data_receive_mask <= custom_command_mask(1);
                uart_state <= button_data_cmd;
                data_byte_id <= 1;
                
                if (custom_command_mask(1)(0) = '1') then
                  data_controller_id <= 1;
                elsif (custom_command_mask(1)(1) = '1') then
                  data_controller_id <= 2;
                elsif (custom_command_mask(1)(2) = '1') then
                  data_controller_id <= 3;
                elsif (custom_command_mask(1)(3) = '1') then
                  data_controller_id <= 4;
                elsif (custom_command_mask(1)(4) = '1') then
                  data_controller_id <= 5;
                elsif (custom_command_mask(1)(5) = '1') then
                  data_controller_id <= 6;
                elsif (custom_command_mask(1)(6) = '1') then
                  data_controller_id <= 7;
                elsif (custom_command_mask(1)(7) = '1') then
                  data_controller_id <= 8;
                else
                  uart_state <= main_cmd;
                end if;
              
              when x"42" => -- 'B'
                
                data_receive_mask <= custom_command_mask(2);
                uart_state <= button_data_cmd;
                data_byte_id <= 1;
                
                if (custom_command_mask(2)(0) = '1') then
                  data_controller_id <= 1;
                elsif (custom_command_mask(2)(1) = '1') then
                  data_controller_id <= 2;
                elsif (custom_command_mask(2)(2) = '1') then
                  data_controller_id <= 3;
                elsif (custom_command_mask(2)(3) = '1') then
                  data_controller_id <= 4;
                elsif (custom_command_mask(2)(4) = '1') then
                  data_controller_id <= 5;
                elsif (custom_command_mask(2)(5) = '1') then
                  data_controller_id <= 6;
                elsif (custom_command_mask(2)(6) = '1') then
                  data_controller_id <= 7;
                elsif (custom_command_mask(2)(7) = '1') then
                  data_controller_id <= 8;
                else
                  uart_state <= main_cmd;
                end if;
                
              when x"43" => -- 'C'
                
                data_receive_mask <= custom_command_mask(3);
                uart_state <= button_data_cmd;
                data_byte_id <= 1;
                
                if (custom_command_mask(3)(0) = '1') then
                  data_controller_id <= 1;
                elsif (custom_command_mask(3)(1) = '1') then
                  data_controller_id <= 2;
                elsif (custom_command_mask(3)(2) = '1') then
                  data_controller_id <= 3;
                elsif (custom_command_mask(3)(3) = '1') then
                  data_controller_id <= 4;
                elsif (custom_command_mask(3)(4) = '1') then
                  data_controller_id <= 5;
                elsif (custom_command_mask(3)(5) = '1') then
                  data_controller_id <= 6;
                elsif (custom_command_mask(3)(6) = '1') then
                  data_controller_id <= 7;
                elsif (custom_command_mask(3)(7) = '1') then
                  data_controller_id <= 8;
                else
                  uart_state <= main_cmd;
                end if;
                
              when x"44" => -- 'D'
                
                data_receive_mask <= custom_command_mask(4);
                uart_state <= button_data_cmd;
                data_byte_id <= 1;
                
                if (custom_command_mask(4)(0) = '1') then
                  data_controller_id <= 1;
                elsif (custom_command_mask(4)(1) = '1') then
                  data_controller_id <= 2;
                elsif (custom_command_mask(4)(2) = '1') then
                  data_controller_id <= 3;
                elsif (custom_command_mask(4)(3) = '1') then
                  data_controller_id <= 4;
                elsif (custom_command_mask(4)(4) = '1') then
                  data_controller_id <= 5;
                elsif (custom_command_mask(4)(5) = '1') then
                  data_controller_id <= 6;
                elsif (custom_command_mask(4)(6) = '1') then
                  data_controller_id <= 7;
                elsif (custom_command_mask(4)(7) = '1') then
                  data_controller_id <= 8;
                else
                  uart_state <= main_cmd;
                end if;
              
              when x"52" => -- 'R'
                buffer_clear <= "11111111";
                --uart_state <= main_cmd;
              
              when x"73" => -- 's'
                uart_state <= setup_cmd_data1;
                
              when others =>
              
            end case;
                    
          when button_data_cmd =>
            -- Store this byte of data in the right spot
            if (data_byte_id = 1) then
              buffer_new_data(data_controller_id) <= "111111111111111111111111" & data_from_uart;
            elsif (data_byte_id = 2) then
              buffer_new_data(data_controller_id) <= "1111111111111111" & data_from_uart & buffer_new_data(data_controller_id)(7 downto 0);
            elsif (data_byte_id = 3) then
              buffer_new_data(data_controller_id) <= "11111111" & data_from_uart & buffer_new_data(data_controller_id)(15 downto 0);
            else
              buffer_new_data(data_controller_id) <= data_from_uart & buffer_new_data(data_controller_id)(23 downto 0);
            end if;
            
            -- Do we need to go to the next controller?
            if ((data_byte_id = 1 and controller_size(data_controller_id) = "00") or (data_byte_id = 2 and controller_size(data_controller_id) = "01") or (data_byte_id = 3 and controller_size(data_controller_id) = "10") or data_byte_id = 4) then
              -- Store the data in the fifo
              buffer_write(data_controller_id) <= '1';
              data_byte_id <= 1;
              if (data_controller_id < 2 and data_receive_mask(2) = '1') then
                data_controller_id <= 2;
              elsif (data_controller_id < 3 and data_receive_mask(3) = '1') then
                data_controller_id <= 3;
              elsif (data_controller_id < 4 and data_receive_mask(4) = '1') then
                data_controller_id <= 4;
              elsif (data_controller_id < 5 and data_receive_mask(5) = '1') then
                data_controller_id <= 5;
              elsif (data_controller_id < 6 and data_receive_mask(6) = '1') then
                data_controller_id <= 6;
              elsif (data_controller_id < 7 and data_receive_mask(7) = '1') then
                data_controller_id <= 7;
              elsif (data_controller_id < 8 and data_receive_mask(8) = '1') then
                data_controller_id <= 8;
              else
                uart_state <= main_cmd;
              end if;
            else
              -- Go to the next byte
              data_byte_id <= data_byte_id + 1;
            end if;
         
          when setup_cmd_data1 =>
            setup_cmd_data(1) <= data_from_uart;
            uart_state <= setup_cmd_data2;
         
          when setup_cmd_data2 =>
            case setup_cmd_data(1) is
              when x"41" => -- 'A'
                custom_command_mask(1) <= data_from_uart;
                uart_state <= main_cmd;
              
              when x"42" => -- 'B'
                custom_command_mask(2) <= data_from_uart;
                uart_state <= main_cmd;

              when x"43" => -- 'C'
                custom_command_mask(3) <= data_from_uart;
                uart_state <= main_cmd;

              when x"44" => -- 'D'
                custom_command_mask(4) <= data_from_uart;
                uart_state <= main_cmd;
              
              when x"63" => -- 'c'
                setup_cmd_data(2) <= data_from_uart;
                uart_state <= setup_cmd_data3;
              
              when x"70" => -- 'p'
                setup_cmd_data(2) <= data_from_uart;
                uart_state <= setup_cmd_data3;
              
              when x"65" => -- 'e'
                setup_cmd_data(2) <= data_from_uart;
                uart_state <= setup_cmd_data3;
              
              when others =>
                uart_state <= main_cmd;
              
            end case;
         
          when setup_cmd_data3 =>
            case setup_cmd_data(1) is
              when x"63" => -- 'c'
                case setup_cmd_data(2) is
                  when x"31" => -- '1'
                    controller_connected(1) <= data_from_uart(7);
                    controller_overread_value(1) <= data_from_uart(6);
                    controller_size(1) <= data_from_uart(1 downto 0);

                  when x"32" => -- '2'
                    controller_connected(2) <= data_from_uart(7);
                    controller_overread_value(2) <= data_from_uart(6);
                    controller_size(2) <= data_from_uart(1 downto 0);
                    
                  when x"33" => -- '3'
                    controller_connected(3) <= data_from_uart(7);
                    controller_overread_value(3) <= data_from_uart(6);
                    controller_size(3) <= data_from_uart(1 downto 0);
                    
                  when x"34" => -- '4'
                    controller_connected(4) <= data_from_uart(7);
                    controller_overread_value(4) <= data_from_uart(6);
                    controller_size(4) <= data_from_uart(1 downto 0);
                    
                  when x"35" => -- '5'
                    controller_connected(5) <= data_from_uart(7);
                    controller_overread_value(5) <= data_from_uart(6);
                    controller_size(5) <= data_from_uart(1 downto 0);
                    
                  when x"36" => -- '6'
                    controller_connected(6) <= data_from_uart(7);
                    controller_overread_value(6) <= data_from_uart(6);
                    controller_size(6) <= data_from_uart(1 downto 0);
                    
                  when x"37" => -- '7'
                    controller_connected(7) <= data_from_uart(7);
                    controller_overread_value(7) <= data_from_uart(6);
                    controller_size(7) <= data_from_uart(1 downto 0);
                    
                  when x"38" => -- '8'
                    controller_connected(8) <= data_from_uart(7);
                    controller_overread_value(8) <= data_from_uart(6);
                    controller_size(8) <= data_from_uart(1 downto 0);
                  
                  when others =>
                end case;
              
                uart_state <= main_cmd;
          
              when x"70" => -- 'p'
                case setup_cmd_data(2) is
                  when x"31" => -- '1'
                    case data_from_uart(3 downto 0) is
                      when x"0" =>
                        port_config(1) <= sr_controller;
                      
                      when x"1" =>
                        port_config(1) <= y_cable;
                        
                      when x"2" =>
                        port_config(1) <= multitap_2p;
                        
                      when x"3" =>
                        port_config(1) <= multitap_5p;
                      
                      when x"f" =>
                        port_config(1) <= fourscore;
                        
                      when others => 
                    end case;
                  
                    port_clock_delay(1) <= data_from_uart(7);
                
                  when x"32" => -- '2'
                    case data_from_uart is
                      when x"00" =>
                        port_config(2) <= sr_controller;
                      
                      when x"01" =>
                        port_config(2) <= y_cable;
                        
                      when x"02" =>
                        port_config(2) <= multitap_2p;
                        
                      when x"03" =>
                        port_config(2) <= multitap_5p;
                      
                      when x"ff" =>
                        port_config(2) <= fourscore;
                        
                      when others =>
                    end case;
                    
                    port_clock_delay(2) <= data_from_uart(7);
                    
                
                  when others =>
                
                end case;
                uart_state <= main_cmd;

              when x"65" => -- 'e'
                setup_cmd_data(3) <= data_from_uart;
                uart_state <= setup_cmd_data4;
              
              when others =>
                uart_state <= main_cmd;
            
            end case;
                            
          when setup_cmd_data4 =>
            case setup_cmd_data(1) is
              when x"65" => -- 'e'
                case setup_cmd_data(2) is
                  when x"31" => -- '1'
                    event_enabled(1) <= setup_cmd_data(3)(7);
                    event_timer_restart(1) <= setup_cmd_data(3)(6);
                    event_timer_length(1) <= to_integer(unsigned(setup_cmd_data(3)(5 downto 0)));
                    event_lane_mask(1) <= data_from_uart;
                    
                  when x"32" => -- '2'
                    event_enabled(2) <= setup_cmd_data(3)(7);
                    event_timer_restart(2) <= setup_cmd_data(3)(6);
                    event_timer_length(2) <= to_integer(unsigned(setup_cmd_data(3)(5 downto 0)));
                    event_lane_mask(2) <= data_from_uart;
                    
                  when x"33" => -- '3'
                    event_enabled(3) <= setup_cmd_data(3)(7);
                    event_timer_restart(3) <= setup_cmd_data(3)(6);
                    event_timer_length(3) <= to_integer(unsigned(setup_cmd_data(3)(5 downto 0)));
                    event_lane_mask(3) <= data_from_uart;
                    
                  when x"34" => -- '4'
                    event_enabled(4) <= setup_cmd_data(3)(7);
                    event_timer_restart(4) <= setup_cmd_data(3)(6);
                    event_timer_length(4) <= to_integer(unsigned(setup_cmd_data(3)(5 downto 0)));
                    event_lane_mask(4) <= data_from_uart;
                  
                  when others =>
                  
                end case;
                
              when others =>
              
            end case;
            
            uart_state <= main_cmd;
                                
        end case;
      	uart_data_recieved <= '1';
			end if;
    end if;
	end process;
  
  process (clk) is
    variable latch_q_ms_timer : integer range 0 to 127 := 0;
    -- 0.25ms = 8000 cycles of the 32MHz clock (0.00025 * 32000000)
    variable latch_clk_timer : integer range 0 to 7999 := 0;

    variable new_buffer_read : std_logic_vector(7 downto 0) := "00000000";
    variable event_count : integer range 0 to 255 := 0;
    variable prev_latch : std_logic := '0';
  begin
    if (rising_edge(clk)) then
      -- Start with no advancing
      event_buffer_read_mask(1) <= "00000000";
      
      -- Start timer
      if (console_latch_f(1) /= prev_latch) then
        -- Rising edge of latch
        if (console_latch_f(1) = '1') then
          -- Check timer length, if 0
          if (event_timer_length(1) = 0) then
            if (event_count < 255) then
              event_count := event_count + 1;
              event_buffer_read_mask(1) <= event_lane_mask(1);
              event_timer_active(1) <= '0';
            end if;
          else
            event_timer_active(1) <= '1';
            latch_clk_timer := 0;
            latch_q_ms_timer := 0;
          end if;
        end if;
        prev_latch := console_latch_f(1);
      end if;
      
      -- Check/advance timer
      if (event_timer_active(1) = '1') then
        if (latch_clk_timer = 7999) then
          if (latch_q_ms_timer >= event_timer_length(1)) then
            event_count := event_count + 1;
            event_buffer_read_mask(1) <= event_lane_mask(1);
            event_timer_active(1) <= '0';
          else
            latch_q_ms_timer := latch_q_ms_timer + 1;
            latch_clk_timer := 0;
          end if;
        else
          latch_clk_timer := latch_clk_timer + 1;
        end if;
      end if;
    
      if (event_signal(1) = '1') then
        if (event_received(1) = '1') then
          event_signal(1) <= '0';
        end if;
      else
        if (event_received(1) = '0') then
          if (event_count > 0) then
            event_count := event_count - 1;
            event_signal(1) <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;
  
  process (clk) is
    variable latch_q_ms_timer : integer range 0 to 127 := 0;
    -- 0.25ms = 8000 cycles of the 32MHz clock (0.00025 * 32000000)
    variable latch_clk_timer : integer range 0 to 7999 := 0;

    variable new_buffer_read : std_logic_vector(7 downto 0) := "00000000";
    variable event_count : integer range 0 to 255 := 0;
    variable prev_latch : std_logic := '0';

  begin
    if (rising_edge(clk)) then
      -- Start with no advancing
      event_buffer_read_mask(2) <= "00000000";
      
      -- Start timer
      if (console_latch_f(2) /= prev_latch) then
        -- Rising edge of latch
        if (console_latch_f(2) = '1') then
          -- Check timer length, if 0
          if (event_timer_length(2) = 0) then
            if (event_count < 255) then
              event_count := event_count + 1;
              event_buffer_read_mask(2) <= event_lane_mask(2);
              event_timer_active(2) <= '0';
            end if;
          else
            event_timer_active(2) <= '1';
            latch_clk_timer := 0;
            latch_q_ms_timer := 0;
          end if;
        end if;
        prev_latch := console_latch_f(2);
      end if;
      
      -- Check/advance timer
      if (event_timer_active(2) = '1') then
        if (latch_clk_timer = 7999) then
          if (latch_q_ms_timer >= event_timer_length(2)) then
            event_count := event_count + 1;
            event_buffer_read_mask(2) <= event_lane_mask(2);
            event_timer_active(2) <= '0';
          else
            latch_q_ms_timer := latch_q_ms_timer + 1;
            latch_clk_timer := 0;
          end if;
        else
          latch_clk_timer := latch_clk_timer + 1;
        end if;
      end if;
    
      if (event_signal(2) = '1') then
        if (event_received(2) = '1') then
          event_signal(2) <= '0';
        end if;
      else
        if (event_received(2) = '0') then
          if (event_count > 0) then
            event_count := event_count - 1;
            event_signal(2) <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  process (clk) is
    variable latch_q_ms_timer : integer range 0 to 127 := 0;
    -- 0.25ms = 8000 cycles of the 32MHz clock (0.00025 * 32000000)
    variable latch_clk_timer : integer range 0 to 7999 := 0;

    variable new_buffer_read : std_logic_vector(7 downto 0) := "00000000";
    variable event_count : integer range 0 to 255 := 0;
    variable prev_latch : std_logic := '0';

  begin
    if (rising_edge(clk)) then
      -- Start with no advancing
      event_buffer_read_mask(3) <= "00000000";
      
      -- Start timer
      if (console_latch_f(3) /= prev_latch) then
        -- Rising edge of latch
        if (console_latch_f(3) = '1') then
          -- Check timer length, if 0
          if (event_timer_length(3) = 0) then
            if (event_count < 255) then
              event_count := event_count + 1;
              event_buffer_read_mask(3) <= event_lane_mask(3);
              event_timer_active(3) <= '0';
            end if;
          else
            event_timer_active(3) <= '1';
            latch_clk_timer := 0;
            latch_q_ms_timer := 0;
          end if;
        end if;
        prev_latch := console_latch_f(3);
      end if;
      
      -- Check/advance timer
      if (event_timer_active(3) = '1') then
        if (latch_clk_timer = 7999) then
          if (latch_q_ms_timer >= event_timer_length(3)) then
            event_count := event_count + 1;
            event_buffer_read_mask(3) <= event_lane_mask(3);
            event_timer_active(3) <= '0';
          else
            latch_q_ms_timer := latch_q_ms_timer + 1;
            latch_clk_timer := 0;
          end if;
        else
          latch_clk_timer := latch_clk_timer + 1;
        end if;
      end if;
    
      if (event_signal(3) = '1') then
        if (event_received(3) = '1') then
          event_signal(3) <= '0';
        end if;
      else
        if (event_received(3) = '0') then
          if (event_count > 0) then
            event_count := event_count - 1;
            event_signal(3) <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  process (clk) is
    variable latch_q_ms_timer : integer range 0 to 127 := 0;
    -- 0.25ms = 8000 cycles of the 32MHz clock (0.00025 * 32000000)
    variable latch_clk_timer : integer range 0 to 7999 := 0;

    variable new_buffer_read : std_logic_vector(7 downto 0) := "00000000";
    variable event_count : integer range 0 to 255 := 0;
    variable prev_latch : std_logic := '0';

  begin
    if (rising_edge(clk)) then
      -- Start with no advancing
      event_buffer_read_mask(4) <= "00000000";
      
      -- Start timer
      if (console_latch_f(4) /= prev_latch) then
        -- Rising edge of latch
        if (console_latch_f(4) = '1') then
          -- Check timer length, if 0
          if (event_timer_length(4) = 0) then
            if (event_count < 255) then
              event_count := event_count + 1;
              event_buffer_read_mask(4) <= event_lane_mask(4);
              event_timer_active(4) <= '0';
            end if;
          else
            event_timer_active(4) <= '1';
            latch_clk_timer := 0;
            latch_q_ms_timer := 0;
          end if;
        end if;
        prev_latch := console_latch_f(4);
      end if;
      
      -- Check/advance timer
      if (event_timer_active(4) = '1') then
        if (latch_clk_timer = 7999) then
          if (latch_q_ms_timer >= event_timer_length(4)) then
            event_count := event_count + 1;
            event_buffer_read_mask(4) <= event_lane_mask(4);
            event_timer_active(4) <= '0';
          else
            latch_q_ms_timer := latch_q_ms_timer + 1;
            latch_clk_timer := 0;
          end if;
        else
          latch_clk_timer := latch_clk_timer + 1;
        end if;
      end if;
    
      if (event_signal(4) = '1') then
        if (event_received(4) = '1') then
          event_signal(4) <= '0';
        end if;
      else
        if (event_received(4) = '0') then
          if (event_count > 0) then
            event_count := event_count - 1;
            event_signal(4) <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  
  buffer_read <= (event_buffer_read_mask(1)(0) & event_buffer_read_mask(1)(1) & event_buffer_read_mask(1)(2) & event_buffer_read_mask(1)(3) & event_buffer_read_mask(1)(4) & event_buffer_read_mask(1)(5) & event_buffer_read_mask(1)(6) & event_buffer_read_mask(1)(7)) or 
                 (event_buffer_read_mask(2)(0) & event_buffer_read_mask(2)(1) & event_buffer_read_mask(2)(2) & event_buffer_read_mask(2)(3) & event_buffer_read_mask(2)(4) & event_buffer_read_mask(2)(5) & event_buffer_read_mask(2)(6) & event_buffer_read_mask(2)(7)) or
                 (event_buffer_read_mask(3)(0) & event_buffer_read_mask(3)(1) & event_buffer_read_mask(3)(2) & event_buffer_read_mask(3)(3) & event_buffer_read_mask(3)(4) & event_buffer_read_mask(3)(5) & event_buffer_read_mask(3)(6) & event_buffer_read_mask(3)(7)) or
                 (event_buffer_read_mask(4)(0) & event_buffer_read_mask(4)(1) & event_buffer_read_mask(4)(2) & event_buffer_read_mask(4)(3) & event_buffer_read_mask(4)(4) & event_buffer_read_mask(4)(5) & event_buffer_read_mask(4)(6) & event_buffer_read_mask(4)(7));
  
  
  
  process (clk) is
  begin
    if (rising_edge(clk)) then
      uart_write <= '0';
      
      
      if (event_received(1) = '1') then
        if (event_signal(1) = '0') then
          event_received(1) <= '0';
        end if;
      end if;
      
      if (event_received(2) = '1') then
        if (event_signal(2) = '0') then
          event_received(2) <= '0';
        end if;
      end if;
      
      if (event_received(3) = '1') then
        if (event_signal(3) = '0') then
          event_received(3) <= '0';
        end if;
      end if;
      
      if (event_received(4) = '1') then
        if (event_signal(4) = '0') then
          event_received(4) <= '0';
        end if;
      end if;
      
      if (uart_buffer_full = '0') then
        if (event_received(1) = '0' and event_signal(1) = '1') then
          event_received(1) <= '1';
          uart_write <= '1';
          data_to_uart <= x"66"; -- "f"
        elsif (event_received(2) = '0' and event_signal(2) = '1') then
          event_received(2) <= '1';
          uart_write <= '1';
          data_to_uart <= x"67"; -- "g"
        elsif (event_received(3) = '0' and event_signal(3) = '1') then
          event_received(3) <= '1';
          uart_write <= '1';
          data_to_uart <= x"68"; -- "h"
        elsif (event_received(4) = '0' and event_signal(4) = '1') then
          event_received(4) <= '1';
          uart_write <= '1';
          data_to_uart <= x"69"; -- "i"
        end if;
      end if;
    end if;
  end process;  
  
  console_clock_final(1) <= console_clock_f(1) when port_clock_delay(1) = '0' else
                            console_clock_f_delay(1);
  
  console_clock_final(2) <= console_clock_f(2) when port_clock_delay(2) = '0' else
                            console_clock_f_delay(2);
  
  console_clock_final(3) <= console_clock_f(3) when port_clock_delay(3) = '0' else
                            console_clock_f_delay(3);
  
  console_clock_final(4) <= console_clock_f(4) when port_clock_delay(4) = '0' else
                            console_clock_f_delay(4);
  
  controller_data(1) <= buffer_data(1);
  controller_data(2) <= buffer_data(2);
  controller_data(3) <= buffer_data(3);
  controller_data(4) <= buffer_data(4);
  controller_data(5) <= buffer_data(5);
  controller_data(6) <= buffer_data(6);
  controller_data(7) <= buffer_data(7);
  controller_data(8) <= buffer_data(8);


  console_d0(1) <= controller_d0(1) when port_config(1) = sr_controller else
                   controller_d0(1) when port_config(1) = y_cable else
                   multitap_d0(1)   when port_config(1) = multitap_2p else
                   multitap_d0(1)   when port_config(1) = multitap_5p else
                   '1';

  console_d1(1) <= controller_d1(1) when port_config(1) = sr_controller else
                   controller_d0(2) when port_config(1) = y_cable else
                   multitap_d1(1)   when port_config(1) = multitap_2p else
                   multitap_d1(1)   when port_config(1) = multitap_5p else
                   '1';

  console_d0(2) <= controller_d0(3) when port_config(2) = sr_controller else
                   controller_d0(3) when port_config(2) = y_cable else
                   multitap_d0(2)   when port_config(2) = multitap_2p else
                   multitap_d0(2)   when port_config(2) = multitap_5p else
                   '1';

  console_d1(2) <= controller_d1(3) when port_config(2) = sr_controller else
                   controller_d0(4) when port_config(2) = y_cable else
                   multitap_d1(2)   when port_config(2) = multitap_2p else
                   multitap_d1(2)   when port_config(2) = multitap_5p else
                   '1';
                   
  console_d0(3) <= controller_d0(5) when port_config(3) = sr_controller else
                   controller_d0(5) when port_config(3) = y_cable else
                   '1';

  console_d1(3) <= controller_d1(5) when port_config(3) = sr_controller else
                   controller_d0(6) when port_config(3) = y_cable else
                   '1';

  console_d0(4) <= controller_d0(7) when port_config(4) = sr_controller else
                   controller_d0(7) when port_config(4) = y_cable else
                   '1';

  console_d1(4) <= controller_d1(7) when port_config(4) = sr_controller else
                   controller_d0(8) when port_config(4) = y_cable else
                   '1';
  
  
  console_d0_oe(1) <= controller_d0_oe(1) when port_config(1) = sr_controller else
                      controller_d0_oe(1) when port_config(1) = y_cable else
                      multitap_d0_oe(1)   when port_config(1) = multitap_2p else
                      multitap_d0_oe(1)   when port_config(1) = multitap_5p else
                      '1';
                      
  console_d1_oe(1) <= controller_d1_oe(1) when port_config(1) = sr_controller else
                      controller_d0_oe(2) when port_config(1) = y_cable else
                      multitap_d1_oe(1)   when port_config(1) = multitap_2p else
                      multitap_d1_oe(1)   when port_config(1) = multitap_5p else
                      '1';  
  
  console_d0_oe(2) <= controller_d0_oe(3) when port_config(2) = sr_controller else
                      controller_d0_oe(3) when port_config(2) = y_cable else
                      multitap_d0_oe(2)   when port_config(2) = multitap_2p else
                      multitap_d0_oe(2)   when port_config(2) = multitap_5p else
                      '1';
                      
  console_d1_oe(2) <= controller_d1_oe(3) when port_config(2) = sr_controller else
                      controller_d0_oe(4) when port_config(2) = y_cable else
                      multitap_d1_oe(2)   when port_config(2) = multitap_2p else
                      multitap_d1_oe(2)   when port_config(2) = multitap_5p else
                      '1';  
  
  console_d0_oe(3) <= controller_d0_oe(5) when port_config(3) = sr_controller else
                      controller_d0_oe(5) when port_config(3) = y_cable else
                      '1';
                      
  console_d1_oe(3) <= controller_d1_oe(5) when port_config(3) = sr_controller else
                      controller_d0_oe(6) when port_config(3) = y_cable else
                      '1';  
  
  console_d0_oe(4) <= controller_d0_oe(7) when port_config(4) = sr_controller else
                      controller_d0_oe(7) when port_config(4) = y_cable else
                      '1';
                      
  console_d1_oe(4) <= controller_d1_oe(7) when port_config(4) = sr_controller else
                      controller_d0_oe(8) when port_config(4) = y_cable else
                      '1';
                      
  
  controller_clock(1) <= console_clock_final(1)    when port_config(1) = sr_controller else
                         console_clock_final(1)    when port_config(1) = y_cable else
                         multitap_port_clock(1)(1) when port_config(1) = multitap_2p else
                         multitap_port_clock(1)(1) when port_config(1) = multitap_5p else
                         '1';

  controller_clock(2) <= '1'                       when port_config(1) = sr_controller else
                         console_clock_final(1)    when port_config(1) = y_cable else
                         multitap_port_clock(1)(2) when port_config(1) = multitap_2p else
                         multitap_port_clock(1)(2) when port_config(1) = multitap_5p else
                         '1';

  controller_clock(5) <= console_clock_final(3)    when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = sr_controller) else
                         console_clock_final(3)    when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = y_cable) else
                         multitap_port_clock(1)(3) when port_config(1) = multitap_2p else
                         multitap_port_clock(1)(3) when port_config(1) = multitap_5p else
                         '1';
  
  controller_clock(6) <= '1'                       when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = sr_controller) else
                         console_clock_final(3)    when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = y_cable) else
                         multitap_port_clock(1)(4) when port_config(1) = multitap_2p else
                         multitap_port_clock(1)(4) when port_config(1) = multitap_5p else
                         '1';
  
  controller_clock(3) <= console_clock_final(2)    when port_config(2) = sr_controller else
                         console_clock_final(2)    when port_config(2) = y_cable else
                         multitap_port_clock(2)(1) when port_config(2) = multitap_2p else
                         multitap_port_clock(2)(1) when port_config(2) = multitap_5p else
                         '1';

  controller_clock(4) <= '1'                       when port_config(2) = sr_controller else
                         console_clock_final(2)    when port_config(2) = y_cable else
                         multitap_port_clock(2)(2) when port_config(2) = multitap_2p else
                         multitap_port_clock(2)(2) when port_config(2) = multitap_5p else
                         '1';

  controller_clock(7) <= console_clock_final(4)    when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = sr_controller) else
                         console_clock_final(4)    when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = y_cable) else
                         '1'                       when port_config(2) = y_cable else
                         multitap_port_clock(2)(3) when port_config(2) = multitap_2p else
                         multitap_port_clock(2)(3) when port_config(2) = multitap_5p else
                         '1';
  
  controller_clock(8) <= '1'                       when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = sr_controller) else
                         console_clock_final(4)    when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = y_cable) else
                         multitap_port_clock(2)(4) when port_config(2) = multitap_2p else
                         multitap_port_clock(2)(4) when port_config(2) = multitap_5p else
                         '1';


  controller_latch(1) <= console_latch_f(1)        when port_config(1) = sr_controller else
                         console_latch_f(1)        when port_config(1) = y_cable else
                         multitap_port_latch(1)(1) when port_config(1) = multitap_2p else
                         multitap_port_latch(1)(1) when port_config(1) = multitap_5p else
                         '0';
  
  controller_latch(2) <= '0'                       when port_config(1) = sr_controller else
                         console_latch_f(1)        when port_config(1) = y_cable else
                         multitap_port_latch(1)(2) when port_config(1) = multitap_2p else
                         multitap_port_latch(1)(2) when port_config(1) = multitap_5p else
                         '0';

  controller_latch(5) <= console_latch_f(3)        when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = sr_controller) else
                         console_latch_f(3)        when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = y_cable) else
                         multitap_port_latch(1)(3) when port_config(1) = multitap_2p else
                         multitap_port_latch(1)(3) when port_config(1) = multitap_5p else
                         '0';

  controller_latch(6) <= '0'                       when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = sr_controller) else
                         console_latch_f(3)        when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = y_cable) else
                         multitap_port_latch(1)(4) when port_config(1) = multitap_2p else
                         multitap_port_latch(1)(4) when port_config(1) = multitap_5p else
                         '0';

  controller_latch(3) <= console_latch_f(2)        when port_config(2) = sr_controller else
                         console_latch_f(2)        when port_config(2) = y_cable else
                         multitap_port_latch(2)(1) when port_config(2) = multitap_2p else
                         multitap_port_latch(2)(1) when port_config(2) = multitap_5p else
                         '0';
  
  controller_latch(4) <= '0'                       when port_config(2) = sr_controller else
                         console_latch_f(2)        when port_config(2) = y_cable else
                         multitap_port_latch(2)(2) when port_config(2) = multitap_2p else
                         multitap_port_latch(2)(2) when port_config(2) = multitap_5p else
                         '0';

  controller_latch(7) <= console_latch_f(4)        when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = sr_controller) else
                         console_latch_f(4)        when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = y_cable) else
                         multitap_port_latch(2)(3) when port_config(2) = multitap_2p else
                         multitap_port_latch(2)(3) when port_config(2) = multitap_5p else
                         '0';

  controller_latch(8) <= '0'                       when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = sr_controller) else
                         console_latch_f(4)        when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = y_cable) else
                         multitap_port_latch(2)(4) when port_config(2) = multitap_2p else
                         multitap_port_latch(2)(4) when port_config(2) = multitap_5p else
                         '0';


  controller_io(1) <= console_io_f(1)        when port_config(1) = sr_controller else
                      console_io_f(1)        when port_config(1) = y_cable else
                      multitap_port_io(1)(1) when port_config(1) = multitap_2p else
                      multitap_port_io(1)(1) when port_config(1) = multitap_5p else
                      '1';

  controller_io(2) <= '1'                    when port_config(1) = sr_controller else
                      console_io_f(1)        when port_config(1) = y_cable else
                      multitap_port_io(1)(2) when port_config(1) = multitap_2p else
                      multitap_port_io(1)(2) when port_config(1) = multitap_5p else
                      '1';

  controller_io(5) <= console_io_f(3)        when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = sr_controller) else
                      console_io_f(3)        when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = y_cable) else
                      multitap_port_io(1)(3) when port_config(1) = multitap_2p else
                      multitap_port_io(1)(3) when port_config(1) = multitap_5p else
                      '1';

  controller_io(6) <= '1'                    when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = sr_controller) else
                      console_io_f(3)        when ((port_config(1) = sr_controller or port_config(1) = y_cable) and port_config(3) = y_cable) else
                      multitap_port_io(1)(4) when port_config(1) = multitap_2p else
                      multitap_port_io(1)(4) when port_config(1) = multitap_5p else
                      '1';

  controller_io(3) <= console_io_f(2)        when port_config(2) = sr_controller else
                      console_io_f(2)        when port_config(2) = y_cable else
                      multitap_port_io(2)(1) when port_config(2) = multitap_2p else
                      multitap_port_io(2)(1) when port_config(2) = multitap_5p else
                      '1';

  controller_io(4) <= '1'                    when port_config(2) = sr_controller else
                      console_io_f(1)        when port_config(2) = y_cable else
                      multitap_port_io(2)(2) when port_config(2) = multitap_2p else
                      multitap_port_io(2)(2) when port_config(2) = multitap_5p else
                      '1';

  controller_io(7) <= console_io_f(4)        when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = sr_controller) else
                      console_io_f(4)        when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = y_cable) else
                      multitap_port_io(2)(3) when port_config(2) = multitap_2p else
                      multitap_port_io(2)(3) when port_config(2) = multitap_5p else
                      '1';

  controller_io(8) <= '1'                    when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = sr_controller) else
                      console_io_f(4)        when ((port_config(2) = sr_controller or port_config(2) = y_cable) and port_config(4) = y_cable) else
                      multitap_port_io(2)(4) when port_config(2) = multitap_2p else
                      multitap_port_io(2)(4) when port_config(2) = multitap_5p else
                      '1';
  
  
  multitap_sw(1) <= '1'                    when port_config(1) = multitap_5p else
                    '0';
  
  multitap_sw(2) <= '1'                    when port_config(2) = multitap_5p else
                    '0';
  
  
  multitap_clock(1) <= console_clock_final(1);
  multitap_latch(1) <= console_latch_f(1);
  multitap_io(1) <= console_io_f(1);
  
  multitap_clock(2) <= console_clock_final(2);
  multitap_latch(2) <= console_latch_f(2);
  multitap_io(2) <= console_io_f(2);
  
  
  multitap_port_d0(1)(1) <= controller_d0(1);
  multitap_port_d0(1)(2) <= controller_d0(2);
  multitap_port_d0(1)(3) <= controller_d0(5);
  multitap_port_d0(1)(4) <= controller_d0(6);
  
  multitap_port_d1(1)(1) <= controller_d1(1);
  multitap_port_d1(1)(2) <= controller_d1(2);
  multitap_port_d1(1)(3) <= controller_d1(5);
  multitap_port_d1(1)(4) <= controller_d1(6);
  
  
  multitap_port_d0_oe(1)(1) <= controller_d0_oe(1);
  multitap_port_d0_oe(1)(2) <= controller_d0_oe(2);
  multitap_port_d0_oe(1)(3) <= controller_d0_oe(5);
  multitap_port_d0_oe(1)(4) <= controller_d0_oe(6);

  multitap_port_d1_oe(1)(1) <= controller_d1_oe(1);
  multitap_port_d1_oe(1)(2) <= controller_d1_oe(2);
  multitap_port_d1_oe(1)(3) <= controller_d1_oe(5);
  multitap_port_d1_oe(1)(4) <= controller_d1_oe(6);
  
  
  multitap_port_d0(2)(1) <= controller_d0(3);
  multitap_port_d0(2)(2) <= controller_d0(4);
  multitap_port_d0(2)(3) <= controller_d0(7);
  multitap_port_d0(2)(4) <= controller_d0(8);
  
  multitap_port_d1(2)(1) <= controller_d1(3);
  multitap_port_d1(2)(2) <= controller_d1(4);
  multitap_port_d1(2)(3) <= controller_d1(7);
  multitap_port_d1(2)(4) <= controller_d1(8);
  
  
  multitap_port_d0_oe(2)(1) <= controller_d0_oe(3);
  multitap_port_d0_oe(2)(2) <= controller_d0_oe(4);
  multitap_port_d0_oe(2)(3) <= controller_d0_oe(7);
  multitap_port_d0_oe(2)(4) <= controller_d0_oe(8);

  multitap_port_d1_oe(2)(1) <= controller_d1_oe(3);
  multitap_port_d1_oe(2)(2) <= controller_d1_oe(4);
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

