// SPDX-License-Identifier: Apache-2.0
// CRC-16/MCRF4XX: poly 0x1021 reflected (0x8408), init 0xFFFF, no xorout.
// Same CRC as the DSI long-packet checksum, so the packet parser can share it.
function [15:0] crc16_byte(input [15:0] c, input [7:0] d);
    integer i;
    begin
        crc16_byte = c ^ {8'h00, d};
        for (i = 0; i < 8; i = i + 1)
            crc16_byte = crc16_byte[0] ? (crc16_byte >> 1) ^ 16'h8408 : crc16_byte >> 1;
    end
endfunction
