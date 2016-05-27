library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity visualization is
    Port ( clk : in  STD_LOGIC;
           data1 : in  STD_LOGIC_VECTOR (15 downto 0);
           data2 : in  STD_LOGIC_VECTOR (15 downto 0);
           data3 : in  STD_LOGIC_VECTOR (15 downto 0);
           data4 : in  STD_LOGIC_VECTOR (15 downto 0);
           latch : out  STD_LOGIC;
           clock : out  STD_LOGIC;
           d0 : out  STD_LOGIC;
           d1 : out  STD_LOGIC;
           d2 : out  STD_LOGIC;
           d3 : out  STD_LOGIC);
end visualization;

architecture Behavioral of visualization is
  signal counter : integer range 0 to 39 := 0;
  signal latched_data1 : std_logic_vector(15 downto 0) := (others => '0');
  signal latched_data2 : std_logic_vector(15 downto 0) := (others => '0');
  signal latched_data3 : std_logic_vector(15 downto 0) := (others => '0');
  signal latched_data4 : std_logic_vector(15 downto 0) := (others => '0');
begin

process (CLK)
  variable cycle_count : integer range 0 to 15 := 0;
begin
  if (rising_edge(CLK)) then
    if (cycle_count = 15) then
      if (counter = 39) then
        counter <= 0;
        latched_data1 <= data1;
        latched_data2 <= data2;
        latched_data3 <= data3;
        latched_data4 <= data4;
      else
        counter <= counter + 1;
      end if;
      
      cycle_count := 0;
    else
      cycle_count := cycle_count + 1;
    end if;
  end if;
end process;


latch <= '1' when (counter = 34 or counter = 35 or counter = 36 or counter = 37) else
         '0';

clock <= '1' when (counter = 1 or counter = 3 or counter = 5 or counter = 7 or counter = 9 or counter = 11 or counter = 13 or counter = 15 or counter = 17 or counter = 19 or counter = 21 or counter = 23 or counter = 25 or counter = 27 or counter = 29 or counter = 31) else
         '0';

d0 <= latched_data1(14) when (counter = 2 or counter = 3) else
      latched_data1(13) when (counter = 4 or counter = 5) else
      latched_data1(12) when (counter = 6 or counter = 7) else
      latched_data1(11) when (counter = 8 or counter = 9) else
      latched_data1(10) when (counter = 10 or counter = 11) else
      latched_data1(9) when (counter = 12 or counter = 13) else
      latched_data1(8) when (counter = 14 or counter = 15) else
      latched_data1(7) when (counter = 16 or counter = 17) else
      latched_data1(6) when (counter = 18 or counter = 19) else
      latched_data1(5) when (counter = 20 or counter = 21) else
      latched_data1(4) when (counter = 22 or counter = 23) else
      latched_data1(3) when (counter = 24 or counter = 25) else
      latched_data1(2) when (counter = 26 or counter = 27) else
      latched_data1(1) when (counter = 28 or counter = 29) else
      latched_data1(0) when (counter = 30 or counter = 31) else
      latched_data1(15);

d1 <= latched_data2(14) when (counter = 2 or counter = 3) else
      latched_data2(13) when (counter = 4 or counter = 5) else
      latched_data2(12) when (counter = 6 or counter = 7) else
      latched_data2(11) when (counter = 8 or counter = 9) else
      latched_data2(10) when (counter = 10 or counter = 11) else
      latched_data2(9) when (counter = 12 or counter = 13) else
      latched_data2(8) when (counter = 14 or counter = 15) else
      latched_data2(7) when (counter = 16 or counter = 17) else
      latched_data2(6) when (counter = 18 or counter = 19) else
      latched_data2(5) when (counter = 20 or counter = 21) else
      latched_data2(4) when (counter = 22 or counter = 23) else
      latched_data2(3) when (counter = 24 or counter = 25) else
      latched_data2(2) when (counter = 26 or counter = 27) else
      latched_data2(1) when (counter = 28 or counter = 29) else
      latched_data2(0) when (counter = 30 or counter = 31) else
      latched_data2(15);

d2 <= latched_data3(14) when (counter = 2 or counter = 3) else
      latched_data3(13) when (counter = 4 or counter = 5) else
      latched_data3(12) when (counter = 6 or counter = 7) else
      latched_data3(11) when (counter = 8 or counter = 9) else
      latched_data3(10) when (counter = 10 or counter = 11) else
      latched_data3(9) when (counter = 12 or counter = 13) else
      latched_data3(8) when (counter = 14 or counter = 15) else
      latched_data3(7) when (counter = 16 or counter = 17) else
      latched_data3(6) when (counter = 18 or counter = 19) else
      latched_data3(5) when (counter = 20 or counter = 21) else
      latched_data3(4) when (counter = 22 or counter = 23) else
      latched_data3(3) when (counter = 24 or counter = 25) else
      latched_data3(2) when (counter = 26 or counter = 27) else
      latched_data3(1) when (counter = 28 or counter = 29) else
      latched_data3(0) when (counter = 30 or counter = 31) else
      latched_data3(15);

d3 <= latched_data4(14) when (counter = 2 or counter = 3) else
      latched_data4(13) when (counter = 4 or counter = 5) else
      latched_data4(12) when (counter = 6 or counter = 7) else
      latched_data4(11) when (counter = 8 or counter = 9) else
      latched_data4(10) when (counter = 10 or counter = 11) else
      latched_data4(9) when (counter = 12 or counter = 13) else
      latched_data4(8) when (counter = 14 or counter = 15) else
      latched_data4(7) when (counter = 16 or counter = 17) else
      latched_data4(6) when (counter = 18 or counter = 19) else
      latched_data4(5) when (counter = 20 or counter = 21) else
      latched_data4(4) when (counter = 22 or counter = 23) else
      latched_data4(3) when (counter = 24 or counter = 25) else
      latched_data4(2) when (counter = 26 or counter = 27) else
      latched_data4(1) when (counter = 28 or counter = 29) else
      latched_data4(0) when (counter = 30 or counter = 31) else
      latched_data4(15);

end Behavioral;

