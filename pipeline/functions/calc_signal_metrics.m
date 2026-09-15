%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

% Calculate signal metrics capturing different types of signal/noise 
% characteristics. 
% 
% Cedric Cannard, 2024

function metrics = calc_signal_metrics(signal, sig_type, fs, winSize)

metrics = [];

% size of sliding windows in s
if isempty(winSize)
    winSize = 2; 
end 
winSize = winSize * fs; 

% Filter padding length (in samples; default = 3*fs)
padLength = 3*fs;

% signal size and # of segments
sig_len = length(signal);
nSeg = floor(sig_len/winSize);

% Highpass filter for accurate results (same for PPG and EEG)
% figure; plot(signal(1:fs*10));  
[b, a] = butter(3, 1/(fs/2), 'high');       % highpass 1 Hz, order 3
startPad = repmat(signal(1), padLength, 1); % Constant padding using the first value
endPad = repmat(signal(end), padLength, 1); % Constant padding using the last value
dataPadded = [startPad; signal; endPad]; % Combine the padded data
sig_filtered = filtfilt(b, a, dataPadded); % Apply the Butterworth filter to the padded data
signal = sig_filtered(padLength+1:end-padLength); % Extract the filtered signal without padding
% hold on; plot(signal(1:fs*10));  

% % Design filter for SNR feature
if strcmpi(sig_type,'eeg')
    % b = design_fir(100,[2*[0 45 50]/fs 1],[1 1 0 0]);
    [b, a] = butter(6, 40/(fs/2), 'low');
elseif  strcmpi(sig_type,'ica')
    [b, a] = butter(3, 7/(fs/2), 'low');  % 4 or 7 Hz cutoff for capturing ocular artifacts
elseif  strcmpi(sig_type,'ppg')
    [b, a] = butter(3, 3/(fs/2), 'low');
end

% figure; hold on;
for iSeg = 1:nSeg

    % Sliding window
    if iSeg == 1
        tStart = 1;
    else
        tStart = tEnd + 1;
    end
    tEnd = (tStart + winSize)-1;
    if tEnd > sig_len
        d = tEnd - sig_len;
        tEnd = sig_len;
        warning('tEnd is %g s beyond the last sample. Replacing with last sample.', round(d*fs,1))
    end
    tSeg = tStart:tEnd;  % time index in samples for this segment
    sig = signal(tSeg); % signal of current segment


    % filter signal with padding
    % figure; plot(sig);  
    startPad = repmat(sig(1), padLength, 1); % Constant padding using the first value
    endPad = repmat(sig(end), padLength, 1); % Constant padding using the last value
    dataPadded = [startPad; sig; endPad]; % Combine the padded data
    sig_filtered = filtfilt(b, a, dataPadded); % Apply the Butterworth filter to the padded data
    sig_filtered = sig_filtered(padLength+1:end-padLength); % Extract the filtered signal without padding

    % sig_filtered = filtfilt(b, a, sig); % no padding
    % hold on; plot(sig_filtered, 'linewidth',2);  

    % tmp = filtfilt(b,a,sig);   % zero-phase filtering
    % tmp = filtfilt_fast(b,1,sig));
    % hold on; plot(tmp);  

    % Portion of flat (in %) - MUST USE HIGHPASS-FILTERED DATA
    metrics.flat(iSeg) = ( sum(abs(diff(sig))<(20*eps)) / length(tSeg) ) *100;

    % Modified MAD-SNR method.
    % Robust method for assessing deviation. Focuses on outlier resistance 
    % and provides a measure of variability. Low values represent low deviation
    % from noise (i.e. bad signal).  
    metrics.SNR1(iSeg) = mad(sig - sig_filtered);  % reflecting deviation
    
    % Modified SNR in dB.
    %  power-based comparisons are usually more meaningful because EEG 
    % signals often have non-Gaussian distributions, and power is a more 
    % direct way to assess how much the noise impacts the signal.
    % and easier to compare and interpret in dB
    signal_power = var(sig);
    noise_power = var(sig - sig_filtered);
    metrics.SNR2(iSeg) = 10*log10(mean(signal_power) / mean(noise_power));  % SNR in decibels (dB)
    % if strcmpi(sig_type,'eeg')
    %     [~, ~, ~, ~, signal_power] = compute_pwr(signal(tSeg), fs, .5, [1 40], 2, 0);
    %     [~, ~, ~, ~, noise_power] = compute_pwr(signal(tSeg), fs, .5, [40 fs/2], 2, 0);
    % elseif  strcmpi(sig_type,'ppg')
    %     [~, ~, ~, ~, signal_power] = compute_pwr(signal(tSeg), fs, .5, [1 5], 2, 0);
    %     [~, ~, ~, ~, noise_power] = compute_pwr(signal(tSeg), fs, .5, [5 fs/2], 2, 0);
    % end        
    % metrics.SNR2(iSeg) = mean(signal_power) / mean(noise_power);  % SNR in decibels (dB)
    

    % % Kurtosis
    % metrics.kurt(iSeg) = kurtosis(sig_filtered);

    % RMS raw signal
    metrics.rms(iSeg) = rms(sig_filtered);

    % % Peak to RMS
    % metrics.peak2rms(iSeg) = peak2rms(sig_filtered);
    
    % % Skewness raw signal
    % metrics.skew(iSeg) = skewness(sig_filtered);

    % Sample entropy
    % metrics.entropy(iSeg) = compute_se(sig_filtered);

    % Fractal volatility dimension
    % metrics.fractal(iSeg) = fractal_volatility(sig_filtered);

end
    





%% Subfunctions

% FIR filter design from Christian's clean_artifacts code
function B = design_fir(N,F,A,nfft,W)
if nargin < 4 || isempty(nfft)
    nfft = max(512,2^ceil(log(N)/log(2))); 
end
if nargin < 5
    W = 0.54 - 0.46*cos(2*pi*(0:N)/N); 
end
F = interp1(round(F*nfft),A,(0:nfft),'pchip');
F = F .* exp(-(0.5*N)*sqrt(-1)*pi*(0:nfft)./nfft);
B = real(ifft([F conj(F(end-1:-1:2))]));
B = B(1:N+1).*W(:)';

% filtfilt_fast from Christian's clean_artifacts code
function X = filtfilt_fast(varargin)
% if nargin == 3
[B, A, X] = deal(varargin{:});
% elseif nargin == 4
%     [N, F, M, X] = deal(varargin{:});
%     B = design_fir(N,F,sqrt(M)); A = 1;
% end
if A == 1
    was_single = strcmp(class(X),'single');
    w = length(B); t = size(X,1);    
    X = double([bsxfun(@minus,2*X(1,:),X(1+mod(((w+1):-1:2)-1,t),:)); X; bsxfun(@minus,2*X(t,:),X(1+mod(((t-1):-1:(t-w))-1,t),:))]);
    X = filter_fast(B,A,X); X = X(length(X):-1:1,:);
    X = filter_fast(B,A,X); X = X(length(X):-1:1,:);
    X([1:w t+w+(1:w)],:) = [];
    if was_single
        X = single(X); end    
else    
    X = filtfilt(B,A,X);
end

% filter_fast from Christian's clean_artifacts code
function [X,Zf] = filter_fast(B,A,X,Zi,dim)
if nargin <= 4
    dim = find(size(X)~=1,1); 
end
if nargin <= 3
    Zi = []; 
end
lenx = size(X,dim);
lenb = length(B);
if lenx == 0
    Zf = Zi;
elseif lenb < 256 || lenx<1024 || lenx <= lenb || lenx*lenb < 4000000 || ~isequal(A,1)
    if nargout > 1
        [X,Zf] = filter(B,A,X,Zi,dim);
    else
        X = filter(B,A,X,Zi,dim);
    end
else
    was_single = strcmp(class(X),'single');
    if isempty(Zi)
        if nargout < 2
            X = unflip(oct_fftfilt(B,flip(double(X),dim)),dim);
        else
            X = flip(X,dim);
            [dummy,Zf] = filter(B,1,X(end-length(B)+1:end,:),Zi,1); %#ok<ASGLU>
            X = oct_fftfilt(B,double(X));
            X = unflip(X,dim);
        end
    else
        X = flip(X,dim);
        tmp = filter(B,1,X(1:length(B),:),Zi,1);
        if nargout > 1
            [dummy,Zf] = filter(B,1,X(end-length(B)+1:end,:),Zi,1); %#ok<ASGLU>
        end
        X = oct_fftfilt(B,double(X));
        X(1:length(B),:) = tmp;
        X = unflip(X,dim);
    end
    if was_single
        X = single(X); 
    end
end

function X = flip(X,dim)
if dim ~= 1
    order = 1:ndims(X);
    order = order([dim 1]);
    X = permute(X,order);
end

function X = unflip(X,dim)
if dim ~= 1
    order = 1:ndims(X);
    order = order([dim 1]);
    X = ipermute(X,order);
end


% Compute power spectral density (PSD)
function [pxx, f] = get_psd(eegData,winSize,taperM,overlap,nfft,Fs,fRange,type)
fh = str2func(taperM);
overlap = winSize/(100/overlap); % convert overlap to samples
for iChan = 1:size(eegData,1)
    [pxx(iChan,:), f] = pwelch(eegData(iChan,:),fh(winSize),overlap,nfft,Fs,type);
end
freq = dsearchn(f,fRange(1)):dsearchn(f, fRange(2)); % extract frequencies of interest
f = f(freq(2:end))';
pxx = pxx(:,freq(2:end));     
pxx = 10*log10(pxx); % normalize to deciBels (dB) 
