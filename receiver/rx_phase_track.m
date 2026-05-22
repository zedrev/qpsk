function [signal, phase_curve] = rx_phase_track(signal)

local_pilot = [1 -1 1 -1 -1 1 -1 1];
pilot_len = length(local_pilot);
blk_len = 64 + pilot_len;   % 每块72个符号

num_blk = floor(length(signal) / blk_len);
phase_curve = zeros(1, num_blk);

if num_blk < 1
    return;
end

pilot_phase = zeros(1, num_blk);
pilot_pos = zeros(1, num_blk);

% Estimate pilot phase at the beginning of each payload block.
for blk = 1:num_blk
    i1 = (blk - 1) * blk_len + 1;
    i2 = i1 + blk_len - 1;

    temp = signal(i1:i2);
    rx_pilot = temp(1:pilot_len);

    pilot_phase(blk) = angle(sum(rx_pilot .* conj(local_pilot)));
    pilot_pos(blk) = i1 + (pilot_len - 1) / 2;
end

pilot_phase = unwrap(pilot_phase);

% Fit the residual carrier phase drift across blocks.
if num_blk >= 2
    coeff = polyfit(pilot_pos, pilot_phase, 1);
    sym_idx = 1:length(signal);
    phase_ramp = polyval(coeff, sym_idx);
else
    phase_ramp = pilot_phase(1) * ones(1, length(signal));
end

signal = signal .* exp(-1i * phase_ramp);

% After removing the phase slope, do a per-block common phase cleanup.
for blk = 1:num_blk
    i1 = (blk - 1) * blk_len + 1;
    i2 = i1 + blk_len - 1;
    temp = signal(i1:i2);
    rx_pilot = temp(1:pilot_len);

    ang_blk = angle(sum(rx_pilot .* conj(local_pilot)));
    phase_curve(blk) = ang_blk;
    signal(i1:i2) = signal(i1:i2) .* exp(-1i * ang_blk);
end

phase_curve = unwrap(phase_curve);

end
