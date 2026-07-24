library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MaskedEventDetector_tb is
end entity MaskedEventDetector_tb;

architecture test of MaskedEventDetector_tb is
    constant CLOCK_PERIOD : time := 100 ns;
    constant HIGH_IMPEDANCE_DATA : std_logic_vector(15 downto 0) :=
        (others => 'Z');

    constant ADDR_SW_CURRENT : std_logic_vector(10 downto 0) :=
        std_logic_vector(to_unsigned(16#020#, 11));
    constant ADDR_SW_MASK : std_logic_vector(10 downto 0) :=
        std_logic_vector(to_unsigned(16#021#, 11));
    constant ADDR_SW_EVENTS : std_logic_vector(10 downto 0) :=
        std_logic_vector(to_unsigned(16#022#, 11));
    constant ADDR_SW_CLEAR : std_logic_vector(10 downto 0) :=
        std_logic_vector(to_unsigned(16#023#, 11));

    signal clock    : std_logic := '0';
    signal resetn   : std_logic := '0';
    signal switches : std_logic_vector(9 downto 0) := (others => '0');
    signal io_read  : std_logic := '0';
    signal io_write : std_logic := '0';
    signal io_addr  : std_logic_vector(10 downto 0) := (others => '0');
    signal io_data  : std_logic_vector(15 downto 0);

    signal tb_data       : std_logic_vector(15 downto 0) := (others => '0');
    signal tb_data_drive : std_logic := '0';
begin
    clock <= not clock after CLOCK_PERIOD / 2;

    io_data <= tb_data when tb_data_drive = '1' else (others => 'Z');

    dut : entity work.MaskedEventDetector
        port map (
            CLOCK    => clock,
            RESETN   => resetn,
            SWITCHES => switches,
            IO_READ  => io_read,
            IO_WRITE => io_write,
            IO_ADDR  => io_addr,
            IO_DATA  => io_data
        );

    stimulus : process
        procedure tick(constant count : in positive := 1) is
        begin
            for i in 1 to count loop
                wait until rising_edge(clock);
                wait for 1 ns;
            end loop;
        end procedure;

        procedure write_register(
            constant address_value : in std_logic_vector(10 downto 0);
            constant data_value    : in std_logic_vector(15 downto 0)
        ) is
        begin
            io_addr       <= address_value;
            tb_data       <= data_value;
            tb_data_drive <= '1';
            io_read       <= '0';
            io_write      <= '1';
            tick;
            io_write      <= '0';
            tb_data_drive <= '0';
            wait for 1 ns;
        end procedure;

        procedure expect_read(
            constant address_value : in std_logic_vector(10 downto 0);
            constant expected      : in std_logic_vector(15 downto 0);
            constant description   : in string
        ) is
        begin
            io_addr       <= address_value;
            io_write      <= '0';
            io_read       <= '1';
            tb_data_drive <= '0';
            wait for 1 ns;
            assert io_data = expected
                report description & ": expected 0x" &
                    integer'image(to_integer(unsigned(expected))) &
                    ", received 0x" &
                    integer'image(to_integer(unsigned(io_data)))
                severity error;
            io_read <= '0';
            wait for 1 ns;
        end procedure;

        procedure expect_high_impedance(
            constant description : in string
        ) is
        begin
            wait for 1 ns;
            assert io_data = HIGH_IMPEDANCE_DATA
                report description
                severity error;
        end procedure;
    begin
        report "Starting MaskedEventDetector verification" severity note;

        -- Reset and allow the two-stage synchronizer/startup guard to fill.
        resetn <= '0';
        tick(2);
        resetn <= '1';
        tick(5);

        expect_read(ADDR_SW_CURRENT, x"0000",
            "Current switches must reset/synchronize to zero");
        expect_read(ADDR_SW_EVENTS, x"0000",
            "Events must be zero after reset");

        -- The peripheral must release the shared bus while idle and for
        -- unsupported reads.
        expect_high_impedance("IO_DATA must be high impedance while idle");
        io_addr <= ADDR_SW_MASK;
        io_read <= '1';
        expect_high_impedance(
            "Reading the write-only mask address must not drive IO_DATA");
        io_read <= '0';

        -- With the reset-default mask of zero, changes must be discarded.
        switches(0) <= '1';
        tick(4);
        expect_read(ADDR_SW_EVENTS, x"0000",
            "An unmasked rising transition must be ignored");
        switches(0) <= '0';
        tick(4);
        expect_read(ADDR_SW_EVENTS, x"0000",
            "An unmasked falling transition must be ignored");

        -- Monitor switches 0 and 2.
        write_register(ADDR_SW_MASK, x"0005");

        switches(0) <= '1';
        tick(4);
        expect_read(ADDR_SW_CURRENT, x"0001",
            "SW_CURRENT must report the synchronized switch value");
        expect_read(ADDR_SW_EVENTS, x"0001",
            "A monitored rising transition must set its event bit");

        switches(0) <= '0';
        tick(4);
        expect_read(ADDR_SW_EVENTS, x"0001",
            "An event must remain set after the switch returns");
        expect_read(ADDR_SW_EVENTS, x"0001",
            "Reading SW_EVENTS must not clear stored events");

        switches(2) <= '1';
        tick(4);
        expect_read(ADDR_SW_EVENTS, x"0005",
            "Events from multiple monitored switches must accumulate");

        write_register(ADDR_SW_CLEAR, x"0001");
        expect_read(ADDR_SW_EVENTS, x"0004",
            "Selective clear must preserve event bits written as zero");

        -- A new mask applies only to future changes. Existing event bit 2
        -- remains visible until explicitly cleared.
        write_register(ADDR_SW_MASK, x"0002");
        expect_read(ADDR_SW_EVENTS, x"0004",
            "Changing the mask must not hide an existing event");
        write_register(ADDR_SW_CLEAR, x"03FF");
        expect_read(ADDR_SW_EVENTS, x"0000",
            "Writing ones to SW_CLEAR must clear selected stored events");

        switches(2) <= '0';
        tick(4);
        expect_read(ADDR_SW_EVENTS, x"0000",
            "A switch removed from the mask must not create future events");

        switches(1) <= '1';
        tick(4);
        expect_read(ADDR_SW_EVENTS, x"0002",
            "A newly masked switch must create future events");
        write_register(ADDR_SW_CLEAR, x"0002");
        expect_read(ADDR_SW_EVENTS, x"0000",
            "The monitored event must be clear before priority testing");

        -- Arrange a new falling event so that its detection cycle coincides
        -- with a write-one-to-clear for the same bit. The new event must win.
        switches(1) <= '0';
        tick(2);
        write_register(ADDR_SW_CLEAR, x"0002");
        expect_read(ADDR_SW_EVENTS, x"0002",
            "A new event must remain set when clear occurs simultaneously");

        -- Verify reset/startup behavior when physical switches are already
        -- high. Writing the mask during startup must not create false events.
        switches <= (others => '1');
        resetn <= '0';
        tick(2);
        resetn <= '1';
        write_register(ADDR_SW_MASK, x"03FF");
        tick(5);
        expect_read(ADDR_SW_CURRENT, x"03FF",
            "Current value must synchronize correctly after reset");
        expect_read(ADDR_SW_EVENTS, x"0000",
            "Initial physical switch positions must not create false events");

        report "ALL MASKED EVENT DETECTOR TESTS PASSED" severity note;
        wait;
    end process;
end architecture test;
