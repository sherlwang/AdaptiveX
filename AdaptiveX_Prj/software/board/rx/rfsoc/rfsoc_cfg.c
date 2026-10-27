/* RFDC setup: fixed hardware contract, selectable application profile. */
#include "rfsoc_cfg.h"
#include <math.h>
#include <stdio.h>

/******************************************************************************/
/********************** Local Helpers *****************************************/
/******************************************************************************/
static int close_value(double Actual, double Expected)
{
    return fabs(Actual - Expected) < 0.000001;
}

static u32 api_failure(const char *Name, u32 Status)
{
    printf("ERROR: %s failed (status=%lu).\r\n", Name, (unsigned long)Status);
    return XRFDC_FAILURE;
}

typedef struct {
    u32 Type;
    u32 Tile;
    u32 Block;       /* Public driver ID: high-speed ADC 0/1, DAC 0/2. */
    u32 ConfigBlock; /* High-speed ADC public block1 maps to raw slice2. */
    u32 Factor;
    u32 Words;
    double FabricMHz;
    u32 DataType;
    u32 MixerType;
    u32 MixerMode;
} RFdc_PathContract;

/* Eight physical converters. ADC I/Q digital pairs are not extra ADCs. */
static const RFdc_PathContract RfdcPaths[] = {
    {XRFDC_ADC_TILE, 0U, 0U, 0U, 1U, 12U, 409.6, 0U,
     XRFDC_MIXER_TYPE_COARSE, XRFDC_MIXER_MODE_R2R},
    {XRFDC_ADC_TILE, 0U, 1U, 2U, 1U, 12U, 409.6, 0U,
     XRFDC_MIXER_TYPE_COARSE, XRFDC_MIXER_MODE_R2R},
    {XRFDC_ADC_TILE, 1U, 0U, 0U, 10U, 12U, 40.96, 1U,
     XRFDC_MIXER_TYPE_FINE, XRFDC_MIXER_MODE_R2C},
    {XRFDC_ADC_TILE, 1U, 1U, 2U, 10U, 12U, 40.96, 1U,
     XRFDC_MIXER_TYPE_FINE, XRFDC_MIXER_MODE_R2C},
    {XRFDC_DAC_TILE, 2U, 0U, 0U, 1U, 12U, 409.6, 0U,
     XRFDC_MIXER_TYPE_COARSE, XRFDC_MIXER_MODE_R2R},
    {XRFDC_DAC_TILE, 2U, 2U, 2U, 1U, 12U, 409.6, 0U,
     XRFDC_MIXER_TYPE_COARSE, XRFDC_MIXER_MODE_R2R},
    {XRFDC_DAC_TILE, 3U, 0U, 0U, 20U, 12U, 40.96, 0U,
     XRFDC_MIXER_TYPE_FINE, XRFDC_MIXER_MODE_C2R},
    {XRFDC_DAC_TILE, 3U, 2U, 2U, 20U, 12U, 40.96, 0U,
     XRFDC_MIXER_TYPE_FINE, XRFDC_MIXER_MODE_C2R}
};
#define RFDC_PATH_COUNT (sizeof(RfdcPaths) / sizeof(RfdcPaths[0]))

/* Preserve ADC0 analog settings independently for both physical converters. */
static XRFdc_DSA_Settings main_adc_dsa_before[2];
static u32 main_adc_zone_before[2];
static u8 main_adc_settings_captured[2];

/******************************************************************************/
/********************** Hardware Contract Checks ******************************/
/******************************************************************************/
u32 FeedbackRFdc_CheckPlatform(const XRFdc_Config *Config)
{
    u32 Tile;
    u32 Block;
    u32 Index;
    u32 Mirror;
    const RFdc_PathContract *Path;

    if (Config == NULL || Config->IPType < XRFDC_GEN3) {
        printf("ERROR: RFDC Gen3 platform configuration is unavailable.\r\n");
        return XRFDC_FAILURE;
    }
    /* Enumerate every enabled tile, including channels unused by a role.
     * This shared hardware contract must match whichever XSA builds the ELF. */
    for (Tile = 0U; Tile < 4U; ++Tile) {
        const XRFdc_ADCTile_Config *Adc = &Config->ADCTile_Config[Tile];
        const XRFdc_DACTile_Config *Dac = &Config->DACTile_Config[Tile];
        if ((Adc->Enable != 0U) != (Tile < 2U) ||
            (Dac->Enable != 0U) != (Tile >= 2U))
            return api_failure("enabled ADC0/ADC1/DAC2/DAC3 tile inventory",
                               XRFDC_FAILURE);
        if (Adc->Enable != 0U) {
            if (Adc->NumSlices != 2U ||
                Adc->PLLEnable != (Tile == 1U) ||
                !close_value(Adc->SamplingRate, FEEDBACK_SAMPLE_GSPS) ||
                !close_value(Adc->RefClkFreq, Tile == 1U ?
                              FEEDBACK_REFCLK_MHZ : FEEDBACK_SAMPLE_GSPS * 1000.0) ||
                !close_value(Adc->FabClkFreq, Tile == 0U ?
                              MAIN_ADC_AXIS_MHZ : FEEDBACK_AXIS_MHZ))
                return api_failure("ADC shared PLL/sample/fabric clock contract",
                                   XRFDC_FAILURE);
        }
        if (Dac->Enable != 0U) {
            if (Dac->PLLEnable != (Tile == 2U) || Dac->LinkCoupling != 0U ||
                !close_value(Dac->SamplingRate, FEEDBACK_SAMPLE_GSPS) ||
                !close_value(Dac->RefClkFreq, Tile == 2U ?
                              FEEDBACK_REFCLK_MHZ : FEEDBACK_SAMPLE_GSPS * 1000.0) ||
                !close_value(Dac->FabClkFreq, Tile == 2U ?
                              MAIN_DAC_AXIS_MHZ : FEEDBACK_AXIS_MHZ))
                return api_failure("DAC shared PLL/sample/fabric/AC contract",
                                   XRFDC_FAILURE);
            for (Block = 0U; Block < 4U; ++Block) {
                if ((Dac->DACBlock_Analog_Config[Block].BlockAvailable != 0U) !=
                    (Block == 0U || Block == 2U))
                    return api_failure("DAC physical block0/block2 inventory",
                                       XRFDC_FAILURE);
            }
        }
    }
    for (Index = 0U; Index < RFDC_PATH_COUNT; ++Index) {
        Path = &RfdcPaths[Index];
        if (Path->Type == XRFDC_ADC_TILE) {
            const XRFdc_ADCTile_Config *Adc = &Config->ADCTile_Config[Path->Tile];
            /* Raw slots0/1 belong to physical ADC API0; slots2/3 to API1.
             * GetDataWidth uses API indices while mixer/analog APIs map API1
             * to raw2. Check both mirror entries, never call ADC APIs2/3. */
            for (Mirror = Path->ConfigBlock; Mirror < Path->ConfigBlock + 2U;
                 ++Mirror) {
                const XRFdc_ADCBlock_DigitalDataPath_Config *Digital =
                    &Adc->ADCBlock_Digital_Config[Mirror];
                const XRFdc_ADCBlock_AnalogDataPath_Config *Analog =
                    &Adc->ADCBlock_Analog_Config[Mirror];
                if (!Analog->BlockAvailable ||
                    Analog->MixMode != (Path->Tile == 0U ? 2U : 0U) ||
                    Digital->MixerInputDataType != Path->DataType ||
                    Digital->DataWidth != Path->Words ||
                    Digital->DecimationMode != Path->Factor ||
                    Digital->MixerType != Path->MixerType)
                    return api_failure("enabled ADC physical/pair data contract",
                                       XRFDC_FAILURE);
            }
        } else {
            const XRFdc_DACTile_Config *Dac = &Config->DACTile_Config[Path->Tile];
            const XRFdc_DACBlock_DigitalDataPath_Config *Digital =
                &Dac->DACBlock_Digital_Config[Path->ConfigBlock];
            if (!Dac->DACBlock_Analog_Config[Path->Block].BlockAvailable ||
                Dac->DACBlock_Analog_Config[Path->Block].MixMode !=
                    (Path->Tile == 2U ? XRFDC_DAC_MIXER_MODE_REAL : 0U) ||
                Digital->MixerInputDataType != Path->DataType ||
                Digital->DataWidth != Path->Words ||
                Digital->InterpolationMode != Path->Factor ||
                Digital->MixerType != Path->MixerType)
                return api_failure("enabled DAC physical data/mixer contract",
                                   XRFDC_FAILURE);
        }
    }
    /* Generated FifoEnable fields are reset configuration, not live status.
     * Every enabled tile is explicitly enabled and checked at runtime. */
    return XRFDC_SUCCESS;
}

/******************************************************************************/
/********************** User Settings Validation ******************************/
/******************************************************************************/
static int valid_fine_settings(double Frequency, double Phase, u32 Zone)
{
    /* Use one unaliased Nyquist interval; comparisons also reject NaN/Inf. */
    const double HalfSampleMHz = FEEDBACK_SAMPLE_GSPS * 500.0;
    return Frequency >= -HalfSampleMHz && Frequency <= HalfSampleMHz &&
           Phase > XRFDC_MIXER_PHASE_OFFSET_LOW_LIMIT &&
           Phase < XRFDC_MIXER_PHASE_OFFSET_UP_LIMIT &&
           (Zone == XRFDC_ODD_NYQUIST_ZONE || Zone == XRFDC_EVEN_NYQUIST_ZONE);
}

u32 FeedbackRFdc_CheckUserSettings(const XRFdc *InstancePtr,
                                  const RFdc_UserSettings *Settings)
{
    u32 Revision;
    u32 Current;
    u32 Tile;
    double Attenuation;
    double Steps;

    if (InstancePtr == NULL || Settings == NULL) {
        printf("ERROR: RFDC instance/settings is NULL.\r\n");
        return XRFDC_FAILURE;
    }
    Revision = InstancePtr->RFdc_Config.SiRevision;
    Attenuation = Settings->feedback_adc_attenuation_db;
    if (InstancePtr->RFdc_Config.IPType < XRFDC_GEN3 ||
        !valid_fine_settings(Settings->feedback_adc_nco_mhz,
                             Settings->feedback_adc_phase_deg,
                             Settings->feedback_adc_nyquist_zone) ||
        !(Attenuation >= XRFDC_MIN_ATTEN &&
          Attenuation <= XRFDC_MAX_ATTEN(Revision)) ||
        Settings->feedback_adc_disable_rts > 1U) {
        printf("ERROR: invalid Rx2 NCO/phase/Nyquist/DSA/RTS setting.\r\n");
        return XRFDC_FAILURE;
    }
    Steps = Attenuation / XRFDC_STEP_ATTEN(Revision);
    if (fabs(Steps - floor(Steps + 0.5)) > 0.000001) {
        printf("ERROR: Rx2 DSA must follow the silicon's %.2f dB step.\r\n",
               (double)XRFDC_STEP_ATTEN(Revision));
        return XRFDC_FAILURE;
    }
    if (Settings->main_dac_nyquist_zone != XRFDC_ODD_NYQUIST_ZONE &&
        Settings->main_dac_nyquist_zone != XRFDC_EVEN_NYQUIST_ZONE) {
        printf("ERROR: main DAC Nyquist zone must be 1 or 2.\r\n");
        return XRFDC_FAILURE;
    }
    if (!valid_fine_settings(Settings->feedback_dac_nco_mhz,
                             Settings->feedback_dac_phase_deg,
                             Settings->feedback_dac_nyquist_zone)) {
        printf("ERROR: invalid Tx6 NCO/phase/Nyquist setting.\r\n");
        return XRFDC_FAILURE;
    }
    for (Tile = MAIN_DAC_TILE; Tile <= FEEDBACK_DAC_TILE; ++Tile) {
        Current = Tile == MAIN_DAC_TILE ? Settings->main_dac_current_ua :
                                          Settings->feedback_dac_current_ua;
        if (InstancePtr->RFdc_Config.DACTile_Config[Tile].LinkCoupling != 0U)
            return api_failure("DAC AC coupling check", XRFDC_FAILURE);
        if (Current < XRFDC_MIN_I_UA(Revision) || Current > XRFDC_MAX_I_UA(Revision)) {
            printf("ERROR: DAC%lu current must be %lu..%lu uA.\r\n",
                   (unsigned long)Tile, (unsigned long)XRFDC_MIN_I_UA(Revision),
                   (unsigned long)XRFDC_MAX_I_UA(Revision));
            return XRFDC_FAILURE;
        }
    }
    return XRFDC_SUCCESS;
}

/******************************************************************************/
/********************** Mixer and FIFO Configuration **************************/
/******************************************************************************/
static u32 configure_fine_mixer(XRFdc *InstancePtr, u32 Type, u32 Tile,
                                u32 Block, u32 Mode, double Frequency,
                                double Phase, u32 Zone)
{
    u32 Status;
    XRFdc_Mixer_Settings Mixer;

    Status = XRFdc_GetMixerSettings(InstancePtr, Type, Tile, Block, &Mixer);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_GetMixerSettings", Status);
    if (Mixer.MixerType != XRFDC_MIXER_TYPE_FINE || Mixer.MixerMode != Mode) {
        printf("ERROR: fine mixer layout differs from the fixed BD (%lu/%lu).\r\n",
               (unsigned long)Tile, (unsigned long)Block);
        return XRFDC_FAILURE;
    }
    /* Keep GUI fine-mixer scaling. TILE events support this high-speed ADC. */
    Mixer.EventSource = XRFDC_EVNT_SRC_TILE;
    Mixer.Freq = Frequency;
    Mixer.PhaseOffset = Phase;
    Status = XRFdc_SetNyquistZone(InstancePtr, Type, Tile, Block, Zone);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_SetNyquistZone", Status);
    Status = XRFdc_SetMixerSettings(InstancePtr, Type, Tile, Block, &Mixer);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_SetMixerSettings", Status);
    Status = XRFdc_ResetNCOPhase(InstancePtr, Type, Tile, Block);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_ResetNCOPhase", Status);
    Status = XRFdc_UpdateEvent(InstancePtr, Type, Tile, Block, XRFDC_EVENT_MIXER);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_UpdateEvent", Status);
    return XRFDC_SUCCESS;
}

u32 FeedbackRFdc_Configure(XRFdc *InstancePtr, const RFdc_UserSettings *Settings)
{
    u32 Status;
    u32 Index;
    u32 Type;
    u32 Tile;
    u32 Factor;
    u32 Zone;
    u32 Current;
    const RFdc_PathContract *Path;
    XRFdc_Mixer_Settings Mixer;
    XRFdc_DSA_Settings Dsa;

    Status = FeedbackRFdc_CheckUserSettings(InstancePtr, Settings);
    if (Status != XRFDC_SUCCESS)
        return Status;
    Status = FeedbackRFdc_CheckPlatform(&InstancePtr->RFdc_Config);
    if (Status != XRFDC_SUCCESS)
        return Status;
    main_adc_settings_captured[0] = 0U;
    main_adc_settings_captured[1] = 0U;
    for (Index = 0U; Index < RFDC_PATH_COUNT; ++Index) {
        Path = &RfdcPaths[Index];
        Status = XRFdc_CheckBlockEnabled(InstancePtr, Path->Type, Path->Tile,
                                          Path->Block);
        if (Status != XRFDC_SUCCESS)
            return api_failure("XRFdc_CheckBlockEnabled", Status);
        if (Path->Type == XRFDC_DAC_TILE)
            Status = XRFdc_GetInterpolationFactor(InstancePtr, Path->Tile,
                                                  Path->Block, &Factor);
        else
            Status = XRFdc_GetDecimationFactor(InstancePtr, Path->Tile,
                                               Path->Block, &Factor);
        if (Status != XRFDC_SUCCESS)
            return api_failure("XRFdc_GetInterpolation/DecimationFactor", Status);
        if (Factor != Path->Factor)
            return api_failure("fixed enabled-path interpolation/decimation",
                               XRFDC_FAILURE);
        Status = XRFdc_GetMixerSettings(InstancePtr, Path->Type, Path->Tile,
                                        Path->Block, &Mixer);
        if (Status != XRFDC_SUCCESS)
            return api_failure("XRFdc_GetMixerSettings(enabled path)", Status);
        if (Mixer.MixerType != Path->MixerType ||
            Mixer.MixerMode != Path->MixerMode ||
            (Path->MixerType == XRFDC_MIXER_TYPE_COARSE &&
             Mixer.CoarseMixFreq != XRFDC_COARSE_MIX_BYPASS))
            return api_failure("fixed enabled-path mixer/bypass", XRFDC_FAILURE);

        if (Path->Type == XRFDC_ADC_TILE && Path->Tile == MAIN_ADC_TILE) {
            /* Both ADC0 physical blocks retain their individual analog state. */
            Status = XRFdc_GetDSA(InstancePtr, Path->Tile, Path->Block,
                                  &main_adc_dsa_before[Path->Block]);
            if (Status != XRFDC_SUCCESS)
                return api_failure("XRFdc_GetDSA(ADC0 preserve)", Status);
            Status = XRFdc_GetNyquistZone(InstancePtr, Path->Type, Path->Tile,
                                          Path->Block,
                                          &main_adc_zone_before[Path->Block]);
            if (Status != XRFDC_SUCCESS)
                return api_failure("XRFdc_GetNyquistZone(ADC0 preserve)", Status);
            main_adc_settings_captured[Path->Block] = 1U;
        } else if (Path->Type == XRFDC_ADC_TILE) {
            Status = configure_fine_mixer(InstancePtr, Path->Type, Path->Tile,
                                          Path->Block, Path->MixerMode,
                                          Settings->feedback_adc_nco_mhz,
                                          Settings->feedback_adc_phase_deg,
                                          Settings->feedback_adc_nyquist_zone);
            if (Status != XRFDC_SUCCESS)
                return Status;
            Status = XRFdc_GetDSA(InstancePtr, Path->Tile, Path->Block, &Dsa);
            if (Status != XRFDC_SUCCESS)
                return api_failure("XRFdc_GetDSA(ADC1)", Status);
            Dsa.Attenuation = Settings->feedback_adc_attenuation_db;
            Dsa.DisableRTS = Settings->feedback_adc_disable_rts;
            Status = XRFdc_SetDSA(InstancePtr, Path->Tile, Path->Block, &Dsa);
            if (Status != XRFDC_SUCCESS)
                return api_failure("XRFdc_SetDSA(ADC1)", Status);
        } else {
            Zone = Path->Tile == MAIN_DAC_TILE ? Settings->main_dac_nyquist_zone :
                                                Settings->feedback_dac_nyquist_zone;
            Current = Path->Tile == MAIN_DAC_TILE ? Settings->main_dac_current_ua :
                                                   Settings->feedback_dac_current_ua;
            if (Path->MixerType == XRFDC_MIXER_TYPE_FINE) {
                Status = configure_fine_mixer(InstancePtr, Path->Type, Path->Tile,
                                              Path->Block, Path->MixerMode,
                                              Settings->feedback_dac_nco_mhz,
                                              Settings->feedback_dac_phase_deg, Zone);
                if (Status != XRFDC_SUCCESS)
                    return Status;
            } else {
                /* DAC2 remains coarse R2R bypass, without fine-NCO writes. */
                Status = XRFdc_SetNyquistZone(InstancePtr, Path->Type, Path->Tile,
                                              Path->Block, Zone);
                if (Status != XRFDC_SUCCESS)
                    return api_failure("XRFdc_SetNyquistZone(DAC2)", Status);
            }
            Status = XRFdc_SetDACVOP(InstancePtr, Path->Tile, Path->Block, Current);
            if (Status != XRFDC_SUCCESS)
                return api_failure("XRFdc_SetDACVOP(enabled DAC)", Status);
        }
    }
    /* Enable every enabled tile's FIFO, independent of TX/RX role. */
    for (Type = XRFDC_ADC_TILE; Type <= XRFDC_DAC_TILE; ++Type) {
        for (Tile = 0U; Tile < 4U; ++Tile) {
            u32 Enabled = Type == XRFDC_ADC_TILE ?
                InstancePtr->RFdc_Config.ADCTile_Config[Tile].Enable :
                InstancePtr->RFdc_Config.DACTile_Config[Tile].Enable;
            if (Enabled == 0U)
                continue;
            Status = XRFdc_SetupFIFO(InstancePtr, Type, Tile, 1U);
            if (Status != XRFDC_SUCCESS)
                return api_failure("XRFdc_SetupFIFO(enabled tile)", Status);
        }
    }
    return XRFDC_SUCCESS;
}

/******************************************************************************/
/********************** Runtime Readback **************************************/
/******************************************************************************/
static u32 readback_path(XRFdc *InstancePtr, u32 Type, u32 Tile, u32 Block,
                         u32 ConfigBlock,
                         u32 ExpectedType, u32 ExpectedMode, u32 ExpectedFactor,
                         u32 ExpectedWords, double ExpectedFabric, u32 ExpectedZone,
                         double Frequency, double Phase)
{
    u32 Status;
    XRFdc_Mixer_Settings Mixer;
    XRFdc_PLL_Settings Pll;
    XRFdc_BlockStatus BlockStatus;
    u32 Factor;
    u32 Zone;
    u32 Words;
    u8 FifoEnabled;
    double Fabric;

    Status = XRFdc_GetMixerSettings(InstancePtr, Type, Tile, Block, &Mixer);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_GetMixerSettings(readback)", Status);
    Status = XRFdc_GetPLLConfig(InstancePtr, Type, Tile, &Pll);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_GetPLLConfig", Status);
    Status = XRFdc_GetFIFOStatus(InstancePtr, Type, Tile, &FifoEnabled);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_GetFIFOStatus", Status);
    Status = XRFdc_GetBlockStatus(InstancePtr, Type, Tile, Block, &BlockStatus);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_GetBlockStatus", Status);
    if (Type == XRFDC_DAC_TILE)
        Status = XRFdc_GetInterpolationFactor(InstancePtr, Tile, Block, &Factor);
    else
        Status = XRFdc_GetDecimationFactor(InstancePtr, Tile, Block, &Factor);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_GetInterpolation/DecimationFactor", Status);
    /* Width and fabric MHz are configuration metadata, not live measurements.
     * GetDataWidth does not map high-speed ADC API1 to its raw config slot2. */
    if (Type == XRFDC_ADC_TILE)
        Words = InstancePtr->RFdc_Config.ADCTile_Config[Tile]
                    .ADCBlock_Digital_Config[ConfigBlock].DataWidth;
    else
        Words = XRFdc_GetDataWidth(InstancePtr, Type, Tile, Block);
    Fabric = XRFdc_GetFabClkFreq(InstancePtr, Type, Tile);
    printf("%s%lu/%lu: Fs=%.6f GSPS factor=%lu configured_words=%lu "
           "configured_fabric=%.6f MHz "
           "mixer=%u/%lu coarse=%lu FIFO=%u clocks=%u.\r\n",
           Type == XRFDC_DAC_TILE ? "DAC" : "ADC", (unsigned long)Tile,
           (unsigned long)Block, Pll.SampleRate, (unsigned long)Factor,
           (unsigned long)Words, Fabric, (unsigned int)Mixer.MixerType,
           (unsigned long)Mixer.MixerMode, (unsigned long)Mixer.CoarseMixFreq,
           (unsigned int)FifoEnabled, (unsigned int)BlockStatus.DataPathClocksStatus);
    if (!close_value(Pll.SampleRate, FEEDBACK_SAMPLE_GSPS) ||
        !close_value(Fabric, ExpectedFabric) || Factor != ExpectedFactor ||
        Words != ExpectedWords || FifoEnabled != 1U ||
        BlockStatus.DataPathClocksStatus != 1U ||
        Mixer.MixerType != ExpectedType || Mixer.MixerMode != ExpectedMode)
        return api_failure("RFDC fixed path / runtime FIFO/clocks readback",
                           XRFDC_FAILURE);
    if (ExpectedType == XRFDC_MIXER_TYPE_COARSE) {
        if (Mixer.CoarseMixFreq != XRFDC_COARSE_MIX_BYPASS)
            return api_failure("coarse R2R bypass readback", XRFDC_FAILURE);
    } else {
        printf("  NCO=%+.6f MHz phase=%.6f deg event=%lu.\r\n", Mixer.Freq,
               Mixer.PhaseOffset, (unsigned long)Mixer.EventSource);
        /* RFDC phase is truncated to 18 bits; allow one phase-code LSB. */
        if (Mixer.EventSource != XRFDC_EVNT_SRC_TILE ||
            !close_value(Mixer.Freq, Frequency) ||
            !(fabs(Mixer.PhaseOffset - Phase) <=
                180.0 / XRFDC_NCO_PHASE_MULTIPLIER + 0.000001))
            return api_failure("fine NCO/phase readback", XRFDC_FAILURE);
    }
    /* Main Rx0's Nyquist setting is preserved, indicated by ExpectedZone=0. */
    if (ExpectedZone != 0U) {
        Status = XRFdc_GetNyquistZone(InstancePtr, Type, Tile, Block, &Zone);
        if (Status != XRFDC_SUCCESS)
            return api_failure("XRFdc_GetNyquistZone", Status);
        if (Zone != ExpectedZone)
            return api_failure("Nyquist zone readback", XRFDC_FAILURE);
    }
    return XRFDC_SUCCESS;
}

static u32 readback_dac_current(XRFdc *InstancePtr, u32 Tile, u32 Block, u32 Current)
{
    u32 Status;
    u32 Actual;
    u32 Revision = InstancePtr->RFdc_Config.SiRevision;
    u32 Code = (u32)(((double)Current - XRFDC_MIN_I_UA_INT(Revision)) /
                      XRFDC_STEP_I_UA(Revision));
    u32 Expected = (u32)(Code * XRFDC_STEP_I_UA(Revision) +
                         XRFDC_MIN_I_UA_INT(Revision));

    Status = XRFdc_GetOutputCurr(InstancePtr, Tile, Block, &Actual);
    if (Status != XRFDC_SUCCESS)
        return api_failure("XRFdc_GetOutputCurr", Status);
    printf("DAC%lu/%lu current: requested=%lu uA quantized=%lu uA actual=%lu uA.\r\n",
           (unsigned long)Tile, (unsigned long)Block, (unsigned long)Current,
           (unsigned long)Expected, (unsigned long)Actual);
    if (Actual != Expected)
        return api_failure("DAC current readback", XRFDC_FAILURE);
    return XRFDC_SUCCESS;
}

u32 FeedbackRFdc_Readback(XRFdc *InstancePtr, const RFdc_UserSettings *Settings)
{
    u32 Status;
    u32 Index;
    u32 Zone;
    u32 Current;
    double Frequency;
    double Phase;
    const RFdc_PathContract *Path;
    XRFdc_DSA_Settings Dsa;

    Status = FeedbackRFdc_CheckUserSettings(InstancePtr, Settings);
    if (Status != XRFDC_SUCCESS)
        return Status;
    for (Index = 0U; Index < RFDC_PATH_COUNT; ++Index) {
        Path = &RfdcPaths[Index];
        Frequency = 0.0;
        Phase = 0.0;
        if (Path->Type == XRFDC_ADC_TILE && Path->Tile == MAIN_ADC_TILE) {
            if (!main_adc_settings_captured[Path->Block])
                return api_failure("ADC0 preserved settings unavailable", XRFDC_FAILURE);
            Zone = main_adc_zone_before[Path->Block];
        } else if (Path->Type == XRFDC_ADC_TILE) {
            Zone = Settings->feedback_adc_nyquist_zone;
            Frequency = Settings->feedback_adc_nco_mhz;
            Phase = Settings->feedback_adc_phase_deg;
        } else if (Path->Tile == MAIN_DAC_TILE) {
            Zone = Settings->main_dac_nyquist_zone;
        } else {
            Zone = Settings->feedback_dac_nyquist_zone;
            Frequency = Settings->feedback_dac_nco_mhz;
            Phase = Settings->feedback_dac_phase_deg;
        }
        Status = readback_path(InstancePtr, Path->Type, Path->Tile, Path->Block,
                               Path->ConfigBlock,
                               Path->MixerType, Path->MixerMode, Path->Factor,
                               Path->Words, Path->FabricMHz, Zone, Frequency, Phase);
        if (Status != XRFDC_SUCCESS)
            return Status;
        if (Path->Type == XRFDC_DAC_TILE) {
            Current = Path->Tile == MAIN_DAC_TILE ? Settings->main_dac_current_ua :
                                                   Settings->feedback_dac_current_ua;
            Status = readback_dac_current(InstancePtr, Path->Tile, Path->Block, Current);
            if (Status != XRFDC_SUCCESS)
                return Status;
        } else {
            Status = XRFdc_GetDSA(InstancePtr, Path->Tile, Path->Block, &Dsa);
            if (Status != XRFDC_SUCCESS)
                return api_failure("XRFdc_GetDSA(enabled ADC readback)", Status);
            printf("ADC%lu/%lu DSA=%.2f dB RTSdisable=%lu%s.\r\n",
                   (unsigned long)Path->Tile, (unsigned long)Path->Block,
                   (double)Dsa.Attenuation, (unsigned long)Dsa.DisableRTS,
                   Path->Tile == MAIN_ADC_TILE ? " (preserved)" : "");
            if (Path->Tile == MAIN_ADC_TILE) {
                if (!close_value(Dsa.Attenuation,
                                  main_adc_dsa_before[Path->Block].Attenuation) ||
                    Dsa.DisableRTS != main_adc_dsa_before[Path->Block].DisableRTS)
                    return api_failure("preserved ADC0 DSA/RTS readback", XRFDC_FAILURE);
            } else if (!close_value(Dsa.Attenuation,
                                     Settings->feedback_adc_attenuation_db) ||
                       Dsa.DisableRTS != Settings->feedback_adc_disable_rts) {
                return api_failure("ADC1 DSA/RTS readback", XRFDC_FAILURE);
            }
        }
    }
    printf("RFDC runtime checks passed for all 4 enabled tiles / 8 physical converters.\r\n");
    return XRFDC_SUCCESS;
}
