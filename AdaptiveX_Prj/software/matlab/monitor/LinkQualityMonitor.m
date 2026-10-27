classdef LinkQualityMonitor < handle
    % LINKQUALITYMONITOR 链路质量监测图形界面。
    % 展示并行路数、调制方式、链路速率、星座分布及 MER/BER 趋势。
    % app = LinkQualityMonitor; 创建界面，初始状态为等待数据。
    % app.updateMeasurement(sample); 提交一批测量结果并更新显示。
    % 输入字段、单位和会话控制说明见 README_GUI.md。

    properties (SetAccess = private)
        Figure
        Running = false
        LastMeasurement = struct([])
        Rates = struct([])
        RunTimes = []
        MERHistory = []
        BERHistory = []
        Receiver = []
        AcquisitionPanel
    end

    properties (Dependent, SetAccess = private)
        ElapsedSeconds
    end

    properties (Access = private)
        RootGrid
        HeaderGrid
        TitleLabel
        MetricsGrid
        ContentGrid
        MetricPanels
        MetricGrids
        MetricValues
        ConstPanel
        MERPanel
        BERPanel
        ConstAxes
        MERAxes
        BERAxes
        ChartTitles
        ConstellationLegend
        LegendItems
        ChartGeometry = NaN(3,3)
        ChartLayoutBusy = false
        ReceivedPoints
        ReferencePoints
        MERLine
        MERFill
        BERLine
        BERFill
        BERZeroPoints
        MERLastPoint
        BERLastPoint
        CurrentMERLabel
        MERCurveValue
        CurrentBERLabel
        RuntimeLabel
        SourceLabel
        StartButton
        EndButton
        RefreshTimer = []
        ClockToken = []
        ElapsedBeforeStart = 0
        SessionEnded = false
        DisplayDirty = false
        BERPlotHistory = []
        HistorySeconds = 60
        TextSizes = struct('Title',24,'Body',14,'Value',28, ...
            'Section',16,'Measurement',24,'Axis',13)
        FontObjects = gobjects(1,0)
        FontBaseSizes = []
        FontScale = NaN
        NarrowLayout = []
        Colors
        UIReady = false
    end

    methods
        function app = LinkQualityMonitor(options)
            arguments
                options.Visible (1,1) string {mustBeMember(options.Visible,["on","off"])} = "on"
            end
            app.Colors = struct('Background',[248 249 252]/255, ...
                'Paper',[1 1 1], 'Ink',[0 0 0], 'Line',[161 171 184]/255, ...
                'Blue',[0 .4470 .7410], 'Red',[1 0 0], ...
                'MER',[137 112 204]/255, 'BER',[38 162 105]/255);
            try
                app.createUI();
                app.UIReady = true;
                app.applyLayout();
                app.reset();
                app.Figure.UserData = app;
                app.settleInitialLayout();
                app.Figure.Visible = options.Visible;
            catch exception
                delete(app);
                rethrow(exception)
            end
        end

        function t = get.ElapsedSeconds(app)
            % 当前会话运行秒数；调用方可在采集时读取，作为测量时间戳。
            t = app.runtime();
        end

        function updateMeasurement(app, sample)
            % 更新一批测量结果；IQ 与单位平均功率参考星座使用相同幅度标尺。
            % P 为并行路数，M 为调制编码：0=BPSK、1=QPSK、2=16QAM。
            % ElapsedSeconds 为测量时刻；省略时使用接收时刻，不改写会话时钟。
            % 显示会话结束后保留当前画面，后续提交不更新显示。
            if app.SessionEnded
                return
            end
            app.validateSample(sample);
            if isfield(sample,'ElapsedSeconds')
                t = double(sample.ElapsedSeconds);
            else
                t = app.runtime();
            end
            if t > app.runtime()
                error('LinkQuality:FutureTime', ...
                    'ElapsedSeconds 应为本会话中已发生的测量时刻，不能晚于 app.ElapsedSeconds。');
            end
            if ~isempty(app.LastMeasurement) && t < app.LastMeasurement.ElapsedSeconds
                error('LinkQuality:TimeOrder', ...
                    '测量时间不能倒退；新采集会话请先调用 app.reset()。');
            end
            if ~app.Running
                app.startMonitoring();
            end

            app.LastMeasurement = sample;
            app.LastMeasurement.ElapsedSeconds = t;
            app.Rates = app.calculateRates(sample.P,sample.M);

            plotBER = sample.BER;
            zeroBER = sample.BER == 0;
            if zeroBER
                % 零误码以 1/N 标记对数图显示界，保留原始 BER=0。
                if isfield(sample,'TotalBits') && ~isempty(sample.TotalBits)
                    plotBER = 1/double(sample.TotalBits);
                else
                    plotBER = NaN;
                end
            end
            if ~isempty(app.RunTimes) && t == app.RunTimes(end)
                index = numel(app.RunTimes);
            else
                index = numel(app.RunTimes)+1;
            end
            app.RunTimes(index) = t;
            app.MERHistory(index) = sample.MERdB;
            app.BERHistory(index) = sample.BER;
            app.BERPlotHistory(index) = plotBER;
            app.pruneHistory(app.runtime());
            % 逐批保存趋势；指标与星座图由刷新计时器统一绘制最新一批。
            app.DisplayDirty = true;
            drawnow limitrate nocallbacks
        end

        function attachReceiver(app,receiver)
            % 可选采集器只绑定一次；start/stop/delete 管理其通信资源。
            if ~isempty(app.Receiver)
                error('LinkQuality:ReceiverAttached','本界面已经绑定采集器。');
            end
            if app.Running
                error('LinkQuality:ReceiverRunning','请先结束当前会话，再绑定采集器。');
            end
            if ~isobject(receiver) || ~isscalar(receiver) || ...
                    ~all(cellfun(@(name)ismethod(receiver,name),{'start','stop','delete'}))
                error('LinkQuality:Receiver','采集器应为支持 start、stop 和 delete 的标量对象。');
            end
            app.Receiver = receiver;
            app.AcquisitionPanel.Visible = 'on';
            app.settleInitialLayout();
        end

        function setAcquisitionStatus(app,text)
            % 由采集器报告连接和接收状态。
            app.SourceLabel.Text = text;
            app.SourceLabel.Tooltip = text;
        end

        function startMonitoring(app)
            % 界面“开始”：新会话清空历史并从 0 计时。
            app.reset();
            app.ClockToken = tic;
            app.Running = true;
            app.SourceLabel.Text = '运行中';
            app.StartButton.Enable = 'off';
            app.EndButton.Enable = 'on';
            if isempty(app.RefreshTimer) || ~isvalid(app.RefreshTimer)
                % 刷新节奏独立于供数；实际运行时间始终取自 tic/toc。
                app.RefreshTimer = timer('Name','LinkQualityDisplay', ...
                    'ExecutionMode','fixedSpacing','Period',.1,'StartDelay',.1, ...
                    'TimerFcn',@(~,~)app.refreshDisplay());
            end
            start(app.RefreshTimer);
            if ~isempty(app.Receiver)
                try
                    app.Receiver.start();
                catch exception
                    app.stopMonitoring();
                    app.setAcquisitionStatus('连接失败');
                    rethrow(exception)
                end
            end
        end

        function stopMonitoring(app)
            % 界面“结束”：冻结数值、曲线和时钟，保留最后画面。
            if ~isempty(app.Receiver)
                app.Receiver.stop();
            end
            app.ElapsedBeforeStart = app.runtime();
            app.ClockToken = [];
            if ~isempty(app.RefreshTimer) && isvalid(app.RefreshTimer)
                stop(app.RefreshTimer);
            end
            % 停止前提交的最后一批即使尚未到刷新时刻，也要显示出来。
            app.refreshDisplay();
            app.SourceLabel.Text = '已结束';
            app.Running = false;
            app.SessionEnded = true;
            app.StartButton.Enable = 'on';
            app.EndButton.Enable = 'off';
            drawnow nocallbacks
        end

        function reset(app)
            % 清空测量值与历史曲线，将会话恢复为等待数据状态。
            if ~isempty(app.Receiver)
                app.Receiver.stop();
            end
            if ~isempty(app.RefreshTimer) && isvalid(app.RefreshTimer)
                stop(app.RefreshTimer);
            end
            app.SessionEnded = false;
            app.DisplayDirty = false;
            app.Running = false;
            app.ElapsedBeforeStart = 0;
            app.ClockToken = [];
            app.LastMeasurement = struct([]);
            app.Rates = struct([]);
            app.RunTimes = [];
            app.MERHistory = [];
            app.BERHistory = [];
            app.BERPlotHistory = [];
            allLines = [app.MERLine app.BERLine app.MERLastPoint ...
                app.BERLastPoint app.BERZeroPoints];
            set(allLines,'XData',NaN,'YData',NaN);
            set([app.MERFill app.BERFill],'XData',NaN,'YData',NaN);
            set(app.ReceivedPoints,'XData',NaN,'YData',NaN);
            set(app.ReferencePoints,'XData',NaN,'YData',NaN);
            app.ConstAxes.XLim = [-1.5 1.5];
            app.ConstAxes.YLim = [-1.5 1.5];
            app.MERAxes.XLim = [0 10];
            app.BERAxes.XLim = [0 10];
            app.MERAxes.YLim = [28 35];
            app.BERAxes.YLim = [1e-6 1e-3];
            app.BERAxes.YTick = 10.^(-6:-3);
            app.CurrentMERLabel.Text = 'MER  — dB';
            app.MERCurveValue.Text = '— dB';
            app.CurrentBERLabel.Text = '—';
            app.RuntimeLabel.Text = app.runtimeText(0);
            for k=1:4
                app.MetricValues(k).Text = '—';
            end
            app.StartButton.Enable = 'on';
            app.EndButton.Enable = 'off';
            app.SourceLabel.Text = '等待数据';
        end

        function delete(app)
            if ~isempty(app.Receiver)
                receiver = app.Receiver;
                app.Receiver = [];
                try
                    delete(receiver);
                catch exception
                    warning('LinkQuality:ReceiverCleanup','采集器释放失败：%s',exception.message);
                end
            end
            if ~isempty(app.RefreshTimer) && isvalid(app.RefreshTimer)
                stop(app.RefreshTimer);
                delete(app.RefreshTimer);
                app.RefreshTimer = [];
            end
            if ~isempty(app.Figure) && isgraphics(app.Figure)
                app.Figure.CloseRequestFcn = [];
                delete(app.Figure);
            end
        end
    end

    methods (Access = private)
        function createUI(app)
            c = app.Colors;
            textSize = app.TextSizes;
            screen = get(groot,'ScreenSize');
            width = min(1220,screen(3)-70);
            height = min(760,screen(4)-80);
            position = [max(20,(screen(3)-width)/2) max(25,(screen(4)-height)/2) width height];
            app.Figure = uifigure('Name','链路质量监测', ...
                'Position',position,'Color',c.Background, ...
                'Visible','off','AutoResizeChildren','off','Tag','LinkQualityMonitor', ...
                'CloseRequestFcn',@(~,~)delete(app), ...
                'SizeChangedFcn',@(~,~)app.applyLayout());
            if isprop(app.Figure,'Theme')
                try
                    app.Figure.Theme = 'light';
                catch
                    % 早期版本虽有 Theme 属性，但不接受 light 字符串。
                    % 所有界面颜色已显式设置，可沿用当前主题。
                end
            end
            app.RootGrid = uigridlayout(app.Figure,[4 1], ...
                'RowHeight',{48,104,0,'1x'},'ColumnWidth',{'1x'}, ...
                'Padding',[24 14 24 16],'RowSpacing',16, ...
                'BackgroundColor',c.Background,'Scrollable','on');
            header = uigridlayout(app.RootGrid,[1 5], ...
                'RowHeight',{'1x'},'ColumnWidth',{'1x',180,194,84,84}, ...
                'Padding',[0 0 0 0],'ColumnSpacing',10,'RowSpacing',2, ...
                'BackgroundColor',c.Background);
            header.Layout.Row = 1;
            app.HeaderGrid = header;
            title = app.label(header,'链路质量监测',textSize.Title,c.Ink,'bold');
            title.Layout.Row = 1; title.Layout.Column = 1;
            app.TitleLabel = title;
            app.SourceLabel = app.label(header,'等待数据',textSize.Body,c.Ink);
            app.SourceLabel.Layout.Row = 1; app.SourceLabel.Layout.Column = 2;
            app.SourceLabel.HorizontalAlignment = 'right';
            app.SourceLabel.Tag = 'MonitorStatus';
            app.RuntimeLabel = app.label(header,app.runtimeText(0),textSize.Body,c.Ink);
            app.RuntimeLabel.Layout.Row = 1; app.RuntimeLabel.Layout.Column = 3;
            app.RuntimeLabel.HorizontalAlignment = 'right';
            app.RuntimeLabel.Tag = 'MonitorRuntime';
            app.StartButton = uibutton(header,'push','Text','开始', ...
                'FontSize',textSize.Body,'FontColor',c.Ink, ...
                'BackgroundColor',c.Paper,'ButtonPushedFcn',@(~,~)app.startMonitoring(), ...
                'Tag','MonitorStart');
            app.StartButton.Layout.Row = 1; app.StartButton.Layout.Column = 4;
            app.EndButton = uibutton(header,'push','Text','结束','Enable','off', ...
                'FontSize',textSize.Body,'FontColor',c.Ink, ...
                'BackgroundColor',c.Paper,'ButtonPushedFcn',@(~,~)app.stopMonitoring(), ...
                'Tag','MonitorEnd');
            app.EndButton.Layout.Row = 1; app.EndButton.Layout.Column = 5;
            app.registerFont(app.StartButton,textSize.Body);
            app.registerFont(app.EndButton,textSize.Body);

            app.MetricsGrid = uigridlayout(app.RootGrid,[1 4], ...
                'ColumnWidth',{'1x','1x','1x','1x'},'RowHeight',{'1x'}, ...
                'Padding',[0 0 0 0],'ColumnSpacing',12, ...
                'BackgroundColor',c.Background);
            app.MetricsGrid.Layout.Row = 2;
            captions = {'P-并行路数','M-调制方式','空口速率','业务速率'};
            app.MetricPanels = gobjects(1,4);
            app.MetricGrids = gobjects(1,4);
            app.MetricValues = gobjects(1,4);
            for k=1:4
                panel = uipanel(app.MetricsGrid,'BorderType','line', ...
                    'BorderColor',c.Line,'BorderWidth',1,'BackgroundColor',c.Paper);
                panel.Layout.Row = 1; panel.Layout.Column = k;
                app.MetricPanels(k) = panel;
                % 上下弹性行等高，使数值始终位于卡片中心，标题靠左上。
                grid = uigridlayout(panel,[3 1],'RowHeight',{'1x',40,'1x'}, ...
                    'Padding',[17 12 17 12],'RowSpacing',0,'BackgroundColor',c.Paper);
                app.MetricGrids(k) = grid;
                caption = app.label(grid,captions{k},textSize.Body,c.Ink);
                caption.Layout.Row = 1;
                caption.VerticalAlignment = 'top';
                app.MetricValues(k) = app.label(grid,'—',textSize.Value,c.Ink,'bold');
                app.MetricValues(k).Layout.Row = 2;
                app.MetricValues(k).HorizontalAlignment = 'center';
                app.MetricValues(k).VerticalAlignment = 'center';
                app.MetricValues(k).Tag = sprintf('MetricValue%d',k);
            end

            app.AcquisitionPanel = uipanel(app.RootGrid,'BorderType','none', ...
                'BackgroundColor',c.Background,'Visible','off','Tag','AcquisitionPanel');
            app.AcquisitionPanel.Layout.Row = 3;

            app.ContentGrid = uigridlayout(app.RootGrid,[2 2], ...
                'RowHeight',{'1x','1x'},'ColumnWidth',{'1x','1x'}, ...
                'Padding',[0 0 0 0],'RowSpacing',16,'ColumnSpacing',18, ...
                'BackgroundColor',c.Background);
            app.ContentGrid.Layout.Row = 4;
            app.ConstPanel = app.chartPanel(c.Blue);
            app.MERPanel = app.chartPanel(c.MER);
            app.BERPanel = app.chartPanel(c.BER);
            app.ConstPanel.Tag = 'ConstellationPanel';
            app.MERPanel.Tag = 'MERPanel';
            app.BERPanel.Tag = 'BERPanel';
            app.ChartTitles = gobjects(1,3);

            % Chart children deliberately do not use content-sized grid rows.
            % Text, tick labels and legends must never resize a live plot box.
            app.ChartTitles(1) = app.label(app.ConstPanel,'星座图',textSize.Section,c.Ink,'bold');
            app.CurrentMERLabel = app.label(app.ConstPanel,'MER  — dB',textSize.Measurement,c.Ink,'bold');
            app.CurrentMERLabel.HorizontalAlignment = 'right';
            app.CurrentMERLabel.Tag = 'CurrentMER';
            app.ConstAxes = app.chartAxes(app.ConstPanel,c.Blue);
            app.ConstAxes.Tag = 'ConstellationAxes';
            app.ConstAxes.XLabel.String = 'In-phase';
            app.ConstAxes.YLabel.String = 'Quadrature';
            app.ConstAxes.XLim = [-1.5 1.5]; app.ConstAxes.YLim = [-1.5 1.5];
            app.ConstAxes.DataAspectRatio = [1 1 1];
            app.ConstAxes.PlotBoxAspectRatio = [1 1 1];
            hold(app.ConstAxes,'on');
            app.ReceivedPoints = scatter(app.ConstAxes,NaN,NaN,6,c.Blue,'filled', ...
                'MarkerFaceAlpha',.55,'MarkerEdgeColor','none','Tag','ReceivedPoints');
            app.ReferencePoints = plot(app.ConstAxes,NaN,NaN,'+', ...
                'Color',c.Red,'MarkerSize',8,'LineWidth',1.1,'Tag','ReferencePoints');
            % A separate fixed UI legend cannot negotiate space with the axes.
            app.ConstellationLegend = uipanel(app.ConstPanel,'BorderType','none', ...
                'BackgroundColor',c.Paper,'AutoResizeChildren','off','Tag','ConstellationLegend');
            app.LegendItems = gobjects(1,4);
            app.LegendItems(1) = app.label(app.ConstellationLegend,'●',textSize.Axis,c.Blue);
            app.LegendItems(2) = app.label(app.ConstellationLegend,'接收点',textSize.Axis,c.Ink);
            app.LegendItems(3) = app.label(app.ConstellationLegend,'＋',textSize.Section,c.Red);
            app.LegendItems(4) = app.label(app.ConstellationLegend,'标准参考',textSize.Axis,c.Ink);

            app.ChartTitles(2) = app.label(app.MERPanel,'MER 曲线',textSize.Section,c.Ink,'bold');
            app.MERCurveValue = app.label(app.MERPanel,'— dB',textSize.Measurement,c.Ink,'bold');
            app.MERCurveValue.HorizontalAlignment = 'right';
            app.MERCurveValue.Tag = 'CurrentMERCurve';
            app.MERAxes = app.chartAxes(app.MERPanel,c.MER);
            app.MERAxes.Tag = 'MERAxes';
            app.MERAxes.XLabel.String = '运行时间（s）';
            app.MERAxes.YLabel.String = 'MER（dB）';
            hold(app.MERAxes,'on');
            app.MERFill = patch(app.MERAxes,NaN,NaN,c.MER, ...
                'FaceAlpha',.1,'EdgeColor','none','HandleVisibility','off');
            app.MERLine = plot(app.MERAxes,NaN,NaN,'Color',c.MER, ...
                'LineWidth',1.5,'Tag','MERTrend');
            app.MERLastPoint = plot(app.MERAxes,NaN,NaN,'.','Color',c.MER,'MarkerSize',10);

            app.ChartTitles(3) = app.label(app.BERPanel,'BER 曲线',textSize.Section,c.Ink,'bold');
            app.CurrentBERLabel = app.label(app.BERPanel,'—',textSize.Measurement,c.Ink,'bold');
            app.CurrentBERLabel.HorizontalAlignment = 'right';
            app.CurrentBERLabel.Tag = 'CurrentBER';
            app.BERAxes = app.chartAxes(app.BERPanel,c.BER);
            app.BERAxes.Tag = 'BERAxes';
            app.BERAxes.YScale = 'log';
            app.BERAxes.TickLabelInterpreter = 'tex';
            app.BERAxes.XLabel.String = '运行时间（s）';
            app.BERAxes.YLabel.String = 'BER';
            hold(app.BERAxes,'on');
            app.BERFill = patch(app.BERAxes,NaN,NaN,c.BER, ...
                'FaceAlpha',.1,'EdgeColor','none','HandleVisibility','off');
            app.BERLine = plot(app.BERAxes,NaN,NaN,'Color',c.BER, ...
                'LineWidth',1.5,'Tag','BERTrend');
            app.BERLastPoint = plot(app.BERAxes,NaN,NaN,'.','Color',c.BER,'MarkerSize',10);
            app.BERZeroPoints = plot(app.BERAxes,NaN,NaN,'v', ...
                'LineStyle','none','Color',c.BER,'MarkerSize',5,'Tag','BERZeroBounds');
        end

        function panel = chartPanel(app,color)
            panel = uipanel(app.ContentGrid,'BorderType','line', ...
                'BorderWidth',1,'BorderColor',color,'BackgroundColor',app.Colors.Paper, ...
                'AutoResizeChildren','off','SizeChangedFcn',@(~,~)app.layoutChartPanels());
        end

        function ax = chartAxes(app,parent,color)
            ax = uiaxes(parent,'Units','pixels','FontSize',app.TextSizes.Axis, ...
                'Color',[250 250 251]/255,'XColor',color, ...
                'YColor',color,'Box','on','LineWidth',1, ...
                'XGrid','on','YGrid','on','GridColor',color,'GridAlpha',.17, ...
                'GridLineStyle','-','TickDir','in');
            ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';
            % Keep the data rectangle fixed when automatic ticks/TightInset change.
            if isprop(ax,'PositionConstraint')
                ax.PositionConstraint = 'innerposition';
            else
                ax.ActivePositionProperty = 'position';
            end
            ax.Toolbar.Visible = 'off';
            % 轴线使用强调色，刻度数字与轴名独立保持黑色。
            if isprop(ax.XAxis,'TickLabelColor')
                ax.XAxis.TickLabelColor = app.Colors.Ink;
                ax.YAxis.TickLabelColor = app.Colors.Ink;
            end
            ax.XLabel.Color = app.Colors.Ink; ax.YLabel.Color = app.Colors.Ink;
            ax.XLabel.FontSize = app.TextSizes.Axis;
            ax.YLabel.FontSize = app.TextSizes.Axis;
            ax.XLabel.Interpreter = 'none'; ax.YLabel.Interpreter = 'none';
            app.registerFont(ax,app.TextSizes.Axis);
        end

        function control = label(app,parent,text,size,color,weight)
            if nargin < 6
                weight = 'normal';
            end
            control = uilabel(parent,'Text',text, ...
                'FontSize',size,'FontColor',color,'FontWeight',weight);
            app.registerFont(control,size);
        end

        function registerFont(app,object,baseSize)
            app.FontObjects(end+1) = object;
            app.FontBaseSizes(end+1) = baseSize;
        end

        function control = placeLabel(app,parent,text,size,color,row,column,weight)
            if nargin < 8
                weight = 'normal';
            end
            control = app.label(parent,text,size,color,weight);
            control.Layout.Row = row; control.Layout.Column = column;
        end

        function applyLayout(app)
            if ~app.UIReady || ~isgraphics(app.Figure)
                return
            end
            windowSize = app.Figure.Position(3:4);
            narrow = windowSize(1) < 940;
            % 以 1220×760 为基准，统一缩放字号；宽度约束保护四列指标卡。
            scale = min([1.5,sqrt(prod(windowSize./[1220 760])),windowSize(1)/1000]);
            scale = round(100*max(.9,scale))/100;
            scaleChanged = ~isequal(scale,app.FontScale);
            modeChanged = ~isequal(narrow,app.NarrowLayout);
            if scaleChanged
                % 始终从基准字号计算，避免逐次取整与单位换算累积偏差。
                for baseSize=unique(app.FontBaseSizes)
                    objects = app.FontObjects(app.FontBaseSizes==baseSize);
                    if exist('fontsize','file') == 2 || exist('fontsize','builtin') == 5
                        fontsize(objects,round(baseSize*scale),'pixels');
                    else
                        for object = reshape(objects,1,[])
                            if isprop(object,'FontUnits')
                                object.FontUnits = 'pixels';
                            end
                            object.FontSize = round(baseSize*scale);
                        end
                    end
                end
                app.FontScale = scale;
                for k=1:numel(app.MetricGrids)
                    app.MetricGrids(k).RowHeight = {'1x',40*scale,'1x'};
                end
            end

            % 网格负责连续伸缩；仅在宽、窄模式切换时重排组件。
            if modeChanged
                app.NarrowLayout = narrow;
                if narrow
                    app.TitleLabel.Layout.Row = 1; app.TitleLabel.Layout.Column = [1 5];
                    app.SourceLabel.Layout.Row = 2; app.SourceLabel.Layout.Column = 1;
                    app.SourceLabel.HorizontalAlignment = 'left';
                    app.RuntimeLabel.Layout.Row = 2; app.RuntimeLabel.Layout.Column = [2 3];
                    app.StartButton.Layout.Row = 2; app.EndButton.Layout.Row = 2;
                    app.MetricsGrid.ColumnWidth = {'1x','1x'};
                    app.MetricsGrid.RowHeight = {'1x','1x'};
                    for k=1:4
                        app.MetricPanels(k).Layout.Row = ceil(k/2);
                        app.MetricPanels(k).Layout.Column = 1+mod(k-1,2);
                    end
                    app.ContentGrid.ColumnWidth = {'1x'};
                    app.ContentGrid.RowHeight = {'22x','13x','13x'};
                    app.ConstPanel.Layout.Row = 1; app.ConstPanel.Layout.Column = 1;
                    app.MERPanel.Layout.Row = 2; app.MERPanel.Layout.Column = 1;
                    app.BERPanel.Layout.Row = 3; app.BERPanel.Layout.Column = 1;
                else
                    app.TitleLabel.Layout.Row = 1; app.TitleLabel.Layout.Column = 1;
                    app.SourceLabel.Layout.Row = 1; app.SourceLabel.Layout.Column = 2;
                    app.SourceLabel.HorizontalAlignment = 'right';
                    app.RuntimeLabel.Layout.Row = 1; app.RuntimeLabel.Layout.Column = 3;
                    app.StartButton.Layout.Row = 1; app.EndButton.Layout.Row = 1;
                    app.MetricsGrid.ColumnWidth = {'1x','1x','1x','1x'};
                    app.MetricsGrid.RowHeight = {'1x'};
                    for k=1:4
                        app.MetricPanels(k).Layout.Row = 1;
                        app.MetricPanels(k).Layout.Column = k;
                    end
                    app.ContentGrid.ColumnWidth = {'1x','1x'};
                    app.ContentGrid.RowHeight = {'1x','1x'};
                    app.ConstPanel.Layout.Row = [1 2]; app.ConstPanel.Layout.Column = 1;
                    app.MERPanel.Layout.Row = 1; app.MERPanel.Layout.Column = 2;
                    app.BERPanel.Layout.Row = 2; app.BERPanel.Layout.Column = 2;
                end
            end
            if scaleChanged || modeChanged
                if narrow
                    app.HeaderGrid.ColumnWidth = [{'1x'},num2cell([90 90 76 76]*scale)];
                    app.HeaderGrid.RowHeight = num2cell([32 36]*scale);
                else
                    app.HeaderGrid.ColumnWidth = [{'1x'},num2cell([180 194 84 84]*scale)];
                    app.HeaderGrid.RowHeight = {'1x'};
                end
            end

            % 保留图表最小阅读空间，短窗口与极窄窗口使用原生滚动。
            if narrow
                headerHeights = [76 220]*scale;
                minimumContent = 960*scale+2*app.ContentGrid.RowSpacing;
            else
                headerHeights = [48 104]*scale;
                minimumContent = 400*scale;
            end
            acquisitionHeight = 0;
            if ~isempty(app.Receiver)
                if narrow
                    acquisitionHeight = max(140,140*scale);
                else
                    acquisitionHeight = max(76,76*scale);
                end
            end
            available = windowSize(2)-sum(app.RootGrid.Padding([2 4])) ...
                -3*app.RootGrid.RowSpacing-sum(headerHeights)-acquisitionHeight;
            contentHeight = '1x';
            if available < minimumContent
                contentHeight = minimumContent;
            end
            rows = [num2cell(headerHeights),{acquisitionHeight,contentHeight}];
            if ~isequal(app.RootGrid.RowHeight,rows)
                app.RootGrid.RowHeight = rows;
            end
            columns = {'1x'};
            if windowSize(1)-sum(app.RootGrid.Padding([1 3])) < 600*scale
                columns = {600*scale};
            end
            if ~isequal(app.RootGrid.ColumnWidth,columns)
                app.RootGrid.ColumnWidth = columns;
            end
            % Resolve the grid before reading panel sizes, including hidden
            % figures whose SizeChangedFcn dispatch may be deferred.
            drawnow nocallbacks
            app.layoutChartPanels();
        end

        function settleInitialLayout(app)
            % The grid client reports geometry asynchronously, even when the
            % figure is hidden. Finish the initial hierarchy changes before
            % exposing/starting the monitor, rather than caching default sizes.
            started = tic;
            while toc(started)<1
                drawnow;
                app.applyLayout();
                content = app.ContentGrid.Position(3:4);
                rows = app.RootGrid.RowHeight;
                width = app.RootGrid.ColumnWidth{1};
                if ~isnumeric(width)
                    width = app.Figure.Position(3)-sum(app.RootGrid.Padding([1 3]));
                end
                height = rows{4};
                if ~isnumeric(height)
                    height = app.Figure.Position(4)-sum(app.RootGrid.Padding([2 4])) ...
                        -3*app.RootGrid.RowSpacing-sum(cell2mat(rows(1:3)));
                end
                if app.NarrowLayout
                    expectedWidth = content(1)-2;
                    expectedHeight = (content(2)-2*app.ContentGrid.RowSpacing)*[22 13 13]/48-2;
                else
                    expectedWidth = (content(1)-app.ContentGrid.ColumnSpacing)/2-2;
                    expectedHeight = [content(2) repmat((content(2)-app.ContentGrid.RowSpacing)/2,1,2)]-2;
                end
                panels = [app.ConstPanel app.MERPanel app.BERPanel];
                sizes = zeros(3,2);
                for k=1:3, sizes(k,:) = panels(k).InnerPosition(3:4); end
                % A vertical scrollbar may consume part of the client width.
                if abs(content(1)-width)<=24 && abs(content(2)-height)<=2 ...
                        && all(abs(sizes(:,1)-expectedWidth)<=2) ...
                        && all(abs(sizes(:,2)-expectedHeight(:))<=2)
                    app.layoutChartPanels();
                    return
                end
                pause(.01);
            end
            app.layoutChartPanels();
        end

        function layoutChartPanels(app)
            % This is the sole owner of chart geometry. It runs only when the
            % panel's pixel size or the window-driven font scale changes.
            % Measurement text, axis limits and tick extents are not inputs.
            if ~app.UIReady || app.ChartLayoutBusy || ~isgraphics(app.Figure)
                return
            end
            app.ChartLayoutBusy = true;
            cleanup = onCleanup(@()app.finishChartLayout()); %#ok<NASGU>
            panels = [app.ConstPanel app.MERPanel app.BERPanel];
            axesHandles = [app.ConstAxes app.MERAxes app.BERAxes];
            values = [app.CurrentMERLabel app.MERCurveValue app.CurrentBERLabel];
            scale = app.FontScale;
            if ~isfinite(scale), scale = 1; end
            for k=1:3
                panelSize = panels(k).InnerPosition(3:4);
                geometryKey = [panelSize scale];
                if isequal(app.ChartGeometry(k,:),geometryKey)
                    continue
                end
                app.ChartGeometry(k,:) = geometryKey;
                width = panelSize(1);
                height = panelSize(2);
                padding = 14*scale;
                headerHeight = 42*scale;
                valueWidth = min(260*scale,.64*width);
                titleWidth = max(40,width-valueWidth-3*padding);
                app.ChartTitles(k).Position = ...
                    [padding,max(1,height-headerHeight),titleWidth,headerHeight];
                values(k).Position = ...
                    [max(1,width-padding-valueWidth),max(1,height-headerHeight),valueWidth,headerHeight];

                % Fixed margins reserve room for changing tick labels and
                % exponents. The inner data rectangle never uses TightInset.
                left = 80*scale;
                right = 24*scale;
                bottom = 52*scale;
                if k==1, bottom = 78*scale; end
                plotWidth = max(20,width-left-right);
                plotHeight = max(20,height-headerHeight-14*scale-bottom);
                position = [left,bottom,plotWidth,plotHeight];
                if k==1
                    % A square inner rectangle plus equal X/Y limits gives a
                    % square, stable plot box even with manual aspect ratios.
                    side = min(plotWidth,plotHeight);
                    position = [left+(plotWidth-side)/2, ...
                        bottom+(plotHeight-side)/2,side,side];
                    legendWidth = min(234*scale,max(20,width-2*padding));
                    app.ConstellationLegend.Position = ...
                        [(width-legendWidth)/2,8*scale,legendWidth,24*scale];
                    slots = [0 20;22 70;110 22;136 98]*scale;
                    for item=1:4
                        app.LegendItems(item).Position = ...
                            [slots(item,1),1,slots(item,2),22*scale];
                    end
                end
                axesHandles(k).InnerPosition = position;
            end
        end

        function finishChartLayout(app)
            if isvalid(app)
                app.ChartLayoutBusy = false;
            end
        end

        function renderMeasurement(app)
            % 指标、调制参考点和接收点统一取自同一批测量结果。
            sample = app.LastMeasurement;
            app.MetricValues(1).Text = app.numberOrDash(sample.P,'%.0f');
            names = {'BPSK','QPSK','16QAM'};
            if isnan(sample.M)
                app.MetricValues(2).Text = '—';
            else
                app.MetricValues(2).Text = names{sample.M+1};
            end
            app.MetricValues(3).Text = app.rateText(app.Rates.AirBps);
            app.MetricValues(4).Text = app.rateText(app.Rates.BusinessBps);
            merText = [app.numberOrDash(sample.MERdB,'%.2f') ' dB'];
            app.CurrentMERLabel.Text = ['MER  ' merText];
            app.MERCurveValue.Text = merText;
            app.CurrentBERLabel.Text = app.berText(sample.BER);
            app.CurrentMERLabel.Tooltip = app.CurrentMERLabel.Text;
            app.MERCurveValue.Tooltip = app.MERCurveValue.Text;
            app.CurrentBERLabel.Tooltip = app.CurrentBERLabel.Text;

            iq = double(sample.IQ(:));
            refs = app.referenceForM(sample.M);
            app.ReceivedPoints.XData = real(iq);
            app.ReceivedPoints.YData = imag(iq);
            app.ReferencePoints.XData = real(refs);
            app.ReferencePoints.YData = imag(refs);
            bound = ceil(1.18 * max([1;abs(real(iq));abs(imag(iq)); ...
                abs(real(refs));abs(imag(refs))])*2)/2;
            app.ConstAxes.XLim = [-bound bound];
            app.ConstAxes.YLim = [-bound bound];
        end

        function pruneHistory(app,t)
            % 以运行时钟裁剪窗口，断流后过期曲线也会自然移出视野。
            keep = app.RunTimes >= t-app.HistorySeconds-1;
            app.RunTimes = app.RunTimes(keep);
            app.MERHistory = app.MERHistory(keep);
            app.BERHistory = app.BERHistory(keep);
            app.BERPlotHistory = app.BERPlotHistory(keep);
        end

        function drawTrends(app,t)
            times = app.RunTimes;
            mer = app.MERHistory;
            ber = app.BERPlotHistory;
            limits = [max(0,t-app.HistorySeconds) max(10,t)];
            app.MERAxes.XLim = limits; app.BERAxes.XLim = limits;
            app.MERLine.XData = times; app.MERLine.YData = mer;
            app.BERLine.XData = times; app.BERLine.YData = ber;
            if isempty(times)
                set([app.MERLastPoint app.BERLastPoint app.BERZeroPoints], ...
                    'XData',NaN,'YData',NaN);
                set([app.MERFill app.BERFill],'XData',NaN,'YData',NaN);
                return
            end
            visible = times >= limits(1);
            merValid = mer(visible & isfinite(mer));
            if ~isempty(merValid)
                pad = max(.5,.2*(max(merValid)-min(merValid)));
                yLimits = [floor((min(merValid)-pad)*2)/2 ceil((max(merValid)+pad)*2)/2];
                app.MERAxes.YLim = yLimits;
                app.updateFill(app.MERFill,times,mer,yLimits(1));
            else
                set(app.MERFill,'XData',NaN,'YData',NaN);
            end
            berValid = ber(visible & isfinite(ber) & ber>0);
            if ~isempty(berValid)
                lowPower = floor(log10(min(berValid)));
                highPower = ceil(log10(max(berValid)));
                if highPower-lowPower < 2
                    lowPower = highPower-2;
                end
                app.BERAxes.YLim = [10^lowPower 10^highPower];
                app.BERAxes.YTick = 10.^(lowPower:highPower);
                app.updateFill(app.BERFill,times,ber,10^lowPower);
            else
                set(app.BERFill,'XData',NaN,'YData',NaN);
            end
            app.MERLastPoint.XData = times(end); app.MERLastPoint.YData = mer(end);
            app.BERLastPoint.XData = times(end); app.BERLastPoint.YData = ber(end);
            zero = app.BERHistory==0 & isfinite(ber);
            app.BERZeroPoints.XData = times(zero);
            app.BERZeroPoints.YData = ber(zero);
        end

        function refreshDisplay(app)
            if ~isgraphics(app.Figure)
                delete(app);
                return
            end
            t = app.runtime();
            if app.DisplayDirty
                app.renderMeasurement();
                app.DisplayDirty = false;
            end
            app.pruneHistory(t);
            app.drawTrends(t);
            app.RuntimeLabel.Text = app.runtimeText(t);
            % 绘制整批结果期间不执行新回调，避免半批显示或嵌套刷新。
            drawnow limitrate nocallbacks
        end

        function t = runtime(app)
            t = app.ElapsedBeforeStart;
            if ~isempty(app.ClockToken)
                t = t + toc(app.ClockToken);
            end
        end
    end

    methods (Static, Access = private)
        function rate = calculateRates(P,M)
            % 默认速率模型：依据并行路数、调制方式和帧结构计算理论速率。
            % f_clk=204.8 MHz，帧头=32+16/P clk，2 训练+6 数据块；
            % 每块 9 CP+1 导频+255clk，每个数据块含 192clk 信息位。
            rate = struct('AirBps',NaN,'BusinessBps',NaN);
            if isnan(P) || isnan(M)
                return
            end
            P = double(P); M = double(M);
            frameClocks = 32+16/P+8*(9+1+255);
            rate.AirBps = 204.8e6*P*2^M;
            rate.BusinessBps = rate.AirBps*6*192/frameClocks;
        end

        function validateSample(sample)
            if ~isstruct(sample) || ~isscalar(sample)
                error('LinkQuality:Sample','测量数据应为标量结构体。');
            end
            fields = {'P','M','IQ','MERdB','BER'};
            if ~all(isfield(sample,fields))
                error('LinkQuality:Fields','测量数据必须含 P、M、IQ、MERdB、BER。');
            end
            validateattributes(sample.P,{'numeric'},{'scalar','real'});
            validateattributes(sample.M,{'numeric'},{'scalar','real'});
            if ~isnan(sample.P) && ~ismember(sample.P,[2 4 8])
                error('LinkQuality:InvalidP','P 应为 2、4、8 或 NaN。');
            end
            if ~isnan(sample.M) && ~ismember(sample.M,[0 1 2])
                error('LinkQuality:InvalidM','M 应为调制编码 0、1、2 或 NaN。');
            end
            validateattributes(sample.IQ,{'numeric'},{'finite'});
            if ~isempty(sample.IQ) && ~isvector(sample.IQ)
                error('LinkQuality:IQShape','IQ 应为复数向量或空数组。');
            end
            validateattributes(sample.MERdB,{'numeric'},{'scalar','real'});
            validateattributes(sample.BER,{'numeric'},{'scalar','real'});
            if isinf(sample.MERdB) || isinf(sample.BER) || ...
                    (~isnan(sample.BER) && (sample.BER<0 || sample.BER>1))
                error('LinkQuality:Metric','MERdB 应为有限数或 NaN，BER 应在 [0,1] 内或为 NaN。');
            end
            if isfield(sample,'ElapsedSeconds')
                validateattributes(sample.ElapsedSeconds,{'numeric'}, ...
                    {'scalar','real','finite','nonnegative'});
            end
            if isfield(sample,'TotalBits') && ~isempty(sample.TotalBits)
                validateattributes(sample.TotalBits,{'numeric'}, ...
                    {'scalar','real','finite','integer','positive'});
            end
        end

        function refs = referenceForM(M)
            switch M
                case 0
                    refs = [-1;1];
                case 1
                    [i,q] = ndgrid([-1 1]/sqrt(2));
                    refs = i(:)+1j*q(:);
                case 2
                    [i,q] = ndgrid([-3 -1 1 3]/sqrt(10));
                    refs = i(:)+1j*q(:);
                otherwise
                    refs = complex(zeros(0,1));
            end
        end

        function updateFill(fillHandle,times,values,base)
            % 含缺测时不填充面积，避免跨越无效测量区间。
            if all(isfinite(values)) && numel(times)>1
                fillHandle.XData = [times fliplr(times)];
                fillHandle.YData = [values repmat(base,size(values))];
            else
                set(fillHandle,'XData',NaN,'YData',NaN);
            end
        end

        function text = numberOrDash(value,format)
            if isnan(value)
                text = '—';
            else
                text = sprintf(format,value);
            end
        end

        function text = rateText(bps)
            if isnan(bps)
                text = '— Gbit/s';
            else
                text = sprintf('%.3f Gbit/s',bps/1e9);
            end
        end

        function text = berText(value)
            if isnan(value)
                text = '—';
            elseif value == 0
                text = '0';
            else
                parts = strsplit(sprintf('%.2e',value),'e');
                exponent = str2double(parts{2});
                digits = sprintf('%d',abs(exponent));
                superscripts = '⁰¹²³⁴⁵⁶⁷⁸⁹';
                power = superscripts(double(digits)-double('0')+1);
                if exponent<0
                    power = ['⁻' power];
                end
                text = [parts{1} ' × 10' power];
            end
        end

        function text = runtimeText(t)
            % 仅显示到整秒，内部运行时间与测量时间戳保留小数秒。
            t = floor(t);
            text = sprintf('运行时间  %02d:%02d:%02d', ...
                floor(t/3600),floor(mod(t,3600)/60),mod(t,60));
        end

    end
end
