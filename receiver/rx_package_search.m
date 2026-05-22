function [out_signal, cor_abs, bo, index_s] = rx_package_search(signal, local_sync, len_frame)
L = length(signal);
N = length(local_sync);

cor_abs = zeros(1, L);
if L < N || N < 2
    error('rx_package_search: input is shorter than sync header.');
end

% Differential correlation suppresses a constant carrier phase/frequency
% rotation across the sync header and is much more robust than direct
% coherent correlation for over-the-air capture.
sync_diff = local_sync(2:end) .* conj(local_sync(1:end-1));
for i = N:L
    seg = signal(i-N+1:i);
    seg_diff = seg(2:end) .* conj(seg(1:end-1));
    cor_abs(i) = abs(sum(seg_diff .* conj(sync_diff)));
end

search_stop = max(N, floor(L / 2));
[~, bo] = max(cor_abs(1:search_stop));
index_s = bo - N + 1;
index_s = max(index_s, 1);
index_e = min(index_s + len_frame - 1, L);

if index_e - index_s + 1 < len_frame
    error('rx_package_search: captured frame is shorter than expected.');
end

out_signal = signal(index_s:index_e);
end
