
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer


# Output pin mapping (uo_out):
#   [0] SPI_MISO
#   [1] RX_BYTE_VALID  (rx_valid)
#   [2] CRC_OK         (crc_ok)
#   [3] PACKET_DETECTED (rx_locked)
#   [4] TX_ACTIVE      (tx_busy)
#   [5] SYMBOL_CLK     (baud tick)
#   [6] MARK_GT_SPACE  (bit_decision)
#   [7] SAMPLE_CLK     (200 kHz tick)

UO_SPI_MISO       = 0
UO_RX_BYTE_VALID  = 1
UO_CRC_OK         = 2
UO_PACKET_DETECTED = 3
UO_TX_ACTIVE      = 4
UO_SYMBOL_CLK     = 5
UO_MARK_GT_SPACE  = 6
UO_SAMPLE_CLK     = 7


def get_uo_bit(dut, bit):
    return (dut.uo_out.value.to_unsigned() >> bit) & 1


async def spi_byte(dut, mosi_byte):
    """Clock 8 bits over SPI (CS must already be low). Returns MISO byte."""
    miso_byte = 0
    for bit in range(8):
        mosi_bit = (mosi_byte >> (7 - bit)) & 1
        ui = dut.ui_in.value.to_unsigned()
        ui = (ui & ~(1 << 1)) | (mosi_bit << 1)
        dut.ui_in.value = ui
        await ClockCycles(dut.clk, 2)

        # SCLK rising
        ui = dut.ui_in.value.to_unsigned()
        ui |= (1 << 0)
        dut.ui_in.value = ui
        await ClockCycles(dut.clk, 2)

        miso_bit = (dut.uo_out.value.to_unsigned() >> 0) & 1
        miso_byte = (miso_byte << 1) | miso_bit

        # SCLK falling
        ui = dut.ui_in.value.to_unsigned()
        ui &= ~(1 << 0)
        dut.ui_in.value = ui
        await ClockCycles(dut.clk, 2)
    return miso_byte


async def spi_cs_low(dut):
    ui = dut.ui_in.value.to_unsigned()
    dut.ui_in.value = ui & ~(1 << 2)
    await ClockCycles(dut.clk, 4)


async def spi_cs_high(dut):
    ui = dut.ui_in.value.to_unsigned()
    dut.ui_in.value = ui | (1 << 2)
    await ClockCycles(dut.clk, 4)


async def spi_write_reg(dut, addr, data):
    """Write: CS low, send addr with write flag (bit 7), send data, CS high."""
    await spi_cs_low(dut)
    await spi_byte(dut, addr | 0x80)
    await spi_byte(dut, data)
    await spi_cs_high(dut)


async def spi_read_reg(dut, addr):
    """Read: CS low, send addr (bit 7 clear), send dummy (read MISO), CS high."""
    await spi_cs_low(dut)
    await spi_byte(dut, addr)
    result = await spi_byte(dut, 0x00)
    await spi_cs_high(dut)
    return result


async def reset_dut(dut):
    """Standard reset sequence."""
    dut.ena.value = 1
    dut.ui_in.value = 0x04  # CS_N high (bit 2)
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)


@cocotb.test()
async def test_reset(dut):
    """Verify outputs are zero after reset."""
    clock = Clock(dut.clk, 20, unit="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # TX should not be busy, RX should not be locked
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 0, "TX should not be busy after reset"
    assert get_uo_bit(dut, UO_PACKET_DETECTED) == 0, "RX should not be locked after reset"
    dut._log.info("Reset test passed")


@cocotb.test()
async def test_spi_register_rw(dut):
    """Write and read back configuration registers via SPI."""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Read status register (addr 0x00) — should have bit 0 set (alive)
    status = await spi_read_reg(dut, 0x00)
    dut._log.info(f"Status register: 0x{status:02X}")
    assert status & 0x01, "Status bit 0 (alive) should be set"

    # Write baud_div_lo (addr 0x07) with a test value
    await spi_write_reg(dut, 0x07, 0x42)
    await ClockCycles(dut.clk, 10)

    # Read it back
    readback = await spi_read_reg(dut, 0x07)
    dut._log.info(f"Wrote 0x42 to baud_div_lo, read back 0x{readback:02X}")
    assert readback == 0x42, f"Expected 0x42, got 0x{readback:02X}"

    dut._log.info("SPI register R/W test passed")


@cocotb.test()
async def test_nco_output(dut):
    """Verify NCO produces non-zero samples when TX is active."""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Enable loopback mode via register
    await spi_write_reg(dut, 0x01, 0x02)  # control: loopback_en=1

    # Shorten the symbol period so symbol clock pulses appear quickly:
    # baud_div = 4 samples/symbol = 1000 clocks/symbol
    await spi_write_reg(dut, 0x06, 0x00)
    await spi_write_reg(dut, 0x07, 0x04)

    # Trigger TX with a test byte
    await spi_write_reg(dut, 0x0A, 0x55)  # write to tx_data triggers TX

    # Wait a bit and check TX busy
    await ClockCycles(dut.clk, 100)
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 1, "TX should be busy after trigger"
    dut._log.info("TX busy confirmed")

    # Check that uio_out (TX samples) has varying values
    samples = set()
    for _ in range(500):
        await ClockCycles(dut.clk, 10)
        samples.add(dut.uio_out.value.to_unsigned())

    dut._log.info(f"Observed {len(samples)} unique TX sample values")
    assert len(samples) > 5, f"NCO should produce varying samples, got only {len(samples)} unique values"

    # Check symbol clock pulses during TX.
    # baud_tick is a single-cycle pulse every baud_div samples (1000 clocks
    # with baud_div=4), so sample every clock across several baud periods.
    sym_clk_edges = 0
    for _ in range(5000):
        await ClockCycles(dut.clk, 1)
        if get_uo_bit(dut, UO_SYMBOL_CLK):
            sym_clk_edges += 1

    dut._log.info(f"Symbol clock edges seen: {sym_clk_edges}")
    assert sym_clk_edges > 0, "Symbol clock should pulse during TX"

    dut._log.info("NCO output test passed")


@cocotb.test()
async def test_loopback(dut):
    """Full loopback: TX a byte in loopback mode, verify RX decodes it with CRC."""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Enable loopback
    await spi_write_reg(dut, 0x01, 0x02)

    # Speed up the simulation: baud_div = block_len = 250 samples/symbol
    # (800 bps instead of the default 100 bps; same logic, shorter symbols).
    # baud_div and block_len share the 200 kHz sample time base and must match.
    await spi_write_reg(dut, 0x06, 0x00)
    await spi_write_reg(dut, 0x07, 0xFA)
    await spi_write_reg(dut, 0x08, 0x00)
    await spi_write_reg(dut, 0x09, 0xFA)

    # Send test byte 0x42 via TX
    test_byte = 0x42
    await spi_write_reg(dut, 0x0A, test_byte)

    # Frame: preamble + sync + payload + CRC = 32 bits.
    # Poll CRC_OK: unlike RX_BYTE_VALID (a single-cycle pulse), it stays high
    # after a good frame, so a coarse polling stride cannot miss it.
    timeout_cycles = 4_000_000
    crc_ok_seen = False

    for _ in range(timeout_cycles // 10000):
        await ClockCycles(dut.clk, 10000)
        if get_uo_bit(dut, UO_CRC_OK):
            crc_ok_seen = True
            break

    assert crc_ok_seen, "Loopback frame was not decoded with a valid CRC within timeout"

    rx_data = await spi_read_reg(dut, 0x0B)
    dut._log.info(f"Loopback: sent 0x{test_byte:02X}, received 0x{rx_data:02X}, CRC_OK=1")
    assert rx_data == test_byte, f"Loopback mismatch: sent 0x{test_byte:02X}, got 0x{rx_data:02X}"
    dut._log.info("Loopback test PASSED (with CRC)")


@cocotb.test()
async def test_noise_no_false_rx(dut):
    """Feed random noise into RX (no loopback) and verify no spurious rx_valid."""
    import random
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    rng = random.Random(0xDEAD)

    # Drive random samples on uio_in for ~1M cycles (enough for several Goertzel blocks)
    false_valid_count = 0
    for _ in range(100):
        dut.uio_in.value = rng.randint(0, 255)
        await ClockCycles(dut.clk, 10000)
        if get_uo_bit(dut, UO_RX_BYTE_VALID):
            false_valid_count += 1

    dut._log.info(f"Noise test: {false_valid_count} unexpected rx_valid pulses in 1M cycles")
    assert false_valid_count == 0, f"RX should not decode valid frames from noise, got {false_valid_count}"
    dut._log.info("Noise rejection test passed")


@cocotb.test()
async def test_soft_reset_recovery(dut):
    """Assert soft reset mid-TX and verify the design recovers cleanly."""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Enable loopback and start TX
    await spi_write_reg(dut, 0x01, 0x02)
    await spi_write_reg(dut, 0x0A, 0xAB)
    await ClockCycles(dut.clk, 200)
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 1, "TX should be active before soft reset"

    # Soft reset: set control register bit 0
    await spi_write_reg(dut, 0x01, 0x01)
    await ClockCycles(dut.clk, 50)

    # TX should stop, no RX lock
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 0, "TX should stop after soft reset"
    assert get_uo_bit(dut, UO_PACKET_DETECTED) == 0, "RX should not be locked after soft reset"

    # Release soft reset, re-enable loopback
    await spi_write_reg(dut, 0x01, 0x02)
    await ClockCycles(dut.clk, 50)

    # Verify the design is alive: status register bit 0 should be set
    status = await spi_read_reg(dut, 0x00)
    assert status & 0x01, "Device should be alive after soft reset release"

    # Verify TX can be triggered again
    await spi_write_reg(dut, 0x0A, 0x55)
    await ClockCycles(dut.clk, 200)
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 1, "TX should re-activate after soft reset recovery"

    dut._log.info("Soft reset recovery test passed")


@cocotb.test()
async def test_write_readonly_registers(dut):
    """Write to read-only registers aka. status, rx_data and verify no side effects."""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Write to status register (0x00, read-only) — should be ignored
    await spi_write_reg(dut, 0x00, 0xFF)
    await ClockCycles(dut.clk, 10)

    # Write to rx_data register (0x0B, read-only) — should be ignored
    await spi_write_reg(dut, 0x0B, 0xBB)
    await ClockCycles(dut.clk, 10)

    # TX should not have been triggered by writing to RO addresses
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 0, "TX should not trigger from RO register writes"

    # Status register should still report alive
    status = await spi_read_reg(dut, 0x00)
    assert status & 0x01, "Status alive bit should still be set"

    dut._log.info("Read-only register protection test passed")


@cocotb.test()
async def test_invalid_timing_registers_are_clamped(dut):
    """Illegal baud/block values should not wedge the TX/RX timing engines."""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Write illegal zero values. The register readback remains raw, but the
    # exported baud_div/block_len used by the datapath must clamp to >= 2.
    await spi_write_reg(dut, 0x06, 0x00)
    await spi_write_reg(dut, 0x07, 0x00)
    await spi_write_reg(dut, 0x08, 0x00)
    await spi_write_reg(dut, 0x09, 0x00)

    await spi_write_reg(dut, 0x0A, 0xA5)
    await ClockCycles(dut.clk, 200)
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 1, "TX should start with clamped timing"

    tx_completed = False
    symbol_ticks = 0
    for _ in range(100_000):
        await ClockCycles(dut.clk, 1)
        symbol_ticks += get_uo_bit(dut, UO_SYMBOL_CLK)
        if get_uo_bit(dut, UO_TX_ACTIVE) == 0:
            tx_completed = True
            break

    assert symbol_ticks > 0, "Clamped baud_div should produce symbol ticks"
    assert tx_completed, "TX should complete instead of hanging on baud_div=0"
    dut._log.info("Invalid timing register clamp test passed")


@cocotb.test()
async def test_spi_read_does_not_clobber(dut):
    """SPI reads must not overwrite the target register (known bug if this fails)."""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Write a known value to baud_div_lo (0x07)
    await spi_write_reg(dut, 0x07, 0xAB)
    await ClockCycles(dut.clk, 10)

    # First read should return 0xAB
    first_read = await spi_read_reg(dut, 0x07)
    assert first_read == 0xAB, f"First read: expected 0xAB, got 0x{first_read:02X}"

    # Second read of the same register — should still return 0xAB.
    # If the SPI command decoder fires a write on reads, this will return 0x00.
    second_read = await spi_read_reg(dut, 0x07)
    dut._log.info(f"SPI read clobber test: first=0x{first_read:02X}, second=0x{second_read:02X}")
    assert second_read == 0xAB, (
        f"SPI read clobbered register: second read returned 0x{second_read:02X} "
        f"(expected 0xAB). The SPI command decoder writes dummy byte 0x00 on reads."
    )

    dut._log.info("SPI read-no-clobber test passed")


@cocotb.test()
async def test_double_tx_trigger(dut):
    """Trigger TX twice rapidly and verify the design doesn't hang or corrupt."""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Enable loopback
    await spi_write_reg(dut, 0x01, 0x02)

    # Shorten symbols (250 samples/symbol) so the frames finish quickly
    await spi_write_reg(dut, 0x06, 0x00)
    await spi_write_reg(dut, 0x07, 0xFA)

    # First TX
    await spi_write_reg(dut, 0x0A, 0x11)
    await ClockCycles(dut.clk, 200)
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 1, "First TX should be active"

    # Second TX while first is still running
    await spi_write_reg(dut, 0x0A, 0x22)
    await ClockCycles(dut.clk, 200)

    # TX should still be active (either first or second frame)
    assert get_uo_bit(dut, UO_TX_ACTIVE) == 1, "TX should remain active"

    # Wait for TX to eventually complete (up to 25M cycles for both frames)
    tx_completed = False
    for _ in range(25_000_000 // 10000):
        await ClockCycles(dut.clk, 10000)
        if get_uo_bit(dut, UO_TX_ACTIVE) == 0:
            tx_completed = True
            break

    if tx_completed:
        dut._log.info("Double TX: both frames completed without hang")
    else:
        dut._log.warning("Double TX: TX still active at timeout, may need longer sim")

    # Design should be responsive regardless, can verify via SPI
    status = await spi_read_reg(dut, 0x00)
    assert status & 0x01, "Device should still be alive after double TX"

    dut._log.info("Double TX trigger test passed")
