function txdata = qpsk_tx_func(data_in, show_plot)
% 函数功能：QPSK发射机
% 输入参数：data_in - uint8字节数组 (60字节协议帧)
% 输出参数：txdata - 发射基带数据
if nargin < 2 || isempty(show_plot)
    show_plot = false;
end

%% train sequence
seq_sync=tx_gen_m_seq([1 0 0 0 0 0 1]);
sync_symbols=tx_modulate(seq_sync, 'BPSK');

%% 输入处理: 支持uint8字节数组或字符串
if ischar(data_in) || isstring(data_in)
    data_text = char(data_in);
    if size(data_text, 1) > 1
        data_text = strjoin(cellstr(data_text), sprintf('\n'));
    end
    data_bytes = unicode2native(data_text, 'UTF-8');
else
    data_bytes = uint8(data_in(:));
end
data_bytes = uint8(data_bytes(:));

% 确保帧定长为60字节
if length(data_bytes) < 60
    data_bytes(end+1:60) = 0;
elseif length(data_bytes) > 60
    data_bytes = data_bytes(1:60);
end

%% bytes to bits (每字节8bit, left-msb)
msgBin = de2bi(data_bytes, 8, 'left-msb');
mst_bits = reshape(double(msgBin).', 1, []);

%% crc32
ret=crc32(mst_bits);
inf_bits=[mst_bits ret.'];

%% scramble
scramble_int=[1,1,0,1,1,0,0];% 本原多项式
sym_bits=scramble(scramble_int, inf_bits);

%% modulate
mod_symbols=tx_modulate(sym_bits, 'QPSK');

%% insert pilot
data_symbols=insert_pilot(mod_symbols);
trans_symbols=[sync_symbols data_symbols];

%% srrc
fir=rcosdesign(1,128,4);
tx_frame=upfirdn(trans_symbols,fir,4);
tx_frame=[tx_frame, zeros(1,2e3)];
txdata = tx_frame.';

%% display
if show_plot
    figure(1);
    clf;
    plot(real(tx_frame));
    hold on;
    plot(imag(tx_frame));
    grid on;
end
end
