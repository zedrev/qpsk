function [complete_msg, is_ready] = reassemble(frag_buffer, msg_id, frag_idx, total_frags, payload)
% 分片重组：将收到的分片存入缓存，收齐后返回完整消息
% 使用持久变量维护分片缓存（按msg_id索引）
% 输入: frag_buffer  - 分片缓存结构体（由调用方维护）
%       msg_id       - 当前帧的消息ID
%       frag_idx     - 分片索引 (0-based)
%       total_frags  - 总分片数
%       payload      - 当前分片的载荷
% 输出: complete_msg - 完整消息 (仅is_ready=true时有效)
%       is_ready     - 是否已收齐

persistent buffer;

% buffer 是一个结构体数组，按 msg_id 索引
% buffer(msg_id+1).frags{total_frags} — 存储各分片
% buffer(msg_id+1).received — 位掩码，标记已收到哪些分片
% buffer(msg_id+1).total — 总分片数

MAX_PAYLOAD = 57;
MAX_MSG_ID = 256;

if isempty(buffer)
    buffer = struct('frags', cell(1, MAX_MSG_ID), ...
                    'received', cell(1, MAX_MSG_ID), ...
                    'total', cell(1, MAX_MSG_ID));
    for k = 1:MAX_MSG_ID
        buffer(k).frags = {};
        buffer(k).received = 0;
        buffer(k).total = 0;
    end
end

idx = msg_id + 1;

% 新消息或总分片数变更：重置缓存
if buffer(idx).total ~= total_frags
    buffer(idx).frags = cell(1, total_frags);
    buffer(idx).received = 0;
    buffer(idx).total = total_frags;
end

% 存入当前分片
buffer(idx).frags{frag_idx + 1} = payload;
buffer(idx).received = bitset(buffer(idx).received, frag_idx + 1);

% 检查是否收齐（位掩码中 total_frags 个位全为1）
expected_mask = bitshift(1, total_frags) - 1;
if bitand(buffer(idx).received, expected_mask) == expected_mask
    % 拼接完整消息
    complete_msg = uint8([]);
    for i = 1:total_frags
        complete_msg = [complete_msg, buffer(idx).frags{i}];
    end
    % 清除缓存
    buffer(idx).frags = {};
    buffer(idx).received = 0;
    buffer(idx).total = 0;
    is_ready = true;
else
    complete_msg = uint8([]);
    is_ready = false;
end
end
