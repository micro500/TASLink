----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    19:29:01 01/19/2016 
-- Design Name: 
-- Module Name:    shift_register - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity shift_register is
    Port ( latch : in  STD_LOGIC;
           clock : in  STD_LOGIC;
           din : in  STD_LOGIC_VECTOR (7 downto 0);
           dout : out  STD_LOGIC);
end shift_register;

architecture Behavioral of shift_register is
  signal latched_data : std_logic_vector(7 downto 0) := "11111111";
begin
shift_out: process(clock, latch, din)
  begin
    if (latch = '1') then
      latched_data <= din;
    elsif (rising_edge(clock)) then
      latched_data <= latched_data(6 downto 0) & '1';
    end if;
  end process;

dout <= latched_data(7);

end Behavioral;

