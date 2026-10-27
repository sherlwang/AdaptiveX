function x = read_iq(file,fraction_bits)
% Read frame, P, packed I and packed Q. Lane 0 is the earliest sample.
% FFT window/FDE use F13; normalized NLMS uses F14 (unit = 16384).
if nargin<2,fraction_bits=13;end
assert(isscalar(fraction_bits) && fraction_bits>=0 && fraction_bits<=15 && fix(fraction_bits)==fraction_bits);
f=fopen(file,'r');assert(f>=0,'Cannot open %s',file);cleaner=onCleanup(@()fclose(f));
c=textscan(f,'%u %u %s %s');
x.frame=double(c{1});x.p=double(c{2});x.samples=complex(zeros(numel(x.frame),8));
i=char(c{3});q=char(c{4});
for lane=1:8
    cols=33-4*lane:36-4*lane;
    a=hex2dec(i(:,cols));b=hex2dec(q(:,cols));
    a(a>=32768)=a(a>=32768)-65536;b(b>=32768)=b(b>=32768)-65536;
    x.samples(:,lane)=complex(a,b)/2^fraction_bits;
end
end
