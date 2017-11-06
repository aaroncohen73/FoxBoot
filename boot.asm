; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.

.NOLIST
.INCLUDE "m328def.inc"
.LIST

;; CONSTANT DEFINITIONS

.EQU F_CPU=		16000000	; 16 MHz clock

.EQU BL_INT=		0xFF		; Interrupt byte sent to ATMega during reset sequence
.EQU BL_PRGM_WRITE=	0x11		; Write program memory command
.EQU BL_PRGM_READ=	0x22		; Read program memory command
.EQU BL_PRGM_ERASE=	0x44		; Erase program memory command
.EQU BL_EXIT=		0x88		; Exit bootloader/Start main program command

.EQU BL_ACK=		0x5A		; ACK/Ready byte
.EQU BL_NACK=		0xA5		; NACK byte

.EQU BL_INT_WAIT=	20		; Wait 20 ms for bootloader interrupt symbol

.EQU PAGESIZEB=		PAGESIZE*2	; Flash page size in bytes

;; REGISTER DEFINITIONS

.DEF REG_SPM1=		R0		; Registers for writing/reading from page buffer during
.DEF REG_SPM2=		R1		; SPM instructions

.DEF REG1=		R16		; General purpose registers for things like passing
.DEF REG2=		R17		; values to/from subroutines and performing quick
.DEF REG3=		R18		; arithmetic computations
.DEF REG4=		R19
.DEF REG5=		R20

.DEF REG_LOOP=		R23		; Loop counter

.DEF REG_IO1=		R24		; Temporary registers for writing to I/O registers
.DEF REG_IO2=		R25

;; RESERVED DATA SEGMENT

.DSEG
prgm_packet: .BYTE PAGESIZEB		; Reserved RAM space for programming command packets

;; CODE SEGMENT

.CSEG

.ORG SECONDBOOTSTART			; Bootloader section starts at 0x3e00

rjmp boot_main				; Start the bootloader

;; Main bootloader entry point
boot_main:
	ldi REG_IO1, low(RAMEND)	; Initialize stack pointer at end of RAM
	ldi REG_IO2, high(RAMEND)
	out SPL, REG_IO1
	out SPH, REG_IO2

	ldi REG_IO1, (1<<PRTWI)|(1<<PRTIM2)|(1<<PRTIM0)|(1<<PRSPI)|(1<<PRADC)	; Disable unused peripherals
	sts PRR, REG_IO1

	ldi REG_IO1, (1<<RXEN0)|(1<<TXEN0)					; Enable UART0 RX and TX
	sts UCSR0B, REG_IO1

	ldi REG_IO1, (1 << UPM01)	; Enable UART0 even parity bit check
	sts UCSR0C, REG_IO1

	ldi REG_IO1, 25			; Set UART0 baud rate to 19.2 kbps
	sts UBRR0L, REG_IO1

	ldi REG_LOOP, BL_INT_WAIT	; Initialize loop counter with number of milliseconds to wait

check_interrupt:
	rcall sub_wait_1ms		; Delay for 1 millisecond

	lds REG_IO1, UCSR0A		; Check for UART0 RX Complete flag
	sbrs REG_IO1, RXC0		; If UART0 RX Complete not set, go to next loop iteration
	rjmp check_interrupt_loop

	lds REG_IO1, UDR0		; Load contents of UART0 data register
	cpi REG_IO1, BL_INT		; Check for interrupt byte
	breq boot_start			; If interrupt byte recieved, start the bootloader

check_interrupt_loop:
	dec REG_LOOP
	cpi REG_LOOP, 0			; If wait time is up without recieving bootloader interrupt, start main program
	breq boot_end

	rjmp check_interrupt		; If wait time is not up yet, go to next loop iteration

boot_start:
	ldi REG1, BL_ACK
	rcall sub_uart_tx_single

boot_loop:
	rcall sub_uart_rx_single
	cpi REG1, BL_PRGM_WRITE		; Write program command
	brne +2
	rjmp prgm_write
	cpi REG1, BL_PRGM_READ		; Read program command (to verify correct write)
	brne +2
	rjmp prgm_read
	cpi REG1, BL_PRGM_ERASE		; Erase program command
	brne +2
	rjmp prgm_erase
	cpi REG1, BL_EXIT		; Exit bootloader and start main program command
	breq boot_end

	ldi REG1, BL_NACK		; If command not recognized, NACK and go to beginning of loop
	rcall sub_uart_tx_single

	rjmp boot_loop

boot_end:
	ldi REG_IO1, 0xFF		; Put all peripherals into power saving mode and start main program
	sts PRR, REG_IO1
	rjmp FLASHEND+1

;; Write a page of program data to flash
prgm_write:
	ldi REG1, BL_ACK		; Respond to command with ACK

	call sub_uart_rx_single		; Receive page number of flash to write
	mov REG5, REG1

	ldi XL, LOW(prgm_packet)	; Load address of packet buffer into X register
	ldi XH, HIGH(prgm_packet)

	ldi REG_LOOP, PAGESIZE		; Initialize loop counter with page size in words

prgm_write_rx_loop:
	call sub_uart_rx_single		; Receive MSB of word
	st X+, REG1
	call sub_uart_rx_single		; Receive LSB of word
	st X+, REG1

	dec REG_LOOP
	cpi REG_LOOP, 0
	brne prgm_write_rx_loop

	;; Check packet CRC

	call sub_uart_rx_single		; Receive MSB of packet CRC
	mov REG3, REG1
	call sub_uart_rx_single		; Receive LSB of packet CRC
	mov REG4, REG1

	ldi XH, HIGH(prgm_packet)	; Calculate CRC of packet minus received CRC
	ldi XL, LOW(prgm_packet)
	ldi REG1, PAGESIZEB
	rcall sub_calc_crc

	cpc REG1, REG3			; Check calculated CRC against received CRC, error if not equal
	cpc REG2, REG4
	brne prgm_write_error

	;; Write data into page buffer

	ldi XH, HIGH(prgm_packet)	; Set up X register with address of received page data
	ldi XL, LOW(prgm_packet)

	ldi ZH, 0x00 			; Set up PCWORD with first address inside page buffer (PCWORD=Z[6:1])
	ldi ZL, 0x00

	ldi REG_LOOP, PAGESIZE		; Initialize loop counter with number of words per page

prgm_write_loop:
	ld REG_SPM1, X+			; Load word into R1:R0
	ld REG_SPM2, X+

	ldi REG_IO1, (1<<SPMEN)		; Write word to data buffer
	out SPMCSR, REG_IO1
	spm

	adiw ZH:ZL, 2			; Increment page buffer address

	dec REG_LOOP			; Decrease loop counter
	cpi REG_LOOP, 0
	brne prgm_write_loop

	;; Write page buffer into flash memory

	mov REG1, REG5			; Get the address of the page to write
	mov REG2, REG1			; (and copy to second register)

	lsr REG1			; Set up upper 7 bits of page address (PCPAGE[7:1]=ZH[6:0])
	mov ZH, REG1

	ror REG2			; Set up lower 1 bit of page address (PCPAGE[0]=ZL[7])
	andi REG2, 0x80
	mov ZL, REG2

	ldi REG_IO1, (1<<PGWRT)|(1<<SPMEN)	; Perform page write
	out SPMCSR, REG_IO1
	spm

	ldi REG1, BL_ACK		; Send ACK and exit write mode
	rcall sub_uart_tx_single
	rjmp prgm_write_loop_end

prgm_write_error:
	ldi REG1, BL_NACK		; Send NACK on error
	rcall sub_uart_tx_single

prgm_write_loop_end:
	rjmp boot_loop

;; Read a page of program data from flash
prgm_read:
	ldi REG1, BL_ACK		; Resond to command with ACK and start read mode
	rcall sub_uart_tx_single

	rcall sub_uart_rx_single	; Get the address of the page to read
	mov REG2, REG1			; (and copy to second register)

	lsr REG1			; Set up upper 7 bits of page address (PCPAGE[7:1]=ZH[6:0])
	mov ZH, REG1

	ror REG2			; Set up lower 1 bit of page address (PCPAGE[0]=ZL[7])
	andi REG2, 0x80
	mov ZL, REG2

	ldi XL, LOW(prgm_packet)	; Load address of program data buffer into X
	ldi XH, HIGH(prgm_packet)

	ldi REG_LOOP, PAGESIZEB		; Initialize loop counter with number of bytes to read

prgm_read_loop:
	lpm REG1, Z+			; Load byte of program memory and store into buffer
	st X+, REG1

	dec REG_LOOP			; Decrease loop counter
	cpi REG_LOOP, 0
	brne prgm_read_loop

	;; Transmit program data read from flash

	ldi XH, HIGH(prgm_packet)	; Calculate CRC of flash program data
	ldi XL, LOW(prgm_packet)
	ldi REG1, PAGESIZEB
	rcall sub_calc_crc

	mov REG3, REG1			; Copy CRC to temporary registers
	mov REG4, REG2

	ldi XL, LOW(prgm_packet)	; Load address of program data buffer into X
	ldi XH, HIGH(prgm_packet)

	ldi REG_LOOP, PAGESIZEB		; Initialize loop counter with number of bytes to transmit

prgm_read_tx_loop:
	ld REG1, X+			; Transmit single byte of program data
	rcall sub_uart_tx_single

	dec REG_LOOP			; Decrease loop counter
	cpi REG_LOOP, 0
	brne prgm_read_tx_loop

	;; Transmit CRC of program data

	mov REG1, REG3			; Transmit MSB of CRC
	rcall sub_uart_tx_single

	mov REG1, REG4			; Transmit LSB of CRC
	rcall sub_uart_tx_single

	ldi REG1, BL_ACK		; Send ACK and exit read mode
	rcall sub_uart_tx_single

	rjmp boot_loop

;; Erase a page of program data in flash
prgm_erase:
	ldi REG1, BL_ACK		; Respond to command with ACK and start erase mode
	rcall sub_uart_tx_single

	rcall sub_uart_rx_single	; Get the address of the page to erase
	mov REG2, REG1			; (and copy to second register)

	lsr REG1			; Set up upper 7 bits of page address (PCPAGE[7:1]=ZH[6:0])
	mov ZH, REG1

	ror REG2			; Set up lower 1 bit of page address (PCPAGE[0]=ZL[7])
	andi REG2, 0x80
	mov ZL, REG2

	ldi REG_IO1, (1<<PGERS)|(1<<SPMEN)	; Perform page erase
	out SPMCSR, REG_IO1
	spm

	ldi REG1, BL_ACK		; Send ACK and exit erase mode
	rcall sub_uart_tx_single

	rjmp boot_loop

;; Transmit a single byte of data over UART0
;; Pre:  REG1 contains the value to be transmitted
;; Post: N/A
sub_uart_tx_single:
	lds REG_IO1, UCSR0A		; Wait for UART0 transmit buffer to be empty
	sbrs REG_IO1, UDRE0
	rjmp sub_uart_tx_single

	sts UDR0, REG1			; Store byte to be sent in UART0 data register
	ret

;; Receive a single byte of data over UART0
;; Pre:  N/A
;; Post: REG1 contains the received value
sub_uart_rx_single:
	lds REG_IO1, UCSR0A		; Wait for UART0 RX Complete flag
	sbrs REG_IO1, RXC0
	rjmp sub_uart_rx_single

	lds REG1, UDR0			; Store received byte
	ret

;; Calculate the CRC of a packet of data
;; Pre:  X contains the address of the data buffer to check
;;       REG1 contains the size of the data buffer
;; Post: REG1:REG2 contains the CRC of the data
sub_calc_crc:
	; TODO
	ret

;; Delay for 1 millisecond
;; Pre:  N/A
;; Post: N/A
sub_wait_1ms:
	ldi REG_IO1, (1<<CS11)		; Set TIMER1 clock source = I/O clock / 8 (2 MHz)
	sts TCCR1B, REG_IO1

	ldi REG_IO1, 0xD0		; Set TIMER1 compare value to 1000 cycles (2 ms)
	ldi REG_IO2, 0x07
	sts OCR1AL, REG_IO1
	sts OCR1AH, REG_IO2

	ldi REG_IO1, 0x00		; Reset timer
	sts TCNT1H, REG_IO1
	sts TCNT1L, REG_IO1

	ldi REG_IO1, (1<<OCF1A)		; Reset output compare flag
	out TIFR1, REG_IO1

wait_check:
	sbis TIFR1, OCF1A		; Loop until output compare flag is set
	rjmp wait_check

	ret