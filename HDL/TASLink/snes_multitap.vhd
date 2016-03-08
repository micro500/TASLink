library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity snes_multitap is
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
end snes_multitap;

architecture Behavioral of snes_multitap is

begin
console_d0 <= '1' when console_latch = '1' else
              port_d0(1) when console_io = '1' else
              port_d0(3);

console_d1 <= '0' when console_latch = '1' else
              port_d0(2) when console_io = '1' else
              port_d0(4);
              
port_clock(1) <= console_clock when console_io = '1' else
               '1';

port_clock(2) <= console_clock when console_io = '1' else
               '1';
               
port_clock(3) <= console_clock when console_io = '0' else
               '1';

port_clock(4) <= console_clock when console_io = '0' else
               '1';

port_latch(1) <= console_latch;
port_latch(2) <= console_latch;
port_latch(3) <= console_latch;
port_latch(4) <= console_latch;
               
port_io(1) <= '1';
port_io(2) <= '1';
port_io(3) <= '1';
port_io(4) <= '1';

console_d0_oe <= '0';
console_d1_oe <= '0';

end Behavioral;

