function chat_app(tx_first)
% QPSK 双人聊天系统 — 基于AD9361硬件
% 协议: 定长60字节帧, 含序列号/分片/长度字段, CRC32校验
%
% 两台设备需要设置不同的频率角色:
%   chat_app(true)  — 本机TX载波高于RX (TX=RX+40kHz)
%   chat_app(false) — 本机TX载波低于RX (TX=RX-40kHz)，与对方配对使用
%
% 示例:
%   设备A: chat_app(true)
%   设备B: chat_app(false)

if nargin < 1, tx_first = true; end

%% ==================== 路径初始化 ====================
proj_root = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(proj_root, 'library')));
addpath(genpath(fullfile(proj_root, '..', '..', 'library', 'matlab')));
addpath(genpath(fullfile(proj_root, 'receiver')));
addpath(genpath(fullfile(proj_root, 'transmitter')));
addpath(genpath(fullfile(proj_root, 'protocol')));

%% ==================== 全局状态 ====================
ip = '192.168.2.1';
data_len = 0;
s = [];           % libiio硬件对象
msg_id_counter = 0;  % 发送消息ID计数器
last_rx_msg_id = -1; % 上次收到的消息ID（防重复打印）

% 分片重组缓存
frag_buf = struct('frags', {}, 'received', {}, 'total', {});
for k = 1:256
    frag_buf(k).frags = {};
    frag_buf(k).received = 0;
    frag_buf(k).total = 0;
end

% TX队列
tx_queue = {};  % 每项为 60字节 uint8 帧
tx_repeat = 5;  % 每帧重复发送次数
recent_tx_frames = zeros(0, 60, 'uint8');
recent_tx_times = zeros(0, 1);
tx_echo_window_sec = 10;
max_recent_tx_frames = 128;

%% ==================== 硬件初始化 ====================
try
    % 生成初始TX数据用于计算长度
    dummy_frame = zeros(60, 1, 'uint8');
    txdata_raw = qpsk_tx_func(dummy_frame);
    txdata_raw = round(txdata_raw .* 2^14);
    txdata = repmat(txdata_raw, 8, 1);
    data_len = length(txdata);

    s = iio_sys_obj_matlab;
    s.ip_address = ip;
    s.dev_name = 'ad9361';
    s.in_ch_no = 2;
    s.out_ch_no = 2;
    s.in_ch_size = length(txdata);
    s.out_ch_size = length(txdata) * 2;
    s = s.setupImpl();

    input = cell(1, s.in_ch_no + length(s.iio_dev_cfg.cfg_ch));
    output = cell(1, s.out_ch_no + length(s.iio_dev_cfg.mon_ch));

    % 频率配置: 两台设备TX/RX角色互换
    base_freq = 2e9;
    offset = 40e3;
    if tx_first
        rx_freq = base_freq;
        tx_freq = base_freq + offset;
    else
        rx_freq = base_freq + offset;
        tx_freq = base_freq;
    end

    input{s.getInChannel('RX_LO_FREQ')}       = rx_freq;
    input{s.getInChannel('RX_SAMPLING_FREQ')} = 40e6;
    input{s.getInChannel('RX_RF_BANDWIDTH')}  = 20e6;
    input{s.getInChannel('RX1_GAIN_MODE')}    = 'manual';
    input{s.getInChannel('RX1_GAIN')}         = 10;
    input{s.getInChannel('TX_LO_FREQ')}       = tx_freq;
    input{s.getInChannel('TX_SAMPLING_FREQ')} = 40e6;
    input{s.getInChannel('TX_RF_BANDWIDTH')}  = 20e6;

    hw_ok = true;
    role_str = 'TX高频侧';
    if ~tx_first, role_str = 'TX低频侧'; end
    hw_msg = ['硬件已连接 (' role_str ')'];
catch err
    hw_ok = false;
    hw_msg = ['硬件连接失败: ' err.message];
end

%% ==================== 创建 UI ====================
h_fig = figure('Name', 'QPSK双人聊天系统', ...
               'Position', [100, 100, 700, 550], ...
               'NumberTitle', 'off', ...
               'CloseRequestFcn', @close_callback, ...
               'MenuBar', 'none');

% 聊天记录框
chat_log = uicontrol('Style', 'listbox', ...
                     'Position', [15, 100, 670, 400], ...
                     'FontSize', 10, ...
                     'HorizontalAlignment', 'left', ...
                     'Max', 1000, ...
                     'String', {['[系统] ' hw_msg]});

% 消息输入框
msg_input = uicontrol('Style', 'edit', ...
                      'Position', [15, 50, 460, 40], ...
                      'FontSize', 12, ...
                      'HorizontalAlignment', 'left', ...
                      'String', '');

% 发送按钮
send_btn = uicontrol('Style', 'pushbutton', ...
                     'String', '发送', ...
                     'Position', [490, 50, 90, 40], ...
                     'FontSize', 12, ...
                     'Callback', @send_callback);

% 状态标签
status_label = uicontrol('Style', 'text', ...
                         'Position', [15, 15, 670, 25], ...
                         'FontSize', 9, ...
                         'HorizontalAlignment', 'left', ...
                         'String', '状态: 就绪');

% 允许回车键发送
set(h_fig, 'KeyPressFcn', @keypress_callback);

%% ==================== 回调函数 ====================
    function send_callback(~, ~)
        if ~hw_ok
            add_chat('[系统] 硬件未连接，无法发送', [1 0 0]);
            return;
        end
        msg_text = strtrim(read_input_text());
        if isempty(msg_text)
            return;
        end

        % 按 UTF-8 明确编码，避免中文和 Unicode 符号被 uint8(char) 截断成 255。
        next_msg_id = mod(msg_id_counter + 1, 256);
        try
            msg_bytes = unicode2native(msg_text, 'UTF-8');
            frames = pack_frame(msg_bytes, next_msg_id);
        catch err
            add_chat(['[系统] 发送失败: ' err.message], [1 0 0]);
            set(status_label, 'String', ['状态: 发送失败 - ' err.message]);
            return;
        end
        msg_id_counter = next_msg_id;
        set(msg_input, 'String', '');

        % 加入TX队列
        for i = 1:size(frames, 1)
            frame = frames(i, :);
            tx_queue{end+1} = frame;
            remember_tx_frame(frame);
        end

        add_chat(['[本机] ' msg_text], [0 0.4 1]);
        set(status_label, 'String', ...
            sprintf('状态: 已排队发送 %d 帧 (msg#%d)', size(frames, 1), msg_id_counter));
    end

    function keypress_callback(~, event)
        if strcmp(event.Key, 'return')
            send_callback([], []);
        end
    end

    function close_callback(~, ~)
        if hw_ok && ~isempty(s)
            try
                s.releaseImpl();
            catch
            end
        end
        delete(h_fig);
    end

    function add_chat(msg, color)
        if nargin < 2, color = [0 0 0]; end
        items = get(chat_log, 'String');
        % 添加时间戳
        ts = datestr(now, 'HH:MM:SS');
        items{end+1} = ['[' ts '] ' msg];
        set(chat_log, 'String', items);
        % 滚动到底部
        set(chat_log, 'Value', length(items));
        drawnow;
    end

    function msg_text = read_input_text()
        raw = get(msg_input, 'String');
        if iscell(raw)
            raw = strjoin(raw(:).', sprintf('\n'));
        end
        msg_text = char(raw);
    end

    function msg_text = decode_utf8_bytes(bytes)
        bytes = uint8(bytes(:).');
        if isempty(bytes)
            msg_text = '';
            return;
        end

        try
            msg_text = native2unicode(bytes, 'UTF-8');
        catch
            msg_text = '[UTF-8解码失败的消息]';
        end
    end

    function remember_tx_frame(frame)
        recent_tx_frames(end+1, :) = uint8(frame(:).');
        recent_tx_times(end+1, 1) = now;
        prune_recent_tx_frames();
    end

    function tf = is_recent_tx_frame(frame)
        prune_recent_tx_frames();
        frame = uint8(frame(:).');
        tf = false;
        if isempty(recent_tx_frames) || numel(frame) ~= 60
            return;
        end
        tf = any(all(recent_tx_frames == frame, 2));
    end

    function prune_recent_tx_frames()
        if isempty(recent_tx_times)
            return;
        end
        keep = ((now - recent_tx_times) * 86400) <= tx_echo_window_sec;
        recent_tx_frames = recent_tx_frames(keep, :);
        recent_tx_times = recent_tx_times(keep);
        if size(recent_tx_frames, 1) > max_recent_tx_frames
            start_idx = size(recent_tx_frames, 1) - max_recent_tx_frames + 1;
            recent_tx_frames = recent_tx_frames(start_idx:end, :);
            recent_tx_times = recent_tx_times(start_idx:end);
        end
    end

%% ==================== 主循环 ====================
if ~hw_ok
    add_chat('[系统] 进入模拟模式（无硬件）', [1 0.5 0]);
end

fprintf('[Chat] QPSK聊天系统启动\n');

while ishandle(h_fig)
    drawnow;

    if ~hw_ok
        pause(0.5);
        continue;
    end

    % ---- 发送: 从队列取帧发送 ----
    if ~isempty(tx_queue)
        frame = tx_queue{1};
        tx_queue(1) = [];  % 出队

        % 生成该帧的TX基带数据
        txdata_raw = qpsk_tx_func(frame);
        txdata_raw = round(txdata_raw .* 2^14);
        txdata_frame = repmat(txdata_raw, 8, 1);

        % 重复发送提高可靠性
        for rep = 1:tx_repeat
            if length(txdata_frame) > data_len
                txdata_frame = txdata_frame(1:data_len);
            elseif length(txdata_frame) < data_len
                txdata_frame(end+1:data_len) = 0;
            end
            input{1} = real(txdata_frame);
            input{2} = imag(txdata_frame);
            output = stepImpl(s, input);

            % 同时处理RX数据；本机回波会在 process_rx_frame 中按完整帧过滤。
            I = output{1}; Q = output{2}; Rx = I + 1i*Q;
            rx_bytes = [];
            crc_ok = false;
            try
                [rx_bytes, crc_ok] = qpsk_rx_func(Rx(end/2:end));
            catch
            end
            if ~isempty(rx_bytes) && crc_ok
                process_rx_frame(rx_bytes);
            end

            pause(0.05);
        end
        set(status_label, 'String', ...
            sprintf('状态: 已发送，队列剩余 %d 帧', length(tx_queue)));
    else
        % ---- 常态接收（发全零）----
        input{1} = zeros(data_len, 1);
        input{2} = zeros(data_len, 1);
        output = stepImpl(s, input);

        I = output{1}; Q = output{2}; Rx = I + 1i*Q;
        rx_bytes = [];
        crc_ok = false;
        try
            [rx_bytes, crc_ok] = qpsk_rx_func(Rx(end/2:end));
        catch
        end
        if ~isempty(rx_bytes) && crc_ok
            process_rx_frame(rx_bytes);
        end

        % 显示RSSI
        try
            rssi = output{s.getOutChannel('RX1_RSSI')};
        catch
            rssi = NaN;
        end
        if ~isnan(rssi)
            set(status_label, 'String', ...
                sprintf('状态: 常态接收 | RSSI: %.1f dB | 队列: %d', rssi, length(tx_queue)));
        end
        pause(0.01);
    end
end

%% ==================== RX帧处理 ====================
    function process_rx_frame(frame_bytes)
        if numel(frame_bytes) ~= 60
            set(status_label, 'String', ...
                sprintf('状态: 丢弃长度异常的帧 (%d 字节)', numel(frame_bytes)));
            return;
        end
        if is_recent_tx_frame(frame_bytes)
            set(status_label, 'String', '状态: 已过滤本机回波帧');
            return;
        end

        try
            [msg_id, frag_idx, total_frags, payload] = unpack_frame(frame_bytes);
        catch err
            set(status_label, 'String', ['状态: 丢弃无效帧 - ' err.message]);
            return;
        end

        if total_frags < 1 || total_frags > 16 || frag_idx < 0 || frag_idx >= total_frags
            set(status_label, 'String', '状态: 丢弃分片信息异常的帧');
            return;
        end

        % 分片重组
        idx = msg_id + 1;
        if frag_buf(idx).total ~= total_frags
            frag_buf(idx).frags = cell(1, total_frags);
            frag_buf(idx).received = 0;
            frag_buf(idx).total = total_frags;
        end
        frag_buf(idx).frags{frag_idx + 1} = payload;
        frag_buf(idx).received = bitset(frag_buf(idx).received, frag_idx + 1);

        expected_mask = bitshift(1, total_frags) - 1;
        if bitand(frag_buf(idx).received, expected_mask) == expected_mask
            % 收齐，拼接
            full_msg = uint8([]);
            for i = 1:total_frags
                if isempty(frag_buf(idx).frags{i})
                    return;
                end
                full_msg = [full_msg, frag_buf(idx).frags{i}];
            end
            % 清除缓存
            frag_buf(idx).frags = cell(1, 1);
            frag_buf(idx).received = 0;
            frag_buf(idx).total = 0;

            % 去重检测
            if msg_id ~= last_rx_msg_id
                last_rx_msg_id = msg_id;
                msg_text = decode_utf8_bytes(full_msg);
                add_chat(['[对方] ' msg_text], [0 0.6 0]);
            end
        end
    end

end
