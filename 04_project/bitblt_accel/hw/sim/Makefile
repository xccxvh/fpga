IVERILOG ?= iverilog
VVP ?= vvp
BUILD := build
RTL := ../rtl

.PHONY: test engine control arbiters display-control control-demux display-dma video-pipeline async-fifo clean

test: engine control arbiters display-control control-demux display-dma video-pipeline async-fifo

engine: $(BUILD)/tb_bitblt_engine.vvp
	$(VVP) $<

control: $(BUILD)/tb_bitblt_ctrl_axi.vvp
	$(VVP) $<

arbiters: $(BUILD)/tb_axi_arbiters.vvp
	$(VVP) $<

display-control: $(BUILD)/tb_display_ctrl_axi.vvp
	$(VVP) $<

control-demux: $(BUILD)/tb_axi_ctrl_demux_1to2.vvp
	$(VVP) $<

display-dma: $(BUILD)/tb_display_dma_axi.vvp
	$(VVP) $<

video-pipeline: $(BUILD)/tb_video_pipeline.vvp
	$(VVP) $<

async-fifo: $(BUILD)/tb_async_fifo.vvp
	$(VVP) $<

$(BUILD):
	mkdir -p $@

$(BUILD)/tb_bitblt_engine.vvp: tb_bitblt_engine.sv $(RTL)/bitblt_engine.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_bitblt_engine -o $@ $^

$(BUILD)/tb_bitblt_ctrl_axi.vvp: tb_bitblt_ctrl_axi.sv $(RTL)/bitblt_ctrl_axi.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_bitblt_ctrl_axi -o $@ $^

$(BUILD)/tb_axi_arbiters.vvp: tb_axi_arbiters.sv \
	$(RTL)/axi_write_arbiter_2to1.v $(RTL)/axi_read_arbiter_2to1.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_axi_arbiters -o $@ $^

$(BUILD)/tb_display_ctrl_axi.vvp: tb_display_ctrl_axi.sv $(RTL)/display_ctrl_axi.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_display_ctrl_axi -o $@ $^

$(BUILD)/tb_axi_ctrl_demux_1to2.vvp: tb_axi_ctrl_demux_1to2.sv $(RTL)/axi_ctrl_demux_1to2.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_axi_ctrl_demux_1to2 -o $@ $^

$(BUILD)/tb_display_dma_axi.vvp: tb_display_dma_axi.sv $(RTL)/display_dma_axi.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_display_dma_axi -o $@ $^

$(BUILD)/tb_video_pipeline.vvp: tb_video_pipeline.sv \
	$(RTL)/video_timing_1280x720.v $(RTL)/pixel_unpack_rgb565.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_video_pipeline -o $@ $^

$(BUILD)/tb_async_fifo.vvp: tb_async_fifo.sv $(RTL)/async_fifo.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_async_fifo -o $@ $^

clean:
	rm -rf $(BUILD)
