function [out_signal,ang] = rx_phase_sync(signal_freq_sync,local_seq)

L = min(length(signal_freq_sync), length(local_seq));
ref = local_seq(1:L);
rx = signal_freq_sync(1:L);

% Use direct complex correlation over the known training sequence.
ang = angle(sum(rx .* conj(ref)));
out_signal = signal_freq_sync .* exp(-1i * ang);

end

