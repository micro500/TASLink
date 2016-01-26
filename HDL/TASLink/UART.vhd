library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity UART is
    Port ( rx_data_out : out STD_LOGIC_VECTOR (7 downto 0);
           rx_data_was_recieved : in STD_LOGIC;
           rx_byte_waiting : out STD_LOGIC;
           clk : in  STD_LOGIC;
			  rx_in : in STD_LOGIC;
			  
			  tx_data_in : in STD_LOGIC_VECTOR (7 downto 0);
           tx_buffer_full : out STD_LOGIC;
           tx_write : in STD_LOGIC;
			  tx_out : out STD_LOGIC);
end UART;

architecture Behavioral of UART is
	signal rx_bit_buffer : std_logic_vector (39 downto 0) := (others => '1');
	signal rx_baud : std_logic := '0';
	signal rx_baud_counter : integer range 0 to 813;
	
	signal rx_data : STD_LOGIC_VECTOR (7 downto 0) := (others => '1');
	
	signal new_byte_waiting_from_buffer : std_logic := '0';
	signal new_byte_waiting_for_external : std_logic := '0';
	signal save_next_byte : std_logic := '1';
	
	signal prev_write_val : std_logic := '0';
	
	signal tx_buffer : std_logic_vector (10 downto 0) := (others => '1');
	signal writing : std_logic := '0';
	
	signal tx_baud_counter : integer range 0 to 3254;
	signal tx_bit_counter : integer range 0 to 13;
	signal new_byte_to_send : std_logic := '0';
begin

tx_ack: process (clk)
	begin
		if (rising_edge(clk)) then
			if (tx_write = '1' and prev_write_val = '0' and writing = '0') then
				new_byte_to_send <= '1';
				prev_write_val <= '1';
			elsif (tx_write = '0' and prev_write_val = '1') then
				prev_write_val <= '0';
				new_byte_to_send <= '0';
			else
				new_byte_to_send <= '0';
			end if;
		end if;
	end process;

tx: process (clk)
	begin
		if (rising_edge(clk)) then
			if (writing = '0' and new_byte_to_send = '1') then
				tx_buffer <= tx_data_in & "011";
				writing <= '1';
				tx_bit_counter <= 0;
				tx_baud_counter <= 0;
			elsif (writing = '1') then
				if (tx_baud_counter = 3254) then
					tx_buffer <= '1' & tx_buffer(10 downto 1);
					
					if (tx_bit_counter = 13) then
						writing <= '0';
					else
						tx_bit_counter <= tx_bit_counter + 1;
					end if;
					tx_baud_counter <= 0;
				else
					tx_baud_counter <= tx_baud_counter + 1;
				end if;
			end if;
		end if;
	end process;

tx_out <= tx_buffer(0);
tx_buffer_full <= writing;

rx_ack: process (clk)
	begin
		if (rising_edge(clk)) then
			if (rx_data_was_recieved = '1') then
				save_next_byte <= '1';
				new_byte_waiting_for_external <= '0';
			elsif (new_byte_waiting_from_buffer = '1') then
				save_next_byte <= '0';
				new_byte_waiting_for_external <= '1';
			end if;
		end if;
	end process;
	
rx: process (clk)
	begin
		if (rising_edge(clk)) then
			if (rx_baud_counter = 813) then
				if (rx_bit_buffer(38 downto 37) = "11" and
					 rx_bit_buffer(34) = rx_bit_buffer(33) and
					 rx_bit_buffer(30) = rx_bit_buffer(29) and
					 rx_bit_buffer(26) = rx_bit_buffer(25) and
					 rx_bit_buffer(22) = rx_bit_buffer(21) and
					 rx_bit_buffer(18) = rx_bit_buffer(17) and
					 rx_bit_buffer(14) = rx_bit_buffer(13) and
					 rx_bit_buffer(10) = rx_bit_buffer(9) and
					 rx_bit_buffer(6) = rx_bit_buffer(5) and
					 rx_bit_buffer(2 downto 1) = "00") then
						 if (save_next_byte = '1') then
							 rx_data <= rx_bit_buffer(34) & rx_bit_buffer(30) & rx_bit_buffer(26) & rx_bit_buffer(22) & rx_bit_buffer(18) & rx_bit_buffer(14) & rx_bit_buffer(10) & rx_bit_buffer(6);
							 new_byte_waiting_from_buffer <= '1';
						 end if;
				       rx_bit_buffer <= (others => '1');
				else
					rx_bit_buffer <= rx_in & rx_bit_buffer(39 downto 1);
					new_byte_waiting_from_buffer <= '0';
				end if;
				rx_baud_counter <= 0;
			else
				new_byte_waiting_from_buffer <= '0';
				rx_baud_counter <= rx_baud_counter + 1;
			end if;
		end if;
	end process;
	
-- new_byte_waiting
rx_byte_waiting <= new_byte_waiting_for_external;

-- data out
rx_data_out <= rx_data;

end Behavioral;

