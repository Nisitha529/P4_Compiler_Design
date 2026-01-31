

##    run: run the program
##         pass parameters to software via 'make RUN_ARGS= run'
RUN_ARGS?=

export DTOP=/home/vboxuser/p4fpga-examples/simple_router/bluesim
CONNECTALDIR=/home/vboxuser/connectal
BSVPATH = /home/vboxuser/p4fpga/src/bsv/infra:/home/vboxuser/connectal/bsv:/home/vboxuser/p4fpga-examples/simple_router/generatedbsv:/hw/bsv:/home/vboxuser/p4fpga-examples/simple_router/bluesim/generatedbsv:/home/vboxuser/p4fpga-examples/simple_router:/home/vboxuser/p4fpga/src/bsv/datapath:/home/vboxuser/p4fpga/src/bsv/generated:/home/vboxuser/p4fpga/src/bsv/library:/home/vboxuser/p4fpga/src/bsv/library/AsymmetricBRAM:/home/vboxuser/p4fpga/src/bsv/library/Bcam:/home/vboxuser/p4fpga/src/bsv/library/DMHC:/home/vboxuser/p4fpga/src/bsv:/home/vboxuser/connectal/lib/bsv:/home/vboxuser/connectal/generated/xilinx:/home/vboxuser/connectal/generated/altera

BOARD=bluesim
PROJECTDIR=/home/vboxuser/p4fpga-examples/simple_router/bluesim
MKTOP=mkXsimTop
OS=ubuntu
TOOLCHAIN?=
DUT=mkxsimtop

export INTERFACES = MemServerRequest MMURequest MemServerIndication MMUIndication XsimMsgRequest XsimMsgIndication MainRequest MainIndication MemServerIndication
BSVFILES = /home/vboxuser/p4fpga/src/bsv/infra/Main.bsv /home/vboxuser/p4fpga/src/bsv/infra/MainAPI.bsv /home/vboxuser/connectal/bsv/ConnectalMemory.bsv /home/vboxuser/connectal/bsv/XsimIF.bsv /home/vboxuser/p4fpga-examples/simple_router/generatedbsv/ConnectalTypes.bsv /hw/bsv/DbgDefs.bsv /home/vboxuser/p4fpga-examples/simple_router/bluesim/generatedbsv/IfcNames.bsv /home/vboxuser/connectal/bsv/DisplayInd.bsv
XCIFILES = 

BSCFLAGS_PROJECT = -show-range-conflict +RTS -K596777766 -RTS -demote-errors G0066:G0045 -suppress-warnings G0046:G0020:G0023:S0015:S0080:S0039 -steps-max-intervals 20 -no-warn-action-shadowing
SIM_CXX_PROJECT = /home/vboxuser/p4fpga-examples/simple_router/matchtable_model.cpp /home/vboxuser/p4fpga/src/bsv/library/AsymmetricBRAM/mem_model.c
VERILATOR_PROJECT_ARGS = 
CFLAGS_PROJECT = 
CXXFLAGS_PROJECT = -std=c++11 -L"/home/hwang/questasim/questa_sim/gcc-4.3.3-linux_x86_64/lib64"
XELABFLAGS = 
XSIMFLAGS  = -R
AWSFLAGS   = 
TOPBSVFILE = /home/vboxuser/connectal/bsv/XsimTop.bsv
BSVDEFINES =  -D PARSER=Parser -D DEPARSER=Deparser -D MATCHTABLE=Control -D TYPEDEF=StructDefines -D NUM_RXCHAN=1 -D NUM_TXCHAN=1 -D NUM_HOSTCHAN=1 -D STREAM -D NicVersion=1685525216 -D DataBusWidth=128 -D IMPORT_HOSTIF -D BYTE_ENABLES -D ClockDefaultParam -D ConnectalVersion=22.05.23b -D NumberOfMasters=1 -D PinType=Empty -D PinTypeInclude=Misc -D NumberOfUserTiles=1 -D SlaveDataBusWidth=32 -D SlaveControlAddrWidth=5 -D BurstLenSize=12 -D project_dir=$(DTOP) -D MainClockPeriod=20 -D DerivedClockPeriod=10.000000 -D CnocTop -D XsimHostInterface -D PhysAddrWidth=40 -D SIMULATION -D CONNECTAL_BITS_DEPENDENCES=bsim -D BOARD_bluesim
QTUSED = 
export BSVDEFINES_LIST = PARSER=Parser DEPARSER=Deparser MATCHTABLE=Control TYPEDEF=StructDefines NUM_RXCHAN=1 NUM_TXCHAN=1 NUM_HOSTCHAN=1 STREAM NicVersion=1685525216 DataBusWidth=128 IMPORT_HOSTIF BYTE_ENABLES ClockDefaultParam ConnectalVersion=22.05.23b NumberOfMasters=1 PinType=Empty PinTypeInclude=Misc NumberOfUserTiles=1 SlaveDataBusWidth=32 SlaveControlAddrWidth=5 BurstLenSize=12 project_dir=$(DTOP) MainClockPeriod=20 DerivedClockPeriod=10.000000 CnocTop XsimHostInterface PhysAddrWidth=40 SIMULATION CONNECTAL_BITS_DEPENDENCES=bsim BOARD_bluesim
export DUT_NAME = mkXsimTop





PARSER=Parser
DEPARSER=Deparser
MATCHTABLE=Control
TYPEDEF=StructDefines
NUM_RXCHAN=1
NUM_TXCHAN=1
NUM_HOSTCHAN=1
STREAM=STREAM
NicVersion=1685525216
DataBusWidth=128
IMPORT_HOSTIF=IMPORT_HOSTIF
BYTE_ENABLES=BYTE_ENABLES
ClockDefaultParam=ClockDefaultParam
ConnectalVersion=22.05.23b
NumberOfMasters=1
PinType=Empty
PinTypeInclude=Misc
NumberOfUserTiles=1
SlaveDataBusWidth=32
SlaveControlAddrWidth=5
BurstLenSize=12
project_dir=$(DTOP)
MainClockPeriod=20
DerivedClockPeriod=10.000000
CnocTop=CnocTop
XsimHostInterface=XsimHostInterface
PhysAddrWidth=40
SIMULATION=SIMULATION
CONNECTAL_BITS_DEPENDENCES=bsim
BOARD_bluesim=BOARD_bluesim


include $(CONNECTALDIR)/scripts/Makefile.connectal.build


export VERILOG_PATH=verilog /home/vboxuser/p4fpga/src/bsv/verilog /home/vboxuser/connectal/verilog $(BLUESPEC_VERILOG)
MODELSIM_FILES= 
FPGAMAKE=$(CONNECTALDIR)/../fpgamake/fpgamake
fpgamake.mk: $(VFILE) Makefile prepare_bin_target
	$(Q)if [ -f ../synth-ip.tcl ]; then vivado -mode batch -source ../synth-ip.tcl; fi
	$(Q)$(FPGAMAKE) $(FPGAMAKE_VERBOSE) -o fpgamake.mk --board=bluesim --part=xc7z020clg484-1  --floorplan=      -t $(MKTOP)  --cachedir="" -b hw/mkTop.bit   $(VERILOG_PATH)

synth.%:fpgamake.mk
	$(MAKE) -f fpgamake.mk Synth/$*/$*-synth.dcp

hw/mkTop.bit: prepare_bin_target  fpgamake.mk
	$(Q)mkdir -p hw
	$(Q)$(MAKE) -f fpgamake.mk
ifneq ($(XILINX),)
	$(Q)rsync -rav --include="*/" --include="*.rpt" --exclude="*" Impl/ bin
else ifneq ($(ALTERA),)
	$(Q)cp -f $(MKTOP).sof bin
endif




