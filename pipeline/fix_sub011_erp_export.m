%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Repair sub-011 ERP export
%
% PROBLEM
%   sub-011's session was split into two recordings:
%       OpenBCI-RAW-2025-05-05_14-17-12_trials1-98.set      -> 66 epochs (38 crash / 28 no-crash)
%       OpenBCI-RAW-2025-05-05_14-44-30_after-trial98.set   -> 22 epochs (15 crash /  7 no-crash)
%
%   Both ERP_EEG_new.mat and ERP_EEG2_new.mat currently contain the SAME data
%   (the 22-epoch second session). The first session's ERP export was
%   overwritten because galea_pipeline_v5_EEG.m always saves to the hardcoded
%   filename "ERP_EEG_new.mat".
%
%   Consequence: galea_group_analysis_EEG.m and galea_group_analysis_EEG_tf.m
%   concatenate the two files, so sub-011 enters the group analysis with
%   30 crash / 14 no-crash trials that are exact duplicates of 15 / 7 unique
%   trials -- duplicated observations in the Level-1 GLM, and far below the
%   preregistered minimum of 30 artifact-free trials per condition.
%
% FIX
%   Re-export both sessions from the epoched .set files that are still intact.
%   After running this, sub-011 has 53 crash / 35 no-crash unique trials,
%   which clears the preregistered threshold.
%
% NOTE
%   The .set files were saved after ASR/ICA/epoch rejection, so no
%   preprocessing is repeated here -- this only rebuilds the .mat exports.
%
% Cedric Cannard, August 2026

clear; close all; clc
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
addpath(paths.eeglab)
eeglab nogui;

subFolder = fullfile(paths.data, 'sub-011');

sets = { ...
    'OpenBCI-RAW-2025-05-05_14-17-12_trials1-98.set',    'ERP_EEG_new.mat'; ...
    'OpenBCI-RAW-2025-05-05_14-44-30_after-trial98.set', 'ERP_EEG2_new.mat'};

for iFile = 1:size(sets, 1)

    setFile = sets{iFile, 1};
    outFile = sets{iFile, 2};

    EEG = pop_loadset('filepath', subFolder, 'filename', setFile);

    no_crash = pop_epoch(EEG, {'no_tire_pop'}, EEG.times([1 end])/1000);
    crash    = pop_epoch(EEG, {'tire_pop'},    EEG.times([1 end])/1000);

    fprintf('%s -> %g crash / %g no-crash trials\n', ...
        setFile, crash.trials, no_crash.trials);

    chanlocs = EEG.chanlocs;
    times    = crash.times;

    % Back up whatever is there before overwriting
    existing = fullfile(subFolder, outFile);
    if isfile(existing)
        movefile(existing, [existing '.bak_' datestr(now, 'yyyymmdd_HHMMSS')]);
    end

    save(fullfile(subFolder, outFile), 'no_crash', 'crash', 'chanlocs', 'times')
end

%% Verify

d1 = load(fullfile(subFolder, 'ERP_EEG_new.mat'));
d2 = load(fullfile(subFolder, 'ERP_EEG2_new.mat'));

nCrash   = size(d1.crash.data, 3)    + size(d2.crash.data, 3);
nNoCrash = size(d1.no_crash.data, 3) + size(d2.no_crash.data, 3);

fprintf('\nMerged sub-011: %g crash / %g no-crash trials\n', nCrash, nNoCrash);

if isequal(size(d1.crash.data), size(d2.crash.data)) && ...
        isequal(d1.crash.data, d2.crash.data)
    error('Files are still identical -- repair failed.')
end

if nCrash < 30 || nNoCrash < 30
    warning('sub-011 still below the preregistered 30-trials-per-condition threshold.')
else
    fprintf('sub-011 clears the preregistered 30-trials-per-condition threshold.\n')
end
