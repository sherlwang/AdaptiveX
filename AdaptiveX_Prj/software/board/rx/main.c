/******************************************************************************
 *
 * Copyright (C) 2018 Xilinx, Inc.  All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
 * OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Except as contained in this notice, the name of the Xilinx shall not be used
 * in advertising or otherwise to promote the sale, use or other dealings in
 * this Software without prior written authorization from Xilinx.
 *
 ******************************************************************************/
/*
 * Fixed SC-FDE board initialization. All BD-enabled RF channels start in
 * both roles. The role label in rfsoc_cfg.h defaults to the current Tx XSA.
 * TX: main Tx4/JA5 (DAC2/0) + feedback Rx2/JA11 (ADC1/0).
 * RX: main Rx0/JA9 (ADC0/0) + feedback Tx6/JA7 (DAC3/0).
 */

/***************************** Include Files ********************************/

#include <stdint.h>
#include <stdio.h>
#include "xparameters.h"
#include "rfsoc_cfg.h"
#include "io_control.h"
#include "platform_drivers.h"
#include "spi_ctrl.h"
#include "clkwiz.h"
#include "xrfdc_dcp.h"
#include "xadc.h"

/************************** Constant Definitions ****************************/

#define RFDC_DEVICE_ID             XPAR_XRFDC_0_DEVICE_ID
#define PL_START_OFFSET            0x004U
#define PL_CLOCK_1PPS_OFFSET        0x010U
#define PL_MODE_OFFSET             0x018U
#define PL_CONFIG_DONE_OFFSET      0x01cU
#define PL_FW_VERSION_OFFSET       0x100U
#define LMK_LOCK_ATTEMPTS          1000U
#define LMK_LOCK_STABLE_READS      5U

/************************** Variable Definitions ****************************/

uint32_t axi_lite_addr = XPAR_UP_AXI_0_BASEADDR;
extern spi_device lmk04828_spi;
XRFdc RFdcInstPtr;

/* Board reference parameters, in Hz. These retain the existing LMK settings.
 * sample_rate here names the LMK reference, NOT the 4.9152 GSPS RFDC rate.
 * clock_1pps is the legacy PL auxiliary counter value, not an AXIS divider. */
uint32_t sample_rate = 409600000U;
uint32_t clock_1pps = 409600000U;
uint16_t auxdac = 1600U;            /* EEPROM read failure fallback. */
uint16_t auxdac_invalid = 1875U;    /* EEPROM outside [1000, 2000). */
uint32_t use_eeprom_auxdac = 1U;    /* Set 0 to use auxdac directly. */
uint32_t require_pll1_lock = 0U;    /* PLL2 is always required. */

/* User RF settings: change values here, then rebuild the application.
 * All frequencies are MHz, phases degrees, current uA, attenuation dB.
 * DAC2 uses PL upconversion and a COARSE BYPASS RFDC mixer. It has no RFDC
 * fine-NCO parameter. Settings apply to every enabled physical block in the
 * named tile: DAC2 blocks 0/2, DAC3 blocks 0/2, ADC1 API blocks 0/1.
 * ADC0 API blocks 0/1 keep their original DSA/Nyquist settings. All eight
 * converters are configured in both profiles; no profile disables a tile. */
RFdc_UserSettings RFdcSettings = {
    .main_dac_current_ua          = 30500U,
    .feedback_dac_current_ua      = 20000U,
    .feedback_adc_nco_mhz         = -1200.0,
    .feedback_adc_phase_deg       = 0.0,
    .feedback_dac_nco_mhz         = 1200.0,
    .feedback_dac_phase_deg       = 0.0,
    .feedback_adc_attenuation_db  = 0.0f,
    .feedback_adc_disable_rts     = 1U,
    .main_dac_nyquist_zone        = 1U,
    .feedback_adc_nyquist_zone    = 1U,
    .feedback_dac_nyquist_zone    = 1U
};

/************************** Function Prototypes *****************************/

static int startup_failed(const char *stage);
static int wait_lmk_lock(void);

/************************** Function Definitions ****************************/

int main(void)
{
    u32 Status;
    uint8_t iic_rd[2];
    float temperature;

#if RFDC_PROFILE == RFDC_PROFILE_TX
    printf("\r\nMain Tx4/JA5 + feedback Rx2/JA11 startup.\r\n");
#else
    printf("\r\nMain Rx0/JA9 + feedback Tx6/JA7 startup.\r\n");
#endif

    /* 1. Stop PL before configuring references or RFDC. */
    AXI_REG_WRITE(axi_lite_addr, PL_START_OFFSET, 0U);
    AXI_REG_WRITE(axi_lite_addr, PL_CONFIG_DONE_OFFSET, 0U);
    AXI_REG_WRITE(axi_lite_addr, PL_MODE_OFFSET, 0U);
    if (AXI_REG_READ(axi_lite_addr, PL_START_OFFSET) != 0U)
        return startup_failed("PL stop register readback");

    Status = platform_init();
    if (Status != 0U)
        return startup_failed("GPIO/SPI platform initialization");

    /* 2. LMK reference and AUX DAC calibration. Keep board routing and the
     * LMK register tables unchanged; no RFDC sample-rate or MMCM writes. */
    if (gpio_set_value(TRX_SW, 1U) != 0 ||
        gpio_set_value(FDDTDD_SW, 1U) != 0 ||
        gpio_set_value(LMK_RESET, 0U) != 0 ||
        gpio_set_value(LMK_REF_SELECT0, 1U) != 0 ||
        gpio_set_value(LMK_REF_SELECT1, 0U) != 0 ||
        gpio_set_value(LMK_SYNC, 0U) != 0)
        return startup_failed("reference GPIO initialization");
    mdelay(500);

    Status = lmk04828_init(&lmk04828_spi, sample_rate);
    if (Status != 0U)
        return startup_failed("LMK initialization");
    if (use_eeprom_auxdac != 0U) {
        if (iic_init(IIC_DEVICE_ID) != XST_SUCCESS ||
            i2c_reg_read(0x50U, 0U, &iic_rd[0]) != XST_SUCCESS ||
            i2c_reg_read(0x50U, 1U, &iic_rd[1]) != XST_SUCCESS) {
            printf("EEPROM calibration unavailable; using AUX DAC %u.\r\n",
                   (unsigned int)auxdac);
        } else {
            auxdac = (uint16_t)iic_rd[0] | ((uint16_t)iic_rd[1] << 8);
            if (auxdac < 1000U || auxdac >= 2000U)
                auxdac = auxdac_invalid;
        }
    }
    printf("AUX DAC calibration value: %u.\r\n", (unsigned int)auxdac);
    Status = lmk04828_update_man_dac(&lmk04828_spi, auxdac);
    if (Status != 0U || wait_lmk_lock() != 0)
        return startup_failed("LMK calibration/lock");

    /* Retain output synchronization and pulse setup. Mixer updates use
     * driver-issued TILE events; no MTS or SYSREF mixer dependency. */
    if (gpio_set_value(LMK_SYNC, 0U) != 0)
        return startup_failed("LMK synchronization low");
    mdelay(1);
    if (gpio_set_value(LMK_SYNC, 1U) != 0)
        return startup_failed("LMK synchronization high");
    mdelay(1);
    if (gpio_set_value(LMK_SYNC, 0U) != 0 ||
        lmk04828_update_sysref_pulse(&lmk04828_spi) != 0 ||
        lmk04828_set_sysref_shots(&lmk04828_spi, 0U) != 0)
        return startup_failed("LMK SYSREF setup");
    mdelay(500);

    /* 3. Check the bound hardware, start all BD-enabled RF tiles, and
     * apply the user settings above. Configuration and readback use the
     * same values. Interpolation, decimation and sample clocks stay fixed. */
    Status = RFdcDcp_initial(&RFdcInstPtr, RFDC_DEVICE_ID);
    if (Status != XRFDC_SUCCESS)
        return startup_failed("RFDC platform/driver initialization");
    Status = RFdcDcp_Start(&RFdcInstPtr, &RFdcSettings);
    if (Status != XRFDC_SUCCESS)
        return startup_failed("RFDC startup/readback");

    /* 4. Read back fixed PL clocks and active RF paths before enabling PL. */
    Status = clkwiz_feedback_check(XPAR_CLK_WIZ_0_BASEADDR, 2000U);
    if (Status != 0U)
        return startup_failed("fixed PL clock configuration");
    Status = FeedbackRFdc_Readback(&RFdcInstPtr, &RFdcSettings);
    if (Status != XRFDC_SUCCESS)
        return startup_failed("final RFDC readback");

    printf("FPGA firmware version: 0x%08lx.\r\n",
           (unsigned long)AXI_REG_READ(axi_lite_addr, PL_FW_VERSION_OFFSET));
    printf("Software build: %s %s.\r\n", __DATE__, __TIME__);
    if (xadc_initial(XPAR_PSU_AMS_DEVICE_ID) == 0) {
        xadc_read_temp(&temperature);
        printf("FPGA temperature: %.1f C.\r\n", (double)temperature);
    }

    /* 5. Start only after every required check has passed. */
    AXI_REG_WRITE(axi_lite_addr, PL_CLOCK_1PPS_OFFSET, clock_1pps);
    AXI_REG_WRITE(axi_lite_addr, PL_MODE_OFFSET, 1U);
    AXI_REG_WRITE(axi_lite_addr, PL_CONFIG_DONE_OFFSET, 1U);
    if (AXI_REG_READ(axi_lite_addr, PL_MODE_OFFSET) != 1U ||
        AXI_REG_READ(axi_lite_addr, PL_CONFIG_DONE_OFFSET) != 1U)
        return startup_failed("PL configuration register readback");
    AXI_REG_WRITE(axi_lite_addr, PL_START_OFFSET, 1U);
    if (AXI_REG_READ(axi_lite_addr, PL_START_OFFSET) != 1U)
        return startup_failed("PL start register readback");

#if RFDC_PROFILE == RFDC_PROFILE_TX
    printf("Running: main Tx4 DAC2/0 real12 at409.6MHz + Rx2 ADC1/0 NCO=%+.6fMHz.\r\n",
           RFdcSettings.feedback_adc_nco_mhz);
#else
    printf("Running: main Rx0 ADC0/0 real12 at409.6MHz + Tx6 DAC3/0 NCO=%+.6fMHz.\r\n",
           RFdcSettings.feedback_dac_nco_mhz);
#endif
    printf("All enabled ADC0/ADC1/DAC2/DAC3 channels configured and checked.\r\n");
    return XRFDC_SUCCESS;
}

static int startup_failed(const char *stage)
{
    AXI_REG_WRITE(axi_lite_addr, PL_START_OFFSET, 0U);
    AXI_REG_WRITE(axi_lite_addr, PL_CONFIG_DONE_OFFSET, 0U);
    printf("ERROR: startup failed at %s; PL stays stopped.\r\n", stage);
    return XRFDC_FAILURE;
}

static int wait_lmk_lock(void)
{
    uint32_t attempt;
    uint32_t stable = 0U;
    int32_t pll1_reg;
    int32_t pll2_reg;

    for (attempt = 0U; attempt < LMK_LOCK_ATTEMPTS; ++attempt) {
        pll1_reg = lmk04828_spi_read(&lmk04828_spi, 0x182U);
        pll2_reg = lmk04828_spi_read(&lmk04828_spi, 0x183U);
        if (pll1_reg < 0 || pll2_reg < 0) {
            printf("ERROR: LMK lock-status SPI read failed.\r\n");
            return -1;
        }
        if ((((uint32_t)pll2_reg >> 1) & 1U) == 1U &&
            (require_pll1_lock == 0U ||
             (((uint32_t)pll1_reg >> 1) & 1U) == 1U)) {
            if (++stable == LMK_LOCK_STABLE_READS) {
                printf("LMK locked: PLL1=%lu PLL2=1.\r\n",
                       (unsigned long)(((uint32_t)pll1_reg >> 1) & 1U));
                return 0;
            }
        } else {
            stable = 0U;
        }
        mdelay(10);
    }
    printf("ERROR: LMK lock check timed out after %lu ms.\r\n",
           (unsigned long)(LMK_LOCK_ATTEMPTS * 10U));
    return -1;
}
