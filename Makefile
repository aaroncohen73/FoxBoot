MCU := atmega328p
AS := gavrasm
AVRDUDE :=avrdude

BOOT := boot.asm
OUT := boot

LFUSE := 0xFF
HFUSE := 0xDC
EFUSE := 0xFF

PROGRAMMER := usbasp
PROGRAMMER_PORT := /dev/ttyUSB0

.PHONY: all clean fuses read-fuses download

all: $(OUT).bin download

fuses:
	@$(AVRDUDE) -p $(MCU) -c $(PROGRAMMER) -P $(PROGRAMMER_PORT) -U lfuse:w:$(LFUSE):m -U hfuse:w:$(HFUSE):m -U efuse:w:$(EFUSE):m

read-fuses:
	@$(AVRDUDE) -p $(MCU) -c $(PROGRAMMER) -P $(PROGRAMMER_PORT) -U lfuse:r:$(LFUSE):m -U hfuse:r:$(HFUSE):m -U efuse:r:$(EFUSE):m

$(OUT).bin: $(BOOT)
	@$(AS) $<

download:
	@if [ -c $(PROGRAMMER_PORT) ];\
	then \
		$(AVRDUDE) -v -p $(MCU) -c $(PROGRAMMER) -P $(PROGRAMMER_PORT) -D -U flash:w:$(OUT).hex:i;\
	else \
		echo "Port $(PROGRAMMER_PORT) not found. Skipping programming..."; \
	fi;

clean:
	@rm -f $(OUT).hex $(OUT).lst
