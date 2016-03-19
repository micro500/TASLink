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

signal port_d0_pulled_up : std_logic_vector(1 to 4);
signal port_d1_pulled_up : std_logic_vector(1 to 1);

begin
port_d0_pulled_up(1) <= port_d0(1) when port_d0_oe(1) = '0' else
                        '1';

port_d0_pulled_up(2) <= port_d0(2) when port_d0_oe(2) = '0' else
                        '1';
                        
port_d0_pulled_up(3) <= port_d0(3) when port_d0_oe(3) = '0' else
                        '1';
                        
port_d0_pulled_up(4) <= port_d0(4) when port_d0_oe(4) = '0' else
                        '1';

port_d1_pulled_up(1) <= port_d1(1) when port_d1_oe(1) = '0' else
                        '1';
                        
console_d0 <= '1' when console_latch = '1' else -- The multiplexer is actually disabled
              -- All the rest below assume latch = '0'
              port_d0_pulled_up(1) when sw = '0' else
              -- All the rest below assume sw = '1'
              port_d0_pulled_up(1) when console_io = '1' else
              port_d0_pulled_up(3);

console_d1 <= port_d1_pulled_up(1) when console_latch = '0' and sw = '0' else -- Port 1 D1 is passed through
              '1'                  when console_latch = '1' and sw = '0' else -- Port 1 D1 is not passed due to the multiplexer being disabled
              port_d0_pulled_up(2) when console_latch = '0' and sw = '1' and console_io = '1' else
              port_d0_pulled_up(4) when console_latch = '0' and sw = '1' and console_io = '0' else
              '0'; -- Line is driven low when latch = '1' in 5p mode

console_d0_oe <= console_latch; -- Due to the multiplexer, this line is only enabled when latch is low
console_d1_oe <= console_latch when sw = '0' else -- Due to the multiplexer, this line is only enabled when latch is low and sw is set to 2p
                 '0'; -- In 5p this line is always driven

              
port_clock(1) <= console_clock when console_latch = '1' else  -- Clock is always passed through to port 1 if latch is high
                 console_clock when console_latch = '0' and sw = '0' else -- Clock is passed through the multitplexer
                 console_clock when console_latch = '0' and sw = '1' and console_io = '1' else -- Clock is only passed if IO is high
                 '1'; -- Multiplexer is disabled, use the pull-up instead;

port_clock(2) <= '1' when sw = '0' else -- This is actually disconnected
                 console_clock when console_latch = '1' and sw = '1' else -- Matches port 1 when sw is set to 5p
                 console_clock when console_latch = '0' and sw = '1' and console_io = '1' else
                 '1';
               
port_clock(3) <= '1' when sw = '0' else -- This is actually disconnected
                 console_clock when console_io = '0' and console_latch = '0' and sw = '1' else -- Only time it is passed through
                 '1'; -- Multiplexer is disabled, use the pull-up instead;

-- Same as port 3 clock
port_clock(4) <= '1' when sw = '0' else -- This is actually disconnected
                 console_clock when console_io = '0' and console_latch = '0' and sw = '1' else -- Only time it is passed through
                 '1'; -- Multiplexer is disabled, use the pull-up instead;

port_latch(1) <= console_latch; -- Directly connected
port_latch(2) <= console_latch when sw = '1' else -- Only passed in 5p mode
                 '1';
port_latch(3) <= console_latch when sw = '1' else -- Only passed in 5p mode
                 '1';
port_latch(4) <= console_latch when sw = '1' else -- Only passed in 5p mode
                 '1';
               
-- Port 1 IO is only connected when sw is in 2p
-- Ports 2-4 IO are never connected
port_io(1) <= console_io when sw = '0'
              else '0';                
port_io(2) <= '0';
port_io(3) <= '0';
port_io(4) <= '0';

end Behavioral;

