library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity shift_register is
    Port ( latch : in  STD_LOGIC;
           clock : in  STD_LOGIC;
           din : in  STD_LOGIC_VECTOR (7 downto 0);
           dout : out  STD_LOGIC;
           sin : in STD_LOGIC;
           clk : in std_logic);
end shift_register;

architecture Behavioral of shift_register is
  signal latched_data : std_logic_vector(7 downto 0) := "11111111";
  signal prev_clk : std_logic := '1';
begin
shift_out: process(clk)
  begin
    if (rising_edge(clk)) then
      if (latch = '1') then
        latched_data <= din;
      elsif (clock /= prev_clk and clock = '1') then
        latched_data <= latched_data(6 downto 0) & sin;
      end if;
      
      prev_clk <= clock;
    end if;
  end process;

dout <= latched_data(7);

end Behavioral;

