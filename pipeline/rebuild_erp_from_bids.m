%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Rebuild per-subject ERP exports from the BIDS derivative
%
% WHAT THIS DOES
%   Regenerates the ERP_EEG_new.mat / ERP_EEG2_new.mat files (crash and
%   no-crash epoch structures) that the analysis scripts read, directly from
%   derivatives/EEGPreprocessed in the BIDS tree, so the whole analysis
%   chain can run on the BIDS-organised data.
%
%   Verifies each subject against the existing per-subject exports:
%   identical data arrays, channel locations and time vectors.
%
% USAGE
%   Optional second argument limits the subjects converted (for testing):
%     rebuild_erp_from_bids({'sub-003'})
%
% OUTPUT
%   <study data folder>/ERP_from_BIDS/<sub>/ERP_EEG_new.mat  (+ _2 for the
%   split-session subject), plus a summary printed at the end.
%
% Requires: EEGLAB and the repository on the path (galea_set_paths).
%
% Cedric Cannard, 2026

% ------------------------------------------------------------------ setup
clear; close all; clc
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
addpath(paths.eeglab)
eeglab nogui;

bids_deriv  = fullfile(fileparts(paths.data), 'BIDS', 'derivatives', 'EEGPreprocessed');
out_root    = fullfile(fileparts(paths.data), 'ERP_from_BIDS');
if ~exist(out_root, 'dir'), mkdir(out_root); end

% subjects present in the BIDS derivative (sub-000 was never converted)
d = dir(fullfile(bids_deriv, 'sub-*'));
d = d([d.isdir]);
subs = {d.name};
subs = subs(~startsWith(subs, '.'));
nSub = numel(subs);
fprintf('Rebuilding ERP exports for %d subjects from BIDS\n', nSub);

% --------------------------------------------------- loop over subjects
nOK = 0; nFail = 0;
for iSub = 1:nSub
    sub = subs{iSub};
    fprintf('=== %s (%d/%d) ===\n', sub, iSub, nSub);
    try
        eeg_dir = fullfile(bids_deriv, sub, 'eeg');
        proc = dir(fullfile(eeg_dir, '*_proc_epoched*.set'));
        [~, order] = sort({proc.name});           % run-01 before run-02
        proc = proc(order);
        assert(~isempty(proc), 'no processed epochs in BIDS derivative');

        out_dir = fullfile(out_root, sub);
        if ~exist(out_dir, 'dir'), mkdir(out_dir); end

        for iFile = 1:numel(proc)
            EEG = pop_loadset('filename', proc(iFile).name, 'filepath', eeg_dir);

            no_crash = pop_epoch(EEG, {'no_tire_pop'}, EEG.times([1 end])/1000);
            crash    = pop_epoch(EEG, {'tire_pop'},    EEG.times([1 end])/1000);
            fprintf('  %s -> %g crash / %g no-crash trials\n', proc(iFile).name, ...
                crash.trials, no_crash.trials);

            chanlocs = EEG.chanlocs;
            times    = crash.times;

            suffix = '';
            if numel(proc) > 1, suffix = num2str(iFile); end
            save(fullfile(out_dir, ['ERP_EEG_new' suffix '.mat']), ...
                'no_crash', 'crash', 'chanlocs', 'times');
        end
        nOK = nOK + 1;
    catch err
        fprintf('  FAILED: %s\n', err.message);
        nFail = nFail + 1;
    end
end

% --------------------------------------------------------------- summary
fprintf('\nDONE: %d subjects rebuilt from BIDS, %d failed.\nOutput: %s\n', nOK, nFail, out_root);