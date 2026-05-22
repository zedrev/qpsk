clc; clear; close all;

% 工程根目录
% 工程根目录：当前脚本所在文件夹
proj_root = fileparts(mfilename('fullpath'));

% 1. 添加同级的 library 文件夹
addpath(genpath(fullfile(proj_root, 'library')));

% 2. 添加上两级的 library/matlab 文件夹（根据你最开始的路径）
addpath(genpath(fullfile(proj_root, '..', '..', 'library', 'matlab')));

% 3. 添加同级的 QPSK 文件夹
addpath(genpath(fullfile(proj_root, 'QPSK')));

% 4. 新增：添加 receiver 和 transmitter 文件夹（含所有子目录）
addpath(genpath(fullfile(proj_root, 'receiver')));
addpath(genpath(fullfile(proj_root, 'transmitter')));

%% IP地址
ip = '192.168.2.1';

%% 检查关键函数是否存在
if exist('qpsk_tx_func', 'file') ~= 2
    error('找不到 qpsk_tx_func');
end

if exist('qpsk_rx_func', 'file') ~= 2
    error('找不到 qpsk_rx_func');
end
msgStr=[
    'a123-----------a',...
    '-b------------b-',...
    '--c----------c--',...
    '---d--------',...
    ];
%% 生成QPSK发送数据
txdata = qpsk_tx_func(msgStr)
txdata = round(txdata .* 2^14);
txdata = repmat(txdata, 8, 1);

%% 创建 MATLAB libiio 对象
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

%% 配置 AD9361 参数
input{s.getInChannel('RX_LO_FREQ')}       = 2e9;
input{s.getInChannel('RX_SAMPLING_FREQ')} = 40e6;
input{s.getInChannel('RX_RF_BANDWIDTH')}  = 20e6;
input{s.getInChannel('RX1_GAIN_MODE')}    = 'manual';
input{s.getInChannel('RX1_GAIN')}         = 10;

input{s.getInChannel('TX_LO_FREQ')}       = 2e9 + 40e3;   % 与RX载波错开40kHz
input{s.getInChannel('TX_SAMPLING_FREQ')} = 40e6;
input{s.getInChannel('TX_RF_BANDWIDTH')}  = 20e6;

%% 主循环
i = 1;          % 从第1次开始
while i <= 6 
    fprintf('Transmitting Data Block %d ...\n', i);

    input{1} = real(txdata);
    input{2} = imag(txdata);

    output = stepImpl(s, input);

    fprintf('Data Block %d Received...\n', i);

    I = output{1};
    Q = output{2};
    Rx = I + 1i * Q;

    % 送入QPSK接收函数
    qpsk_rx_func(Rx(end/2:end));

    i = i + 1;
    pause(0.1);
end

fprintf('Transmission and reception finished\n');

%% 读取RSSI
rssi1 = output{s.getOutChannel('RX1_RSSI')};
disp(['RX1 RSSI = ', num2str(rssi1)]);

%% 释放资源
s.releaseImpl();