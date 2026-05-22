function msg_bits = str_to_bits(msgStr)

if ischar(msgStr) || isstring(msgStr)
    msgStr = char(msgStr);
    if size(msgStr, 1) > 1
        msgStr = strjoin(cellstr(msgStr), sprintf('\n'));
    end
    msg_bytes = unicode2native(msgStr, 'UTF-8');
else
    msg_bytes = uint8(msgStr(:));
end

msgBin = de2bi(uint8(msg_bytes(:)),8,'left-msb');
len = size(msgBin,1).*size(msgBin,2);
msg_bits = reshape(double(msgBin).',len,1).';

end

