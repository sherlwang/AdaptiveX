#ifndef SRC_CLKWIZ_H_
#define SRC_CLKWIZ_H_

/***************************** Include Files ********************************/

#include <stdint.h>

/************************** Function Prototypes *****************************/

/* Checks the locked flag and generated configuration registers; writes nothing.
 * This is configuration readback, not an independent frequency measurement. */
int clkwiz_feedback_check(uint32_t base_address, uint32_t timeout_ms);

#endif
