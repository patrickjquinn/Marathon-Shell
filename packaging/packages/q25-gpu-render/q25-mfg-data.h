// SPDX-License-Identifier: GPL-2.0
/* MFG data verbatim except numeric indexes, linux-mediatek/linux 2ed59e4327792985e094d45c695629c76f3a0b9e. */
#include "mtk-pm-domains.h"
#define MT6789_TOP_AXI_PROT_EN_1_MFG1     (BIT(21))
#define MT6789_TOP_AXI_PROT_EN_2_MFG1     (BIT(5) | BIT(6))
#define MT6789_TOP_AXI_PROT_EN_MFG1       (BIT(21) | BIT(22))
#define MT6789_TOP_AXI_PROT_EN_2_MFG1_2ND (BIT(7))
static const struct scpsys_domain_data q25_mfg_data[] = {
    [2] =
        {
            .name              = "mfg0",
            .sta_mask          = BIT(2),
            .ctl_offs          = 0x308,
            .pwr_sta_offs      = 0x016c,
            .pwr_sta2nd_offs   = 0x0170,
            .sram_pdn_bits     = GENMASK(8, 8),
            .sram_pdn_ack_bits = GENMASK(12, 12),
            .caps              = MTK_SCPD_KEEP_DEFAULT_OFF | MTK_SCPD_DOMAIN_SUPPLY,
        },
    [3] =
        {
            .name              = "mfg1",
            .sta_mask          = BIT(3),
            .ctl_offs          = 0x30C,
            .pwr_sta_offs      = 0x016c,
            .pwr_sta2nd_offs   = 0x0170,
            .sram_pdn_bits     = GENMASK(8, 8),
            .sram_pdn_ack_bits = GENMASK(12, 12),
            .bp_cfg =
                {
                    BUS_PROT_WR_IGN(INFRA, MT6789_TOP_AXI_PROT_EN_1_MFG1, 0x02A8, 0x02AC, 0x0258),
                    BUS_PROT_WR_IGN(INFRA, MT6789_TOP_AXI_PROT_EN_2_MFG1, 0x0714, 0x0718, 0x0724),
                    BUS_PROT_WR_IGN(INFRA, MT6789_TOP_AXI_PROT_EN_MFG1, 0x02A0, 0x02A4, 0x0228),
                    BUS_PROT_WR_IGN(INFRA, MT6789_TOP_AXI_PROT_EN_2_MFG1_2ND, 0x0714, 0x0718,
                                    0x0724),
                },
            .caps = MTK_SCPD_KEEP_DEFAULT_OFF | MTK_SCPD_DOMAIN_SUPPLY,
        },
    [4] =
        {
            .name              = "mfg2",
            .sta_mask          = BIT(4),
            .ctl_offs          = 0x310,
            .pwr_sta_offs      = 0x016c,
            .pwr_sta2nd_offs   = 0x0170,
            .sram_pdn_bits     = GENMASK(8, 8),
            .sram_pdn_ack_bits = GENMASK(12, 12),
            .caps              = MTK_SCPD_KEEP_DEFAULT_OFF,
        },
    [5] =
        {
            .name              = "mfg3",
            .sta_mask          = BIT(5),
            .ctl_offs          = 0x314,
            .pwr_sta_offs      = 0x016c,
            .pwr_sta2nd_offs   = 0x0170,
            .sram_pdn_bits     = GENMASK(8, 8),
            .sram_pdn_ack_bits = GENMASK(12, 12),
            .caps              = MTK_SCPD_KEEP_DEFAULT_OFF,
        },
};
static const struct scpsys_soc_data q25_mfg_soc = {.domains_data = q25_mfg_data,
                                                   .num_domains  = ARRAY_SIZE(q25_mfg_data)};
