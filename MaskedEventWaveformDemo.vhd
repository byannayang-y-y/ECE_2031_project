library ieee;
use ieee.std_logic_1164.all;

entity MaskedEventWaveformDemo is
    port (
        clock    : in  std_logic;
        reset_n  : in  std_logic;
        switches : in  std_logic_vector(9 downto 0);
        mask     : in  std_logic_vector(9 downto 0);
        clear    : in  std_logic_vector(9 downto 0);
        events   : out std_logic_vector(9 downto 0);
        previous : out std_logic_vector(9 downto 0);
        changed  : out std_logic_vector(9 downto 0);
        monitored_changes : out std_logic_vector(9 downto 0)
    );
end entity MaskedEventWaveformDemo;

architecture rtl of MaskedEventWaveformDemo is
    signal previous_reg : std_logic_vector(9 downto 0) := (others => '0');
    signal events_reg   : std_logic_vector(9 downto 0) := (others => '0');
    signal changed_sig  : std_logic_vector(9 downto 0);
    signal monitored_sig : std_logic_vector(9 downto 0);
begin
    changed_sig <= switches xor previous_reg;
    monitored_sig <= changed_sig and mask;

    previous <= previous_reg;
    changed <= changed_sig;
    monitored_changes <= monitored_sig;
    events <= events_reg;

    process (clock)
    begin
        if rising_edge(clock) then
            if reset_n = '0' then
                previous_reg <= switches;
                events_reg <= (others => '0');
            else
                events_reg <= (events_reg and not clear) or monitored_sig;
                previous_reg <= switches;
            end if;
        end if;
    end process;
end architecture rtl;
