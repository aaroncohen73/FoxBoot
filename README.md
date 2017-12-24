# FoxBoot - An AVR Bootloader for Foxes
#### ...but humans can use it too

FoxBoot is a lightweight self-programming bootloader for AVR microcontrollers.
Currently, the only supported microcontroller is the ATmega328p, but support
for others is planned in the future!

FoxBoot is licensed under the GNU Public License Version 3 or higher. For more
information see the COPYING file or visit https://www.gnu.org/licenses/gpl-3.0.en.html

If you have any issues or contributions, feel free to email me at aaron@tixoh.net

## Quickstart:
FoxBoot can be built using the
[gavrasm](http://www.avr-asm-tutorial.net/gavrasm/index_en.html) assembler and
uploaded over ISP using [AVRDUDE](http://www.nongnu.org/avrdude/).
If you are using an ISP programmer other than USBASP, consult the documentation
for AVRDUDE and replace the `PROGRAMMER` variable inside the Makefile accordingly.

First, connect your AVR microcontroller to your programmer and run `make fuses` to
set the correct fuses for bootloader operation. Then just run `make` to build and
upload the bootloader.

## Using FoxBoot:
At the moment there is no utility for uploading programs to the microcontroller
via FoxBoot, but one is currently in development.

### Important notes:
- FoxBoot takes up the lower 4 pages of program memory (0x3E00-0x3FFF)
- The microcontroller clock is set to use a 16 MHz external crystal, so there must
be one connected across XTAL1 and XTAL2 with decoupling caps to ground on each
pin.
- Word data is sent and received by FoxBoot with the most significant byte first.
- On main program startup, all peripherals are placed in power saving mode. To
re-enable peripherals, write 0 to their respective bits in the Power Reduction
Register.

## Talking to FoxBoot:
On reset, FoxBoot waits 20 ms for the interrupt byte (0xFF) to be sent through
UART0. If this byte is not detected within the timeframe, the main program is
started and the device must be reset again in order to enter bootloader interactive
mode. Once interactive mode is entered, FoxBoot will send an ACK byte (0x5A). After
that, the desired command should be entered. If the command is successfully
recognized, the ACK byte (0x5A) will be sent. Otherwise, NACK (0xA5) will be sent.
In interactive mode, the following commands are possible:

#### Write Page (0x11)

TX:

-----------------------------------------------------------------------
| 0x11 | Page # (1 byte) | Page Data (See below) | Checksum (2 bytes) |
-----------------------------------------------------------------------

RX:

------------
| ACK/NACK |
------------

This command will write a page of program data to flash memory.

The checksum is a 16 bit CRC using the polynomial 0x8005, and is calculated over
the "Page Data" section of the packet. If the page write was successful,
ACK will be sent. If the page data doesn't match the checksum, NACK will be sent.

Note: The Write Page command does not erase pages before writing to them. To
ensure that data is written correclty, call the Erase Page command first.

#### Read Page (0x22)

TX:

--------------------------
| 0x22 | Page # (1 byte) |
--------------------------

RX:

----------------------------------------------------
| Page Data (See below) | Checksum (2 bytes) | ACK |
----------------------------------------------------

This command will read a page of program data from flash memory.

#### Erase Page (0x44)

TX:

--------------------------
| 0x44 | Page # (1 byte) |
--------------------------

RX:

-------
| ACK |
-------

This command will erase a page of flash memory.

#### Exit Bootloader (0x88)

TX:

--------
| 0x88 |
--------

RX:

-------
| ACK |
-------

This command will exit the bootloader and start the main program at flash
address 0x0000

## Device Page Size Table

--------------------------------------
| Device     | Page Size             |
--------------------------------------
| ATmega328p | 64 words (128 bytes)  |
--------------------------------------

## TODO

- Clean up documentation/Write a proper specification that can be implemented
- Add support for more devices
