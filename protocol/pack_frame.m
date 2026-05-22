function frames = pack_frame(msg_bytes, msg_id)
% 将消息打包为一个或多个定长协议帧（每帧60字节）
% 输入: msg_bytes - uint8 消息字节数组（聊天文本使用 UTF-8 字节）
%       msg_id    - 消息ID (0-255)
% 输出: frames   - N×60 uint8 数组，每行一帧

MAX_PAYLOAD = 57;  % 每帧最大载荷
MAX_FRAGS = 16;    % 最多16个分片

msg_bytes = uint8(msg_bytes(:).');
msg_id = double(msg_id);
if ~isscalar(msg_id) || msg_id < 0 || msg_id > 255 || fix(msg_id) ~= msg_id
    error('消息ID必须是0到255之间的整数');
end

msg_len = numel(msg_bytes);
total_frags = max(1, ceil(msg_len / MAX_PAYLOAD));

if total_frags > MAX_FRAGS
    error('消息过长，最多支持 %d 字节', MAX_FRAGS * MAX_PAYLOAD);
end

frames = zeros(total_frags, 60, 'uint8');

for i = 1:total_frags
    start_idx = (i-1) * MAX_PAYLOAD + 1;
    end_idx = min(i * MAX_PAYLOAD, msg_len);
    if start_idx <= msg_len
        chunk = msg_bytes(start_idx:end_idx);
    else
        chunk = uint8([]);
    end
    chunk_len = length(chunk);

    % 字节0: message_id
    frames(i, 1) = uint8(msg_id);

    % 字节1: frag_info [7:4]=frag_idx, [3:0]=total_frags-1
    frag_idx = i - 1;
    tf_encoded = total_frags - 1;
    frames(i, 2) = uint8(bitor(bitshift(frag_idx, 4), tf_encoded));

    % 字节2: payload_len
    frames(i, 3) = uint8(chunk_len);

    % 字节3-59: payload (补零)
    frames(i, 4:4+chunk_len-1) = chunk;
end
end
