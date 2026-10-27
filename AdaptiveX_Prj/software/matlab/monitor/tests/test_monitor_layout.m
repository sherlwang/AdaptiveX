function tests = test_monitor_layout
% Regression: live values/ticks never move chart panels or inner plot boxes.
% Run: runtests(fullfile(projectFolder,'tests','test_monitor_layout.m'))
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.PreviousPath = path;
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

function teardownOnce(testCase)
path(testCase.TestData.PreviousPath);
end

function testInitialLayoutUsesResolvedPanelRectangles(testCase)
app = LinkQualityMonitor('Visible','off');
cleanup = onCleanup(@()deleteMonitor(app)); %#ok<NASGU>
receiver = timer('Name','LayoutTestReceiver','StartDelay',3600,'TimerFcn',@(~,~)[]);
app.attachReceiver(receiver);
% No explicit resize callback: construction/attachment must finish the
% browser's asynchronous initial grid layout without user intervention.
drawnow;
constPanel = findall(app.Figure,'Tag','ConstellationPanel');
constAxes = findall(app.Figure,'Tag','ConstellationAxes');
merPanel = findall(app.Figure,'Tag','MERPanel');
merAxes = findall(app.Figure,'Tag','MERAxes');
verifyGreaterThan(testCase,constAxes.InnerPosition(3), ...
    .45*min(constPanel.InnerPosition(3:4)));
verifyGreaterThan(testCase,merAxes.InnerPosition(3),.6*merPanel.InnerPosition(3));
value = findall(app.Figure,'Tag','CurrentMER');
verifyGreaterThan(testCase,value.Position(2),.8*constPanel.InnerPosition(4));
end

function testMeasurementsLeaveWideAndNarrowGeometryFixed(testCase)
windowSizes = [1220 760;700 640];
for layout = 1:size(windowSizes,1)
    app = LinkQualityMonitor('Visible','off');
    cleanup = onCleanup(@()deleteMonitor(app));
    % Exercise the actual acquisition-row height without opening a socket.
    % timer implements the same start/stop/delete lifecycle as a receiver.
    receiver = timer('Name','LayoutTestReceiver','ExecutionMode','singleShot', ...
        'StartDelay',3600,'TimerFcn',@(~,~)[]);
    app.attachReceiver(receiver);
    resizeWindow(app,windowSizes(layout,:));
    app.startMonitoring();
    initial = measurement(2,0,.21,30,1e-5);
    updateAndPaint(testCase,app,initial);
    baseline = chartGeometry(app.Figure);
    constAxes = findall(app.Figure,'Tag','ConstellationAxes');
    initialLimits = constAxes.XLim;

    % Unknown modes, absent IQ/measurements and real zero BER have very
    % different label widths from ordinary finite measurements.
    sample = measurement(NaN,NaN,[],NaN,NaN);
    updateAndPaint(testCase,app,sample);
    verifyFixed(testCase,baseline,chartGeometry(app.Figure));
    references = findall(app.Figure,'Tag','ReferencePoints');
    verifyEmpty(testCase,references.XData);
    sample = measurement(8,2,.06,-1e7,0);
    sample.TotalBits = 1e16;
    updateAndPaint(testCase,app,sample);
    verifyFixed(testCase,baseline,chartGeometry(app.Figure));

    % Every mode is exercised while IQ limits cross from sub-unit samples
    % through multi-digit/scientific ticks, and MER crosses orders of magnitude.
    modes = [repelem([2 4 8],3)' repmat((0:2)',3,1)];
    amplitudes = [.12 .8 1.3 3 12 75 123 1200 12345];
    merValues = [-120 -1e-6 0 .001 9.99 99.99 999.99 1e5 1e8];
    berValues = [NaN 0 1 1e-2 1e-4 1e-6 1e-8 1e-12 1.23e-15];
    for index = 1:size(modes,1)
        sample = measurement(modes(index,1),modes(index,2), ...
            amplitudes(index),merValues(index),berValues(index));
        sample.TotalBits = 1e16;
        updateAndPaint(testCase,app,sample);
        verifyFixed(testCase,baseline,chartGeometry(app.Figure));
        verifyEqual(testCase,constAxes.XLim,constAxes.YLim);
        verifyEqual(testCase,constAxes.InnerPosition(3), ...
            constAxes.InnerPosition(4),'AbsTol',.5);
    end
    verifyNotEqual(testCase,constAxes.XLim,initialLimits, ...
        'Axis limits should still respond to the received amplitudes.');

    % Fast-forward the presentation of elapsed time without a multi-hour
    % wall-clock test. drawnow nocallbacks paints the actual UIAxes renderer
    % while preserving this deliberately wide tick/status/runtime fixture.
    runtimeLabel = findall(app.Figure,'Tag','MonitorRuntime');
    runtimeLabel.Text = '运行时间  12345:59:59';
    app.setAcquisitionStatus(repmat('正在接收数据 ',1,15));
    merAxes = findall(app.Figure,'Tag','MERAxes');
    berAxes = findall(app.Figure,'Tag','BERAxes');
    merAxes.XLim = [0 12345678];
    berAxes.XLim = [12345000 12345678];
    drawnow nocallbacks;
    verifyFixed(testCase,baseline,chartGeometry(app.Figure));

    % Actual clock/timer progress and the start/end labels are covered too.
    pause(1.05);
    drawnow;
    verifyGreaterThan(testCase,app.ElapsedSeconds,1);
    verifyFixed(testCase,baseline,chartGeometry(app.Figure));
    app.stopMonitoring();
    drawnow;
    verifyFixed(testCase,baseline,chartGeometry(app.Figure));
    app.reset();
    drawnow;
    verifyFixed(testCase,baseline,chartGeometry(app.Figure));
    delete(app);
    clear cleanup
end
end

function testWindowResizeStillReflowsPanelsAndPlotBoxes(testCase)
app = LinkQualityMonitor('Visible','off');
cleanup = onCleanup(@()deleteMonitor(app)); %#ok<NASGU>
resizeWindow(app,[1220 760]);
wide = chartGeometry(app.Figure);
resizeWindow(app,[1440 1000]);
larger = chartGeometry(app.Figure);
verifyNotEqual(testCase,larger.Panels,wide.Panels);
verifyNotEqual(testCase,larger.Axes,wide.Axes);
resizeWindow(app,[700 640]);
narrow = chartGeometry(app.Figure);
verifyNotEqual(testCase,narrow.Panels,larger.Panels);
verifyNotEqual(testCase,narrow.Axes,larger.Axes);
root = app.AcquisitionPanel.Parent;
verifyEqual(testCase,char(root.Scrollable),'on');
verifyGreaterThan(testCase,root.RowHeight{4},app.Figure.Position(4));
constPanel = findall(app.Figure,'Tag','ConstellationPanel');
merPanel = findall(app.Figure,'Tag','MERPanel');
berPanel = findall(app.Figure,'Tag','BERPanel');
verifyEqual(testCase,constPanel.Layout.Column,1);
verifyEqual(testCase,merPanel.Layout.Row,2);
verifyEqual(testCase,berPanel.Layout.Row,3);
constAxes = findall(app.Figure,'Tag','ConstellationAxes');
verifyEqual(testCase,char(constAxes.PositionConstraint),'innerposition');
end

function sample = measurement(P,M,amplitude,mer,ber)
if isempty(amplitude)
    iq = [];
else
    iq = amplitude*complex([-1;-.3;.4;1],[.8;-.2;.6;-1]);
end
sample = struct('P',P,'M',M,'IQ',iq,'MERdB',mer,'BER',ber);
end

function updateAndPaint(testCase,app,sample)
app.updateMeasurement(sample);
if isnan(sample.MERdB)
    merText = 'MER  — dB';
else
    merText = sprintf('MER  %.2f dB',sample.MERdB);
end
points = findall(app.Figure,'Tag','ReceivedPoints');
label = findall(app.Figure,'Tag','CurrentMER');
deadline = tic;
while toc(deadline)<3
    pause(.04);
    drawnow;
    if isequal(label.Text,merText) && ...
            isequal(points.XData(:),real(sample.IQ(:))) && ...
            isequal(points.YData(:),imag(sample.IQ(:)))
        break
    end
end
verifyEqual(testCase,label.Text,merText,'Display timer did not render this sample.');
verifyEqual(testCase,points.XData(:),real(sample.IQ(:)));
verifyEqual(testCase,points.YData(:),imag(sample.IQ(:)));
drawnow;
end

function resizeWindow(app,dimensions)
app.Figure.Position(3:4) = dimensions;
app.Figure.SizeChangedFcn(app.Figure,[]);
% Grid layout and panel SizeChangedFcn are asynchronous. Flush both passes.
drawnow;
drawnow;
end

function geometry = chartGeometry(fig)
panelTags = {'ConstellationPanel','MERPanel','BERPanel'};
axesTags = {'ConstellationAxes','MERAxes','BERAxes'};
geometry.Panels = zeros(3,8);
geometry.Axes = zeros(3,12);
for k=1:3
    panel = findall(fig,'Tag',panelTags{k});
    ax = findall(fig,'Tag',axesTags{k});
    geometry.Panels(k,:) = [double(panel.Position),getpixelposition(panel,true)];
    parentPixels = getpixelposition(ax.Parent,true);
    inner = double(ax.InnerPosition);
    absoluteInner = [parentPixels(1:2)+inner(1:2),inner(3:4)];
    % UIAxes.Position is the decoration-inclusive outer rectangle. Tick
    % labels may extend it while the visible data rectangle remains fixed.
    geometry.Axes(k,:) = [inner,absoluteInner,observedPlotBox(ax)];
end
legendPanel = findall(fig,'Tag','ConstellationLegend');
geometry.Legend = [double(legendPanel.Position),getpixelposition(legendPanel,true)];
textTags = {'CurrentMER','CurrentMERCurve','CurrentBER','MonitorRuntime','MonitorStatus'};
geometry.Labels = zeros(numel(textTags),4);
for k=1:numel(textTags)
    label = findall(fig,'Tag',textTags{k});
    geometry.Labels(k,:) = label.Position;
end
end

function position = observedPlotBox(ax)
% Measure the data rectangle, rather than the UIAxes wrapper's outer frame.
% Account for any letterboxing from a manual aspect ratio.
parentPixels = getpixelposition(ax.Parent,true);
inner = double(ax.InnerPosition);
position = [parentPixels(1:2)+inner(1:2),inner(3:4)];
if strcmp(ax.PlotBoxAspectRatioMode,'manual')
    ratio = ax.PlotBoxAspectRatio(1)/ax.PlotBoxAspectRatio(2);
elseif strcmp(ax.DataAspectRatioMode,'manual')
    ratio = (diff(ax.XLim)/ax.DataAspectRatio(1)) / ...
        (diff(ax.YLim)/ax.DataAspectRatio(2));
else
    return
end
width = min(position(3),position(4)*ratio);
height = width/ratio;
position = [position(1)+(position(3)-width)/2, ...
    position(2)+(position(4)-height)/2,width,height];
end

function verifyFixed(testCase,expected,actual)
fields = fieldnames(expected);
for index=1:numel(fields)
    name = fields{index};
    verifyEqual(testCase,actual.(name),expected.(name),'AbsTol',.5);
end
end

function deleteMonitor(app)
if ~isempty(app) && isvalid(app)
    delete(app);
end
end
