#include "clkwiz.h"
#include "io_control.h"
#include "platform_drivers.h"
#include <stdio.h>

int clkwiz_feedback_check(uint32_t base_address, uint32_t timeout_ms)
{
    uint32_t elapsed;
    uint32_t feedback;
    uint32_t output0;
    uint32_t output1;
    uint32_t output2;

    for (elapsed = 0; elapsed < timeout_ms; ++elapsed) {
        if ((AXI_REG_READ(base_address, 0x004U) & 1U) != 0U)
            break;
        mdelay(1);
    }
    if (elapsed == timeout_ms) {
        printf("ERROR: Clock Wizard did not lock within %lu ms.\r\n",
               (unsigned long)timeout_ms);
        return -1;
    }

    /* Values are the generated clk_wiz_drp.vhd reset register image.
     * 307.2 MHz * 10 / 3 = 1024 MHz; output divisors are 2.5, 5 and 25.
     * Output0 bit18 enables its fractional divide; preserve it in the check. */
    feedback = AXI_REG_READ(base_address, 0x200U);
    output0 = AXI_REG_READ(base_address, 0x208U);
    output1 = AXI_REG_READ(base_address, 0x214U);
    output2 = AXI_REG_READ(base_address, 0x220U);
    if ((feedback & 0x07ffffffU) != 0x00000a03U ||
        (output0 & 0x0007ffffU) != 0x0005f402U ||
        (output1 & 0x000000ffU) != 5U ||
        (output2 & 0x000000ffU) != 25U) {
        printf("ERROR: Clock Wizard configuration mismatch: "
               "FB=%08lx OUT0=%08lx OUT1=%08lx OUT2=%08lx.\r\n",
               (unsigned long)feedback, (unsigned long)output0,
               (unsigned long)output1, (unsigned long)output2);
        return -1;
    }
    printf("Clock Wizard locked; configuration: 409.6 / 204.8 / 40.96 MHz.\r\n");
    return 0;
}
