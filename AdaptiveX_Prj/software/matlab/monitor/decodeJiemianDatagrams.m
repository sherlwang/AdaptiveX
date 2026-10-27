function [iq, bitCounts, errorCounts, metadata] = decodeJiemianDatagrams(payload)
% DECODEJIEMIANDATAGRAMS Decode the current Rx MAC1 RX264 protocol.
% Each uint8 column is one complete 264-byte UDP datagram (no network header).
% IQ follows the source order: I0+jQ0, I1+jQ1 for each of 31 wire records.
% Counts are disjoint observation intervals, not counts of this source frame.
    validateattributes(payload,{'uint8'},{'2d'},mfilename,'payload');
    if isempty(payload) || size(payload,1) ~= 264
        error('RxUDP:PacketLength','Rx UDP payload must contain exactly 264 bytes per datagram.');
    end
    if any(payload(257,:)~=82 | payload(258,:)~=88)
        error('RxUDP:Magic','Rx UDP metadata must start with the bytes 52 58 (RX).');
    end
    if any(payload(259,:)~=1)
        error('RxUDP:Version','Only Rx UDP protocol version 1 is supported.');
    end
    mode = payload(260,:);
    p = double(bitand(bitshift(mode,-2),uint8(15)));
    m = double(bitand(mode,uint8(3)));
    if any(bitand(mode,uint8(128))==0 | bitand(mode,uint8(64))~=0 ...
            | ~ismember(p,[2 4 8]) | m>2)
        error('RxUDP:InvalidMode','Invalid Rx valid/reserved/P/M metadata.');
    end

    words = reshape(double(payload(1:248,:)),8,[]);
    i = [words(1,:)+256*words(2,:);words(3,:)+256*words(4,:)];
    q = [words(5,:)+256*words(6,:);words(7,:)+256*words(8,:)];
    i(i>=32768) = i(i>=32768)-65536;
    q(q>=32768) = q(q>=32768)-65536;
    iq = reshape(complex(i,q),[],1)/16384;
    weights = [1 256 65536 16777216];
    bitCounts = (weights*double(payload(249:252,:))).';
    errorCounts = (weights*double(payload(253:256,:))).';
    frameID = uint32((weights*double(payload(261:264,:))).');
    metadata = struct('P',p(:),'M',m(:),'FrameID',frameID, ...
        'Version',reshape(payload(259,:),[],1));
end
