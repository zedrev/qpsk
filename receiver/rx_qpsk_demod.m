function [soft_bits_out, evm] = rx_qpsk_demod(rx_symbols, swap_iq, inv_i, inv_q)

if nargin < 2, swap_iq = false; end
if nargin < 3, inv_i = false; end
if nargin < 4, inv_q = false; end

bitI = real(rx_symbols) > 0;
bitQ = imag(rx_symbols) > 0;

if inv_i
    bitI = ~bitI;
end
if inv_q
    bitQ = ~bitQ;
end

if swap_iq
    soft_bits = [bitQ; bitI];
else
    soft_bits = [bitI; bitQ];
end

soft_bits_out = reshape(double(soft_bits), 1, []);

idealI = sign(real(rx_symbols));
idealQ = sign(imag(rx_symbols));
ideal = idealI + 1i * idealQ;

err = rx_symbols - ideal;
evm = mean(abs(err));

end