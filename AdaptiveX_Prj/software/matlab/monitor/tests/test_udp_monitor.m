function tests = test_udp_monitor
% Independent wire fixtures for Rx MAC1 UDP264 protocol version 1.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.PreviousPath = path;
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

function teardownOnce(testCase)
path(testCase.TestData.PreviousPath);
end

function testSignedQ14LittleEndianMetadataAndInterleaving(testCase)
payload = zeros(264,1,'uint8');
% Wire: I0_lo I0_hi I1_lo I1_hi Q0_lo Q0_hi Q1_lo Q1_hi.
payload(1:8) = uint8([255 127 0 192 0 128 255 255]);
payload(9:16) = uint8([1 128 52 18 255 63 0 64]);
payload(17:24) = uint8([1 0 0 0 1 0 0 128]);
payload(25:32) = uint8([255 255 0 128 0 192 255 127]);
% N=0xFEDCBA98, E=0x01234567, RX/version1/P8-M2, FID=0xFEDCBA98.
payload(249:264) = uint8([152 186 220 254 103 69 35 1 82 88 1 162 152 186 220 254]);
[iq,bits,errors,meta] = decodeJiemianDatagrams(payload);
expected = complex(zeros(62,1));
expected(1:8) = complex([32767;-16384;-32767;4660;1;0;-1;-32768], ...
    [-32768;-1;16383;16384;1;-32768;-16384;32767])/16384;
verifySize(testCase,iq,[62 1]);
verifyEqual(testCase,iq,expected);
verifyEqual(testCase,double(bits),4275878552);
verifyEqual(testCase,double(errors),19088743);
verifyClass(testCase,meta.P,'double');
verifyClass(testCase,meta.M,'double');
verifyClass(testCase,meta.FrameID,'uint32');
verifyClass(testCase,meta.Version,'uint8');
verifyEqual(testCase,meta.P,8);
verifyEqual(testCase,meta.M,2);
verifyEqual(testCase,meta.FrameID,uint32(4275878552));
verifyEqual(testCase,meta.Version,uint8(1));
end

function testAllNineMetadataModesAndPacketTimeOrder(testCase)
modeBytes = [136 137 138 144 145 146 160 161 162];
payload = zeros(264,9,'uint8');
expected = complex(zeros(62*9,1));
for packet = 1:9
    packetExpected = complex(zeros(62,1));
    for row = 1:31
        indices = 8*(row-1)+(1:8);
        payload(indices,packet) = uint8([row+packet 0 100+row 0 50+row 0 200+row 0])';
        packetExpected(2*row-1) = complex(row+packet,50+row)/16384;
        packetExpected(2*row) = complex(100+row,200+row)/16384;
    end
    payload(249:264,packet) = uint8([64 48 32 16 4 3 2 1 ...
        82 88 1 modeBytes(packet) packet 0 0 128])';
    expected((packet-1)*62+(1:62)) = packetExpected;
end
[iq,bits,errors,meta] = decodeJiemianDatagrams(payload);
verifyEqual(testCase,iq,expected);
verifyEqual(testCase,double(bits),repmat(270544960,9,1));
verifyEqual(testCase,double(errors),repmat(16909060,9,1));
verifyEqual(testCase,meta.P,[2;2;2;4;4;4;8;8;8]);
verifyEqual(testCase,meta.M,[0;1;2;0;1;2;0;1;2]);
verifyEqual(testCase,meta.FrameID,uint32(2147483648+(1:9)'));
verifyEqual(testCase,meta.Version,ones(9,1,'uint8'));
end

function testStatisticsAndMetadataNeverBecomeIQ(testCase)
payload = zeros(264,1,'uint8');
payload(249:264) = uint8([255 255 255 255 0 0 0 128 82 88 1 145 255 255 255 255]);
[iq,bits,errors,meta] = decodeJiemianDatagrams(payload);
verifySize(testCase,iq,[62 1]);
verifyEqual(testCase,real(iq),zeros(62,1));
verifyEqual(testCase,imag(iq),zeros(62,1));
verifyEqual(testCase,double(bits),4294967295);
verifyEqual(testCase,double(errors),2147483648);
verifyEqual(testCase,meta.FrameID,uint32(4294967295));
end

function testLengthMagicVersionAndModeValidation(testCase)
[good,~] = wirePacket(136,[1 0 0 0],0,1);
badLengths = {uint8([]),zeros(264,0,'uint8'),zeros(256,1,'uint8'), ...
    zeros(263,1,'uint8'),zeros(265,1,'uint8'),zeros(528,1,'uint8'),zeros(263,2,'uint8')};
for index = 1:numel(badLengths)
    verifyError(testCase,@()decodeJiemianDatagrams(badLengths{index}),'RxUDP:PacketLength');
end
for index = [257 258]
    bad = good; bad(index) = 0;
    verifyError(testCase,@()decodeJiemianDatagrams(bad),'RxUDP:Magic');
end
for version = [0 2]
    bad = good; bad(259) = version;
    verifyError(testCase,@()decodeJiemianDatagrams(bad),'RxUDP:Version');
end
% valid=0; reserved=1; P=0/1/3/15; M=3 must all be rejected.
for modeByte = [8 200 128 132 140 188 139]
    bad = good; bad(260) = modeByte;
    verifyError(testCase,@()decodeJiemianDatagrams(bad),'RxUDP:InvalidMode');
end
bad = [good good]; bad(259,2) = 2;
verifyError(testCase,@()decodeJiemianDatagrams(bad),'RxUDP:Version');
end

function testPassivePushAutomaticallyDisplaysAllNineModes(testCase)
requireNetworkToolboxes(testCase);
timersBefore = monitorTimerCounts();
[fig,app,board,localPort] = openLoopback();
cleanup = onCleanup(@()deleteMonitor(app)); %#ok<NASGU>
receiver = app.Receiver;
verifyEqual(testCase,receiver.StaleAfterSeconds,1);
verifyEmpty(testCase,findall(fig,'Tag','UDPParallelP'));
verifyEmpty(testCase,findall(fig,'Tag','UDPModulationM'));
verifyEmpty(testCase,findall(fig,'Tag','UDPGroups'));
app.startMonitoring();
verifyTrue(testCase,app.Running);
% The PC must not send the former acquisition request, even before data arrives.
verifyFalse(testCase,waitUntil(@()board.NumDatagramsAvailable>0,.15));
verifyEqual(testCase,receiver.ReceivedDatagrams,0);
modeBytes = [136 137 138 144 145 146 160 161 162];
pValues = [2 2 2 4 4 4 8 8 8];
mValues = [0 1 2 0 1 2 0 1 2];
pMetric = findall(fig,'Tag','MetricValue1');
mMetric = findall(fig,'Tag','MetricValue2');
mNames = {'BPSK','QPSK','16QAM'};
for index = 1:9
    [payload,expectedIQ] = wirePacket(modeBytes(index),[index 0 0 128],index,index);
    write(board,payload,'uint8','127.0.0.1',localPort);
    assertTrue(testCase,waitUntil(@()receiver.ReceivedDatagrams>=index && ...
        receiver.PublishedBatches>=index && sampleHasFrame(app,uint32(2147483648+index)),2), ...
        sprintf('P=%d/M=%d did not publish one pushed packet.',pValues(index),mValues(index)));
    verifyEqual(testCase,app.LastMeasurement.P,pValues(index));
    verifyEqual(testCase,app.LastMeasurement.M,mValues(index));
    verifyEqual(testCase,receiver.CurrentP,pValues(index));
    verifyEqual(testCase,receiver.CurrentM,mValues(index));
    verifyEqual(testCase,receiver.LastFrameID,uint32(2147483648+index));
    verifyEqual(testCase,app.LastMeasurement.IQ,expectedIQ);
    verifySize(testCase,app.LastMeasurement.IQ,[62 1]);
    verifyEqual(testCase,app.LastMeasurement.PacketCount,1);
    verifyEqual(testCase,app.LastMeasurement.FrameIDs,uint32(2147483648+index));
    verifyEqual(testCase,app.LastMeasurement.ProtocolVersion,1);
    verifyEqual(testCase,app.LastMeasurement.MERdB,measureMER(expectedIQ,mValues(index)),'AbsTol',1e-10);
    verifyEqual(testCase,receiver.TotalBits,index*65536);
    verifyEqual(testCase,receiver.ErrorBits,index*(index+1)/2);
    verifyEqual(testCase,app.LastMeasurement.BER,(index*(index+1)/2)/(index*65536));
    assertTrue(testCase,waitUntil(@()strcmp(char(pMetric.Text),sprintf('%d',pValues(index))) && ...
        strcmp(char(mMetric.Text),mNames{mValues(index)+1}),2));
end
verifyEqual(testCase,receiver.RejectedDatagrams,0);
verifyEqual(testCase,board.NumDatagramsAvailable,0);
verifyGreaterThanOrEqual(testCase,app.LastMeasurement.ElapsedSeconds,0);
verifyLessThanOrEqual(testCase,app.LastMeasurement.ElapsedSeconds,app.ElapsedSeconds);
delete(app);
verifyFalse(testCase,isgraphics(fig));
verifyEqual(testCase,monitorTimerCounts(),timersBefore);
assertPortReleased(testCase,localPort);
clear board
end

function testMixedModesFrameLabelsRejectionsTimeoutAndLifecycle(testCase)
requireNetworkToolboxes(testCase);
timersBefore = monitorTimerCounts();
[fig,app,board,localPort] = openLoopback();
cleanup = onCleanup(@()deleteMonitor(app)); %#ok<NASGU>
receiver = app.Receiver;
receiver.StaleAfterSeconds = .5;
addressInput = findall(fig,'Tag','UDPBoardAddress');
[good,~] = wirePacket(136,[152 186 220 254],1,1);
% Address filtering is separate from the source-port rejection below.
addressInput.Value = '127.0.0.2';
app.startMonitoring();
write(board,good,'uint8','127.0.0.1',localPort);
assertTrue(testCase,waitUntil(@()receiver.RejectedDatagrams>=1,2));
verifyEqual(testCase,receiver.ReceivedDatagrams,0);
verifyTrue(testCase,app.Running);
verifyEmpty(testCase,app.LastMeasurement);
app.stopMonitoring();
assertPortReleased(testCase,localPort);
addressInput.Value = '127.0.0.1';
app.startMonitoring();
intruder = udpport('datagram','IPV4','OutputDatagramSize',1024);
write(intruder,good,'uint8','127.0.0.1',localPort);
write(board,good(1:263),'uint8','127.0.0.1',localPort);
bad = good; bad(259) = 2;
write(board,bad,'uint8','127.0.0.1',localPort);
bad = good; bad(257) = 0;
write(board,bad,'uint8','127.0.0.1',localPort);
bad = good; bad(260) = 8;
write(board,bad,'uint8','127.0.0.1',localPort);
bad = good; bad(249:252) = 0; % E>N must fail receiver interval validation.
write(board,bad,'uint8','127.0.0.1',localPort);
bad = good; bad(260) = 139;
write(board,bad,'uint8','127.0.0.1',localPort);
assertTrue(testCase,waitUntil(@()receiver.RejectedDatagrams>=7,2));
verifyEqual(testCase,receiver.RejectedDatagrams,7);
verifyEqual(testCase,receiver.ReceivedDatagrams,0);
verifyEqual(testCase,receiver.TotalBits,0);
verifyEqual(testCase,receiver.ErrorBits,0);
verifyTrue(testCase,app.Running);
clear intruder
% Two intervals may have the same source FID. A mode change flushes that pair.
[a,iqA] = wirePacket(136,[152 186 220 254],1,1);
[b,iqB] = wirePacket(136,[152 186 220 254],2,2);
[c,iqC] = wirePacket(162,[255 255 255 255],3,3);
sendPackets(board,[a b c],localPort);
assertTrue(testCase,waitUntil(@()receiver.ReceivedDatagrams>=3 && ...
    receiver.PublishedBatches>=2 && sampleHasFrame(app,uint32(4294967295)),2));
verifyEqual(testCase,receiver.ReceivedDatagrams,3);
verifyEqual(testCase,receiver.TotalBits,3*65536);
verifyEqual(testCase,receiver.ErrorBits,6);
verifyEqual(testCase,app.LastMeasurement.P,8);
verifyEqual(testCase,app.LastMeasurement.M,2);
verifyEqual(testCase,app.LastMeasurement.IQ,iqC);
verifyEqual(testCase,app.LastMeasurement.PacketCount,1);
verifyEqual(testCase,app.LastMeasurement.FrameIDs,uint32(4294967295));
verifyEqual(testCase,numel(app.MERHistory),2);
verifyEqual(testCase,app.MERHistory,[measureMER([iqA;iqB],0) measureMER(iqC,2)],'AbsTol',1e-10);
% uint32 wrap and a later numeric retreat are valid source-frame labels.
[wrapped,~] = wirePacket(162,[0 0 0 0],4,4);
[forward,~] = wirePacket(162,[100 0 0 0],5,5);
[retreated,~] = wirePacket(162,[50 0 0 0],6,6);
sendPackets(board,[wrapped forward retreated],localPort);
assertTrue(testCase,waitUntil(@()receiver.ReceivedDatagrams>=6 && sampleHasFrame(app,uint32(50)),2));
verifyEqual(testCase,receiver.ReceivedDatagrams,6);
verifyEqual(testCase,receiver.TotalBits,6*65536);
verifyEqual(testCase,receiver.ErrorBits,21);
verifyEqual(testCase,receiver.LastFrameID,uint32(50));
verifyEqual(testCase,app.LastMeasurement.BER,21/(6*65536));
verifyEqual(testCase,app.LastMeasurement.FrameIDs,uint32([0;100;50]));
verifyEqual(testCase,app.LastMeasurement.PacketCount,3);
verifyEqual(testCase,receiver.RejectedDatagrams,7);
lastIQ = app.LastMeasurement.IQ;
assertTrue(testCase,waitUntil(@()receiver.Stale,2));
verifyTrue(testCase,app.Running);
verifyEqual(testCase,app.LastMeasurement.IQ,lastIQ);
status = findall(fig,'Tag','MonitorStatus');
verifyTrue(testCase,contains(char(status.Text),'超时'));
[recovery,recoveryIQ] = wirePacket(145,[49 0 0 0],0,7);
write(board,recovery,'uint8','127.0.0.1',localPort);
assertTrue(testCase,waitUntil(@()receiver.ReceivedDatagrams>=7 && ...
    ~receiver.Stale && sampleHasFrame(app,uint32(49)),2));
verifyTrue(testCase,app.Running);
verifyEqual(testCase,receiver.CurrentP,4);
verifyEqual(testCase,receiver.CurrentM,1);
verifyEqual(testCase,app.LastMeasurement.IQ,recoveryIQ);
verifyEqual(testCase,app.LastMeasurement.BER,21/(7*65536));
verifyEqual(testCase,app.LastMeasurement.MERdB,measureMER(recoveryIQ,1),'AbsTol',1e-10);
[emptyInterval,~] = wirePacket(145,[48 0 0 0],0,8);
emptyInterval(249:252) = 0;
write(board,emptyInterval,'uint8','127.0.0.1',localPort);
assertTrue(testCase,waitUntil(@()receiver.ReceivedDatagrams>=8 && sampleHasFrame(app,uint32(48)),2));
verifyEqual(testCase,receiver.TotalBits,7*65536);
verifyEqual(testCase,receiver.ErrorBits,21);
verifyEqual(testCase,app.LastMeasurement.BER,21/(7*65536));
verifyEqual(testCase,board.NumDatagramsAvailable,0);
app.stopMonitoring();
verifyFalse(testCase,app.Running);
verifyEqual(testCase,char(addressInput.Enable),'on');
verifyEqual(testCase,monitorTimerCounts(),timersBefore+[0 1]);
assertPortReleased(testCase,localPort);
app.startMonitoring();
verifyEqual(testCase,receiver.TotalBits,0);
verifyEqual(testCase,receiver.ErrorBits,0);
verifyEqual(testCase,receiver.ReceivedDatagrams,0);
verifyEqual(testCase,receiver.RejectedDatagrams,0);
verifyEqual(testCase,receiver.PublishedBatches,0);
verifyTrue(testCase,isnan(receiver.CurrentP));
verifyTrue(testCase,isnan(receiver.CurrentM));
verifyEmpty(testCase,app.LastMeasurement);
% Zero-bit intervals have no BER denominator; zero errors later retain BER=0.
[zeroCount,~] = wirePacket(145,[10 0 0 0],0,8);
zeroCount(249:252) = 0;
write(board,zeroCount,'uint8','127.0.0.1',localPort);
assertTrue(testCase,waitUntil(@()sampleHasFrame(app,uint32(10)),2));
verifyEqual(testCase,receiver.ReceivedDatagrams,1);
verifyEqual(testCase,receiver.TotalBits,0);
verifyTrue(testCase,isnan(app.LastMeasurement.BER));
[zeroError,~] = wirePacket(145,[11 0 0 0],0,9);
write(board,zeroError,'uint8','127.0.0.1',localPort);
assertTrue(testCase,waitUntil(@()receiver.ReceivedDatagrams>=2 && sampleHasFrame(app,uint32(11)),2));
verifyEqual(testCase,receiver.TotalBits,65536);
verifyEqual(testCase,receiver.ErrorBits,0);
verifyEqual(testCase,app.LastMeasurement.BER,0);
verifyEqual(testCase,app.LastMeasurement.TotalBits,65536);
zeroBounds = findall(fig,'Tag','BERZeroBounds');
assertTrue(testCase,waitUntil(@()isscalar(zeroBounds.YData) && zeroBounds.YData==1/65536,2));
app.reset();
verifyFalse(testCase,app.Running);
verifyEmpty(testCase,app.LastMeasurement);
verifyEqual(testCase,monitorTimerCounts(),timersBefore+[0 1]);
assertPortReleased(testCase,localPort);
app.startMonitoring();
delete(app);
verifyFalse(testCase,isgraphics(fig));
verifyFalse(testCase,isvalid(receiver));
verifyEqual(testCase,monitorTimerCounts(),timersBefore);
assertPortReleased(testCase,localPort);
clear board
end

function [payload,iq] = wirePacket(modeByte,fidBytes,errorCount,seed)
% Fixed hand-written little-endian fields; no decoder/common encoder is called.
payload = zeros(264,1,'uint8');
payload(1:248) = repmat(uint8([100+seed 20 200+seed 30 150+seed 40 50+seed 10])',31,1);
payload(249:264) = uint8([0 0 1 0 errorCount 0 0 0 82 88 1 modeByte fidBytes]);
iq = repmat(complex([5220+seed;7880+seed],[10390+seed;2610+seed])/16384,31,1);
end

function value = measureMER(iq,m)
switch m
    case 0
        refs = [-1;1];
    case 1
        [i,q] = ndgrid([-1 1]/sqrt(2)); refs = complex(i(:),q(:));
    case 2
        [i,q] = ndgrid([-3 -1 1 3]/sqrt(10)); refs = complex(i(:),q(:));
end
calculator = comm.MER('ReferenceSignalSource','Estimated from reference constellation', ...
    'ReferenceConstellation',refs);
value = calculator(iq);
release(calculator);
end

function [fig,app,board,localPort] = openLoopback()
board = udpport('datagram','IPV4','Timeout',1,'OutputDatagramSize',1024);
localPort = availableUDPPort();
[fig,app] = jiemian('Visible','off');
address = findall(fig,'Tag','UDPBoardAddress');
remotePort = findall(fig,'Tag','UDPRemotePort');
local = findall(fig,'Tag','UDPLocalPort');
address.Value = '127.0.0.1';
remotePort.Value = double(board.LocalPort);
local.Value = localPort;
end

function requireNetworkToolboxes(testCase)
assertTrue(testCase,exist('udpport','file')==2,'Instrument Control Toolbox is required.');
assertTrue(testCase,exist('comm.MER','class')==8,'Communications Toolbox is required.');
end

function yes = sampleHasFrame(app,frame)
yes = ~isempty(app.LastMeasurement) && isfield(app.LastMeasurement,'FrameID') && ...
    app.LastMeasurement.FrameID==frame;
end

function sendPackets(board,payload,localPort)
if size(payload,2)>1
    % Make this fixture one queued input set: write can dispatch timer callbacks.
    % Only the test pauses acquisition; production collection remains unchanged.
    acquisition = timerfindall('Name','RxUDP264Acquisition');
    assert(numel(acquisition)==1,'RxUDPTest:Timer', ...
        'The multi-packet fixture requires exactly one acquisition timer.');
    wasRunning = strcmp(acquisition.Running,'on');
    if wasRunning, stop(acquisition); end
    resume = onCleanup(@()resumeAcquisition(acquisition,wasRunning)); %#ok<NASGU>
end
for packet = 1:size(payload,2)
    write(board,payload(:,packet),'uint8','127.0.0.1',localPort);
end
if size(payload,2)>1
    pause(.02); % Allow every datagram to reach the socket before polling resumes.
end
end

function resumeAcquisition(acquisition,wasRunning)
if wasRunning && isvalid(acquisition) && strcmp(acquisition.Running,'off')
    start(acquisition);
end
end

function ready = waitUntil(predicate,timeout)
started = tic;
ready = predicate();
while ~ready && toc(started)<timeout
    drawnow;
    pause(.01);
    ready = predicate();
end
end

function port = availableUDPPort()
probe = udpport('datagram','IPV4');
port = double(probe.LocalPort);
clear probe
end

function assertPortReleased(testCase,port)
probe = udpport('datagram','IPV4','LocalPort',port);
verifyEqual(testCase,double(probe.LocalPort),port);
clear probe
end

function counts = monitorTimerCounts()
counts = [numel(timerfindall('Name','RxUDP264Acquisition')), ...
    numel(timerfindall('Name','LinkQualityDisplay'))];
end

function deleteMonitor(app)
if ~isempty(app) && isvalid(app), delete(app); end
end
