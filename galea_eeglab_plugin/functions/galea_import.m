%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Import raw data collected with GaleaGUI software with the Galea Beta headset
% into MATLAB and convert to EEGLAB format.
%    
% Example:
%   DATA = galea_import()
% 
% Cedric Cannard, July 2024

function [EEG, EOG, EMG, PPG, EDA, IMU, AUX] = galea_import(montage, filename, filepath)
% Optional FILENAME and FILEPATH skip the file-selection dialog, so the import
% can be scripted and tested non-interactively. Omit them for the dialog.
%
% Every marker in the trigger channel is imported, with its raw numeric code as
% the event type. What each code means is specific to the experiment that
% recorded it, so nothing is renamed here - select the ones you want afterwards
% with the usual EEGLAB tools (Edit > Select epochs/events, pop_epoch, etc).

if ~exist('montage', 'var') || isempty(montage)
    montage = 'default';
end

if nargin >= 3 && ~isempty(filename) && ~isempty(filepath)
    if ~isfile(fullfile(filepath, filename))
        error('galea_import:noFile', 'No such file: %s', fullfile(filepath, filename));
    end
else
    % Select file
    data_path = dir;
    data_path = data_path(1).folder;
    [filename, filepath] = uigetfile2({ '*.txt' }, 'Select main RAW file', data_path);
    if isequal(filename, 0), error('galea_import:cancelled', 'No file selected.'); end
end
% if ~contains(filename, 'Aux')
%     disp("Importing EEG/EOG/EMG data into EEGLAB...")
%     mode = 1;
% else
%     disp("Importing EDA/PPG/IMU into EEGLAB...")
%     mode = 2;
% end

% Load data
warning off
DATA = readtable(fullfile(filepath, filename));
warning on

% Time stamps
% if mode == 1
    % time_col = 27; % 26: Unix packet timestamp on local machine; 27 Galea device timestamps (in s); 28 ADC timestamps; 30: reformatted timestamps into datetime format based on device timestamp, packet time-delta and round-trip time.
% else
    % time_col = 16; % 16: Unix packet timestamp on local machine; 17 Galea device timestamps (in s); 18 ADC timestamps; 20: reformatted timestamps into datetime format based on device timestamp, packet time-delta and round-trip time.
% end   
% t = DATA{:,time_col};  
t = DATA.RawDeviceTimestamp;  

% Convert datetime to POSIX time (absolute seconds since 1970)
% t = posixtime(t);  % Keep full timestamp in seconds

% Remove time base for relative time
t = t - t(1);  

% Remove duplicate from pocket
t_diff = diff(t);
if sum(t_diff==0)>1 
    fprintf('Removing %g (%g%% of data) duplicate samples from timestamp pockets.\n', sum(t_diff==0), round((sum(t_diff==0) / length(t_diff))*100,2) );
    t(t_diff==0) = [];
    DATA(t_diff==0,:) = [];
    t_diff(t_diff==0,:) = [];
end

% Estimate sample rate from time stamps.
%
% Two things bite here. First, use the total recording SPAN, not the median
% inter-sample interval: the board delivers samples in bursts over USB, which
% skews the distribution of t_diff and biases the median low.
%
% Second, the file carries two clocks and they disagree by about 0.9%%. On
% sub-005, 266,340 samples with zero dropped packets (SampleIndex wraps 0-255
% in steps of 1 throughout), RawPCTimestamp gives 249.95 Hz and
% RawDeviceTimestamp gives 247.72 Hz. That gap is far too large for crystal
% drift, so one of the two is not a real-time clock. Neither is trustworthy
% enough to be the sole estimator: the PC clock lands on the nominal 250 Hz for
% the EEG stream but on 50.77 Hz for the 50 Hz Aux stream, and the device clock
% does the reverse.
%
% So estimate from both, then snap to the board's nominal rate when one is
% within tolerance, and fall back to the measured value with a warning when
% neither is. The rates are known constants for this hardware; the timestamps
% are noisy measurements of them.
NOMINAL_RATES = [250 125 50 25];   % Galea / OpenBCI ExG board
TOL = 0.03;                        % 3%%, comfortably wider than the clock gap

fs_span = (length(t) - 1) / (t(end) - t(1));
if any(strcmp(DATA.Properties.VariableNames, 'RawPCTimestamp'))
    tpc = DATA.RawPCTimestamp;
    fs_pc = (length(tpc) - 1) / (tpc(end) - tpc(1));
else
    fs_pc = NaN;
end

cand = [fs_span fs_pc];
cand = cand(isfinite(cand) & cand > 0);
[relErr, which_nom] = min(min(abs(NOMINAL_RATES(:) - cand(:).') ./ NOMINAL_RATES(:), [], 2));
if relErr <= TOL
    fs = NOMINAL_RATES(which_nom);
else
    fs = round(fs_span);
    warning('galea_import:rate', ...
        ['Measured rate %.2f Hz is not within %g%%% of any nominal rate (%s). ' ...
         'Using the measured value.'], fs_span, 100*TOL, mat2str(NOMINAL_RATES));
end

if isfinite(fs_pc)
    fprintf('Sampling rate: %g Hz (device clock %.2f Hz, PC clock %.2f Hz)\n', fs, fs_span, fs_pc);
else
    fprintf('Sampling rate: %g Hz (device clock %.2f Hz)\n', fs, fs_span);
end
fprintf('Data length: %g min \n', round( t(end)/60));

% Check sample rate stability
num_samples = length(t);
num_fs = 1/unique(t_diff); % number of sample rates, rounding at ms resolution
num_fs(isinf(num_fs)) = [];
num_fs(num_fs==0) = [];
num_fs(num_fs==fs) = [];
num_fs(num_fs*1000<10) = [];  % remove if varies by less than 1 ms
% Only worth reporting if it affects a real share of the recording. A handful of
% samples out of hundreds of thousands is normal USB jitter, not instability.
if ~isempty(num_fs) && round(length(num_fs)/num_samples*100,2) > 1
    warning('Sampling rate unstable. %g/%g samples (%g%% of the data) varied by >1 ms.',length(num_fs),num_samples,round(length(num_fs)/num_samples*100,2));
    % figure('Color','w'); histogram(num_fs); xlabel("Samples variation (in seconds)"); ylabel("# of samples")
end

% Check if data have gaps longer than 1 second
idx = t_diff > 1;
if any(idx)
    warning('%g gaps (> 1 s) were detected.', sum(idx))
    disp(t_diff(idx))
end

% if mode == 1 
    data = double(DATA{:,2:19})';  % all data channels
% elseif mode == 2
    % data = double(DATA{:,2:15})';  % all data channels
% end    

% elseif strcmpi(montage, 'custom')
%     eegdata = double(DATA{:,[7:19]})';  % including EMG channels converted to EEG
% end
% figure; plot(t,eegdata);

% % If montage is "custom", flip Fp1 and Fp2 polarity to match other
% channel  (NOT CONSISTENT ACROSS FILES)
% if strcmpi(montage, 'custom')
%     warning("Flipping polarity of Fp1/Fp2 channels to match other EEG channels's polarity! Please double-check signals.")
%     data(7:8,:) = -data(7:8,:);
% end

% convert to EEGLAB
EEG = eeg_emptyset;
EEG.filepath = filepath;
EEG.filename = filename;
EEG.setname = filename(1:end-4);
EEG.srate = fs;
EEG.times = t*1000;  % convert to ms
EEG.data = data;
EEG.nbchan = size(data,1);
EEG.pnts   = size(data,2);
EEG.xmax = t(end);
EEG.xmin = 0;
EEG = eeg_checkset(EEG);

% Channel labels
% if mode == 1 
    if strcmpi(montage,'default')
        chanLabels = {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'VEOG' 'HEOG' 'EMG5' 'EMG6' 'F1' 'F2' 'C3' 'C4' 'P3' 'P4' 'O1' 'O2' 'CZ' 'PZ'};
    elseif strcmpi(montage,'custom')  % 2 EMG channels converted to EEG
        chanLabels = {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'VEOG' 'HEOG' 'Fp1' 'Fp2' 'F1' 'F2' 'C3' 'C4' 'P3' 'P4' 'O1' 'O2' 'CZ' 'PZ'};
    else
        warning("Unknown montage. Using default montage.")
        chanLabels = {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'VEOG' 'HEOG' 'EMG5' 'EMG6' 'F1' 'F2' 'C3' 'C4' 'P3' 'P4' 'O1' 'O2' 'CZ' 'PZ'};
    end

% elseif mode == 2
    % chanLabels = {'EDA' 'PPG_red' 'PPG_IR' 'Board_temp' 'Battery' 'ACC1' 'ACC2' 'ACC3' 'GYR_X' 'GYR_Y' 'GYR_Z' 'MEG1' 'MEG2' 'MEG3'};
% end
for iChan = 1:EEG.nbchan
    EEG.chanlocs(iChan).labels = chanLabels{iChan};
end

% EEG channel locations
% if mode == 1
    EEG = eeg_checkset(EEG);
    locPath = fileparts(which('dipfitdefs.m'));
    EEG = pop_chanedit(EEG,'lookup',fullfile(locPath,'standard_BEM','elec','standard_1005.elc'));
% end

% % Event markers
% EEG.event = [];
% filelist = dir(filepath);
% filenames = {filelist.name};
% if any(contains(filenames, 'MarkerTimestamps'))
%     disp('Importing Unity .CSV file with markers...')
% 
%     % Pull events from csv file generated by Unity on VR PC
%     tbl = readtable(fullfile(filepath, filenames{contains(filenames, 'MarkerTimestamps')}) );
%     marker_labels = tbl{:,1};
%     marker_types = tbl{:,2};
%     marker_lats = tbl{:,3};
%     marker_lats = marker_lats - marker_lats(1); % align to start at time 0
%     marker_lats = round(marker_lats .* 1000); % in milliseconds
% 
%     % Find matching timestamps in Galea data
%     pc_timestamps = round(DATA{:,time_col} .* 1000);  % in milliseconds
%     [unique_timestamps, first_occurrence_idx] = unique(pc_timestamps, 'stable');  % 'first' or 'stable'
%     matching_idx = interp1(unique_timestamps, first_occurrence_idx, marker_lats, 'nearest', 'extrap');
%     % marker_timestamps = DATA{matching_idx,time_col};  % get the corresponding timestamps to match with EEG
%     % % marker_timestamps = posixtime(marker_timestamps);  
%     % % marker_timestamps = marker_timestamps - posixtime(DATA{1,time_col});  % relative time
%     % marker_timestamps = marker_timestamps - DATA{1,time_col};  % relative time
%     % marker_timestamps = round(marker_timestamps * fs); % back to samples
% 
%     nEv = length(marker_labels);
%     if nEv>0
%         fprintf('Importing %g event markers... \n', nEv)
%         % unique(markers)
%         for iEv = 1:nEv
% 
%             % EEG.event(iEv).type = num2str(markers(iEv));    % event names in character strings
%             % EEG.event(iEv).latency = round(lats(iEv)*fs);   % Events latency in samples
%             EEG.event(iEv).type = num2str(marker_types(iEv));    % event names in character strings
%             % EEG.event(iEv).latency = marker_timestamps(iEv);      % Events latency in samples
%             EEG.event(iEv).latency = matching_idx(iEv);      % Events latency in samples
% 
%         end
%         EEG = eeg_checkset(EEG,'eventconsistency');
%         EEG = eeg_checkset(EEG);
%         disp("")
%         disp("Event label:      Number of events:")
%         summary(categorical({EEG.event.type}'));
%     else
%         EEG.trials = 1;
%     end
% 
% end

%% ---- Event markers ----
% Robust to the different RAW-file variants the Galea / OpenBCI GUI writes:
% (a) a numeric marker/trigger column in the main file (any name containing
%     Marker/Trigger/Event, or the literal 'Analog' columns some builds use);
%     also accepts a string column whose values look like event labels;
% (b) a sidecar MarkerTimestamps CSV written by the VR PC (Unity).
% The old code required one numeric column whose header contained 'Marker'
% and silently imported ZERO events when the header differed (the 'no events'
% bug). Detection is logged either way, so a failed detection is visible.
markers = [];
markerColName = '';
nEv = 0;   % set in each import branch below; 0 = marker-less recording
vn = DATA.Properties.VariableNames;
% Scan from the LAST column backwards: marker/trigger columns sit at the end
% of the Galea RAW layout, and scanning backwards guarantees a real marker
% column beats any pathological mostly-zero data channel.
for iCol = numel(vn):-1:1
    col = DATA{:,iCol};
    if ~isnumeric(col), continue; end
    % A marker column is mostly zeros with a few nonzero codes.
    nz = col ~= 0;
    if any(nz) && mean(nz) < 0.05 && all(isfinite(col))
        markers = col;
        markerColName = vn{iCol};
        break;
    end
end

% Unity/VR PC sidecar CSV takes precedence when present (real clock times).
filelist = dir(filepath);
filenames = {filelist.name};
sidecar = filenames(contains(filenames, 'MarkerTimestamps', 'IgnoreCase', true));
useSidecar = false;
if ~isempty(sidecar)
    tbl = readtable(fullfile(filepath, sidecar{1}));
    % expect label, code, latency columns; tolerate a header or not
    if size(tbl, 2) >= 3 && all(isnumeric(tbl{:,3}))
        marker_types  = tbl{:,2};
        marker_lats   = tbl{:,3};
        useSidecar = true;
    end
end

if useSidecar
    disp('Importing Unity .CSV file with markers...')
    marker_lats = marker_lats - marker_lats(1);           % align to start at 0
    marker_lats = round(marker_lats .* 1000);             % in milliseconds
    pcTsCols = DATA{:, contains(vn, 'RawPCTimestamp', 'IgnoreCase', true)};
    pc_timestamps = round(pcTsCols(:, 1) .* 1000);
    [unique_timestamps, first_idx] = unique(pc_timestamps, 'stable');
    matching_idx = interp1(unique_timestamps, first_idx, marker_lats, 'nearest', 'extrap');
    nEv = numel(matching_idx);
    if nEv > 0
        fprintf('Importing %g event markers from %s...\n', nEv, sidecar{1})
        for iEv = 1:nEv
            EEG.event(iEv).type    = num2str(marker_types(iEv));
            EEG.event(iEv).latency = matching_idx(iEv);
        end
        EEG = eeg_checkset(EEG, 'eventconsistency');
    end
elseif ~isempty(markers)
    marker_sample_idx = find(markers ~= 0);
    nEv = numel(marker_sample_idx);
    fprintf('%g event markers detected (column "%s"). Importing them...\n', nEv, markerColName)
    for iEv = 1:nEv
        EEG.event(iEv).type = num2str(markers(marker_sample_idx(iEv)));
        EEG.event(iEv).latency = marker_sample_idx(iEv);
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
else
    % Last resort: nothing numeric found, but the header names a marker-ish
    % column that is empty or string-typed. Report loudly instead of failing
    % silently - the user sees WHY there are no events.
    cand = vn(contains(vn, {'Marker','Trigger','Event'}, 'IgnoreCase', true));
    if isempty(cand)
        fprintf(['No event-marker column found in %s. If this recording should ' ...
                 'have events, check the RAW file header.'], filename);
    else
        fprintf(['Marker-like column(s) %s present but empty/non-numeric; ' ...
                 'no events imported.'], strjoin(cand, ', '));
    end
    fprintf('\n');
    EEG.trials = 1;
end
if isempty(EEG.event)
    EEG.trials = 1;
end
EEG = eeg_checkset(EEG);
disp('')
disp('Event label:      Number of events:')
if isempty(EEG.event)
    fprintf('%g events (no markers in this recording)\n', 0);
else
    summary(categorical({EEG.event.type}'));
end

% Final check
% pop_eegplot(EEG,1,1,1);
EEG = eeg_checkset(EEG);

% EOG
EOG = pop_select(EEG, 'channel', {'VEOG' 'HEOG'});

% EMG
if strcmpi(montage, 'custom')
    EMG = pop_select(EEG, 'channel', {'EMG1' 'EMG2' 'EMG3' 'EMG4'});
else
    EMG = pop_select(EEG, 'channel', {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'EMG5' 'EMG6'});
end

% Remove them from EEG
if strcmpi(montage,'custom')
    EEG = pop_select(EEG, 'nochannel', {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'VEOG' 'HEOG'});
else
    EEG = pop_select(EEG, 'nochannel', {'EMG1' 'EMG2' 'EMG3' 'EMG4' 'VEOG' 'HEOG' 'EMG5' 'EMG6'});
end

%% AUX DATA


auxFile = galea_aux_filename(filename, filepath);
disp(['Aux file: ' auxFile]);

% Load data
try
    disp("Importing AUX file...")
    warning off
    DATA = readtable(fullfile(filepath, auxFile));
    warning on
catch
    error("Failed to import the corresponding Aux file. Check filename: %s", auxFile)
end


% Time stamps
t = DATA.RawDeviceTimestamp;  

% Remove time base for relative time
t = t - t(1);  

% Remove duplicate from pocket
t_diff = diff(t);
if sum(t_diff==0)>1 
    fprintf('warning %g (%g%% of data) duplicate samples from timestamp pockets.\n', sum(t_diff==0), round((sum(t_diff==0) / length(t_diff))*100,2) );
    t(t_diff==0) = [];
    DATA(t_diff==0,:) = [];
    t_diff(t_diff==0,:) = [];
end

% Estimate sample rate from time stamps.
%
% Two things bite here. First, use the total recording SPAN, not the median
% inter-sample interval: the board delivers samples in bursts over USB, which
% skews the distribution of t_diff and biases the median low.
%
% Second, the file carries two clocks and they disagree by about 0.9%%. On
% sub-005, 266,340 samples with zero dropped packets (SampleIndex wraps 0-255
% in steps of 1 throughout), RawPCTimestamp gives 249.95 Hz and
% RawDeviceTimestamp gives 247.72 Hz. That gap is far too large for crystal
% drift, so one of the two is not a real-time clock. Neither is trustworthy
% enough to be the sole estimator: the PC clock lands on the nominal 250 Hz for
% the EEG stream but on 50.77 Hz for the 50 Hz Aux stream, and the device clock
% does the reverse.
%
% So estimate from both, then snap to the board's nominal rate when one is
% within tolerance, and fall back to the measured value with a warning when
% neither is. The rates are known constants for this hardware; the timestamps
% are noisy measurements of them.
NOMINAL_RATES = [250 125 50 25];   % Galea / OpenBCI ExG board
TOL = 0.03;                        % 3%%, comfortably wider than the clock gap

fs_span = (length(t) - 1) / (t(end) - t(1));
if any(strcmp(DATA.Properties.VariableNames, 'RawPCTimestamp'))
    tpc = DATA.RawPCTimestamp;
    fs_pc = (length(tpc) - 1) / (tpc(end) - tpc(1));
else
    fs_pc = NaN;
end

cand = [fs_span fs_pc];
cand = cand(isfinite(cand) & cand > 0);
[relErr, which_nom] = min(min(abs(NOMINAL_RATES(:) - cand(:).') ./ NOMINAL_RATES(:), [], 2));
if relErr <= TOL
    fs = NOMINAL_RATES(which_nom);
else
    fs = round(fs_span);
    warning('galea_import:rate', ...
        ['Measured rate %.2f Hz is not within %g%%% of any nominal rate (%s). ' ...
         'Using the measured value.'], fs_span, 100*TOL, mat2str(NOMINAL_RATES));
end

if isfinite(fs_pc)
    fprintf('Sampling rate: %g Hz (device clock %.2f Hz, PC clock %.2f Hz)\n', fs, fs_span, fs_pc);
else
    fprintf('Sampling rate: %g Hz (device clock %.2f Hz)\n', fs, fs_span);
end
fprintf('Data length: %g min \n', round( t(end)/60));

% Check sample rate stability
num_samples = length(t);
num_fs = 1/unique(t_diff); % number of sample rates, rounding at ms resolution
num_fs(isinf(num_fs)) = [];
num_fs(num_fs==0) = [];
num_fs(num_fs==fs) = [];
num_fs(num_fs*1000<10) = [];  % remove if varies by less than 1 ms
if ~isempty(num_fs) && round(length(num_fs)/num_samples*100,2)>1
    warning('Sampling rate unstable. %g/%g samples (%g%% of the data) varied by >1 ms.', length(num_fs), num_samples, round(length(num_fs)/num_samples*100,2));
    % figure('Color','w'); histogram(num_fs); xlabel("Samples variation (in seconds)"); ylabel("# of samples")
end

% Check if data have gaps longer than 1 second
idx = t_diff > 1;
if any(idx)
    warning('%g gaps (> 1 s) were detected.', sum(idx))
    disp(t_diff(idx))
end

data = double(DATA{:,2:15})';  % AUX data channels

% convert to EEGLAB
TMP = eeg_emptyset;
TMP.filepath = filepath;
TMP.filename = filename;
TMP.setname = filename(1:end-4);
TMP.srate = fs;
TMP.times = t*1000;  % convert to ms
TMP.data = data;
TMP.nbchan = size(data,1);
TMP.pnts   = size(data,2);
TMP.xmax = t(end);
TMP.xmin = 0;
TMP.trials = 1;
TMP = eeg_checkset(TMP);

% Channel labels
chanLabels = {'EDA' 'PPG_red' 'PPG_IR' 'Board_temp' 'Battery' 'ACC_X' 'ACC_Y' 'ACC_Z' 'GYR_X' 'GYR_Y' 'GYR_Z' 'MEG_X' 'MEG_Y' 'MEG_Z'};
for iChan = 1:TMP.nbchan
    TMP.chanlocs(iChan).labels = chanLabels{iChan};
end

% Load the event markers from EEG file
if nEv>0
    disp('Resampling to import the correct event latencies into AUX data')
    TMP = pop_resample(TMP, EEG.srate);
    TMP.event = EEG.event;
    TMP = eeg_checkset(TMP, 'eventconsistency');
    TMP = eeg_checkset(TMP);
    TMP = pop_resample(TMP, fs);
else
    TMP.trials = 1;
end

% Final check
% pop_eegplot(TMP,1,1,1);
TMP = eeg_checkset(TMP);


% PPG
PPG = pop_select(TMP, 'channel', {'PPG_red' 'PPG_IR'});

% EDA
EDA = pop_select(TMP, 'channel', {'EDA'});

% IMU
IMU = pop_select(TMP, 'channel', {'ACC_X' 'ACC_Y' 'ACC_Z' 'GYR_X' 'GYR_Y' 'GYR_Z' 'MEG_X' 'MEG_Y' 'MEG_Z'});

% Aux
AUX = pop_select(TMP, 'channel', {'Battery' 'Board_temp'});


