function report = verify_link(simulation_dir,make_plot,write_report)
% Verify the delivered receiver against the transmitter's MATLAB bit truth.
% FDE uses a separate floating-point LS / moving-mean ZF calculation.
if nargin<2,make_plot=true;end
if nargin<3,write_report=true;end
root=fileparts(fileparts(mfilename('fullpath')));
r=load(fullfile(root,'data','reference.mat'));
bit_result=jsondecode(fileread(fullfile(simulation_dir,'bit_results.json')));
assert(strcmp(bit_result.status,'PASS'),'HDL output does not match MATLAB bit truth.');
fde=read_iq(fullfile(simulation_dir,'fde.txt'),13);
% The NLMS BPSK reference/decision unit is 16384, i.e. F14.
nlms=read_iq(fullfile(simulation_dir,'nlms.txt'),14);
window=read_iq(fullfile(simulation_dir,'window.txt'),13);
frames=numel(r.frame_symbols);p=r.meta.parallelism;
fde_mer=nan(frames,1);nlms_mer=nan(frames,1);fde_vs_matlab=nan(frames,1);
window_length=5;
for n=1:frames
    tx=reshape(r.frame_symbols{n},p,[]);
    indices=r.pilot_clks(:)+(1:255);
    expected=reshape(tx(:,reshape(indices.',1,[])),[],1);
    a=fde.samples(fde.frame==n-1,1:p).';a=a(:);
    b=nlms.samples(nlms.frame==n-1,1:p).';b=b(:);
    assert(numel(a)==numel(expected) && numel(b)==numel(expected),'Missing output in frame %d.',n-1);
    fde_mer(n)=10*log10(sum(abs(2*expected).^2)/sum(abs(a-2*expected).^2));
    nlms_mer(n)=10*log10(sum(abs(expected).^2)/sum(abs(b-expected).^2));
    rows=window.samples(window.frame==n-1,:).';
    assert(numel(rows)==2048*8,'Incomplete FFT input in frame %d.',n-1);
    received=reshape(rows,2048,8);
    nominal=zeros(8,256);
    train_start=32+16/p+9;
    nominal(1:8/p:8,:)=tx(:,train_start+(1:256));
    spectrum=fft(nominal(:));freq=fft(received);
    phase=exp(1j*2*pi*5*(0:2047)'/256);
    h=(freq(:,1)+freq(:,2))./(2*spectrum).*phase;
    h=reshape(h,256*p,[]);
    h=movmean(h,window_length,1,'Endpoints','shrink');
    g=phase./h(:);
    % FFT is DFT/32, IFFT is 64*ifft: the fixed FDE gain is 2.
    equalized=2*ifft(freq(:,3:8).*g);
    ideal=complex(zeros(p*255,6));
    for block=1:6
        time=reshape(equalized(:,block),8,256);
        data=time(1:8/p:8,2:256);ideal(:,block)=data(:);
    end
    ideal=ideal(:);
    fde_vs_matlab(n)=10*log10(sum(abs(ideal).^2)/sum(abs(a-ideal).^2));
end
summary=table((0:frames-1)',fde_mer,nlms_mer,fde_vs_matlab, ...
    'VariableNames',{'Frame','FDE_MER_dB','NLMS_MER_dB','HDL_vs_floatFDE_dB'});
disp(summary);
fprintf('Coded BER: %d / %d = %.9g\n',bit_result.coded.bit_errors,bit_result.coded.bits,bit_result.coded.ber);
fprintf('Decoded BER: %d / %d = %.9g\n',bit_result.decoded.bit_errors,bit_result.decoded.bits,bit_result.decoded.ber);
report=struct('scope','16 P2/BPSK frames; fixed sampling phase; Mov_ZF window 5', ...
    'fde_fixed_gain',2, ...
    'iq_fraction_bits',struct('window',13,'fde',13,'nlms',14), ...
    'coded',bit_result.coded,'decoded',bit_result.decoded,'frames',frames, ...
    'fde_mer_db',fde_mer,'nlms_mer_db',nlms_mer,'hdl_vs_float_fde_db',fde_vs_matlab, ...
    'mean_fde_mer_db',mean(fde_mer),'mean_nlms_mer_db',mean(nlms_mer), ...
    'minimum_hdl_vs_float_fde_db',min(fde_vs_matlab));
if write_report
    f=fopen(fullfile(simulation_dir,'matlab_verification.json'),'w');assert(f>=0);cleaner=onCleanup(@()fclose(f));
    fprintf(f,'%s\n',jsonencode(report,PrettyPrint=true));
end
if make_plot
    figure('Name','Public receiver verification','Color','w');
    tiledlayout(2,1);
    nexttile;plot(summary.Frame,[fde_mer,nlms_mer],'-o');grid on;
    xlabel('Frame');ylabel('MER (dB)');legend('FDE','NLMS','Location','best');
    nexttile;plot(summary.Frame,fde_vs_matlab,'-o');grid on;
    xlabel('Frame');ylabel('HDL / floating-point FDE error ratio (dB)');
end
end
