----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    18:06:22 01/23/2016 
-- Design Name: 
-- Module Name:    toggle - Behavioral 
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

entity toggle is
    Port ( signal_in : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
end toggle;

architecture Behavioral of toggle is
signal toggle : std_logic := '0';
begin

  process(signal_in)
  begin
    if (rising_edge(signal_in)) then
      toggle <= not(toggle);
    end if;
  end process;

signal_out <= toggle;
end Behavioral;

