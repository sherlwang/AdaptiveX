/* Fixed RFDC interfaces; application settings do not change sample clocks. */
#ifndef SRC_RFSOC_RFSOC_CFG_H_
#define SRC_RFSOC_RFSOC_CFG_H_

/******************************************************************************/
/***************************** Include Files **********************************/
/******************************************************************************/
#include "xrfdc.h"

/******************************************************************************/
/********************** Hardware Profile Definitions **************************/
/******************************************************************************/
#define RFDC_PROFILE_TX 0
#define RFDC_PROFILE_RX 1
#ifndef RFDC_PROFILE
#define RFDC_PROFILE RFDC_PROFILE_TX
#endif
#if RFDC_PROFILE != RFDC_PROFILE_TX && RFDC_PROFILE != RFDC_PROFILE_RX
#error "RFDC_PROFILE must be RFDC_PROFILE_TX (0) or RFDC_PROFILE_RX (1)"
#endif

#define MAIN_DAC_TILE              2U
#define MAIN_DAC_BLOCK             0U
#define MAIN_DAC_AXIS_MHZ          409.6
#define MAIN_DAC_INTERPOLATION     1U
#define MAIN_DAC_AXIS_WORDS        12U
#define FEEDBACK_DAC_TILE          3U
#define FEEDBACK_DAC_BLOCK         0U
#define FEEDBACK_ADC_TILE          1U
#define FEEDBACK_ADC_BLOCK         0U
#define FEEDBACK_DAC_PLL_TILE      2U
#define FEEDBACK_ADC_FABRIC_TILE   0U
#define FEEDBACK_SAMPLE_GSPS       4.9152
#define FEEDBACK_REFCLK_MHZ        409.6
#define FEEDBACK_AXIS_MHZ          40.96
#define FEEDBACK_TX_INTERPOLATION  20U
#define FEEDBACK_RX_DECIMATION     10U
#define FEEDBACK_AXIS_WORDS        12U
#define MAIN_ADC_TILE              0U
#define MAIN_ADC_BLOCK             0U
#define MAIN_ADC_AXIS_MHZ          409.6
#define MAIN_ADC_AXIS_WORDS        12U
#define MAIN_ADC_DECIMATION        1U

/******************************************************************************/
/********************** Application Settings **********************************/
/******************************************************************************/
/* Define one instance in main.c. All enabled physical blocks of each tile
 * share that tile's user settings in both role profiles. ADC0's two physical
 * blocks each preserve their own DSA/RTS/Nyquist. Fine NCO settings never apply
 * to the real, bypassed DAC2. Phase is strictly between -180 and +180 degrees. */
typedef struct {
    u32 main_dac_current_ua;
    u32 feedback_dac_current_ua;
    double feedback_adc_nco_mhz;
    double feedback_adc_phase_deg;
    double feedback_dac_nco_mhz;
    double feedback_dac_phase_deg;
    float feedback_adc_attenuation_db;
    u32 feedback_adc_disable_rts;
    u32 main_dac_nyquist_zone;
    u32 feedback_adc_nyquist_zone;
    u32 feedback_dac_nyquist_zone;
} RFdc_UserSettings;

/******************************************************************************/
/********************** Function Prototypes ***********************************/
/******************************************************************************/
u32 FeedbackRFdc_CheckPlatform(const XRFdc_Config *Config);
u32 FeedbackRFdc_CheckUserSettings(const XRFdc *InstancePtr,
                                  const RFdc_UserSettings *Settings);
u32 FeedbackRFdc_Configure(XRFdc *InstancePtr, const RFdc_UserSettings *Settings);
u32 FeedbackRFdc_Readback(XRFdc *InstancePtr, const RFdc_UserSettings *Settings);

#endif
