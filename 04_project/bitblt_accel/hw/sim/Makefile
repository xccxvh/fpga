IVERILOG ?= iverilog
VVP ?= vvp
BUILD := build
RTL := ../rtl

.PHONY: test engine arbiters clean

test: engine arbiters

engine: $(BUILD)/tb_bitblt_engine.vvp
	$(VVP) $<

arbiters: $(BUILD)/tb_axi_arbiters.vvp
	$(VVP) $<

$(BUILD):
	mkdir -p $@

$(BUILD)/tb_bitblt_engine.vvp: tb_bitblt_engine.sv $(RTL)/bitblt_engine.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_bitblt_engine -o $@ $^

$(BUILD)/tb_axi_arbiters.vvp: tb_axi_arbiters.sv \
	$(RTL)/axi_write_arbiter_2to1.v $(RTL)/axi_read_arbiter_2to1.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_axi_arbiters -o $@ $^

clean:
	rm -rf $(BUILD)
