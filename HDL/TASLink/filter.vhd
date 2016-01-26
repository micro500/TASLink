----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    17:28:11 01/23/2016 
-- Design Name: 
-- Module Name:    filter - Behavioral 
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

entity filter is
    Port ( signal_in : in  STD_LOGIC;
           clk : in  STD_LOGIC;
           signal_out : out  STD_LOGIC);
end filter;

architecture Behavioral of filter is
  signal counter : integer range 0 to 6 := 0;
  signal current_output : std_logic := '0';
begin

  process(clk)
    
  begin
    if (rising_edge(clk)) then
      if (signal_in = current_output) then
        counter <= 0;
      else
        counter <= counter + 1;
        if (counter = 6) then
          current_output <= not(current_output);
          counter <= 0;
        end if;
      end if;
    end if;
  end process;

signal_out <= current_output;

end Behavioral;

