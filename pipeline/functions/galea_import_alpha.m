%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Load Galea data into MATLAB and convert to EEGLAB.
% 
% Channel   Type    Label
% 1         EMG     Left Cheek
% 2         EMG     Right Cheek
% 3         EMG     Left Eyebrow
% 4         EMG     Right Eyebrow
% 5         EOG     VEOG
% 6         EOG     HEOG
% 7         EMG     Left forehead (can be converted to EEG Fp1)
% 8         EMG     Right forehead (can be converted to EEG Fp2)
% 9         EEG     F1
% 10        EEG     F2
% 11        EEG     C3
% 12        EEG     C4
% 13        EEG     P3
% 14        EEG     P4
% 15        EEG     O1
% 16        EEG     O2
% 17        EEG     Cz
% 18        EEG     Pz
% 19        PPG     Red
% 20        PPG     IR
% 21        EDA 
% 22        Temperature 
% N/A development use
% N/A development use
% 23        Battery 
% 24        Timestamps
% 25        Markers
% 
% Alpha model (prototype): timestamps - columns 19 & 20
%   
% Example:
%   EEG = galea_import_alpha(filepath)
% 
% Cedric Cannard, July 2024

function EEG = galea_import_alpha(filepath)


% Load .csv data
data = readmatrix(filepath);
data(1,:) = [];  % remove 1st row (Alpha model)

% Channel labels
chanLabels = {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'VEOG' 'HEOG' 'EMG5' 'EMG6' 'F1' 'F2' 'C3' 'C4' 'P3' 'P4' 'O1' 'O2' 'CZ' 'PZ' 'PPG1' 'PPG2' 'EDA' 'temp'};
num_channels = length(chanLabels);

% Timestamps and sample rate (fs)
t = data(:,19);  % alpha model
if t(1)~=0, t = t-t(1); end
time_diffs = diff(t);
time_diff_mod = mode(time_diffs);
fs = single(1 / time_diff_mod);
fprintf('Sampling Rate detected: %g Hz \n',fs);

% Data length
num_samples = size(data,1);
data_len_sec = round(t(end),1);

% Check if data have gaps longer than 1 second
idx = time_diffs > 1;
if any(idx)
    warning('%g gaps (> 1 s) were detected.', sum(idx))
    disp(time_diffs(idx))
end

% Check sample rate stability
num_fs = round(single(1./unique(time_diffs)),1);
num_fs(isinf(num_fs)) = [];
num_fs(num_fs==fs) = [];
if ~isempty(num_fs)
    warning('Sampling rate unstable in %g/%g samples (%g%% of the data).',length(num_fs),num_samples,round(length(num_fs)/num_samples*100,2));
end

% EEG data
eegdata = double(data(:,2:num_channels+1))';
% figure; plot(eegdata);

% conver to EEGLAB
EEG = eeg_emptyset;
EEG.setname = extractBefore(filepath,'.');
EEG.srate = fs; 
EEG.times = t*1000;  % convert to ms
EEG.data = eegdata;
EEG.nbchan = num_channels;
EEG.pnts   = num_samples;
EEG.xmin = t(1);
EEG.xmax = data_len_sec;
EEG = eeg_checkset(EEG);

% Channel labels
for iChan = 1:EEG.nbchan
    EEG.chanlocs(iChan).labels = chanLabels{iChan}; 
end
EEG = eeg_checkset(EEG);

% Import channel locations
locPath = fileparts(which('dipfitdefs.m'));
EEG = pop_chanedit(EEG,'lookup',fullfile(locPath,'standard_BEM','elec','standard_1005.elc'));

