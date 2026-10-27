classdef JiemianUDPReceiver < handle
    % Passive receiver for the current Rx MAC1 RX264 constellation stream.
    % P/M/FID come from each packet; FID is a source frame, not a packet number.
    properties (SetAccess = private)
        App
        TotalBits = 0
        ErrorBits = 0
        ReceivedDatagrams = 0
        RejectedDatagrams = 0
        PublishedBatches = 0
        LastFrameID = uint32(0)
        CurrentP = NaN
        CurrentM = NaN
        Stale = false
    end
    properties
        StaleAfterSeconds (1,1) double {mustBePositive,mustBeFinite} = 1
    end
    properties (Access = private)
        Socket = []
        PollTimer = []
        MER = []
        MERMode = NaN
        AddressInput
        RemotePortInput
        LocalPortInput
        StatusLabel
        FrameLabel
        ModeLabel
        SaveButton
        Controls
        Grid
        Labels
        Narrow = []
        Address = '192.168.2.77'
        RemotePort = 8001
        Active = false
        Busy = false
        PendingIQ = complex(zeros(62,0))
        PendingFrames = zeros(0,1,'uint32')
        PendingP = NaN
        PendingM = NaN
        PendingTime = 0
        LastPacketToken = []
        LastPublishToken = []
        LastRejectReason = ''
    end
    methods
        function source = JiemianUDPReceiver(app)
            source.App = app;
            app.attachReceiver(source);
            source.createControls();
        end

        function start(source)
            source.stop();
            if exist('udpport','file') ~= 2 || exist('comm.MER','class') ~= 8
                error('RxUDP:Toolboxes', ...
                    'UDP 接收需要 Instrument Control Toolbox，MER 计算需要 Communications Toolbox。');
            end
            address = char(strtrim(source.AddressInput.Value));
            octets = str2double(strsplit(address,'.'));
            if numel(octets)~=4 || any(~isfinite(octets) | octets<0 | octets>255 | fix(octets)~=octets)
                error('RxUDP:Address','请输入有效的板端 IPv4 地址。');
            end
            source.Address = sprintf('%d.%d.%d.%d',octets);
            source.RemotePort = source.RemotePortInput.Value;
            source.TotalBits = 0;
            source.ErrorBits = 0;
            source.ReceivedDatagrams = 0;
            source.RejectedDatagrams = 0;
            source.PublishedBatches = 0;
            source.LastFrameID = uint32(0);
            source.CurrentP = NaN;
            source.CurrentM = NaN;
            source.Stale = false;
            source.clearPending();
            source.LastRejectReason = '';
            source.FrameLabel.Text = '来源帧号  —';
            try
                source.Socket = udpport('datagram','IPV4', ...
                    'LocalPort',source.LocalPortInput.Value,'Timeout',1);
                % Rx transmits on its own. Never send requests or periodically
                % flush the receive queue: doing so discards observation intervals.
                source.Active = true;
                source.LastPacketToken = tic;
                source.LastPublishToken = tic;
                source.setControlsEnabled('off');
                source.setStatus('等待 Rx 自动上传');
                source.PollTimer = timer('Name','RxUDP264Acquisition', ...
                    'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                    'Period',.02,'StartDelay',.02, ...
                    'TimerFcn',@(~,~)source.poll());
                start(source.PollTimer);
            catch exception
                source.stop();
                rethrow(exception)
            end
        end

        function stop(source)
            source.Active = false;
            if ~isempty(source.PollTimer) && isvalid(source.PollTimer)
                stop(source.PollTimer);
                delete(source.PollTimer);
            end
            source.PollTimer = [];
            % Preserve the last partial display batch even with fewer than 30 packets.
            if ~isempty(source.PendingFrames) && ~isempty(source.App) ...
                    && isvalid(source.App) && source.App.Running
                try
                    source.publishPending();
                catch exception
                    warning('RxUDP:FinalDisplay','%s',exception.message);
                end
            end
            source.Socket = [];
            if ~isempty(source.MER), release(source.MER); end
            source.MER = [];
            source.MERMode = NaN;
            source.clearPending();
            source.setControlsEnabled('on');
            if ~isempty(source.StatusLabel) && isgraphics(source.StatusLabel)
                source.StatusLabel.Text = 'UDP 已停止';
            end
        end

        function delete(source)
            source.stop();
            source.App = [];
        end
    end
    methods (Access = private)
        function poll(source)
            if ~source.Active || source.Busy, return; end
            source.Busy = true;
            cleanup = onCleanup(@()source.unlock()); %#ok<NASGU>
            try
                % Bound each callback so network load cannot monopolize the UI.
                count = min(source.Socket.NumDatagramsAvailable,128);
                if count > 0
                    packets = read(source.Socket,count,'uint8');
                    for k=1:numel(packets)
                        packet = packets(k);
                        if ~strcmp(packet.SenderAddress,source.Address) || packet.SenderPort~=source.RemotePort
                            source.reject('来源地址或端口不匹配');
                            continue
                        end
                        try
                            [iq,bits,errors,meta] = decodeJiemianDatagrams(uint8(packet.Data(:)));
                        catch exception
                            if startsWith(exception.identifier,'RxUDP:')
                                source.reject(exception.message);
                                continue
                            end
                            rethrow(exception)
                        end
                        if errors > bits
                            source.reject('错误比特数大于总比特数');
                            continue
                        end
                        % A source-frame label may repeat or wrap. There is no
                        % packet sequence field, so never deduplicate using FID.
                        if ~isempty(source.PendingFrames) && ...
                                (source.PendingP~=meta.P || source.PendingM~=meta.M)
                            source.publishPending();
                        end
                        source.TotalBits = source.TotalBits+bits;
                        source.ErrorBits = source.ErrorBits+errors;
                        source.ReceivedDatagrams = source.ReceivedDatagrams+1;
                        source.CurrentP = meta.P;
                        source.CurrentM = meta.M;
                        source.LastFrameID = meta.FrameID;
                        source.PendingP = meta.P;
                        source.PendingM = meta.M;
                        source.PendingIQ(:,end+1) = iq;
                        source.PendingFrames(end+1,1) = meta.FrameID;
                        source.PendingTime = source.App.ElapsedSeconds;
                        source.LastPacketToken = tic;
                        source.Stale = false;
                    end
                end
                if ~isempty(source.PendingFrames) && toc(source.LastPublishToken)>=.1
                    source.publishPending();
                end
                source.refreshStatus();
            catch exception
                source.App.stopMonitoring();
                source.App.setAcquisitionStatus('UDP 接收失败');
                source.setStatus(exception.message);
                warning('RxUDP:Receive','%s',exception.message);
            end
        end

        function publishPending(source)
            if isempty(source.PendingFrames), return; end
            if isempty(source.MER) || source.MERMode~=source.PendingM
                if ~isempty(source.MER), release(source.MER); end
                source.MER = comm.MER('ReferenceSignalSource', ...
                    'Estimated from reference constellation', ...
                    'ReferenceConstellation',source.references(source.PendingM));
                source.MERMode = source.PendingM;
            end
            iq = source.PendingIQ(:);
            sample = struct('P',source.PendingP,'M',source.PendingM,'IQ',iq, ...
                'MERdB',source.MER(iq),'BER',NaN, ...
                'ElapsedSeconds',source.PendingTime, ...
                'FrameID',source.PendingFrames(end), ...
                'FrameIDs',source.PendingFrames, ...
                'PacketCount',numel(source.PendingFrames),'ProtocolVersion',1);
            if ~isfinite(sample.MERdB), sample.MERdB = NaN; end
            if source.TotalBits > 0
                sample.BER = source.ErrorBits/source.TotalBits;
                sample.TotalBits = source.TotalBits;
            end
            source.App.updateMeasurement(sample);
            source.PublishedBatches = source.PublishedBatches+1;
            source.clearPending();
            source.LastPublishToken = tic;
        end

        function clearPending(source)
            source.PendingIQ = complex(zeros(62,0));
            source.PendingFrames = zeros(0,1,'uint32');
            source.PendingP = NaN;
            source.PendingM = NaN;
        end

        function reject(source,reason)
            source.RejectedDatagrams = source.RejectedDatagrams+1;
            source.LastRejectReason = reason;
        end

        function refreshStatus(source)
            age = toc(source.LastPacketToken);
            source.Stale = age > source.StaleAfterSeconds;
            if source.Stale
                source.App.setAcquisitionStatus('数据超时');
                source.setStatus(sprintf('%.1f 秒未收到有效包 · 保留最后画面',age));
            elseif source.ReceivedDatagrams==0
                source.App.setAcquisitionStatus('等待 UDP');
                source.setStatus('等待 Rx 自动上传');
            else
                source.App.setAcquisitionStatus('UDP 接收中');
                source.setStatus(sprintf('接收 %d 包 · 拒绝 %d 包 · 累计 %.0f bit', ...
                    source.ReceivedDatagrams,source.RejectedDatagrams,source.TotalBits));
            end
            if source.ReceivedDatagrams > 0
                source.FrameLabel.Text = sprintf('来源帧号  0x%08X',source.LastFrameID);
            end
            if ~isempty(source.LastRejectReason)
                source.StatusLabel.Tooltip = sprintf('%s\n最近拒绝原因：%s', ...
                    source.StatusLabel.Text,source.LastRejectReason);
            end
        end

        function unlock(source)
            if isvalid(source), source.Busy = false; end
        end

        function createControls(source)
            panel = source.App.AcquisitionPanel;
            panel.AutoResizeChildren = 'off';
            source.Grid = uigridlayout(panel,[2 8], ...
                'ColumnWidth',{56,'1x',64,76,64,76,104,100}, ...
                'RowHeight',{28,28},'Padding',[10 6 10 6], ...
                'RowSpacing',4,'ColumnSpacing',8,'BackgroundColor',[1 1 1]);
            source.Labels = gobjects(1,3);
            captions = {'板端 IP','板端端口','本地端口'};
            for k=1:3
                source.Labels(k) = uilabel(source.Grid,'Text',captions{k}, ...
                    'FontColor',[0 0 0]);
            end
            source.AddressInput = uieditfield(source.Grid,'text', ...
                'Value','192.168.2.77','Tag','UDPBoardAddress');
            source.RemotePortInput = source.portInput('UDPRemotePort');
            source.LocalPortInput = source.portInput('UDPLocalPort');
            source.ModeLabel = uilabel(source.Grid,'Text','P/M 自动识别', ...
                'FontColor',[0 0 0],'Tag','UDPModeSource');
            source.FrameLabel = uilabel(source.Grid,'Text','来源帧号  —', ...
                'FontColor',[0 0 0],'Tag','UDPFrameID');
            source.StatusLabel = uilabel(source.Grid,'Text','Rx264 · 持续接收', ...
                'FontColor',[0 0 0],'Tag','UDPStatus');
            source.SaveButton = uibutton(source.Grid,'Text','保存图片', ...
                'ButtonPushedFcn',@(~,~)source.saveImage(),'Tag','UDPSave');
            source.Controls = [source.AddressInput,source.RemotePortInput,source.LocalPortInput];
            panel.SizeChangedFcn = @(~,~)source.applyLayout();
            source.applyLayout();
        end

        function input = portInput(source,tag)
            input = uieditfield(source.Grid,'numeric','Value',8001, ...
                'Limits',[1 65535],'RoundFractionalValues','on','Tag',tag);
        end

        function applyLayout(source)
            narrow = source.App.Figure.Position(3)<940;
            if isequal(source.Narrow,narrow), return; end
            source.Narrow = narrow;
            if narrow
                source.Grid.ColumnWidth = {70,'1x',70,'1x'};
                source.Grid.RowHeight = {28,28,28,28};
                labels = [1 1;1 3;2 1];
                inputs = [1 2;1 4;2 2];
                source.ModeLabel.Layout.Row = 2;
                source.ModeLabel.Layout.Column = [3 4];
                source.FrameLabel.Layout.Row = 3;
                source.FrameLabel.Layout.Column = [1 4];
                source.StatusLabel.Layout.Row = 4;
                source.StatusLabel.Layout.Column = [1 3];
                source.SaveButton.Layout.Row = 4;
                source.SaveButton.Layout.Column = 4;
            else
                source.Grid.ColumnWidth = {56,'1x',64,76,64,76,104,100};
                source.Grid.RowHeight = {28,28};
                labels = [1 1;1 3;1 5];
                inputs = [1 2;1 4;1 6];
                source.ModeLabel.Layout.Row = 1;
                source.ModeLabel.Layout.Column = [7 8];
                source.FrameLabel.Layout.Row = 2;
                source.FrameLabel.Layout.Column = [5 7];
                source.StatusLabel.Layout.Row = 2;
                source.StatusLabel.Layout.Column = [1 4];
                source.SaveButton.Layout.Row = 2;
                source.SaveButton.Layout.Column = 8;
            end
            for k=1:3
                source.Labels(k).Layout.Row = labels(k,1);
                source.Labels(k).Layout.Column = labels(k,2);
                source.Controls(k).Layout.Row = inputs(k,1);
                source.Controls(k).Layout.Column = inputs(k,2);
            end
        end

        function setControlsEnabled(source,value)
            if ~isempty(source.Controls)
                set(source.Controls(isgraphics(source.Controls)),'Enable',value);
            end
        end

        function setStatus(source,text)
            source.StatusLabel.Text = text;
            source.StatusLabel.Tooltip = text;
        end

        function saveImage(source)
            folder = fullfile(fileparts(mfilename('fullpath')),'Results');
            filename = fullfile(folder,['LinkQuality_' datestr(now,'yyyymmdd_HHMMSS_FFF') '.png']);
            try
                if ~isfolder(folder), mkdir(folder); end
                exportapp(source.App.Figure,filename);
                source.setStatus(['已保存：' filename]);
            catch exception
                uialert(source.App.Figure,exception.message,'保存失败');
            end
        end
    end
    methods (Static, Access = private)
        function refs = references(M)
            switch M
                case 0
                    refs = [-1;1];
                case 1
                    [i,q] = ndgrid([-1 1]/sqrt(2));
                    refs = complex(i(:),q(:));
                case 2
                    [i,q] = ndgrid([-3 -1 1 3]/sqrt(10));
                    refs = complex(i(:),q(:));
            end
        end
    end
end
