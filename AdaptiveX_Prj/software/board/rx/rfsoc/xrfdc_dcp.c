/* Start all shared-clock participants before waiting; preserve the BD clocks. */
#include "xrfdc_dcp.h"
#include "rfsoc_cfg.h"
#include "platform_drivers.h"
#include <stdio.h>

/******************************************************************************/
/********************** RFDC Driver Initialization ****************************/
/******************************************************************************/
int RFdcDcp_initial(XRFdc *InstancePtr, u16 DeviceId)
{
    u32 Status;
    XRFdc_Config *Config = XRFdc_LookupConfig(DeviceId);

    if (Config == NULL) {
        printf("ERROR: RFDC configuration was not found.\r\n");
        return XRFDC_FAILURE;
    }
    Status = FeedbackRFdc_CheckPlatform(Config);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = XRFdc_CfgInitialize(InstancePtr, Config);
    if (Status != XRFDC_SUCCESS) {
        printf("ERROR: RFDC driver initialization failed.\r\n");
        return XRFDC_FAILURE;
    }
    return XRFDC_SUCCESS;
}

/******************************************************************************/
/********************** Shared Clock Startup Helpers **************************/
/******************************************************************************/
static int kick_tile(XRFdc *InstancePtr, u32 Type, u32 Tile)
{
    u32 Status;

    Status = XRFdc_CheckTileEnabled(InstancePtr, Type, Tile);
    if (Status != XRFDC_SUCCESS) {
        printf("ERROR: %s tile %lu is not enabled.\r\n",
               Type == XRFDC_DAC_TILE ? "DAC" : "ADC", (unsigned long)Tile);
        return XRFDC_FAILURE;
    }

    /* Follow the local driver's XRFdc_StartUpDist sequence: trigger every
     * participant before waiting. A blocking StartUp on ADC1 can wait for an
     * AXIS clock that only becomes available after ADC0 starts clk_adc0.
     * State1->15 preserves GUI settings; this is not a global tile reset. */
    XRFdc_ClrSetReg(InstancePtr, XRFDC_CTRL_STS_BASE(Type, Tile),
                   XRFDC_RESTART_STATE_OFFSET, XRFDC_PWR_STATE_MASK,
                   (XRFDC_SM_STATE1 << XRFDC_RSR_START_SHIFT) | XRFDC_SM_STATE15);
    XRFdc_WriteReg(InstancePtr, XRFDC_CTRL_STS_BASE(Type, Tile),
                   XRFDC_RESTART_OFFSET, XRFDC_RESTART_MASK);
    return XRFDC_SUCCESS;
}

static int wait_tile(XRFdc *InstancePtr, u32 Type, u32 Tile, u32 State)
{
    u32 Status;

    /* The public driver's WaitForState has a bounded retry count. */
    Status = XRFdc_WaitForState(InstancePtr, Type, Tile, State);
    if (Status != XRFDC_SUCCESS) {
        printf("ERROR: %s tile %lu did not reach state %lu.\r\n",
               Type == XRFDC_DAC_TILE ? "DAC" : "ADC",
               (unsigned long)Tile, (unsigned long)State);
        return XRFDC_FAILURE;
    }
    return XRFDC_SUCCESS;
}

static int wait_pll(XRFdc *InstancePtr, u32 Type, u32 Tile)
{
    u32 Status;
    u32 lock_status;
    unsigned int attempt;

    for (attempt = 0; attempt < 2000U; ++attempt) {
        Status = XRFdc_GetPLLLockStatus(InstancePtr, Type, Tile, &lock_status);
        if (Status != XRFDC_SUCCESS) {
            printf("ERROR: PLL lock-status API failed for %s tile %lu.\r\n",
                   Type == XRFDC_DAC_TILE ? "DAC" : "ADC", (unsigned long)Tile);
            return XRFDC_FAILURE;
        }
        if (lock_status == XRFDC_PLL_LOCKED)
            return XRFDC_SUCCESS;
        mdelay(1);
    }
    printf("ERROR: %s tile %lu PLL lock timed out.\r\n",
           Type == XRFDC_DAC_TILE ? "DAC" : "ADC", (unsigned long)Tile);
    return XRFDC_FAILURE;
}

static int wait_restart_complete(XRFdc *InstancePtr, u32 Type, u32 Tile)
{
    u32 attempt;
    u32 base_address = XRFDC_CTRL_STS_BASE(Type, Tile);

    /* Match the driver's full-startup completion check. State15 alone does not
     * include the generated wrapper's fabric-clock/FIFO-ready done indication. */
    for (attempt = 0U; attempt < XRFDC_RESTART_CLR_DLY_CNT; ++attempt) {
        if (XRFdc_ReadReg16(InstancePtr, base_address, XRFDC_RESTART_OFFSET) == 0U)
            return XRFDC_SUCCESS;
        mdelay(XRFDC_RESTART_CLR_WAIT / 1000U);
    }
    printf("ERROR: %s tile %lu startup/fabric readiness timed out at state %lu.\r\n",
           Type == XRFDC_DAC_TILE ? "DAC" : "ADC", (unsigned long)Tile,
           (unsigned long)XRFdc_ReadReg16(InstancePtr, base_address,
                                          XRFDC_CURRENT_STATE_OFFSET));
    return XRFDC_FAILURE;
}

/******************************************************************************/
/********************** Profile Startup ***************************************/
/******************************************************************************/
int RFdcDcp_Start(XRFdc *InstancePtr, const RFdc_UserSettings *Settings)
{
    u32 Status;

    /* Reject illegal user settings before starting any tile. */
    Status = FeedbackRFdc_CheckUserSettings(InstancePtr, Settings);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = FeedbackRFdc_CheckPlatform(&InstancePtr->RFdc_Config);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    /* ADC1 supplies the ADC sampling clock. ADC0 supplies clk_adc0, which
     * drives the shared Clock Wizard. DAC2 is the DAC PLL provider to DAC3.
     * All four enabled tiles start for BOTH role profiles, including unused
     * payload channels. No reset, sample-clock, or MTS changes occur. */
    Status = kick_tile(InstancePtr, XRFDC_ADC_TILE, FEEDBACK_ADC_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = kick_tile(InstancePtr, XRFDC_ADC_TILE, FEEDBACK_ADC_FABRIC_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = kick_tile(InstancePtr, XRFDC_DAC_TILE, FEEDBACK_DAC_PLL_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = kick_tile(InstancePtr, XRFDC_DAC_TILE, FEEDBACK_DAC_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;

    /* State7 is the driver's clock-distribution-ready state. Public custom
     * startup stopping at clock-detect state6 is insufficient for this role. */
    Status = wait_tile(InstancePtr, XRFDC_ADC_TILE, FEEDBACK_ADC_TILE, XRFDC_SM_STATE7);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_tile(InstancePtr, XRFDC_DAC_TILE, FEEDBACK_DAC_PLL_TILE, XRFDC_SM_STATE7);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_pll(InstancePtr, XRFDC_ADC_TILE, FEEDBACK_ADC_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_pll(InstancePtr, XRFDC_DAC_TILE, FEEDBACK_DAC_PLL_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_tile(InstancePtr, XRFDC_ADC_TILE, FEEDBACK_ADC_TILE, XRFDC_SM_STATE15);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_tile(InstancePtr, XRFDC_ADC_TILE, FEEDBACK_ADC_FABRIC_TILE, XRFDC_SM_STATE15);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_tile(InstancePtr, XRFDC_DAC_TILE, FEEDBACK_DAC_PLL_TILE, XRFDC_SM_STATE15);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_tile(InstancePtr, XRFDC_DAC_TILE, FEEDBACK_DAC_TILE, XRFDC_SM_STATE15);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_restart_complete(InstancePtr, XRFDC_ADC_TILE, FEEDBACK_ADC_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_restart_complete(InstancePtr, XRFDC_ADC_TILE, FEEDBACK_ADC_FABRIC_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_restart_complete(InstancePtr, XRFDC_DAC_TILE, FEEDBACK_DAC_PLL_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    Status = wait_restart_complete(InstancePtr, XRFDC_DAC_TILE, FEEDBACK_DAC_TILE);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;

    Status = FeedbackRFdc_Configure(InstancePtr, Settings);
    if (Status != XRFDC_SUCCESS)
        return XRFDC_FAILURE;
    return FeedbackRFdc_Readback(InstancePtr, Settings);
}
