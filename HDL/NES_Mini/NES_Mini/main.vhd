library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;


entity main is
    Port ( clk : in  STD_LOGIC;
           RX : in  STD_LOGIC;
           TX_real : out  STD_LOGIC;
           
           console_d0_oe : out STD_LOGIC_VECTOR(1 to 2);
           console_d0_out : out STD_LOGIC_VECTOR(1 to 2);
           console_d1_oe : out STD_LOGIC_VECTOR(1 to 2);
           console_d1_out : out STD_LOGIC_VECTOR(1 to 2);
           console_clock_oe : out STD_LOGIC_VECTOR(1 to 2);
           console_clock_out : out STD_LOGIC_VECTOR(1 to 2);
           console_d0_in : in STD_LOGIC_VECTOR(1 to 2);
           console_clock_in : in STD_LOGIC_VECTOR(1 to 2);
           debug : inout STD_LOGIC_VECTOR(7 downto 0);

           visualization_clock : out STD_LOGIC_VECTOR(1 to 2);
           visualization_latch : out STD_LOGIC_VECTOR(1 to 2);
           visualization_d1 : out STD_LOGIC_VECTOR(1 to 2);
           visualization_d0 : out STD_LOGIC_VECTOR(1 to 2));
end main;

architecture Behavioral of main is

  component filter is
    Port ( signal_in : in  STD_LOGIC;
           clk : in  STD_LOGIC;
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
  
  component fifo is
    Port ( data_in : in  STD_LOGIC_VECTOR (15 downto 0);
           write_en : in  STD_LOGIC;
           data_out : out  STD_LOGIC_VECTOR (15 downto 0);
           read_en : in  STD_LOGIC;
           clk : in  STD_LOGIC;
           empty : out  STD_LOGIC;
           full : out  STD_LOGIC;
           clear : in  STD_LOGIC);
  end component;

  signal console_d0_in_f : std_logic_vector(1 to 2);
  signal console_clock_in_f : std_logic_vector(1 to 2);
  
  signal vsync_in_f : std_logic;



  type i2c_states is (idle, reading_addr, wait_for_addr_ack, addr_ack_high, reading, wait_for_read_ack, read_ack_high, wait_for_vsync, wait_for_vsync_timer, writing, wait_for_write_ack, write_ack_high, ignore);
  signal i2c_state : i2c_states := idle;

  signal last_sclk : std_logic := '1';
  
  signal bits_finished : integer range 0 to 8 := 0;
  signal bytes_received : integer range 0 to 8 := 0;
  signal bits_written : integer range 0 to 240 := 0;
  
  signal i2c_tx_data : std_logic_vector(167 downto 0) := (others => '0');

  signal i2c_addr_rx_data : std_logic_vector(7 downto 0) := (others => '0');
  
  signal i2c_rx_data : std_logic_vector(7 downto 0) := (others => '0');
  
  signal last_command : std_logic_vector(7 downto 0) := (others => '1');
  
  signal clk_high_timer : integer range 0 to 320 := 0;
  
  signal toggle_signal : std_logic := '0';
  signal toggle_signal2 : std_logic := '0';
  
  type vector8 is array (natural range <>) of std_logic_vector(7 downto 0);
  signal data0 : vector8(1 to 2) := (others => x"80");
  signal data1 : vector8(1 to 2) := (others => x"80");
  signal data2 : vector8(1 to 2) := (others => x"80");
  signal data3 : vector8(1 to 2) := (others => x"80");
  signal data6 : vector8(1 to 2) := (others => x"FF");
  signal data7 : vector8(1 to 2) := (others => x"FF");
  
  signal fake_vsync : std_logic := '1';
  signal fake_vsync_counter : integer range 0 to 793894 := 0;
  
  signal last_vsync : std_logic := '1';
  
  signal empty_input : std_logic := '0';
  signal prev_vsync : std_logic := '1'; 
  
  signal prev_vsync_in_f : std_logic := '1';
  
  type change_sig_states is (wait_vsync1_0, wait_vsync1_1, wait_vsync2_0, wait_vsync2_1, wait_timer_0, wait_timer_1, wait_vsync3_0, wait_vsync3_1, wait_timer2, wait_timer3_0, wait_timer3_1);
  signal change_sig_state : change_sig_states := wait_vsync1_0;

  signal change_sig_timer : integer range 0 to 3200000 := 0;
  
  signal data_from_uart : STD_LOGIC_VECTOR (7 downto 0);
  signal uart_data_recieved : STD_LOGIC := '0';
  signal uart_byte_waiting : STD_LOGIC := '0';
  
  signal data_to_uart : STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
  signal uart_buffer_full : STD_LOGIC;
  signal uart_write : STD_LOGIC := '0';
  
  type uart_states is (main_cmd, reset_data, button_data_cmd, setup_cmd_data1, setup_cmd_data2, setup_cmd_data3, setup_cmd_data4);
  signal uart_state : uart_states := main_cmd;
  signal data_controller_id : integer range 1 to 2;
  signal data_byte_id : integer range 1 to 2;



  type uart_tx_states is (wait_tx_buffer, wait_timer);
  signal uart_tx_state : uart_tx_states := wait_tx_buffer;
  signal uart_tx_timer : integer range 0 to 3200000 := 0;
  
  signal TX : std_logic := '0';
  
  signal hz_timer_length : integer range 0 to 3200000 := 32000;
  signal hz_timer_ms10 : integer range 0 to 255 := 10;
  
  signal button_state : integer range 0 to 3 := 0;
  
  
  type vector16 is array (natural range <>) of std_logic_vector(15 downto 0);
  signal buffer_new_data : vector16(1 to 2);
  signal buffer_write : std_logic_vector(1 to 2);
  signal buffer_data : vector16(1 to 2);
  signal buffer_read : std_logic_vector(1 to 2);
  signal buffer_empty : std_logic_vector(1 to 2);
  signal buffer_full : std_logic_vector(1 to 2);
  signal buffer_clear : std_logic_vector(2 downto 1);
  
  signal first_poll : std_logic := '0';

begin

  uart1: UART port map (rx_data_out => data_from_uart,
                        rx_data_was_recieved => uart_data_recieved,
                        rx_byte_waiting => uart_byte_waiting,
                        clk => CLK,
                        rx_in => RX,
                        tx_data_in => data_to_uart,
                        tx_buffer_full => uart_buffer_full,
                        tx_write => uart_write,
                        tx_out => TX);


  
    vsync_filter: filter port map (signal_in => debug(7),
                                   clk => CLK,
                                   signal_out => vsync_in_f);
  GENERATE_CONTROLLERS:
  for I in 1 to 2 generate                                 
    data_filter: filter port map (signal_in => console_d0_in(I),
                                  clk => CLK,
                                  signal_out => console_d0_in_f(I));
                                   
    clock_filter: filter port map (signal_in => console_clock_in(I),
                                   clk => CLK,
                                   signal_out => console_clock_in_f(I));

    buffers: fifo port map ( data_in => buffer_new_data(I),
                             write_en => buffer_write(I),
                             data_out => buffer_data(I),
                             read_en => buffer_read(I),
                             clk => clk,
                             empty => buffer_empty(I),
                             full => buffer_full(I),
                             clear => buffer_clear(I));
  end generate GENERATE_CONTROLLERS;

  
  
  uart_recieve_btye: process(CLK)
	begin
		if (rising_edge(CLK)) then
      uart_data_recieved <= '0';
      buffer_clear <= "00";
      buffer_write <= "00";
    
			if (uart_byte_waiting = '1' and uart_data_recieved = '0') then
        case uart_state is
          when main_cmd =>
            case data_from_uart is
              when x"66" => -- 'f'
                
                data_controller_id <= 1;
                uart_state <= button_data_cmd;
              
              when x"52" => -- 'R'
                buffer_clear <= "11";
                --uart_state <= main_cmd;
              
              when others =>
              
            end case;

          when button_data_cmd =>
            -- Store this byte of data in the right spot
            if (data_byte_id = 1) then
              buffer_new_data(data_controller_id) <= "11111111" & data_from_uart;
            else
              buffer_new_data(data_controller_id) <= data_from_uart & buffer_new_data(data_controller_id)(7 downto 0);
            end if;
            
            -- Do we need to go to the next controller?
            if (data_byte_id = 2 ) then
              -- Store the data in the fifo
              buffer_write(data_controller_id) <= '1';
              data_byte_id <= 1;
              if (data_controller_id = 1) then
                data_controller_id <= 2;
              else
                uart_state <= main_cmd;
              end if;
            else
              -- Go to the next byte
              data_byte_id <= data_byte_id + 1;
            end if;
          when others =>
            uart_state <= main_cmd;
                                
        end case;
      	uart_data_recieved <= '1';
			end if;
    end if;
	end process;

  process(CLK)
	begin
		if (rising_edge(CLK)) then
      uart_write <= '0';
      buffer_read <= "00";

      if (fake_vsync /= prev_vsync and fake_vsync = '0') then
        if (uart_write = '0' and uart_buffer_full = '0') then
          uart_write <= '1';
          data_to_uart <= x"66"; -- 'f'
        end if;
        
        buffer_read <= "11";
        
        data6(1) <= buffer_data(1)(0) & buffer_data(1)(2) & '1' & buffer_data(1)(5) & buffer_data(1)(8) & buffer_data(1)(4) & '1' & '1';
        data7(1) <= '1' & buffer_data(1)(6) & '1' & buffer_data(1)(7) & '1' & '1' & buffer_data(1)(1) & buffer_data(1)(3);
        
        data6(2) <= buffer_data(2)(0) & buffer_data(2)(2) & '1' & buffer_data(2)(5) & buffer_data(2)(8) & buffer_data(2)(4) & '1' & '1';
        data7(2) <= '1' & buffer_data(2)(6) & '1' & buffer_data(2)(7) & '1' & '1' & buffer_data(2)(1) & buffer_data(2)(3);
      end if;
      
      prev_vsync <= fake_vsync;

    end if;
	end process;  
  
  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (change_sig_state = wait_vsync1_0) then
        if (vsync_in_f /= prev_vsync_in_f and vsync_in_f = '0') then
          change_sig_timer <= 0;
          change_sig_state <= wait_timer3_0;
        end if;
      elsif (change_sig_state = wait_timer3_0) then
        if (change_sig_timer = hz_timer_length) then
          change_sig_timer <= 0;
          change_sig_state <= wait_timer3_1;
          fake_vsync <= '0';
        else
          change_sig_timer <= change_sig_timer + 1;
        end if;
      elsif (change_sig_state = wait_timer3_1) then
        if (change_sig_timer = 6106) then
          change_sig_state <= wait_vsync1_0;
          change_sig_timer <= 0;
          fake_vsync <= '1';
        else
          change_sig_timer <= change_sig_timer + 1;
        end if;
      end if;
      
      prev_vsync_in_f <= vsync_in_f;
    end if;
  end process;


  process (clk) is
  begin
    if (rising_edge(clk)) then
      case i2c_state is
        when idle =>
          console_clock_oe(1) <= '1';
          console_d0_OE(1) <= '1';
          clk_high_timer <= 0;
          
          if (console_clock_in_f(1) /= last_sclk and console_clock_in_f(1) = '0') then
            i2c_state <= reading_addr;
            bits_finished <= 0;
            i2c_addr_rx_data <= (others => '0');
          end if;
          
        when reading_addr =>
          if (console_clock_in_f(1) /= last_sclk) then
            if (console_clock_in_f(1) = '1') then
              i2c_addr_rx_data <= i2c_addr_rx_data(6 downto 0) & console_d0_in_f(1);
              bits_finished <= bits_finished + 1;
            else
              
              if (bits_finished = 8) then
                if (i2c_addr_rx_data(7 downto 1) = "1010010") then
                  i2c_state <= wait_for_addr_ack;
                  console_d0_oe(1) <= '0';
                else
                  i2c_state <= ignore;
                end if;
              end if;
              
            end if;
          end if;
        
        when wait_for_addr_ack =>
          if (console_clock_in_f(1) /= last_sclk and console_clock_in_f(1) = '1') then
            i2c_state <= addr_ack_high;
          end if;
          
        when addr_ack_high =>
          if (console_clock_in_f(1) /= last_sclk and console_clock_in_f(1) = '0') then
            if (i2c_addr_rx_data(0) = '0') then
              i2c_state <= reading;
              i2c_rx_data <= (others => '0');
              bytes_received <= 0;
              
              console_d0_oe(1) <= '1';
            else
              i2c_state <= writing;
              i2c_tx_data <= (others => '0');
              if (last_command = x"FA") then
                i2c_tx_data(167 downto 120) <= x"01" & x"00" & x"A4" & x"20" & x"03" & x"01";
              elsif (last_command = x"00") then
                  i2c_tx_data(167 downto 104) <= data0(1) & data1(1) & data2(1) & data3(1) & x"00" & x"00" & data6(1) & data7(1);
                  i2c_state <= wait_for_vsync;
                  console_clock_OE(1) <= '0';
                  console_d0_oe(1) <= '1';
              end if;
              
            end if;

            bits_finished <= 0;
            
          end if;
          
        when reading =>
          if (console_clock_in_f(1) /= last_sclk) then
            if (console_clock_in_f(1) = '1') then
              i2c_rx_data <= i2c_rx_data(6 downto 0) & console_d0_in_f(1);
              bits_finished <= bits_finished + 1;
            else
              if (bits_finished = 8) then
              
                if (bytes_received = 0) then
                  last_command <= i2c_rx_data;
                end if;
                
                bytes_received <= bytes_received + 1;
                i2c_state <= wait_for_read_ack;
                console_d0_oe(1) <= '0';
              end if;
            end if;
          end if;
          
        when wait_for_read_ack =>
          if (console_clock_in_f(1) /= last_sclk and console_clock_in_f(1) = '1') then
            i2c_state <= read_ack_high;
          end if;
          
        when read_ack_high =>
          if (console_clock_in_f(1) /= last_sclk and console_clock_in_f(1) = '0') then
            i2c_state <= reading;

            console_d0_oe(1) <= '1';
            bits_finished <= 0;
          end if;
        
        when writing =>
          console_d0_oe(1) <= i2c_tx_data(167);
          
          if (console_clock_in_f(1) /= last_sclk) then
            if (console_clock_in_f(1) = '1') then
              bits_finished <= bits_finished + 1;
            else
              i2c_tx_data <= i2c_tx_data(166 downto 0) & '0';
              if (bits_finished = 8) then
                i2c_state <= wait_for_write_ack;
                console_d0_oe(1) <= '1';
              end if;
              
            end if;
          end if;
        
        when wait_for_write_ack =>
          if (console_clock_in_f(1) /= last_sclk and console_clock_in_f(1) = '1') then
            i2c_state <= write_ack_high;
          end if;

        when write_ack_high =>
          if (console_clock_in_f(1) /= last_sclk and console_clock_in_f(1) = '0') then
            i2c_state <= writing;

            bits_finished <= 0;
          end if;
        
        when wait_for_vsync =>
          if (fake_vsync /= last_vsync and fake_vsync = '0') then
            i2c_state <= writing;

            bits_finished <= 0;
            console_clock_OE(1) <= '1';
          end if;

        
        when ignore =>
        
        when others =>
        
      end case;

      if (i2c_state /= idle and console_clock_in_f(1) = '1') then
        if (clk_high_timer = 320) then
          i2c_state <= idle;
        else
          clk_high_timer <= clk_high_timer + 1;
        end if;
      elsif (console_clock_in_f(1) = '0') then
        clk_high_timer <= 0;
      end if;
      
      last_sclk <= console_clock_in_f(1);
      last_vsync <= fake_vsync;
    end if;
  end process;

console_d0_out(1) <= '0';
console_d0_out(2) <= '0';
console_d1_out(1) <= '1';
console_d1_out(2) <= '1';

console_d1_oe(1) <= '0';
console_d1_oe(2) <= '0';

console_clock_out(1) <= '0';
console_clock_out(2) <= '0';

--fake_vsync <= vsync_in_f;

debug(0) <= fake_vsync;
debug(1) <= TX;
debug(2) <= RX;
debug(3) <= debug(7);
debug(4) <= '0';
debug(5) <= '0';
debug(6) <= '0';
--debug(7) <= '0';

visualization_d0 <= "00";
visualization_d1 <= "00";
visualization_clock <= "00";
visualization_latch <= "00";

console_clock_oe(2) <= '1';
console_d0_oe(2) <= '1';

TX_real <= TX;

end Behavioral;

