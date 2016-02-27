library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity controller is
    Port ( console_clock : in  STD_LOGIC;
           console_latch : in  STD_LOGIC;
           console_io : in  STD_LOGIC;
           console_d0 : out  STD_LOGIC;
           console_d1 : out  STD_LOGIC;
           console_d0_oe : out  STD_LOGIC;
           console_d1_oe : out  STD_LOGIC;
           data : in  STD_LOGIC_VECTOR (31 downto 0);
           overread_value : in  STD_LOGIC;
           size : in  STD_LOGIC_VECTOR (1 downto 0);
           connected : in  STD_LOGIC;
           clk : STD_LOGIC);
end controller;

architecture Behavioral of controller is
  component shift_register is
    Port ( latch : in  STD_LOGIC;
           clock : in  STD_LOGIC;
           din : in  STD_LOGIC_VECTOR (7 downto 0);
           dout : out  STD_LOGIC;
           sin : in STD_LOGIC;
           clk : in std_logic);
  end component;
  
  signal sr1_dout : std_logic;
  signal sr1_sin : std_logic;
  
  signal sr2_dout : std_logic;
  signal sr2_sin : std_logic;
  
  signal sr3_dout : std_logic;
  signal sr3_sin : std_logic;
  
  signal sr4_dout : std_logic;
  signal sr4_sin : std_logic;

begin
  sr1: shift_register port map (latch => console_latch,
                                clock => console_clock,
                                din => data(7 downto 0),
                                dout => sr1_dout,
                                sin => sr1_sin,
                                clk => clk);
                                
  sr2: shift_register port map (latch => console_latch,
                                clock => console_clock,
                                din => data(15 downto 8),
                                dout => sr2_dout,
                                sin => sr2_sin,
                                clk => clk);
                                
  sr3: shift_register port map (latch => console_latch,
                                clock => console_clock,
                                din => data(23 downto 16),
                                dout => sr3_dout,
                                sin => sr3_sin,
                                clk => clk);
                                
  sr4: shift_register port map (latch => console_latch,
                                clock => console_clock,
                                din => data(31 downto 24),
                                dout => sr4_dout,
                                sin => sr4_sin,
                                clk => clk);
  
  sr1_sin <= overread_value when size = "00" else
             sr2_dout;
  
  sr2_sin <= overread_value when (size = "00" or size = "01") else
             sr3_dout;
             
  sr3_sin <= overread_value when (size = "00" or size = "01" or size = "10") else
             sr4_dout;

  sr4_sin <= overread_value;
  
  console_d0 <= sr1_dout;
  console_d0_oe <= not connected;
  
  console_d1 <= '1';
  console_d1_oe <= '1'; -- disabled
end Behavioral;

