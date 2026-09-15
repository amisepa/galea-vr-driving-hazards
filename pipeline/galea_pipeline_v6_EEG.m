%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

clear; close all; clc
eeglab; close
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
codepath = paths.root;
datapath = paths.data;
addpath(fullfile(codepath,'pipeline','functions'))
cd(datapath)

%%%%%%%%%%%%%%%%%%%%%%%%%%%% PARAMETERS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
montage = 'custom';      % 'default' (10 default EEG channels) or 'custom' (EMG channels 7-8 converted to Fp1/Fp2 disc electrodes, 12 EEG channels)
causal_filt = true;      % false (noncausal zero-phase filter) and true (causal min-phase filter; preserves causality + doesn't introduce group delays)
filt_cutoffs = [0.5 30]; % filter cutoff frequencies (in Hz)
minCorr = .55;            % minimum correlation with other channels before flagging as bad
maxTol = .3;             % max portion tolerated before flagging as bad channel
ignored_quantile = .2;   % ignored quantile for flagging channel as bad
asr_sd = 100;            % ASR SD threshold (conservative default = 100)
epoch_lims = [-3 3];    % limits -1500 ms to +1500 ms
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

load(fullfile(datapath, 'sInfo.mat'))
fprintf('Last subject processed: %g\n', sInfo(end).subject)

% Import data
[EEG, EOG, EMG, PPG, EDA, IMU, AUX] = galea_import(montage);  
sub_num = regexp(regexprep(EEG.filepath, ['\' filesep '$'], ''), 'sub-(\d+)$', 'tokens');
sub_num = str2double(sub_num{:}{:});

% Create new sInfo to store preprocessing info
if sub_num == 1
    sInfo = [];  % start new sInfo file
    warning("Subject 1 selected. Overwriting sInfo!!!")
end

sInfo(end+1).subject = sub_num;  % returns '002' as a string
sInfo(end).filepath = EEG.filepath;
sInfo(end).filename = EEG.filename;

% % Save chanlocs, 2st time for stats
% chanlocs = EEG.chanlocs;
% save(fullfile(datapath, 'chanlocs.mat'), 'chanlocs')

% Trim period before baseline starts with lots of artifacts
EEG = pop_select(EEG, 'nopoint', [0 EEG.event(1).latency - EEG.srate*1]); % 1 second
% EOG = pop_select(EOG, 'nopoint', [1 EOG.event(1).latency - EOG.srate*5]);

% Trim period after last event with lots of artifacts
EEG = pop_select(EEG, 'nopoint', [EEG.event(end).latency + EEG.srate*1 EEG.pnts]);
% EOG = pop_select(EOG, 'nopoint', [EOG.event(end).latency + EOG.srate*5 EOG.pnts]);

sInfo(end).file_length = EEG.xmax / 60;
sInfo(end).data_type = 'EEG';

% Rename events
disp("")
EEG = galea_rename_events(EEG);
% EOG.event = EEG.event;
% EMG.event = EEG.event;
% PPG.event = EEG.event;
% EDA.event = EEG.event;
% IMU.event = EEG.event;
sInfo(end).events = EEG.event;

% if length(EEG.event) < 80
%     error("less than 80 trials total at import. This file won't have enough trials (40 in each condition) and needs to be skipped. ")
% end

%-------------------------------------------------------------------------%
%                           FILTER EEG
%-------------------------------------------------------------------------%
% lowpass filter
EEG = pop_eegfiltnew(EEG,'hicutoff',filt_cutoffs(2),'minphase',causal_filt); % minimum-phase nonlinear causal filter to preserve causality + not introcuding group delays
% EEG = pop_eegfiltnew(EEG,'locutoff',58,'hicutoff',62,'revfilt',1,'minphase',1,'usefftfilt',1);  % notch filter to remove power line noise

% highpass filter (FINAL DATASET INCLUDING LOWER-FEQS
EEG = pop_eegfiltnew(EEG,'locutoff',filt_cutoffs(1),'minphase', causal_filt);      % final data for ERP analysis

pop_eegplot(EEG,1,1,1);

%% FILTER POLARITY OF CHANNELS Fp1 and Fp2

EEG = fix_polarity(EEG, {'Fp1','Fp2'}, 8, 0.5); % lower threshold is more sensisitve
% pop_eegplot(EEG,1,1,1);

%% REST OF PIPELINE

%COPY DATASET TO RUN ICA ON 1-HZ HIGHPASS-FILTERED DATA FOR BETTER
% DECOMPOSITION

TMPEEG = EEG;  % ICA does not perform well on data highpass below 1 hz, but we want to preserve low frequencies for anticipation --> so different filtering here for ICA decomposition
TMPEEG = pop_eegfiltnew(TMPEEG,'locutoff', 1,'minphase',causal_filt);  % for ICA, highpass at 1 hz

if causal_filt
    sInfo(end).filter = 'causal';
else
    sInfo(end).filter = 'noncausal';
end
sInfo(end).filt_cutoffs = filt_cutoffs;

% % Filter EOG
% EOG = pop_eegfiltnew(EOG,'locutoff',.75,'minphase',causal_filt); % minimum-phase nonlinear causal filter to preserve causality + not introcuding group delays
% EOG = pop_eegfiltnew(EOG,'hicutoff',30,'minphase',causal_filt); % minimum-phase nonlinear causal filter to preserve causality + not introcuding group delays

% Inspect data
% pop_eegplot(EEG,1,1,1);

%-------------------------------------------------------------------------%
%               Remove bad channels on TMPEEG 
%-------------------------------------------------------------------------%
% (ASR tools also need highpass filter > .75 hz)
% eeglab functions
% [TMPEEG, badChan] = clean_channels_nolocs(TMPEEG, minCorr, [], 2, maxTol); 
% [ERP, badChan] = clean_channels(ERP, minCorr, 100, 2, maxTol, 200); 


% Copy for visualizing bad channels and artifacts
oriEEG = TMPEEG;

% Automatic flagging of bad channels using custom method, gives better results
[badChan, flaggedRatio] = flag_bad_eeg_channels_window(TMPEEG.data, TMPEEG.srate, minCorr, ignored_quantile, maxTol);
badChanNum = find(badChan);
badChanLabel = {oriEEG.chanlocs(badChan).labels};
disp("Bad channels detected: ")
disp(badChanLabel)

% % Manual labeling of channels if needed
% badChan = {'P4' 'O1' 'O2'};  
% TMPEEG = pop_select(TMPEEG,'nochannel', badChan);
% vis_artifacts(TMPEEG,oriEEG);
% % badChan = {oriEEG.chanlocs(badChan).labels};

% Remove the bad channels
TMPEEG = pop_select(TMPEEG,'nochannel', {TMPEEG.chanlocs(badChan).labels});
TMPEEG.etc.clean_channel_mask = true(1,oriEEG.nbchan);
TMPEEG.etc.clean_channel_mask(badChanNum) = false;
vis_artifacts(TMPEEG,oriEEG); %set(gcf,'Name','Channels removed','Toolbar','none','Menu','none','NumberTitle', 'Off');

% Store to report later in paper
sInfo(end).badChan = badChan;

% Also remove from EEG ddataset filtered at 0.5 Hz 
EEG = pop_select(EEG,'nochannel', {oriEEG.chanlocs(badChan).labels});

% Subject must be excluded if more than 50% channels were bad
if EEG.nbchan <= 6
    sInfo(end).exclude_subject = true;
    save(fullfile(datapath, 'sInfo.mat'), 'sInfo') % Save all preprocessing outputs for reporting later
    error("Less than 50% EEG channels present. This file needs to be excluded from analysis.")
end



%-------------------------------------------------------------------------%
%              Remove large artifacts with ASR before ICA
%-------------------------------------------------------------------------%

% ASR
cleanEEG = clean_asr(TMPEEG, asr_sd,[],[],[],[],[],[],[],false,[]);
% cleanEEG = clean_asr(TMPEEG,100,[],[],[],'off','off',[],[],false,maxmem); % no clean baseline mode
mask = sum(abs(TMPEEG.data-cleanEEG.data),1) > 1e-10;
warning('%.1f%% of data were reconstructed by ASR \n', sum(mask)/ length(mask) *100)
sInfo(end).artifact_portion = sum(mask)/ length(mask);
if sum(mask)/ length(mask) *100 > 50
    sInfo(end).exclude_subject = true; % mark subject to be excluded from analysis
    save(fullfile(datapath, 'sInfo.mat'), 'sInfo') % Save all preprocessing outputs for reporting later
    error("more than 50% of data are bad, subject must be excluded from further processing and analysis.")
end

% % Take reconstructed data instead of removing bad portions entirely
% TMPEEG = cleanEEG;

% Remove bad sections instead of reconstruction
badData = reshape(find(diff([false mask false])),2,[])';
badData(:,2) = badData(:,2)-1;
smallIntervals = diff(badData,[],2) <= 5;
badData(smallIntervals,:) = [];
mask = false(1,TMPEEG.pnts);
for iSeg = 1:size(badData,1)
    lowBound = badData(iSeg,1);
    highBound = badData(iSeg,2);
    mask(lowBound:highBound) = true;
end
badDataRatio = round(100*(mean(mask)),1);
badDataSec = round(sum(mask)/TMPEEG.srate,1);
TMPEEG = pop_select(TMPEEG,'nopoint',badData);
TMPEEG.etc.clean_sample_mask = ~mask;
warning('%.1f%% of data were removed by ASR \n', sum(mask)/ length(mask) *100)
EEG = pop_select(EEG,'nopoint',badData); % Also remove from EEG dataset filtered at 0.5 Hz 

% Visualize the differences
vis_artifacts(TMPEEG,oriEEG);

%-------------------------------------------------------------------------%
%                   GEDAI instead of ASR + ICA
%-------------------------------------------------------------------------%

% % ---- GEDAI artifact reconstruction (alternative to ASR) ----
% % dataRank_before = sum(eig(cov(double(EEG2.data')))>1E-7);
% [cleanEEG, ~, SENSAI_score, ~, ~, mean_ENOVA, ~] = GEDAI(EEG, 'auto', 12, 0.5, 'precomputed', true, true, Inf);
% % dataRank_after = sum(eig(cov(double(cleanEEG.data')))>1E-7);
% sInfo(end).sensai = round(SENSAI_score, 2);
% sInfo(end).enova  = round(mean_ENOVA, 2);
% exportapp(gcf, fullfile(EEG.filepath, 'GEDAI_cleaning.png'))
% close(gcf)
% EEG = cleanEEG;  % IMPORTANT: keeps timestamps aligned with ECG/RESP


%-------------------------------------------------------------------------%
%                          ICA (on highpass filtered TMPEEG)
%-------------------------------------------------------------------------%

% ICA (on TMPEEG data highpass-filtered at 1 hz)
% Interpolate bad electrodes (after ASR to avoid data rank issues with PCA)
disp("Interpolating bad channels with spehircal splines...")
EEG = pop_interp(EEG, oriEEG.chanlocs, 'spherical'); % only if we remove 1 or 2 channels
TMPEEG = pop_interp(TMPEEG, oriEEG.chanlocs, 'spherical'); % only if we remove 1 or 2 channels

% Effective data rank
dataRank = sum(eig(cov(double(TMPEEG.data')))>1E-7);  % for continuous data
% dataRank = sum(eig(cov(double(TMPEEG.data(:,:)'))) > 1E-7); % epoched data

% Run ICA
% PICARD initialises from a random rotation, so an unseeded run gives slightly
% different components each time and the pipeline is not reproducible from the
% raw files. Seed immediately before it, not once at the top of the script, so
% that re-running this section alone gives the same answer as a full run.
rng(2026, 'twister');
TMPEEG = pop_runica(TMPEEG,'icatype','picard','mode','standard','pca',dataRank);    % PICARD (very fast and good results, need to install plugin in EEGLAB extension manager)
% TMPEEG = pop_runica(TMPEEG, 'icatype', 'runica','extended',1,'pca',dataRank);        % Infomax (default)

% % Run AMICA (much longer but best ICA agorithm)
% how to setup: https://sccn.ucsd.edu/~jason/amica_web.html
% tic
% c = parcluster;                             % cluster profile
% n_threads = getenv('NUMBER_OF_PROCESSORS');  % number of threads
% if ischar(n_threads), n_threads = str2double(n_threads); end
% [W, S, mods] = runamica15(TMPEEG.data,'max_threads',n_threads-1,'max_iter',1000, ...
%     'pcakeep',dataRank,'outdir',fullfile(new_filepath,'amica_outputs'));
% % [W, S, mods] = runamica15(TMPEEG.data,'max_iter',1000,'max_threads',n_threads-1, ...
% %     'pcakeep',dataRank,'do_reject',0,'numrej',1,'rejsig',3,...
% %     'lrate', 1e-3, 'share_comps', 0, ...
% %     'outdir',fullfile(new_filepath,'amica_outputs'));
% % [~, ~, mods] = runamica15(TMPEEG.data, ...
% %     'max_iter', 1000, ...                               % max_iter: Higher iterations can improve convergence, especially for larger datasets
% %     'max_threads', n_threads-1, ...                     % max_threads: Max number of threads for parallel processing
% %     'pcakeep', dataRank, ...                            % pcakeep: Keep PCA components based on data rank
% %     'do_reject', 0, ...                                 % do_reject: whether the algorithm should reject components during processing (1 = yes, 0 = no)
% %     'numrej', 1, ...                                    % numrej: Number of components to reject based on rejection criteria
% %     'rejsig', 3, ...                                    % rejsig: Rejection threshold based on the number of sd (common range: 3-5)
% %     'num_mix', 3, ...                                   % num_mix: Number of mixture components (default = 3, higher captures more complex data, but increases computation time.)
% %     'outdir', fullfile(new_filepath, 'amica_outputs'), ...  % outdir: Output directory for the results
% %     'lrate', 1e-3, ...                                  % lrate: Learning rate (default is 1e-3, but lower values might improve convergence)
% %     'share_comps', 0, ...                               % share_comps: allow component sharing between mixtures (default = 0, 1 might help with datasets that could benefit from shared components.)
% %     'num_models', 3);
% toc
% TMPEEG.icaweights = W;
% TMPEEG.icasphere  = S;
% TMPEEG = eeg_checkset(TMPEEG,'ica');
% TMPEEG = eeg_checkset(TMPEEG);

% % Remove AMICA segments
% oriEEG2 = TMPEEG;
% mask = mods.Lt==0;
% badData = reshape(find(diff([false mask false])), 2, [])';
% badData(:, 2) = badData(:, 2) - 1;
% % TMPEEG.etc.clean_sample_mask = true(1, length(mask)); % Initialize all samples as clean
% if ~isempty(badData)
%     % % Ignore very small segments
%     % smallIntervals = diff(badData')' < 5;         % 5 samples
%     % badData(smallIntervals, :) = [];
%     % fprintf('Ignoring %g%% of bad segments that are <10 samples long. \n', round(sum(smallIntervals) / sum(diff(badData')') *100,1) )
%
%     % Update clean_sample_mask to exclude short segments for vis_artifacts
%     for i = 1:size(badData, 1)
%         TMPEEG.etc.clean_sample_mask(badData(i, 1):badData(i, 2)) = false;
%     end
% end
% TMPEEG = pop_select(TMPEEG,'nopoint',badData);
% fprintf('%g %% of data were considered to be artifacts and were removed. \n', round((1-TMPEEG.xmax/oriEEG2.xmax)*100,2))
% vis_artifacts(TMPEEG,oriEEG2,'ShowSetname',false);
% set(gcf,'Name','Segments removed by AMICA','NumberTitle','Off','Toolbar','none','Menu','none');
% % saveas(gcf,fullfile(new_filepath, sprintf('sub-%2.2d_bad-segments-amica.fig',count)) ); close(gcf)
% sInfo(count).amica_segments = badData;

% Transfer the ICA weights to dataset filtered at 0.1 Hz
EEG.icaweights = TMPEEG.icaweights;
EEG.icasphere  = TMPEEG.icasphere;
EEG = eeg_checkset(EEG,'ica');
EEG = eeg_checkset(EEG);

%-------------------------------------------------------------------------%
%                        REMOVE OCULAR COMPONENTS
%-------------------------------------------------------------------------%

% % classification with ICLabel from highpass filtered dataset
% TMPEEG = pop_iclabel(TMPEEG,'default');
% TMPEEG = pop_icflag(TMPEEG,[NaN NaN; NaN NaN; .9 1; NaN NaN; NaN NaN; NaN NaN; NaN NaN]);
% pop_eegplot(TMPEEG,0,1,1);             % ICA time series
% pop_selectcomps(TMPEEG,1:dataRank);    % plot flagged ICs
% badComp = TMPEEG.reject.gcompreject;   % we'll remove components based on this better decomposition

% Force-flag 1st component if not flagged as it's (pretty much) always eye blinks
% if ~badComp(1)
    warning("1st eye component likely missed dur to poor signal quality, force-flagging it.")
    badComp(1) = true;
    TMPEEG.reject.gcompreject(1) = true;
% end

% Transfer to dataset filtered at 0.5 Hz
% EEG = pop_iclabel(EEG,'default');
% EEG = pop_icflag(EEG,[NaN NaN; NaN NaN; .9 1; NaN NaN; NaN NaN; NaN NaN; NaN NaN]);
% % % EEG = pop_icflag(EEG,[NaN NaN; NaN NaN; NaN NaN; NaN NaN; NaN NaN; NaN NaN; .3 1]);
pop_eegplot(EEG,0,1,1);             % ICA time series
saveas(gcf, fullfile(EEG.filepath, 'ICA_time-series.fig'));
% badComp = EEG.reject.gcompreject;
EEG.reject.gcompreject = TMPEEG.reject.gcompreject;
pop_selectcomps(EEG,1:dataRank);    % plot flagged ICs
% set(gcf,'Name','Independent components','toolbar','none','menu','none','numbertitle','off');
% saveas(gcf,fullfile(EEG.filepath, 'bad-components.png')); %close(gcf)
% print(gcf, fullfile(EEG.filepath, 'bad-components.png'), '-dpng', '-r300');
exportapp(gcf, fullfile(EEG.filepath, 'ICA_topographies.png'));

sInfo(end).bad_comps = badComp; % for reporting later

% % Custom method leveraging EOG channels (correlation, regression, or both)
% method = 'both'; % 'correlation' (default), 'regression', or 'both'
% pmethod = 'fisher';    % 'fisher' (Fisher z with Bonferroni over lags and EOG refs; Fast) or 'perm' ( uses circular shift permutations that preserve EOG autocorrelation; longer)
% LagSec = 0.3;          % Maximum absolute lag for cross correlation (in s).default = 0.8; 0.3 tighter match if EOG and EEG are well aligned
% MinAbsR = 0.05;        % ES floor for correlation method. Default = 0.05 (0.10 = stricter, fewer components; 0.02 = more sensitive, may catch subtle saccades).
% MinR2 = 0.03;          % same as minAbsR but for regression pathway.
% ThreshP = 0.05;        % FDR alpha trheshold (default = 0.05)
% [badComp, scores, details] = flag_ica_eog(EEG, EOG, ...
%     'Method', method, 'Band', [],  'PMethod', pmethod, ...
%     'LagSec', LagSec, 'MinAbsR', MinAbsR, 'MinR2', MinR2, 'ThreshP', ThreshP, ...
%     'UseParallel', false, 'ReportTop', dataRank, 'OpenProp', false);
 
% % % Update in EEGLAB and plot topographies
% EEG.reject.gcompreject = zeros(dataRank,1);
% % badComp = [1,2];  % for manual labeling
% EEG.reject.gcompreject(badComp) = true; 
% pop_eegplot(EEG,1,1,1);             % EEG time series
% pop_eegplot(EEG,0,1,1);             % ICA time series
% pop_selectcomps(EEG,1:dataRank);    % plot flagged ICs
% set(gcf,'Name','Independent components','toolbar','none','menu','none','numbertitle','off');
% % saveas(gcf,fullfile(subFolder, sprintf('sub-%2.2d_bad-components.png',iSub))); close(gcf)

% Extract the bad components from data
warning('Removing %g bad component(s). \n', sum(badComp))
EEG = pop_subcomp(EEG, find(badComp), 0);
EEG = eeg_checkset(EEG);
% pop_eegplot(EEG,1,1,1);
sInfo(end).badComp = sum(badComp);

%-------------------------------------------------------------------------%
%                               EPOCH
%-------------------------------------------------------------------------%


% events = unique({EEG.event.type});

% EEG = pop_epoch(EEG,{'exp_crash_start' 'exp_crash' 'exp_nocrash_start' 'exp_nocrash'}, [-2 2],'epochinfo', 'yes');
% --- v6: tag stimulus events with trial order and the PREVIOUS trial's type ---
% Custom event fields survive pop_epoch and pop_rejepoch, so this is the only
% place trial identity can be captured. Needed for the Level-1 previous-trial
% nuisance regressor; the interval before a trial is ~2.5 s shorter after a
% crash than after a near miss, and post-crash arousal may carry over.
stim_idx = find(ismember({EEG.event.type}, {'tire_pop','no_tire_pop'}));
fprintf('Tagging %g stimulus events with trial order...\n', numel(stim_idx));
for k = 1:numel(stim_idx)
    EEG.event(stim_idx(k)).trial_num = k;
    if k == 1
        EEG.event(stim_idx(k)).prev_crash = NaN;   % no predecessor
    else
        EEG.event(stim_idx(k)).prev_crash = ...
            double(strcmp(EEG.event(stim_idx(k-1)).type, 'tire_pop'));
    end
end

EEG = pop_epoch(EEG,{'no_tire_pop' 'tire_pop'}, epoch_lims,'epochinfo', 'yes'); % IMPORTANT take tire popping as time 0!!

sInfo(end).epoch_lims = epoch_lims;

% Remove bad trials
% Custom SNR (high-frequency artifacts) and RMS (large amplitude artifacts) metrics
badTrials = find_badTrials(EEG,'mean',1);
EEG = pop_rejepoch(EEG, badTrials, 0);
% set(gcf,'Name','Epochs removed','Toolbar','none','Menu','none','NumberTitle', 'Off'); 
sInfo(end).bad_trials = badTrials;

% % Baseline correction
% Remove aperiodic exponent/offset instead?
%  Probably best not to do any baseline correction to compare with prestim period!
% EXP = pop_rmbase(EXP, [EXP.times(1) -1500] ,[]);  
sInfo(end).baseline_corr = false;

% Export .set file for statistical analysis
EEG = pop_saveset(EEG, 'filepath', EEG.filepath, 'filename', EEG.filename);

%-------------------------------------------------------------------------%
%                        WITHIN-SUBJECT ERP
%-------------------------------------------------------------------------%

ERP = EEG;

% % Smooth
% ERP = pop_eegfiltnew(ERP,'hicutoff',15,'minphase',causal_filt);  % same filter as earlier for consistency

% Extract conditions trials
no_crash = pop_epoch(ERP, {'no_tire_pop'}, epoch_lims);
crash = pop_epoch(ERP, {'tire_pop'}, epoch_lims);
% bsl = pop_epoch(EXP, {'bsl_deviation'}, [-1 2]);
fprintf('Total number of trials remaining after preprocessing: %g trials \n', ERP.trials)
fprintf('%g no-crash trials \n', no_crash.trials)
fprintf('%g crash trials \n', crash.trials)
% fprintf('%g control trials \n', bsl.trials)
sInfo(end).n_crash = crash.trials;
sInfo(end).n_nocrash = no_crash.trials;

% Compare conditions - ERP of all channels combined
idx = contains({ERP.chanlocs.labels}, {ERP.chanlocs.labels});
x = squeeze(mean(no_crash.data(idx,:,:),1));      
y = squeeze(mean(crash.data(idx,:,:),1));  
% plotHDI(crash.times, x, y, 'mean', 0.05, [], 'no crash','crash');    % 95% Bayesian HDIs
% figure; plotDiff(crash.times, x, y, 'mean', 'CI', [], 'no crash','crash');   % 95% CIs
figure; plotDiff(crash.times, x, y, 'mean', 'SE', [], sprintf('no crash (%g trials)',no_crash.trials), sprintf('crash (%g trials)',crash.trials));  
title(sprintf('Subject %g (all channels)', sub_num))
% xlim([-1300 1500])
axis tight; box on
print(gcf, fullfile(EEG.filepath, 'EEG-ERP.png'), '-dpng', '-r300');


% Save outputs
if no_crash.trials < 30 || crash.trials < 30
    sInfo(end).exclude_subject = true; % mark subject to be excluded from analysis
    save(fullfile(datapath, 'sInfo.mat'), 'sInfo') % Save all preprocessing outputs for reporting later
    error("Less than 30 trials in at least one condition! This dataset must be excluded from analysis (see Data Exclusion section in Study preregistration)!")
end
chanlocs = ERP.chanlocs;
times = crash.times;
% --- v6: pull the per-trial metadata back off the epoched structures ---
getmeta = @(S, f) arrayfun(@(e) local_first(e, f), S.epoch);
trialinfo = struct();
trialinfo.crash_trial_num    = getmeta(crash,    'eventtrial_num');
trialinfo.crash_prev_crash   = getmeta(crash,    'eventprev_crash');
trialinfo.nocrash_trial_num  = getmeta(no_crash, 'eventtrial_num');
trialinfo.nocrash_prev_crash = getmeta(no_crash, 'eventprev_crash');
fprintf('Trial metadata: %g crash, %g no-crash tagged.\n', ...
    numel(trialinfo.crash_trial_num), numel(trialinfo.nocrash_trial_num));

save(fullfile(EEG.filepath, "ERP_EEG_new.mat"), "no_crash", "crash", "chanlocs","times","trialinfo")
save(fullfile(datapath, 'sInfo.mat'), 'sInfo') % Save all preprocessing outputs for reporting later


%% ---- v6 local helper ----
function v = local_first(ep, fieldname)
% Return the field value of the epoch's time-locking event. Epochs are +/-3 s
% and the stimulus-onset asynchrony is ~12 s, so each epoch holds exactly one
% stimulus event; the cell wrapper is unwrapped defensively anyway.
v = NaN;
if ~isfield(ep, fieldname), return; end
x = ep.(fieldname);
if iscell(x)
    x = x(~cellfun(@isempty, x));
    if isempty(x), return; end
    x = x{1};
end
if ~isempty(x), v = double(x(1)); end
end
