%% Convert the study data to BIDS + HED
%
% WHAT THIS DOES
%   Creates a BIDS dataset from the per-subject recordings in the study data
%   folder, with HED-annotated events, and re-exports the processed epochs
%   (the pipeline output behind the paper's analyses) as a BIDS derivative.
%
%   raw          OpenBCI-RAW-*.txt  +  OpenBCI-RAW-Aux-*.txt
%                -> continuous unprocessed EEG/EOG/EMG + PPG/EDA/IMU,
%                   imported with the plugin (galea_import) so channel types,
%                   device-derived sampling rates and marker labels are set,
%                   then exported with bids_export.
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
%     sub-XXX/eeg/sub-XXX_task-drivinghazard_eeg.set + _eeg.json
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
addpath(fullfile(paths.eeglab, 'plugins', 'EEG-BIDS'));             % bids_export
addpath(fullfile(paths.eeglab, 'plugins', 'EEG-BIDS', 'JSONio'));   % jsonwrite/jsonread
eeglab nogui;

bids_root       = fullfile(fileparts(paths.data), 'BIDS');

% ------------------------------------------------------------ subjects
subject_list = dir(fullfile(paths.data, 'sub-*'));
subject_list = subject_list([subject_list.isdir]);
subject_names = {subject_list.name};
subject_names = setdiff(subject_names, 'sub-000');   % pilot subject excluded
subject_names = subject_names(~startsWith(subject_names, '.'));
nSub = numel(subject_names);
fprintf('Converting %d subjects (pilot sub-000 excluded)\n', nSub);

% ------------------------------------------------- dataset_description
gInfo.Name = 'Galea VR driving-hazards EEG/PPG dataset';
gInfo.BIDSVersion = '1.10';
gInfo.HEDVersion = '8.1.0';
gInfo.Authors = {'Cedric Cannard', 'Demet Yesilbas'};
gInfo.ReferencesAndLinks = {'https://osf.io/xuw34'};
gInfo.License = 'CC0-1.0';

README = [ ...
  'BIDS version of the dataset for Cannard & Yesilbas (2026), "Reactive and ' ...
  'predictive processes during unpredictable driving hazards in virtual reality" ' ...
  '(preregistered at https://osf.io/xuw34).' newline newline ...
  'Participants watched immersive VR driving scenes (Varjo Aero HMD) while EEG, ' ...
  'EOG, EMG, PPG, EDA and IMU were recorded with the Galea multimodal headset ' ...
  '(OpenBCI board, dry electrodes). 120 experimental trials per participant; ' ...
  'collision vs no-collision was assigned per trial by a quantum random number ' ...
  'generator, independently at 50% probability. A baseline block preceded the ' ...
  'experimental block.' newline newline ...
  'Raw continuous recordings are in sub-XXX/eeg (EEG .set + events.tsv with ' ...
  'HED 8.1.0 tags). The processed epochs used for the paper''s analyses are in ' ...
  'derivatives/EEGPreprocessed/. Stimulus sequences are in the repository ' ...
  '(data/stim_sequences_delivered).'];

% -------------------------------------------------------- task sidecar
tInfo = struct();
tInfo.TaskName = 'drivinghazard';
tInfo.InstitutionName = 'Institute of Noetic Sciences';
tInfo.InstitutionAddress = 'Petaluma, CA, USA';
tInfo.PowerLineFrequency = 50;
tInfo.Manufacturer = 'Galea (OpenBCI GaleaBeta board), Varjo Aero HMD';
tInfo.ManufacturersModelName = 'Galea Beta';
tInfo.EEGReference = 'CMS/DRL (machinery reference); re-referenced to common average during preprocessing';
tInfo.TriggerChannelCount = 0;

% ----------------------------------------------- event column metadata
eInfoDesc.onset.Description  = 'Event onset relative to recording start';
eInfoDesc.onset.Units        = 'seconds';
eInfoDesc.duration.Description = 'Event duration';
eInfoDesc.duration.Units     = 'seconds';
eInfoDesc.sample.Description = 'Event sample (MATLAB convention, starting at 1)';
eInfoDesc.value.Description  = 'Original Unity/OpenBCI marker code';
eInfoDesc.trial_type.Description = 'Experimental condition of the event';
eInfoDesc.trial_type.Levels.collision    = 'Tire-pop onset of a collision trial';
eInfoDesc.trial_type.Levels.no_collision = 'Matching time point in a no-collision trial';
eInfoDesc.trial_type.Levels.baseline     = 'Baseline-block event (stationary driving scene)';
eInfoDesc.trial_type.Levels.block_start  = 'Start of a recording block';
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
HED.baseline_block    = 'Event, Experimental-block, Description/Stationary-driving-scene baseline block';
HED.baseline_trial    = 'Event, Experimental-trial, Description/Baseline trial onset, Visual-event, Driving-scene';
HED.baseline_dev      = 'Event, Experimental-trial, Description/Baseline deviation, Visual-event, Road-deviation';
HED.experiment_block  = 'Event, Experimental-block, Description/Collision-hazard experimental block';
HED.collision_trial   = 'Event, Experimental-trial, Description/Collision trial start, Visual-event, Driving-scene';
HED.collision_pop     = 'Event, Sensory-event, Auditory-event, Tire-blowout-sound, Visual-event, Driving-scene-collision';
HED.no_collision_pop  = 'Event, Experimental-trial-timepoint, Description/Time-matched control in no-collision trial, Visual-event, Driving-scene';
HED.no_collision_trl  = 'Event, Experimental-trial, Description/No-collision trial start, Visual-event, Driving-scene';

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
        assert(~isempty(raw_txt), 'no main RAW file');
        nRuns = numel(raw_txt);

        stage_dir = fullfile(tempdir, 'galea_bids_stage');
        if ~exist(stage_dir, 'dir'), mkdir(stage_dir); end
        files_i = cell(1, nRuns); runs_i = 1:nRuns;
        for iRun = 1:nRuns
            [EEG_raw, ~, ~, ~, ~, ~, ~] = galea_import('custom', raw_txt(iRun).name, sub_dir);
            EEG_raw = galea_rename_events(EEG_raw);

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
            EEG_raw = eeg_checkset(EEG_raw);

            % bids_export deletes its target dir, so export goes to a staging
            % folder in temp and is moved into place afterwards.
            % unique staged filename per run (BIDS run entity comes from
            % data(iSub).run below); suffix only when there are several runs
            if nRuns > 1
                EEG_raw.setname = sprintf('%s_task-drivinghazard_run-%02d', sub, iRun);
            else
                EEG_raw.setname = sprintf('%s_task-drivinghazard', sub);
            end
            pop_saveset(EEG_raw, 'filename', [EEG_raw.setname '.set'], 'filepath', stage_dir);
            files_i{iRun} = fullfile(stage_dir, [EEG_raw.setname '.set']);
        end
        data(iSub).file    = files_i;
        data(iSub).session = ones(1, nRuns);
        data(iSub).run     = runs_i;

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
            base = sprintf('%s_task-drivinghazard_proc_epoched%s', sub, run_tag);
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
            jsonwrite(fullfile(proc_dir, [base '_events.json']), eInfoDesc, struct('indent', '  '));
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
    'exportformat', 'eeglab');

% move the staged derivative into the exported tree
if exist(fullfile(tempdir, 'galea_bids_stage', 'derivatives'), 'dir')
    moved = movefile(fullfile(tempdir, 'galea_bids_stage', 'derivatives'), fullfile(bids_root, 'derivatives'));
    fprintf('Derivative moved into BIDS tree: %d\n', moved);
end

fprintf('\nDONE: %d subjects exported, %d failed.\nBIDS root: %s\n', nOK, nFail, bids_root);