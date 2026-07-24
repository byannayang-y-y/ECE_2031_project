library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity MaskedReactionGame_tb is
end entity MaskedReactionGame_tb;

architecture test of MaskedReactionGame_tb is
    constant CLOCK_PERIOD : time := 100 ns;

    constant ADDR_LEDS  : std_logic_vector(10 downto 0) :=
        std_logic_vector(to_unsigned(16#001#, 11));
    constant ADDR_TIMER : std_logic_vector(10 downto 0) :=
        std_logic_vector(to_unsigned(16#002#, 11));
    constant ADDR_HEX0  : std_logic_vector(10 downto 0) :=
        std_logic_vector(to_unsigned(16#004#, 11));
    constant ADDR_HEX1  : std_logic_vector(10 downto 0) :=
        std_logic_vector(to_unsigned(16#005#, 11));

    signal clock    : std_logic := '0';
    signal resetn   : std_logic := '0';
    signal switches : std_logic_vector(9 downto 0) := (others => '0');

    signal io_read  : std_logic;
    signal io_write : std_logic;
    signal io_addr  : std_logic_vector(10 downto 0);
    signal io_data  : std_logic_vector(15 downto 0);

    signal led_reg  : std_logic_vector(9 downto 0) := (others => '0');
    signal hex0_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal hex1_reg : std_logic_vector(15 downto 0) := (others => '0');

    signal hex0_write_count : natural := 0;
    signal hex1_write_count : natural := 0;
    signal timer_reset_count : natural := 0;

    -- The real board timer counts at 10 Hz. This accelerated model retains
    -- the same reset/read interface while keeping the test short.
    signal timer_count   : unsigned(15 downto 0) := (others => '0');
    signal timer_divider : natural range 0 to 19 := 0;
begin
    clock <= not clock after CLOCK_PERIOD / 2;

    cpu : entity work.SCOMP
        port map (
            clock     => clock,
            resetn    => resetn,
            IO_READ   => io_read,
            IO_WRITE  => io_write,
            IO_ADDR   => io_addr,
            IO_DATA   => io_data,
            dbg_FETCH => open,
            dbg_AC    => open,
            dbg_PC    => open,
            dbg_NMA   => open,
            dbg_MD    => open,
            dbg_IR    => open
        );

    detector : entity work.MaskedEventDetector
        port map (
            CLOCK    => clock,
            RESETN   => resetn,
            SWITCHES => switches,
            IO_READ  => io_read,
            IO_WRITE => io_write,
            IO_ADDR  => io_addr,
            IO_DATA  => io_data
        );

    -- Timer is the only legacy peripheral that drives the shared read bus
    -- in this game.
    io_data <= std_logic_vector(timer_count)
        when io_read = '1' and io_addr = ADDR_TIMER
        else (others => 'Z');

    legacy_peripherals : process(clock, resetn)
    begin
        if resetn = '0' then
            led_reg           <= (others => '0');
            hex0_reg          <= (others => '0');
            hex1_reg          <= (others => '0');
            hex0_write_count  <= 0;
            hex1_write_count  <= 0;
            timer_reset_count <= 0;
            timer_count       <= (others => '0');
            timer_divider     <= 0;
        elsif rising_edge(clock) then
            if io_write = '1' and io_addr = ADDR_LEDS then
                led_reg <= io_data(9 downto 0);
            end if;

            if io_write = '1' and io_addr = ADDR_HEX0 then
                hex0_reg         <= io_data;
                hex0_write_count <= hex0_write_count + 1;
            end if;

            if io_write = '1' and io_addr = ADDR_HEX1 then
                hex1_reg         <= io_data;
                hex1_write_count <= hex1_write_count + 1;
            end if;

            if io_write = '1' and io_addr = ADDR_TIMER then
                timer_count       <= (others => '0');
                timer_divider     <= 0;
                timer_reset_count <= timer_reset_count + 1;
            elsif timer_divider = 19 then
                timer_count   <= timer_count + 1;
                timer_divider <= 0;
            else
                timer_divider <= timer_divider + 1;
            end if;
        end if;
    end process;

    stimulus : process
        procedure tick(constant count : in positive := 1) is
        begin
            for i in 1 to count loop
                wait until rising_edge(clock);
                wait for 1 ns;
            end loop;
        end procedure;

        procedure wait_for_count(
            signal observed_count : in natural;
            constant target_count : in natural;
            constant description  : in string
        ) is
        begin
            for i in 1 to 4000 loop
                exit when observed_count >= target_count;
                tick;
            end loop;

            assert observed_count >= target_count
                report "Timed out waiting for " & description
                severity failure;
        end procedure;

        procedure one_clock_flick(constant switch_index : in natural) is
        begin
            wait until falling_edge(clock);
            switches(switch_index) <= '1';
            wait until falling_edge(clock);
            switches(switch_index) <= '0';
        end procedure;

        variable target_index_1 : natural;
        variable target_index_2 : natural;
        variable target_index_loop : natural;
        variable wrong_index    : natural;
        variable first_score    : unsigned(15 downto 0);
        variable previous_score : unsigned(15 downto 0);
    begin
        tick(5);
        resetn <= '1';

        -- Initial zero score and zero right-side display.
        wait_for_count(hex1_write_count, 1, "initial score display");
        assert hex1_reg = x"0000"
            report "Score did not initialize to zero"
            severity failure;

        tick(100);

        -- Start round one using SW9 only.
        switches(9) <= '1';
        wait_for_count(hex0_write_count, 2, "round-one target display");
        target_index_1 := to_integer(unsigned(hex0_reg(2 downto 0)));

        assert unsigned(hex0_reg) <= 7
            report "Target number was outside the SW0-SW7 range"
            severity failure;

        switches(9) <= '0';
        wait_for_count(timer_reset_count, 1, "round-one timer start");
        tick(40);

        -- A non-target switch change must not complete the round.
        wrong_index := (target_index_1 + 1) mod 8;
        one_clock_flick(wrong_index);
        tick(100);

        assert hex1_write_count = 1
            report "A masked-out wrong switch incorrectly completed the round"
            severity failure;

        -- A pulse lasting only one system clock must still be remembered.
        one_clock_flick(target_index_1);
        wait_for_count(hex1_write_count, 2, "round-one score update");
        wait_for_count(hex0_write_count, 3, "round-one reaction-time display");

        first_score := unsigned(hex1_reg);
        assert first_score > 0
            report "Round-one reaction time was not added to the score"
            severity failure;
        assert hex0_reg = hex1_reg
            report "First-round time and accumulated score should match"
            severity failure;

        -- All switches are already down. Verify that a second round can run
        -- and that its reaction time accumulates into the score.
        tick(100);
        switches(9) <= '1';
        wait_for_count(hex0_write_count, 4, "round-two target display");
        target_index_2 := to_integer(unsigned(hex0_reg(2 downto 0)));

        assert unsigned(hex0_reg) <= 7
            report "Second target number was outside the SW0-SW7 range"
            severity failure;

        switches(9) <= '0';
        wait_for_count(timer_reset_count, 2, "round-two timer start");
        tick(60);
        one_clock_flick(target_index_2);
        wait_for_count(hex1_write_count, 3, "round-two score update");
        wait_for_count(hex0_write_count, 5, "round-two reaction-time display");

        assert unsigned(hex1_reg) > first_score
            report "Second-round time was not accumulated into the score"
            severity failure;

        -- Continue through many more rounds to catch any state, call-stack,
        -- target-wrap, or event-clear failure that appears after round two.
        previous_score := unsigned(hex1_reg);
        for round_number in 3 to 16 loop
            tick(100);
            switches(9) <= '1';
            wait_for_count(
                hex0_write_count,
                2 * round_number,
                "later-round target display"
            );
            target_index_loop :=
                to_integer(unsigned(hex0_reg(2 downto 0)));

            assert unsigned(hex0_reg) <= 7
                report "Later-round target was outside the SW0-SW7 range"
                severity failure;

            switches(9) <= '0';
            wait_for_count(
                timer_reset_count,
                round_number,
                "later-round timer start"
            );
            tick(20 + round_number);
            one_clock_flick(target_index_loop);
            wait_for_count(
                hex1_write_count,
                round_number + 1,
                "later-round score update"
            );
            wait_for_count(
                hex0_write_count,
                2 * round_number + 1,
                "later-round reaction-time display"
            );

            assert unsigned(hex1_reg) > previous_score
                report "A later round did not accumulate into the score"
                severity failure;
            previous_score := unsigned(hex1_reg);
        end loop;

        assert led_reg = switches
            report "LED feedback did not match the synchronized switch state"
            severity failure;

        report "ALL MASKED REACTION GAME INTEGRATION TESTS PASSED"
            severity note;
        stop;
        wait;
    end process;
end architecture test;
