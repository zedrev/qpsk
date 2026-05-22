function varargout = qpsk_rx_func(rxdata, show_plot)
% QPSK接收机
% 用法1 (显示模式): qpsk_rx_func(rxdata, show_plot) — 打印结果，画图
% 用法2 (数据模式): [rx_bytes, crc_ok] = qpsk_rx_func(rxdata) — 返回解析后的字节和CRC状态
%   rx_bytes: 60字节协议帧 (uint8), 无效时为[]
%   crc_ok:   CRC校验通过为true

global cyc;
if isempty(cyc), cyc = 0; end
if nargin < 2, show_plot = false; end
return_data = (nargout > 0);

%% Sync header and frame structure
seq_sync = tx_gen_m_seq([1 0 0 0 0 0 1]);
local_sync = tx_modulate(seq_sync, 'BPSK');
sync_len = length(local_sync);
pilot_len = 8;
payload_blk_len = 64;
num_payload_blk = 4;
frame_len = sync_len + num_payload_blk * (pilot_len + payload_blk_len);

rx_signal = rxdata;

%% matched filtering
fir = rcosdesign(1, 128, 4);
rx_sig_filter = upfirdn(rx_signal, fir, 1);

%% normalization
c1 = max([abs(real(rx_sig_filter.')), abs(imag(rx_sig_filter.'))]);
rx_sig_norm = rx_sig_filter ./ c1;

%% sampling synchronization
[time_error, rx_sig_down] = rx_timing_recovery(rx_sig_norm.');

%% package search
[rx_frame, cor_abs, th_max, index_s] = rx_package_search(rx_sig_down, local_sync, frame_len);

%% coarse freq synchronization
coarse_sync_seq = rx_frame(1:8);
[deltaf1, out_signal1] = rx_freq_sync(coarse_sync_seq, 4, rx_frame);

%% first fine freq synchronization
fine_sync_seq_1 = out_signal1(1:120);
[deltaf2, out_signal2] = rx_freq_sync(fine_sync_seq_1, 2, out_signal1);

%% second fine freq synchronization
fine_sync_seq_2 = out_signal2(1:120);
[deltaf3, out_signal3] = rx_freq_sync(fine_sync_seq_2, 2, out_signal2);
deltaf = deltaf1 + deltaf2 + deltaf3;

%% initial phase estimate
[out_signal4, ang] = rx_phase_sync(out_signal3, local_sync);

%% remove sync header
rx_no_syn_seq = out_signal4(sync_len+1:end);

%% pilot-aided phase track
[out_signal6, phase_curve] = rx_phase_track(rx_no_syn_seq);

%% delete pilots and demodulate
out_signal7 = rx_delete_pilot(out_signal6);
[soft_bits_rx, evm] = rx_qpsk_demod(out_signal7);

%% descramble
Si = [1 1 0 1 1 0 0];
soft_bits_out = zeros(1, length(soft_bits_rx));
for k = 1:length(soft_bits_rx)
    [bit_out, Si] = descramble(soft_bits_rx(k), Si);
    soft_bits_out(k) = bit_out;
end

%% crc32 check
best_shift = 0;
best_crc_err = inf;
best_bits_shift = [];
for shift = 0:1
    bits_shift = soft_bits_out;
    if shift == 1
        bits_shift = [soft_bits_out(2:end), soft_bits_out(1)];
    end

    if length(bits_shift) < 32
        continue;
    end

    ret = crc32(bits_shift(1:end-32)).';
    crc_bits_32 = bits_shift(end-31:end);
    crc_err = sum(xor(ret, crc_bits_32), 2);

    if crc_err < best_crc_err
        best_crc_err = crc_err;
        best_bits_shift = bits_shift;
        best_shift = shift;
    end
end

soft_bits_out = best_bits_shift;
if isempty(soft_bits_out)
    crc_ok_flag = false;
elseif best_crc_err == 0
    crc_ok_flag = true;
else
    crc_ok_flag = false;
end

cyc = cyc + 1;

%% bit -> bytes (480 bits = 60 bytes, after stripping 32-bit CRC)
if length(soft_bits_out) > 32
    msg_bits = soft_bits_out(1:end-32).';
    Nbits = floor(numel(msg_bits) / 8) * 8;
    msg_bits = msg_bits(1:Nbits);
    Ny = Nbits / 8;
    w = [128 64 32 16 8 4 2 1];
    rx_bytes = zeros(1, Ny, 'uint8');
    for k = 0:Ny-1
        rx_bytes(k+1) = w * msg_bits(8*k + (1:8));
    end
else
    rx_bytes = [];
    crc_ok_flag = false;
end

%% 数据模式: 返回解析结果，不做显示
if return_data
    varargout{1} = rx_bytes;
    varargout{2} = crc_ok_flag;
    return;
end

%% 显示模式 (原有行为)
crc_32 = 'NO';
if crc_ok_flag, crc_32 = 'YES'; end

if ~isempty(rx_bytes)
    display_bytes = rx_bytes(:).';
    last_nonzero = find(display_bytes ~= 0, 1, 'last');
    if isempty(last_nonzero)
        rx_text = '';
    else
        display_bytes = display_bytes(1:last_nonzero);
        try
            rx_text = native2unicode(display_bytes, 'UTF-8');
        catch
            rx_text = char(display_bytes);
            rx_text(rx_text < 32) = '.';
        end
    end
else
    rx_text = '[payload too short]';
end

disp(rx_text);
disp(['length(rx_frame) = ', num2str(length(rx_frame))]);
disp(['length(rx_no_syn_seq) = ', num2str(length(rx_no_syn_seq))]);
disp(['length(out_signal6) = ', num2str(length(out_signal6))]);
disp(['length(out_signal7) = ', num2str(length(out_signal7))]);
disp(['bit shift = ', num2str(best_shift)]);
disp(['phase_sync = ', num2str(ang)]);

if ~show_plot
    return;
end

%% display
figure(2); clf;

subplot(231);
plot(real(rx_signal), 'r');
hold on;
plot(imag(rx_signal), 'b');
grid on;
title('rx original signal');

subplot(232);
pwelch(rx_signal, [], [], [], 40e6, 'centered', 'psd');

subplot(233);
plot(real(out_signal7), imag(out_signal7), 'b*');
title('constellation');
axis([-1.5 1.5 -1.5 1.5]);
axis square;

subplot(234);
plot(phase_curve);
title('phase track');

subplot(235);
text(0.15, 1.00, ['frame start: ', num2str(index_s, 5)]);
text(0.15, 0.82, ['freq offset: ', num2str(deltaf/1e3, 3), ' kHz']);
text(0.15, 0.64, 'mode: QPSK');
text(0.15, 0.46, ['EVM: ', num2str(evm * 100, 3), '%']);
text(0.15, 0.26, ['phase: ', num2str(ang, 3), ' rad']);
text(0.15, 0.08, ['bit shift: ', num2str(best_shift)]);
text(0.15, -0.10, ['CRC32: ', crc_32]);
axis off;

figure(3); clf;
plot(real(out_signal7), imag(out_signal7), '.');
title('before demod constellation');
axis equal;

end
