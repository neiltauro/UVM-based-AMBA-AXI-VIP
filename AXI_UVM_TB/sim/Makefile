#==============================================================================
# Makefile  –  AXI VIP  (1 master / 1 slave)
# Tests:
#   single_write_test      – single-beat write
#   single_read_test       – single-beat read
#   fixed_burst_test       – FIXED burst
#   incr_burst_test        – INCR  burst
#   wrap_burst_test        – WRAP  burst
#   outstanding_write_test – multiple outstanding writes
#   outstanding_read_test  – multiple outstanding reads
#==============================================================================

SIMULATOR = VCS

FSDB_PATH = /home/cad/eda/SYNOPSYS/VERDI_2022/verdi/T-2022.06-SP1/share/PLI/VCS/LINUX64

RTL  = ../rtl/axi_if.sv
SVTB_TOP = ../top/top.sv
INC  = +incdir+../rtl +incdir+../tb +incdir+../test +incdir+../master_uvc +incdir+../slave_uvc
PKG  = ../test/axi_pkg.sv

# ---- aliases ----
clean              : clean_$(SIMULATOR)
sv_cmp             : sv_cmp_$(SIMULATOR)
single_write_test  : run_single_write_$(SIMULATOR)
single_read_test   : run_single_read_$(SIMULATOR)
fixed_burst_test   : run_fixed_burst_$(SIMULATOR)
incr_burst_test    : run_incr_burst_$(SIMULATOR)
wrap_burst_test    : run_wrap_burst_$(SIMULATOR)
outstanding_write  : run_outstanding_write_$(SIMULATOR)
outstanding_read   : run_outstanding_read_$(SIMULATOR)
regression_test    : run_regression_$(SIMULATOR)
regress            : regress_$(SIMULATOR)
report             : report_$(SIMULATOR)
cov                : cov_$(SIMULATOR)

help:
	@echo "============================================================"
	@echo " make single_write_test   – single-beat write"
	@echo " make single_read_test    – single-beat read"
	@echo " make fixed_burst_test    – FIXED burst"
	@echo " make incr_burst_test     – INCR  burst"
	@echo " make wrap_burst_test     – WRAP  burst"
	@echo " make outstanding_write   – multiple outstanding writes"
	@echo " make outstanding_read    – multiple outstanding reads"
	@echo " make regression_test     – all 7 sequences in one run (full regression)"
	@echo " make regress             – run all 7 tests + regression_test"
	@echo " make report              – merge coverage"
	@echo " make cov                 – open coverage GUI"
	@echo "============================================================"

#==============================================================================
# VCS
#==============================================================================
VCS_COMPILE = vcs -l vcs.log -timescale=1ns/1ps -sverilog \
              -ntb_opts uvm -debug_access+all -full64 -kdb -lca \
              -P $(FSDB_PATH)/novas.tab $(FSDB_PATH)/pli.a \
              $(INC) $(RTL) $(PKG) $(SVTB_TOP) \
              +define+UVM_REPORT_DISABLE_FILE_LINE

VCS_SIM = ./simv +ntb_random_seed_automatic +UVM_VERBOSITY=UVM_LOW

sv_cmp_VCS:
	$(VCS_COMPILE)

run_single_write_VCS: clean sv_cmp_VCS
	$(VCS_SIM) +fsdbfile+single_write.fsdb -cm_dir ./cov1 +UVM_TESTNAME=single_write_test
	urg -dir cov1.vdb -format both -report rpt_single_write

run_single_read_VCS:
	$(VCS_SIM) +fsdbfile+single_read.fsdb  -cm_dir ./cov2 +UVM_TESTNAME=single_read_test
	urg -dir cov2.vdb -format both -report rpt_single_read

run_fixed_burst_VCS:
	$(VCS_SIM) +fsdbfile+fixed_burst.fsdb  -cm_dir ./cov3 +UVM_TESTNAME=fixed_burst_test
	urg -dir cov3.vdb -format both -report rpt_fixed_burst

run_incr_burst_VCS:
	$(VCS_SIM) +fsdbfile+incr_burst.fsdb   -cm_dir ./cov4 +UVM_TESTNAME=incr_burst_test
	urg -dir cov4.vdb -format both -report rpt_incr_burst

run_wrap_burst_VCS:
	$(VCS_SIM) +fsdbfile+wrap_burst.fsdb   -cm_dir ./cov5 +UVM_TESTNAME=wrap_burst_test
	urg -dir cov5.vdb -format both -report rpt_wrap_burst

run_outstanding_write_VCS:
	$(VCS_SIM) +fsdbfile+out_write.fsdb    -cm_dir ./cov6 +UVM_TESTNAME=outstanding_write_test
	urg -dir cov6.vdb -format both -report rpt_out_write

run_outstanding_read_VCS:
	$(VCS_SIM) +fsdbfile+out_read.fsdb     -cm_dir ./cov7 +UVM_TESTNAME=outstanding_read_test
	urg -dir cov7.vdb -format both -report rpt_out_read

run_regression_VCS:
	$(VCS_SIM) +fsdbfile+regression.fsdb   -cm_dir ./cov8 +UVM_TESTNAME=regression_test
	urg -dir cov8.vdb -format both -report rpt_regression

report_VCS:
	urg -dir cov1.vdb cov2.vdb cov3.vdb cov4.vdb cov5.vdb cov6.vdb cov7.vdb cov8.vdb \
	    -dbname merged/merged -format both -report rpt_merged

regress_VCS: clean_VCS sv_cmp_VCS \
	run_single_write_VCS run_single_read_VCS \
	run_fixed_burst_VCS  run_incr_burst_VCS  run_wrap_burst_VCS \
	run_outstanding_write_VCS run_outstanding_read_VCS \
	run_regression_VCS \
	report_VCS

cov_VCS:
	verdi -cov -covdir merged.vdb

view_single_write_VCS:  ; verdi -ssf single_write.fsdb
view_single_read_VCS:   ; verdi -ssf single_read.fsdb
view_fixed_burst_VCS:   ; verdi -ssf fixed_burst.fsdb
view_incr_burst_VCS:    ; verdi -ssf incr_burst.fsdb
view_wrap_burst_VCS:    ; verdi -ssf wrap_burst.fsdb
view_outstanding_write_VCS: ; verdi -ssf out_write.fsdb
view_outstanding_read_VCS:  ; verdi -ssf out_read.fsdb
view_regression_VCS:        ; verdi -ssf regression.fsdb

clean_VCS:
	rm -rf simv* csrc* *.tmp *.vpd *.vdb *.key *.log *hdrs.h \
	       rpt_* merged *.fsdb novas* verdi* cov?
	clear

#==============================================================================
# Questa
#==============================================================================
sv_cmp_Questa:
	vlib work
	vmap work work
	vlog -work work $(INC) $(RTL) $(PKG) $(SVTB_TOP)

VSIM_BASE = vsim -cvgperinstance -vopt -voptargs=+acc -coverage -sva \
            -sv_seed random work.top

run_single_write_Questa: sv_cmp_Questa
	$(VSIM_BASE) -wlf single_write.wlf -l log1.log -c \
	  -do "log -r /*; coverage save -onexit cov1; run -all; exit" \
	  +UVM_TESTNAME=single_write_test
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html cov1

run_single_read_Questa:
	$(VSIM_BASE) -wlf single_read.wlf -l log2.log -c \
	  -do "log -r /*; coverage save -onexit cov2; run -all; exit" \
	  +UVM_TESTNAME=single_read_test
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html cov2

run_fixed_burst_Questa:
	$(VSIM_BASE) -wlf fixed_burst.wlf -l log3.log -c \
	  -do "log -r /*; coverage save -onexit cov3; run -all; exit" \
	  +UVM_TESTNAME=fixed_burst_test
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html cov3

run_incr_burst_Questa:
	$(VSIM_BASE) -wlf incr_burst.wlf -l log4.log -c \
	  -do "log -r /*; coverage save -onexit cov4; run -all; exit" \
	  +UVM_TESTNAME=incr_burst_test
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html cov4

run_wrap_burst_Questa:
	$(VSIM_BASE) -wlf wrap_burst.wlf -l log5.log -c \
	  -do "log -r /*; coverage save -onexit cov5; run -all; exit" \
	  +UVM_TESTNAME=wrap_burst_test
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html cov5

run_outstanding_write_Questa:
	$(VSIM_BASE) -wlf out_write.wlf -l log6.log -c \
	  -do "log -r /*; coverage save -onexit cov6; run -all; exit" \
	  +UVM_TESTNAME=outstanding_write_test
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html cov6

run_outstanding_read_Questa:
	$(VSIM_BASE) -wlf out_read.wlf -l log7.log -c \
	  -do "log -r /*; coverage save -onexit cov7; run -all; exit" \
	  +UVM_TESTNAME=outstanding_read_test
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html cov7

run_regression_Questa:
	$(VSIM_BASE) -wlf regression.wlf -l log8.log -c \
	  -do "log -r /*; coverage save -onexit cov8; run -all; exit" \
	  +UVM_TESTNAME=regression_test
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html cov8

report_Questa:
	vcover merge merged_cov cov1 cov2 cov3 cov4 cov5 cov6 cov7 cov8
	vcover report -cvg -details -nocompactcrossbins -codeAll -assert -directive -html merged_cov

regress_Questa: clean_Questa sv_cmp_Questa \
	run_single_write_Questa run_single_read_Questa \
	run_fixed_burst_Questa  run_incr_burst_Questa  run_wrap_burst_Questa \
	run_outstanding_write_Questa run_outstanding_read_Questa \
	run_regression_Questa \
	report_Questa cov_Questa

cov_Questa:
	firefox covhtmlreport/index.html &

clean_Questa:
	rm -rf transcript* *.log fcover* covhtml* cov? merged_cov *.wlf modelsim.ini work
	clear

#==============================================================================