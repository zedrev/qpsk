function [msg_id, frag_idx, total_frags, payload] = unpack_frame(frame_bytes)
% 解析一个协议帧
% 输入: frame_bytes - 60字节 uint8 数组
% 输出: msg_id      - 消息ID
%       frag_idx    - 分片索引 (0-based)
%       total_frags - 总分片数
%       payload     - 实际载荷字节 (uint8)

MAX_PAYLOAD = 57;
MAX_FRAGS = 16;

frame_bytes = uint8(frame_bytes(:).');
if numel(frame_bytes) ~= 60
    error('协议帧长度必须为60字节，当前为%d字节', numel(frame_bytes));
end

msg_id = double(frame_bytes(1));

frag_info = double(frame_bytes(2));
frag_idx = bitshift(frag_info, -4);
total_frags = bitand(frag_info, 15) + 1;
if total_frags < 1 || total_frags > MAX_FRAGS
    error('协议帧总分片数异常: %d', total_frags);
end
if frag_idx < 0 || frag_idx >= total_frags
    error('协议帧分片索引异常: %d/%d', frag_idx, total_frags);
end

payload_len = double(frame_bytes(3));
if payload_len > MAX_PAYLOAD
    error('协议帧载荷长度异常: %d', payload_len);
end

if payload_len == 0
    payload = uint8([]);
else
    payload = frame_bytes(4:4+payload_len-1);
end
end
