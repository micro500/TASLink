library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo is
    Generic (
        constant FIFO_DEPTH : positive := 150
     );
    Port ( data_in : in  STD_LOGIC_VECTOR (15 downto 0);
           write_en : in  STD_LOGIC;
           data_out : out  STD_LOGIC_VECTOR (15 downto 0);
           read_en : in  STD_LOGIC;
           clk : in  STD_LOGIC;
           empty : out  STD_LOGIC;
           full : out  STD_LOGIC;
           clear : in  STD_LOGIC);
end fifo;

architecture Behavioral of fifo is
  type data_buffer is array(0 to FIFO_DEPTH-1) of std_logic_vector(15 downto 0);
  signal queue : data_buffer;
    
  signal buffer_tail : integer range 0 to FIFO_DEPTH-1 := 0;
  signal buffer_head : integer range 0 to FIFO_DEPTH-1 := 0;
  
  signal address_to_use : integer range 0 to FIFO_DEPTH-1;
begin

  fifo_proc: process(clk)
  begin
    if (rising_edge(clk)) then
      if (clear = '1') then
        buffer_head <= 0;
        buffer_tail <= 0;
      else 
        if (write_en = '1') then
          -- Make sure there is room for this data
          if ((buffer_head = (FIFO_DEPTH - 1) and buffer_tail /= 0) or (buffer_head /= (FIFO_DEPTH - 1) and (buffer_head + 1) /= buffer_tail)) then
            queue(buffer_head) <= data_in;
            
            -- move
            if (buffer_head = (FIFO_DEPTH - 1)) then
              buffer_head <= 0;
            else
              buffer_head <= buffer_head + 1;
            end if;         
          end if;  
        end if;
        
        if (read_en = '1') then
          -- move tail pointer if possible
          if (buffer_tail /= buffer_head) then
            if (buffer_tail = (FIFO_DEPTH - 1)) then
              buffer_tail <= 0;
            else
              buffer_tail <= buffer_tail + 1;
            end if;
          end if;  
        end if;
      end if;
    end if;
  end process;
  
  address_to_use <= buffer_tail when buffer_head /= buffer_tail else
                    (FIFO_DEPTH - 1) when buffer_tail = 0 else
                    buffer_tail - 1;

  data_out <= queue(address_to_use);

  full <= '1' when (buffer_head = (FIFO_DEPTH - 1) and buffer_tail = 0) or (buffer_head /= (FIFO_DEPTH - 1) and (buffer_head + 1) = buffer_tail) else
          '0';
  empty <= '1' when buffer_head = buffer_tail else
           '0';

end Behavioral;

