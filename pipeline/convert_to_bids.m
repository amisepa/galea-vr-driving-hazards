%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Convert the study data to BIDS + HED
%
% WHAT THIS DOES
%   Creates a BIDS dataset from the per-subject recordings in the study data
%   folder, with HED-annotated events, and re-exports the processed epochs
%   (the pipeline output behind the paper's analyses) as a BIDS derivative.
%
%   raw          OpenBCI-RAW-*.txt  +  OpenBCI-RAW-Aux-*.txt
%                -> continuous unprocessed EEG/EOG/EMG at 250 Hz (main .set)
%                   and PPG/EDA/IMU at the aux native ~50 Hz (second .set,
%                   acq-aux entity), imported with the plugin (galea_import)
%                   so channel types, device-derived sampling rates and
%                   marker labels are set, then exported with bids_export.
%   processed    OpenBCI-RAW-*.set  (epoched, ICA-cleaned, 12-channel EEG)
%                -> derivatives/EEGPreprocessed/ as a BIDS derivative.
%
%   Every event gets a HED 8.1.0 tag string; trial_type distinguishes
%   collision / no-collision / baseline events.
%
%   sub-000 is a pilot participant and is excluded.
%
% OUTPUT
%   <study data folder>/BIDS/
%     dataset_description.json, participants.tsv/.json, README
%     sub-XXX/eeg/sub-XXX_task-vrCollisionHazard_eeg.set + _eeg.json
%              + _channels.tsv + _events.tsv (+ _events.json with HED)
%     derivatives/EEGPreprocessed/sub-XXX/eeg/...
%
% Requires: EEGLAB, the EEG-BIDS plugin, and the repository on the path
% (run galea_set_paths first).
%
% Cedric Cannard, 2026

% ------------------------------------------------------------------ setup
clear; close all; clc
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
addpath(fullfile(paths.eeglab, 'plugins', 'EEG-BIDS'));             % bids_export, eeg_mergechannels
addpath(fullfile(paths.eeglab, 'plugins', 'EEG-BIDS', 'JSONio'));   % jsonwrite/jsonread
eeglab nogui;

bids_root       = fullfile(fileparts(paths.data), 'BIDS');

% ------------------------------------------------------------ subjects
subject_list = dir(fullfile(paths.data, 'sub-*'));
subject_list = subject_list([subject_list.isdir]);
subject_names = {subject_list.name};
% PILOT-SUBSET for testing: revert to the full list for the full run.
% subject_names = {'sub-018'};   % PILOT-SUBSET (uncomment for quick test)
    subject_names = setdiff(subject_names, 'sub-000');   % pilot subject excluded
subject_names = subject_names(~startsWith(subject_names, '.'));
nSub = numel(subject_names);
fprintf('Converting %d subjects (pilot sub-000 excluded)\n', nSub);

% ------------------------------------------------- dataset_description
gInfo.Name = 'Neural and physiological dynamics before and after unpredictable collision events in virtual reality';
gInfo.BIDSVersion = '1.10';
gInfo.HEDVersion = '8.1.0';
gInfo.Authors = {'Cedric Cannard', 'Demet Yesilbas'};
gInfo.ReferencesAndLinks = {'Preregistration: https://osf.io/xuw34'};
% Dataset licence: CC0-1.0 is the OpenNeuro norm for DATA (facts, no
% copyright-protectable expression); the ANALYSIS CODE stays GPL-3.0.
gInfo.License = 'CC0-1.0';

README = [ ...
  'BIDS dataset for Cannard & Yesilbas (2026), "Reactive and predictive ' ...
  'processes during unpredictable driving hazards in virtual reality: an ' ...
  'exploratory brain and body study with multimodal neurophysiological ' ...
  'monitoring".' newline newline ...
  'PREREGISTRATION: https://osf.io/xuw34 ("Neural and physiological dynamics ' ...
  'before and after unpredictable collision events in virtual reality using ' ...
  'novel wearable sensing"). Analysis code: ' ...
  'https://github.com/amisepa/galea-vr-driving-hazards.' newline newline ...
  'Participants watched immersive VR driving scenes (Varjo Aero HMD) while EEG, ' ...
  'EOG, EMG, PPG, EDA and IMU were recorded with the Galea multimodal headset ' ...
  '(OpenBCI board, dry electrodes). 120 experimental trials per participant; ' ...
  'collision vs no-collision was assigned per trial by a quantum random number ' ...
  'generator (ANU QRNG API), independently at 50% probability. A baseline ' ...
  'block preceded the experimental block.' newline newline ...
  'RAW layer: sub-XXX/eeg contains the continuous unprocessed recordings, as ' ...
  'two EEGLAB .set files per run with _channels.tsv (typed), _eeg.json and ' ...
  '_events.tsv (HED 8.1.0 annotated): the main recording (12 EEG + 2 EOG + 4 ' ...
  'EMG channels at 250 Hz, task-vrCollisionHazard) and the peripheral ' ...
  'recording (PPG, EDA and 9-axis IMU at their native ~50 Hz aux rate, ' ...
  'acq-aux). No signal was resampled or filtered; EOG/EMG channels are ' ...
  're-attached to the EEG set only because galea_import splits them out.' newline newline ...
  'sourcedata/: the original unmodified OpenBCI recordings (.txt + Aux .txt ' ...
  'and BrainFlow CSVs where present), as produced by the acquisition software.' newline newline ...
  'DERIVATIVE: derivatives/EEGPreprocessed/ holds the epoched, ICA-cleaned ' ...
  '12-channel EEG used for the paper''s analyses. Stimulus sequences are in ' ...
  'the analysis repository (data/stim_sequences_delivered).'];

% -------------------------------------------------------- task sidecar
tInfo = struct();
tInfo.TaskName = 'vrCollisionHazard';
tInfo.InstitutionName = 'Institute of Noetic Sciences';
tInfo.InstitutionAddress = 'Petaluma, CA, USA';
tInfo.PowerLineFrequency = 50;
tInfo.Manufacturer = 'Galea (OpenBCI GaleaBeta board), Varjo Aero HMD';
tInfo.ManufacturersModelName = 'Galea Beta';
tInfo.EEGReference = 'CMS/DRL (machinery reference); re-referenced to common average during preprocessing';
tInfo.TriggerChannelCount = 0;

% ----------------------------------------------- event column metadata
eInfoDesc.onset.Description  = 'Event onset relative to recording start';
eInfoDesc.onset.Units        = 's';
eInfoDesc.duration.Description = 'Event duration';
eInfoDesc.duration.Units     = 's';
eInfoDesc.sample.Description = 'Event sample (MATLAB convention, starting at 1)';
eInfoDesc.value.Description  = 'Original Unity/OpenBCI marker code';
eInfoDesc.trial_type.Description = 'Experimental condition of the event';
eInfoDesc.trial_type.Levels.collision    = 'Tire-pop onset of a collision trial';
eInfoDesc.trial_type.Levels.no_collision = 'Matching time point in a no-collision trial';
eInfoDesc.trial_type.Levels.baseline      = 'Baseline-block event (stationary driving scene)';
eInfoDesc.trial_type.Levels.baseline_block = 'Start of the stationary-driving-scene baseline time-block';
eInfoDesc.trial_type.Levels.block_start   = 'Start of a recording block';
eInfoDesc.HED.LongName = 'HED 8.1.0 annotation string';

cInfoDesc.name.Description = 'Channel name (10-20 labels for EEG, stream names otherwise)';
cInfoDesc.type.Description = 'Channel type (EEG, EOG, EMG, PPG, EDA, MISC)';
cInfoDesc.reference.Description = 'Recording reference (Galea machinery reference)';

% participants.tsv (pseudonymous; no demographic columns are shipped)
pInfo = cell(nSub + 1, 1);
pInfo{1} = 'participant_id';
for iSub = 1:nSub
    pInfo{iSub + 1} = subject_names{iSub};
end
pInfoDesc.participant_id.Description = 'unique participant identifier';

% ------------------------------------------------- HED tag assignment
% One HED string per event label. Trial-onset events carry the trial context
% (driving-scene, collision/no-collision); tire-pop events carry the
% sensory event itself (sound + visual change).
HED.baseline_block    = 'Event, Experiment-structure, Description/Start of the baseline time-block';
HED.baseline_trial    = 'Event, Experiment-structure, Description/Start of a baseline driving-scene trial';
HED.baseline_dev      = 'Event, Experiment-structure, Description/Baseline driving period with a road deviation';
HED.experiment_block  = 'Event, Experiment-structure, Description/Start of the experimental time-block';
HED.collision_trial   = 'Event, Experiment-structure, Description/Start of a collision driving-scene trial';
HED.collision_pop     = 'Event, Sensory-event, Environmental-sound, Description/Tire-blowout-sound, Visual-presentation, Virtual-world, Description/Collision-driving-scene';
HED.no_collision_pop  = 'Event, Sensory-event, Visual-presentation, Virtual-world, Description/Time-matched control point of a no-collision driving-scene trial';
HED.no_collision_trl  = 'Event, Experiment-structure, Description/Start of a no-collision driving-scene trial';

% Marker label -> {trial_type, HED tag}
LABEL_HED = { ...
    'BSL',              'baseline_block',    HED.baseline_block
    'bsl_start',        'baseline',          HED.baseline_trial
    'bsl_dev',          'baseline',          HED.baseline_dev
    'EXP',              'block_start',       HED.experiment_block
    'crash_start',      'collision',         HED.collision_pop
    'tire_pop',         'collision',         HED.collision_pop
    'no_crash_start',   'no_collision',      HED.no_collision_trl
    'no_tire_pop',      'no_collision',      HED.no_collision_pop };

% --------------------------------------------------- loop over subjects
nOK = 0; nFail = 0;
for iSub = 1:nSub
    sub = subject_names{iSub};
    sub_dir = fullfile(paths.data, sub);
    fprintf('=== %s (%d/%d) ===\n', sub, iSub, nSub);

    % ---- 1. RAW continuous recording(s) (unprocessed) -----------------
    % Most subjects have one recording. sub-011 was interrupted and has two
    % (trials 1-98, then after trial 98): they become run-01 / run-02.
    try
        raw_txt = dir(fullfile(sub_dir, 'OpenBCI-RAW-*.txt'));
        raw_txt = raw_txt(~contains({raw_txt.name}, 'Aux'));
        [~, order] = sort({raw_txt.name});        % chronological by timestamp
        raw_txt = raw_txt(order);
        if isempty(raw_txt)
            % No OpenBCI .txt main file: an auxiliary BrainFlow-only recording
            % (e.g. a separate PPG/EDA capture). Its files are still copied to
            % sourcedata/ below, but there is no EEG recording to convert, so
            % the subject's BIDS layer only reflects the OpenBCI capture(s).
            fprintf('  (no OpenBCI main recording; sourcedata only)\n');
            src_only = true;
        else
            src_only = false;
        end
        assert(~src_only, 'no OpenBCI main recording to convert (sourcedata only)');
        nRuns = numel(raw_txt);

        stage_dir = fullfile(tempdir, 'galea_bids_stage');
        if ~exist(stage_dir, 'dir'), mkdir(stage_dir); end
        files_i = cell(1, nRuns); aux_i = cell(1, nRuns); runs_i = 1:nRuns;
        for iRun = 1:nRuns
            [EEG_raw, EOG_raw, EMG_raw, PPG_raw, EDA_raw, IMU_raw, ~] = galea_import('custom', raw_txt(iRun).name, sub_dir);
            EEG_raw = galea_rename_events(EEG_raw);
            % Keep ALL EEG-scoped streams in the main recording, unmodified:
            % undo only the channel split made by galea_import. EEGLAB data
            % are [channels x samples], so appending channels is vertical
            % concatenation; all three sets share the same 250 Hz time base.
            eeg_chans = EEG_raw.nbchan;
            for k = 1:eeg_chans,   EEG_raw.chanlocs(k).type = 'EEG'; end
            for k = 1:EOG_raw.nbchan, EOG_raw.chanlocs(k).type = 'EOG'; end
            for k = 1:EMG_raw.nbchan, EMG_raw.chanlocs(k).type = 'EMG'; end
            EEG_raw.data     = [EEG_raw.data;     EOG_raw.data;     EMG_raw.data];
            EEG_raw.chanlocs = [EEG_raw.chanlocs, EOG_raw.chanlocs, EMG_raw.chanlocs];
            EEG_raw.nbchan   = eeg_chans + EOG_raw.nbchan + EMG_raw.nbchan;
            EEG_raw = eeg_checkset(EEG_raw);

            % SECOND .set at the aux native rate (~50 Hz): PPG/EDA/IMU as
            % acquired, NOT resampled (acq-aux entity; BIDS sidecar _eeg.json
            % lists its own SamplingFrequency). Battery/Board_temp are device
            % health channels and are not exported.
            % galea_import returns PPG / EDA / IMU as separate structures at
            % the same aux rate and time base: stitch them back together.
            AUX_raw = PPG_raw;
            AUX_raw.data     = [PPG_raw.data; EDA_raw.data; IMU_raw.data];
            AUX_raw.chanlocs = [PPG_raw.chanlocs, EDA_raw.chanlocs, IMU_raw.chanlocs];
            AUX_raw.nbchan   = PPG_raw.nbchan + EDA_raw.nbchan + IMU_raw.nbchan;
            for k = 1:AUX_raw.nbchan
                lbl = AUX_raw.chanlocs(k).labels;
                if any(strcmpi(lbl, {'PPG_red','PPG_IR'}))
                    AUX_raw.chanlocs(k).type = 'PPG';
                elseif strcmpi(lbl, 'EDA')
                    AUX_raw.chanlocs(k).type = 'GSR';   % BIDS enum for electrodermal activity
                else
                    AUX_raw.chanlocs(k).type = 'MISC';   % IMU streams
                end
            end
            AUX_raw = eeg_checkset(AUX_raw);
            % The aux streams carry the same markers (borrowed inside
            % galea_import for event latencies): rename + HED-tag them too.
            AUX_raw = galea_rename_events(AUX_raw);
            for iEv = 1:numel(AUX_raw.event)
                row = strcmp(LABEL_HED(:, 1), AUX_raw.event(iEv).type);
                if any(row)
                    AUX_raw.event(iEv).trial_type = LABEL_HED{row, 2};
                    AUX_raw.event(iEv).HED        = LABEL_HED{row, 3};
                else
                    AUX_raw.event(iEv).trial_type = 'n/a';
                    AUX_raw.event(iEv).HED        = 'Event';
                end
            end

            % HED + trial_type on every event
            for iEv = 1:numel(EEG_raw.event)
                row = strcmp(LABEL_HED(:, 1), EEG_raw.event(iEv).type);
                if any(row)
                    EEG_raw.event(iEv).trial_type = LABEL_HED{row, 2};
                    EEG_raw.event(iEv).HED        = LABEL_HED{row, 3};
                else
                    EEG_raw.event(iEv).trial_type = 'n/a';
                    EEG_raw.event(iEv).HED        = 'Event';
                end
            end
            % Raw import as loaded by galea_import: 12 EEG + typed EOG/EMG
            % channels, no filtering, no re-referencing, no epoching.
            
            % bids_export deletes its target dir, so export goes to a staging
            % folder in temp and is moved into place afterwards.
            % unique staged filename per run (BIDS run entity comes from
            % data(iSub).run below); suffix only when there are several runs
            if nRuns > 1
                EEG_raw.setname = sprintf('%s_task-vrCollisionHazard_run-%02d', sub, iRun);
                AUX_raw.setname = sprintf('%s_task-vrCollisionHazard_acq-aux_eeg_run-%02d', sub, iRun);
            else
                EEG_raw.setname = sprintf('%s_task-vrCollisionHazard', sub);
                AUX_raw.setname = sprintf('%s_task-vrCollisionHazard_acq-aux_eeg', sub);
            end
            pop_saveset(EEG_raw, 'filename', [EEG_raw.setname '.set'], 'filepath', stage_dir);
            pop_saveset(AUX_raw, 'filename', [AUX_raw.setname '.set'], 'filepath', stage_dir);
            aux_i{iRun} = fullfile(stage_dir, [AUX_raw.setname '.set']);
            files_i{iRun} = fullfile(stage_dir, [EEG_raw.setname '.set']);
        end
        data(iSub).file    = files_i;
        data(iSub).auxfile = aux_i;   % reference only: not passed to bids_export
        data(iSub).session = ones(1, nRuns);
        data(iSub).run     = arrayfun(@(r) sprintf('%02d', r), runs_i, 'UniformOutput', false);

        % ---- 2. PROCESSED epochs: HED-tag now, write after the export --
        set_files = dir(fullfile(sub_dir, 'OpenBCI-RAW-*.set'));
        [~, order] = sort({set_files.name});
        set_files = set_files(order);
        for iRun = 1:numel(set_files)
            EEG_proc = pop_loadset('filename', set_files(iRun).name, 'filepath', sub_dir);
            for iEv = 1:numel(EEG_proc.event)
                row = strcmp(LABEL_HED(:, 1), EEG_proc.event(iEv).type);
                if any(row)
                    EEG_proc.event(iEv).trial_type = LABEL_HED{row, 2};
                    EEG_proc.event(iEv).HED        = LABEL_HED{row, 3};
                else
                    EEG_proc.event(iEv).trial_type = 'n/a';
                    EEG_proc.event(iEv).HED        = 'Event';
                end
            end
            EEG_proc = eeg_checkset(EEG_proc);
            proc_dir = fullfile(stage_dir, 'derivatives', 'EEGPreprocessed', sub, 'eeg');
            if ~exist(proc_dir, 'dir'), mkdir(proc_dir); end
            run_tag = '';
            if numel(set_files) > 1, run_tag = sprintf('_run-%02d', iRun); end
            base = sprintf('%s_task-vrCollisionHazard_proc_epoched%s', sub, run_tag);
            pop_saveset(EEG_proc, 'filename', [base '.set'], 'filepath', proc_dir);
            % events sidecar (onset/sample/value/trial_type/HED) for the derivative.
            % bids_writeeventfile has an finputcheck quirk with its own
            % 'omitsample' default, so the TSV/JSON are written directly.
            ev = EEG_proc.event;
            nEv = numel(ev);
            fid = fopen(fullfile(proc_dir, [base '_events.tsv']), 'w');
            fprintf(fid, 'onset\tduration\tsample\tvalue\ttrial_type\tHED\n');
            for iEv = 1:nEv
                dur = 0; if isfield(ev, 'duration'), dur = ev(iEv).duration; end
                tt = 'n/a'; hed = 'Event';
                if isfield(ev, 'trial_type'), tt = ev(iEv).trial_type; end
                if isfield(ev, 'HED'), hed = ev(iEv).HED; end
                fprintf(fid, '%.6f\t%.6f\t%d\t%s\t%s\t%s\n', ...
                    (ev(iEv).latency-1)/EEG_proc.srate, dur, ev(iEv).latency, ev(iEv).type, tt, hed);
            end
            fclose(fid);
            % sidecar JSON: column descriptions. The HED column is NOT
            % described here on purpose: 'HED' as a sidecar key is illegal
            % (HED spec Appendix B, SIDECAR_INVALID). The HED column in
            % events.tsv is recognised by HED tools directly, and the version
            % is declared in the EEG sidecar's HEDVersion field.
            jsonwrite(fullfile(proc_dir, [base '_events.json']), eInfoDesc, struct('indent', '  '));
        end
        % ---- 3. SOURCEDATA: original OpenBCI files, unmodified ----------
        src_dir = fullfile(stage_dir, 'sourcedata', sub);
        if ~exist(src_dir, 'dir'), mkdir(src_dir); end
        srcFiles = [dir(fullfile(sub_dir, 'OpenBCI-*.txt')); dir(fullfile(sub_dir, 'BrainFlow-*.csv')); dir(fullfile(sub_dir, 'Timestamp_*.txt'))];
        for iSrc = 1:numel(srcFiles)
            copyfile(fullfile(srcFiles(iSrc).folder, srcFiles(iSrc).name), fullfile(src_dir, srcFiles(iSrc).name));
        end
        nOK = nOK + 1;
    catch err
        fprintf('  FAILED: %s\n', err.message);
        nFail = nFail + 1;
    end
end

% ------------------------------------------------------ bids_export raw
% Export the staged continuous raw recordings into the BIDS tree.
bids_export(data, ...
    'targetdir', bids_root, ...
    'gInfo', gInfo, ...
    'tInfo', tInfo, ...
    'pInfo', pInfo, 'pInfoDesc', pInfoDesc, ...
    'eInfoDesc', eInfoDesc, ...
    'cInfoDesc', cInfoDesc, ...
    'trialtype', LABEL_HED(:, 1:2), ...
    'README', README, ...
    'interactive', 'off', ...
    'modality', 'eeg', ...
    'exportformat', 'eeglab');

% copy the staged acq-aux recordings into each subject's eeg/ folder
% (bids_export only handles the main EEG files; the aux-rate peripheral
%  .set files are plain copies with no sidecar beyond what bids_export
%  would write, so we write their channels.tsv/eeg.json directly below)
auxFiles = dir(fullfile(tempdir, 'galea_bids_stage', 'sub-*_acq-aux*.set'));
fprintf('Copying %d acq-aux recordings...\n', numel(auxFiles));
for iAux = 1:numel(auxFiles)
    tok = regexp(auxFiles(iAux).name, '^(sub-\d+)_task-vrCollisionHazard(_acq-aux_eeg)(_run-(\d+))?\.set$', 'tokens', 'once');
    if isempty(tok), continue; end
    auxSub = tok{1};
    if numel(tok) >= 4, auxRun = tok{4}; else, auxRun = ''; end
    destDir = fullfile(bids_root, auxSub, 'eeg');
    if ~exist(destDir, 'dir'), mkdir(destDir); end
    copyfile(fullfile(auxFiles(iAux).folder, auxFiles(iAux).name), ...
             fullfile(destDir, auxFiles(iAux).name));
    % channels.tsv for the aux recording (typed)
    fid = fopen(fullfile(destDir, strrep(auxFiles(iAux).name, '_eeg.set', '_channels.tsv')), 'w');
    fprintf(fid, 'name\ttype\tunits\n');
    auxEEG = pop_loadset('filename', auxFiles(iAux).name, 'filepath', auxFiles(iAux).folder);
    for k = 1:auxEEG.nbchan
        ty = 'MISC'; un = 'n/a';
        if isfield(auxEEG.chanlocs, 'type') && ~isempty(auxEEG.chanlocs(k).type), ty = upper(auxEEG.chanlocs(k).type); end
        if strcmpi(ty, 'PPG') || strcmpi(ty, 'GSR'), un = 'V'; else, un = 'n/a'; end
        fprintf(fid, '%s\t%s\t%s\n', auxEEG.chanlocs(k).labels, ty, un);
    end
    fclose(fid);
    % eeg.json sidecar for the aux recording
    auxInfo = struct();
    auxInfo.TaskName = 'vrCollisionHazard';
    auxInfo.TaskDescription = 'Peripheral physiological streams of the vrCollisionHazard task at their native sampling rate';
    auxInfo.SamplingFrequency = auxEEG.srate;
    auxInfo.EEGChannelCount = 0;
    auxInfo.MiscChannelCount = sum(cellfun(@(c) any(strcmpi(c, {'ACC_X','ACC_Y','ACC_Z','GYR_X','GYR_Y','GYR_Z','MEG_X','MEG_Y','MEG_Z'})), {auxEEG.chanlocs.labels}));
    auxInfo.PPGChannelCount = sum(strcmpi({auxEEG.chanlocs.labels}, 'PPG_red')) + sum(strcmpi({auxEEG.chanlocs.labels}, 'PPG_IR'));
    auxInfo.EDACHannelCount = sum(strcmpi({auxEEG.chanlocs.labels}, 'EDA'));
    auxInfo.Manufacturer = tInfo.Manufacturer;
    auxInfo.ManufacturersModelName = tInfo.ManufacturersModelName;
    auxInfo.InstitutionName = tInfo.InstitutionName;
    auxInfo.InstitutionAddress = tInfo.InstitutionAddress;
    auxInfo.PowerLineFrequency = tInfo.PowerLineFrequency;
    auxInfo.EEGReference = 'n/a (no EEG channels in this recording)';
    jsonwrite(fullfile(destDir, strrep(auxFiles(iAux).name, '_eeg.set', '_eeg.json')), auxInfo, struct('indent', '  '));
    % events.tsv for the aux recording (BIDS requires events for every
    % recording in the EEG modality folder; same markers as the main .set)
    ev = auxEEG.event;
    fid = fopen(fullfile(destDir, strrep(auxFiles(iAux).name, '_eeg.set', '_events.tsv')), 'w');
    fprintf(fid, 'onset\tduration\tsample\tvalue\ttrial_type\tHED\n');
    if ~isempty(ev)
        for iEv = 1:numel(ev)
            dur = 0; if isfield(ev, 'duration'), dur = ev(iEv).duration; end
            tt = 'n/a'; hed = 'Event';
            if isfield(ev, 'trial_type'), tt = ev(iEv).trial_type; end
            if isfield(ev, 'HED'), hed = ev(iEv).HED; end
            fprintf(fid, '%.6f\t%.6f\t%d\t%s\t%s\t%s\n', ...
                (ev(iEv).latency-1)/auxEEG.srate, dur, ev(iEv).latency, ev(iEv).type, tt, hed);
        end
    end
    fclose(fid);
    fprintf('  %s (%d ch @ %g Hz)\n', auxFiles(iAux).name, auxEEG.nbchan, auxEEG.srate);
end
if exist(fullfile(tempdir, 'galea_bids_stage', 'sourcedata'), 'dir')
    moved2 = movefile(fullfile(tempdir, 'galea_bids_stage', 'sourcedata'), fullfile(bids_root, 'sourcedata'));
    fprintf('sourcedata moved into BIDS tree: %d\n', moved2);
end

fprintf('\nDONE: %d subjects exported, %d failed.\nBIDS root: %s\n', nOK, nFail, bids_root);