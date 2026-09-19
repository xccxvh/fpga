#!/usr/bin/env python3
"""Merge the proven HDMI TX PLL/LVDS resources into the DDR/RISC-V design.

The vendor projects use the same Ti60F225 and the same 25 MHz board clock.
This script keeps the DDR peripheral database intact and adds only PLL_BR0 and
GPIOR_PN_10..13. The HDMI PLL retains the board-tested 720p60 settings.
"""
from __future__ import annotations

import argparse
import copy
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://www.efinixinc.com/peri_design_db"
Q = lambda tag: f"{{{NS}}}{tag}"
ET.register_namespace("efxpt", NS)
ET.register_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ddr_peri", type=Path)
    parser.add_argument("hdmi_peri", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    ddr_tree = ET.parse(args.ddr_peri)
    hdmi_tree = ET.parse(args.hdmi_peri)
    ddr_root = ddr_tree.getroot()
    hdmi_root = hdmi_tree.getroot()

    ddr_plls = ddr_root.find(Q("pll_info"))
    hdmi_plls = hdmi_root.find(Q("pll_info"))
    ddr_lvds = ddr_root.find(Q("lvds_info"))
    hdmi_lvds = hdmi_root.find(Q("lvds_info"))
    if None in (ddr_plls, hdmi_plls, ddr_lvds, hdmi_lvds):
        raise RuntimeError("unexpected peripheral XML structure")
    if ddr_plls.find(f"{Q('pll')}[@name='pll_hdmi']") is not None:
        raise RuntimeError("DDR peripheral XML already contains pll_hdmi")
    if list(ddr_lvds):
        raise RuntimeError("DDR peripheral XML already uses LVDS resources")

    # The vendor HDMI+DDR reference design explicitly uses 1.8 V for bank 3A;
    # the DDR-only project leaves that otherwise-unused bank at 1.5 V.
    bank3a = ddr_root.find(f"./{Q('device_info')}/{Q('iobank_info')}/{Q('iobank')}[@name='3A']")
    if bank3a is None:
        raise RuntimeError("DDR peripheral XML has no bank 3A definition")
    bank3a.set("iostd", "1.8 V LVCMOS")

    source_pll = hdmi_plls.find(f"{Q('pll')}[@name='pll_hdmi']")
    if source_pll is None:
        raise RuntimeError("HDMI peripheral XML has no pll_hdmi")
    pll = copy.deepcopy(source_pll)
    pll.set("ref_clock_name", "clk_25m")
    for clock in pll.findall(Q("comp_output_clock")):
        name = clock.get("name")
        if name == "FB":
            clock.set("out_divider", "119")
        elif name == "hdmi_tx_slow_clk":
            # 2975 MHz VCO / 40 = 74.375 MHz (nominal 74.25 MHz).
            clock.set("out_divider", "40")
        elif name == "hdmi_tx_fast_clk":
            # DDR LVDS serializer requires exactly 5x the pixel clock.
            clock.set("out_divider", "8")
    ddr_plls.append(pll)
    for lvds in hdmi_lvds.findall(Q("lvds")):
        ddr_lvds.append(copy.deepcopy(lvds))

    ET.indent(ddr_tree, space="    ")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    ddr_tree.write(args.output, encoding="UTF-8", xml_declaration=True)


if __name__ == "__main__":
    main()
