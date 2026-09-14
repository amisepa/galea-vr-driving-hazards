%% Import raw data collected with GaleaGUI software with the Galea Beta headset
% into MATLAB and convert to EEGLAB format.
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
%   
% Example:
%   DATA = galea_import_beta(montage)
% 
% Cedric Cannard, July 2024

function EEG = galea_import()

disp("Importing EEG data into EEGLAB...")

% Import EEG/EMG/EOG
[filename, filepath] = uigetfile2({ '*.txt' }, 'Select main RAW file');
filepath = fullfile(filepath, filename);
disp("Importing raw data into Matlab...")
DATA = readtable(filepath);

% Time stamps
t = DATA{:,28};  % 26: Unix packet timestamp on local machine; 27 ADC timestamps (in s); 28:  adjusted timestamps based on device timestamp, packet time-delta and round-trip time.
t = t-t(1);  % convert to relative time (in s)

% Data length
num_samples = size(t,1);
% data_len_sec = floor(num_samples/fs);
data_len_sec = floor(t(end));
fprintf('Data length: %g min \n', round(data_len_sec/60,1))

% Estimate sample rate from time stamps
time_diffs = round(diff(t),3); % rounded to millisecond
time_diff_mod = mean(time_diffs);
fs = round(single(1 / time_diff_mod));
if fs ~= 500
    warning('Sampling rate detected: %g Hz \n',fs);
    warning("Hard-coding fs = 500 Hz")
    fs = 500;
end

% % Check sample rate stability
% num_fs = 1/unique(time_diffs); % number of sample rates, rounding at ms resolution
% num_fs(isinf(num_fs)) = [];
% num_fs(num_fs==0) = [];
% num_fs(num_fs==fs) = [];
% num_fs(num_fs*1000<10) = [];  % remove if varies by less than 1 ms
% if ~isempty(num_fs)
%     warning('Sampling rate unstable. %g/%g samples (%g%% of the data) varied by >1 ms.',length(num_fs),num_samples,round(length(num_fs)/num_samples*100,2));
%     % figure('Color','w'); histogram(num_fs); xlabel("Samples variation (in seconds)"); ylabel("# of samples")
% end

% Check if data have gaps longer than 1 second
idx = time_diffs > 1;
if any(idx)
    warning('%g gaps (> 1 s) were detected.', sum(idx))
    disp(time_diffs(idx))
end

% EEG data
% if strcmpi(montage, 'default')
eegdata = double(DATA{:,2:19})';  % all data channels
% elseif strcmpi(montage, 'custom')
%     eegdata = double(DATA{:,[4:5 8:19]})';  % including EMG channels converted to EEG
% end
% figure; plot(t,eegdata);

% convert to EEGLAB
EEG = eeg_emptyset;
EEG.setname = filename(1:end-4);
EEG.srate = fs;
EEG.times = t*1000;  % convert to ms
EEG.data = eegdata;
EEG.nbchan = size(eegdata,1);
EEG.pnts   = num_samples;
EEG.xmax = data_len_sec;
EEG.xmin = 0;
EEG = eeg_checkset(EEG);

% Channel labels
if strcmpi(montage,'default')
    chanLabels = {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'VEOG' 'HEOG' 'EMG5' 'EMG6' 'F1' 'F2' 'C3' 'C4' 'P3' 'P4' 'O1' 'O2' 'CZ' 'PZ'};
elseif strcmpi(montage,'custom')
    chanLabels = {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'VEOG' 'HEOG' 'Fp1' 'Fp2' 'F1' 'F2' 'C3' 'C4' 'P3' 'P4' 'O1' 'O2' 'CZ' 'PZ'};
end   
for iChan = 1:EEG.nbchan
    EEG.chanlocs(iChan).labels = chanLabels{iChan};
end
EEG = eeg_checkset(EEG);

% Import channel locations
locPath = fileparts(which('dipfitdefs.m'));
EEG = pop_chanedit(EEG,'lookup',fullfile(locPath,'standard_BEM','elec','standard_1005.elc'));

% % Remove channels with missing values
% idx = any(isnan(EEG.data)');
% if sum(idx)>0
%     warning("Removing %g channels with missing values!", sum(idx))
%     EEG.data(idx,:) = [];
%     EEG.nbchan = EEG.nbchan - sum(idx);
%     EEG.chanlocs(idx) = [];
%     EEG = eeg_checkset(EEG);
% end

% Event markers
EEG.event = [];
markers = DATA{:,29};
lats = t; lats(markers==0) = [];  % event latencies (using timestamps)
% lats = find(markers~=0);          % event latencies (using samples?)
markers(markers==0) = [];
nEv = length(markers);
if nEv>0
    fprintf('%g event markers detected. Importing them... \n', nEv)
    % unique(markers)
    for iEv = 1:nEv
        % if markers(iEv)==1
        %     EEG.event(iEv).type = 'baseline';
        % elseif markers(iEv)==2
        %     EEG.event(iEv).type = 'bsl_start';
        % elseif markers(iEv)==3
        %     EEG.event(iEv).type = 'bsl_deviation';
        % elseif markers(iEv)==5
        %     EEG.event(iEv).type = 'experiment';
        % elseif markers(iEv)==6
        %     EEG.event(iEv).type = 'expt_deviation';
        % elseif markers(iEv)==7
        %     EEG.event(iEv).type = 'expt_nocrash_start';
        % elseif markers(iEv)==8
        %     EEG.event(iEv).type = 'expt_crash_start';
        % end

        % Events latency in samples
        EEG.event(iEv).type = num2str(markers(iEv));
        EEG.event(iEv).latency = round(lats(iEv)*fs); 

    end
    EEG = eeg_checkset(EEG,'eventconsistency');
    EEG = eeg_checkset(EEG);
    disp("")
    disp("Event label:      Number of events:")
    summary(categorical({EEG.event.type}'));
end
% pop_eegplot(EEG,1,1,1);

