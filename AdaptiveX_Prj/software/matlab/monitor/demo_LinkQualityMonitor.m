function app = demo_LinkQualityMonitor
% DEMO_LINKQUALITYMONITOR 链路质量监测 GUI 的简单调用示例。
% app = demo_LinkQualityMonitor; 用示例数据更新约 30 秒，结束后保留画面。
% 接入实际数据时，替换循环中的 sample 赋值，保留 updateMeasurement 调用。
    app = LinkQualityMonitor;
    app.startMonitoring();

    % 构造单位平均功率的 16QAM 示例符号，不依赖通信工具箱。
    randomSource = RandStream('mt19937ar','Seed',20261020);
    [i,q] = ndgrid([-3 -1 1 3]/sqrt(10));
    references = i(:)+1j*q(:);
    for k=1:120
        % 点击“结束”或关闭窗口后，调用方停止供数。
        if ~isvalid(app) || ~app.Running
            return
        end
        % 在采集这一批时记录时间；后续处理耗时不改变其曲线位置。
        sample.ElapsedSeconds = app.ElapsedSeconds;
        symbols = references(randi(randomSource,16,1024,1));
        noise = 10^(-(30+sin(k/10))/20)/sqrt(2) ...
            *(randn(randomSource,size(symbols))+1j*randn(randomSource,size(symbols)));

        sample.P = 4;
        sample.M = 2;
        sample.IQ = symbols+noise;
        sample.MERdB = 10*log10(sum(abs(symbols).^2)/sum(abs(noise).^2));
        % BER 使用独立示例值，仅演示接口供数与绘图。
        sample.TotalBits = 1e6;
        sample.BER = round(sample.TotalBits*10^(-4.5+.5*sin(k/12)))/sample.TotalBits;
        app.updateMeasurement(sample);
        pause(.25);
    end
    if isvalid(app)
        app.stopMonitoring();
    end
end
