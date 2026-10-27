function make_adc_input(output_file,snr_db,cfo_hz,delay_samples,seed)
% Make another real-IF stimulus from the supplied numerical Tx frame symbols.
% This does not rebuild the hidden encoder. Decoded bit truth stays unchanged.
if nargin<2,snr_db=25;end
if nargin<3,cfo_hz=20000;end
if nargin<4,delay_samples=7;end
if nargin<5,seed=7311;end
assert(delay_samples>=0 && fix(delay_samples)==delay_samples);
root=fileparts(fileparts(mfilename('fullpath')));
r=load(fullfile(root,'data','reference.mat'));rng(seed,'twister');
l=24/r.meta.parallelism;
filter=comm.RaisedCosineTransmitFilter('Shape','Square root', ...
    'RolloffFactor',0.15,'FilterSpanInSymbols',16, ...
    'OutputSamplesPerSymbol',l,'Gain',sqrt(l));
wave=filter([vertcat(r.frame_symbols{:});zeros(40,1)]);
t=(0:numel(wave)-1)'/4.9152e9;
adc=real(wave.*exp(1j*(2*pi*(1.2e9+cfo_hz)*t+0.15)));
adc=adc+sqrt(mean(adc.^2)*10^(-snr_db/10))*randn(size(adc));
adc=[zeros(delay_samples,1);adc];adc(end+1:end+mod(-numel(adc),24))=0;
q=round(adc*8192);assert(all(q>=-32768 & q<=32767),'ADC clipping');
words=reshape(mod(q,65536),12,[]);f=fopen(output_file,'w');assert(f>=0);cleaner=onCleanup(@()fclose(f));
for k=1:size(words,2),fprintf(f,'%04x',flipud(words(:,k)));fprintf(f,'\n');end
fprintf('Created %d 12-lane ADC words. Seed=%d, SNR=%g dB, CFO=%g Hz, delay=%d samples.\n',size(words,2),seed,snr_db,cfo_hz,delay_samples);
end
