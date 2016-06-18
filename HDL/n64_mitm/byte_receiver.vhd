library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity byte_receiver is
    Port ( new_bit : in  STD_LOGIC;
           bit_val : in  STD_LOGIC_VECTOR (1 downto 0);
           new_byte : out  STD_LOGIC;
           byte_val : out  STD_LOGIC_VECTOR (7 downto 0);
           CLK : in  STD_LOGIC);
end byte_receiver;

architecture Behavioral of byte_receiver is
  type rx_modes is (idle_mode, receive_mode);
  signal rx_mode : rx_modes := idle_mode;


  signal rx_data : std_logic_vector(7 downto 0);
  signal rx_timer : integer range 0 to 160 := 0;
  signal bit_count : integer range 0 to 7 := 0;

  signal new_byte_temp : std_logic := '0';

begin
  process (clk)
  begin
    if (rising_edge(clk)) then
      new_byte_temp <= '0';
      if (rx_mode = idle_mode) then
        if (new_bit = '1' and (bit_val = "00" or bit_val = "01")) then
          rx_data <= "0000000" & bit_val(0);
          rx_timer <= 0;
          rx_mode <= receive_mode;
          bit_count <= 1;
        end if;
      else
        if (new_bit = '1' and (bit_val = "00" or bit_val = "01")) then
          rx_data <= rx_data(6 downto 0) & bit_val(0);
          if (bit_count = 7) then
            rx_mode <= idle_mode;
            new_byte_temp <= '1';
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

new_byte <= new_byte_temp;
byte_val <= rx_data;

end Behavioral;

