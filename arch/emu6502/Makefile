TRG=rom.o65

XA=xa -k -XMASM
FILE=file65
RELOC=reloc65

all: $(TRG)

ROMSTART=36352	# $8e00

$(TRG): 
	${XA} -R -I../../include -I.. -I../.. \
		-DROMSTART=$(ROMSTART) \
		-bt $$(($(ROMSTART)-2)) -bd 768 -bz 8 -bb 2640 rom.a65 -o rom.o65 -l rom.lab;
	${FILE} rom.o65;

clean:
	rm -f $(TRG) rom.lab rom.o65 reloc.lst
