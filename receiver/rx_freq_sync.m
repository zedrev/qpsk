function [deltaf,out_signal] = rx_freq_sync(sync_samples,Num,samples_package)

Tchip=1/10000000;

len=length(samples_package);

L0 = length(sync_samples);
N = floor(L0 / Num);

if N < 1
    deltaf = 0;
    out_signal = samples_package;
    return;
end

zr = sync_samples .^ 2;
r0 = zeros(1, N);
for m = 1:N
    r0(m) = mean(zr(1+m:L0) .* conj(zr(1:L0-m)));
end

lag = 1:N;
deltaf = angle(sum(r0)) / (2 * pi * mean(lag) * Tchip * 2);
freq_offset=deltaf;
out_signal=samples_package(1:end).*exp(-1i*2*pi*freq_offset*(1:len)*Tchip);

end

