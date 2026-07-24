-- MaskedEventDetector.vhd
-- Masked switch-event detector peripheral for SCOMP
--
-- Monitors the ten DE10-Lite slide switches.
-- Software may:
--   Read  0x020: synchronized current switch state
--   Write 0x021: switch monitoring mask
--   Read  0x022: latched switch-change events
--   Write 0x023: selectively clear events
--
-- Masked-out changes are discarded.
-- Event flags remain set until explicitly cleared.
-- If a clear and a new event occur for the same bit during the
-- same clock cycle, the new event takes priority.
--
-- ECE 2031 Summer 2026

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY MaskedEventDetector IS
    PORT(
        CLOCK       : IN    STD_LOGIC;
        RESETN      : IN    STD_LOGIC;

        -- Physical DE10-Lite slide switches
        SWITCHES    : IN    STD_LOGIC_VECTOR(9 DOWNTO 0);

        -- SCOMP I/O bus
        IO_READ     : IN    STD_LOGIC;
        IO_WRITE    : IN    STD_LOGIC;
        IO_ADDR     : IN    STD_LOGIC_VECTOR(10 DOWNTO 0);
        IO_DATA     : INOUT STD_LOGIC_VECTOR(15 DOWNTO 0)
    );
END MaskedEventDetector;


ARCHITECTURE RTL OF MaskedEventDetector IS

    --------------------------------------------------------------------
    -- SCOMP I/O addresses
    --------------------------------------------------------------------

    CONSTANT ADDR_SW_CURRENT : STD_LOGIC_VECTOR(10 DOWNTO 0) :=
        STD_LOGIC_VECTOR(TO_UNSIGNED(16#020#, 11));

    CONSTANT ADDR_SW_MASK : STD_LOGIC_VECTOR(10 DOWNTO 0) :=
        STD_LOGIC_VECTOR(TO_UNSIGNED(16#021#, 11));

    CONSTANT ADDR_SW_EVENTS : STD_LOGIC_VECTOR(10 DOWNTO 0) :=
        STD_LOGIC_VECTOR(TO_UNSIGNED(16#022#, 11));

    CONSTANT ADDR_SW_CLEAR : STD_LOGIC_VECTOR(10 DOWNTO 0) :=
        STD_LOGIC_VECTOR(TO_UNSIGNED(16#023#, 11));


    --------------------------------------------------------------------
    -- Switch synchronization
    --------------------------------------------------------------------

    -- Two-stage synchronizer for the asynchronous physical switches.
    SIGNAL SYNC_STAGE_1 : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL SYNC_CURRENT : STD_LOGIC_VECTOR(9 DOWNTO 0);

    -- Previous synchronized sample used for change detection.
    SIGNAL PREVIOUS_SAMPLE : STD_LOGIC_VECTOR(9 DOWNTO 0);

    -- Allows the synchronizer to fill before event detection begins.
    SIGNAL STARTUP_VALID : STD_LOGIC_VECTOR(2 DOWNTO 0);


    --------------------------------------------------------------------
    -- Peripheral registers and event-detection signals
    --------------------------------------------------------------------

    SIGNAL MASK_REG   : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL EVENTS_REG : STD_LOGIC_VECTOR(9 DOWNTO 0);

    SIGNAL CHANGED_BITS      : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL MONITORED_CHANGES : STD_LOGIC_VECTOR(9 DOWNTO 0);

    SIGNAL WRITE_MASK  : STD_LOGIC;
    SIGNAL WRITE_CLEAR : STD_LOGIC;


    --------------------------------------------------------------------
    -- Read-bus signals
    --------------------------------------------------------------------

    SIGNAL READ_ENABLE : STD_LOGIC;
    SIGNAL READ_DATA   : STD_LOGIC_VECTOR(15 DOWNTO 0);

BEGIN

    --------------------------------------------------------------------
    -- Change detection
    --------------------------------------------------------------------

    -- XOR detects both 0-to-1 and 1-to-0 switch transitions.
    CHANGED_BITS <= SYNC_CURRENT XOR PREVIOUS_SAMPLE;

    -- Only switches enabled by the mask produce stored events.
    MONITORED_CHANGES <= CHANGED_BITS AND MASK_REG;


    --------------------------------------------------------------------
    -- SCOMP write decoding
    --------------------------------------------------------------------

    WRITE_MASK <= '1'
        WHEN IO_WRITE = '1'
         AND IO_ADDR = ADDR_SW_MASK
        ELSE '0';

    WRITE_CLEAR <= '1'
        WHEN IO_WRITE = '1'
         AND IO_ADDR = ADDR_SW_CLEAR
        ELSE '0';


    --------------------------------------------------------------------
    -- Synchronizer, mask register, and event register
    --------------------------------------------------------------------

    PROCESS(CLOCK, RESETN)
    BEGIN
        IF RESETN = '0' THEN

            SYNC_STAGE_1    <= (OTHERS => '0');
            SYNC_CURRENT    <= (OTHERS => '0');
            PREVIOUS_SAMPLE <= (OTHERS => '0');

            STARTUP_VALID <= (OTHERS => '0');

            MASK_REG   <= (OTHERS => '0');
            EVENTS_REG <= (OTHERS => '0');

        ELSIF RISING_EDGE(CLOCK) THEN

            ------------------------------------------------------------
            -- Two-stage switch synchronizer
            ------------------------------------------------------------

            SYNC_STAGE_1 <= SWITCHES;
            SYNC_CURRENT <= SYNC_STAGE_1;


            ------------------------------------------------------------
            -- Shift in ones until synchronization startup is complete
            ------------------------------------------------------------

            STARTUP_VALID <=
                STARTUP_VALID(1 DOWNTO 0) & '1';


            ------------------------------------------------------------
            -- SW_MASK write
            --
            -- Bits 15:10 of IO_DATA are ignored.
            ------------------------------------------------------------

            IF WRITE_MASK = '1' THEN
                MASK_REG <= IO_DATA(9 DOWNTO 0);
            END IF;


            ------------------------------------------------------------
            -- Startup initialization
            --
            -- Suppress event generation while the synchronizer fills.
            -- PREVIOUS_SAMPLE is repeatedly initialized from the current
            -- synchronized value so the initial physical switch positions
            -- do not generate false events.
            ------------------------------------------------------------

            IF STARTUP_VALID(2) = '0' THEN

                PREVIOUS_SAMPLE <= SYNC_CURRENT;
                EVENTS_REG      <= (OTHERS => '0');

            ELSE

                --------------------------------------------------------
                -- Normal event detection
                --------------------------------------------------------

                PREVIOUS_SAMPLE <= SYNC_CURRENT;

                IF WRITE_CLEAR = '1' THEN

                    -- Write-one-to-clear:
                    --   1 clears the corresponding stored event.
                    --   0 leaves the corresponding event unchanged.
                    --
                    -- MONITORED_CHANGES is ORed after clearing, so a
                    -- newly detected event wins over a simultaneous clear.
                    EVENTS_REG <=
                        (EVENTS_REG AND NOT IO_DATA(9 DOWNTO 0))
                        OR MONITORED_CHANGES;

                ELSE

                    -- Sticky flags remain set until software clears them.
                    EVENTS_REG <=
                        EVENTS_REG OR MONITORED_CHANGES;

                END IF;

            END IF;

        END IF;
    END PROCESS;


    --------------------------------------------------------------------
    -- SCOMP read decoding
    --
    -- The peripheral drives IO_DATA only for supported IN operations.
    -- Reads from SW_MASK and SW_CLEAR are not supported.
    --------------------------------------------------------------------

    READ_ENABLE <= '1'
        WHEN IO_READ = '1'
         AND (
                IO_ADDR = ADDR_SW_CURRENT
             OR IO_ADDR = ADDR_SW_EVENTS
         )
        ELSE '0';


    --------------------------------------------------------------------
    -- Read-data multiplexer
    --------------------------------------------------------------------

    PROCESS(IO_ADDR, SYNC_CURRENT, EVENTS_REG)
    BEGIN

        -- Reserved bits 15:10 always read as zero.
        READ_DATA <= (OTHERS => '0');

        CASE IO_ADDR IS

            WHEN ADDR_SW_CURRENT =>
                READ_DATA(9 DOWNTO 0) <= SYNC_CURRENT;

            WHEN ADDR_SW_EVENTS =>
                READ_DATA(9 DOWNTO 0) <= EVENTS_REG;

            WHEN OTHERS =>
                READ_DATA <= (OTHERS => '0');

        END CASE;

    END PROCESS;


    --------------------------------------------------------------------
    -- Shared SCOMP data bus
    --
    -- Drive IO_DATA only during a valid read of this peripheral.
    -- Otherwise, remain at high impedance so another peripheral or
    -- SCOMP itself may use the shared bus.
    --------------------------------------------------------------------

    IO_DATA <= READ_DATA
        WHEN READ_ENABLE = '1'
        ELSE (OTHERS => 'Z');

END RTL;
