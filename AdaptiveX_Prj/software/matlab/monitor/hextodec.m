function decimal = hextodec(hex, width_d)
% Signed hexadecimal samples with width_d fractional bits.
hex_int = hex2dec(hex);
width_hex = size(hex, 2);
hex_n = hex_int >= 2^(width_hex*4-1);
hex_int(hex_n) = hex_int(hex_n) - 2^(width_hex*4);
decimal = hex_int / 2^width_d;
end
