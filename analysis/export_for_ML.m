%% Export the repaired data for the classification analyses
%
% Produces one self-contained, portable file so the ML/DL work can be re-run
% without access to the raw recordings. Saved as MAT v7 so it loads in MATLAB
% (v7 rather than v7.3 so it loads everywhere without HDF5 support).
%
% Contents:
%   ERP_avg      [nSub x 2 x nChan x nTime]  subject-averaged ERPs, robust
%                                            (Huber) mean over trials.
%                                            Index 1 = collision, 2 = no collision.
%   ERP_times    [1 x nTime]   ms relative to the tyre-pop event
%   chan_labels  {1 x nChan}   front-to-back order
%   subjects     {nSub x 1}    subject IDs, aligned with ERP_avg rows
%   n_trials     [nSub x 2]    trials contributing to each average
%
%   HR_avg       [nSubHR x 2 x nTimeHR]  subject-averaged heart rate (bpm)
%   HR_times     [1 x nTimeHR]           seconds relative to the event
%   HR_subjects  {nSubHR x 1}            subject IDs for the HR rows
%   both_idx     struct with the EEG and HR row indices of the subjects that
%                have BOTH modalities, for multimodal analyses
%
% Cedric Cannard, August 2026

clear; clc
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
data_path = paths.data;
out_file  = paths.ml_dataset;
addpath(paths.robust)
addpath(fullfile(paths.robust, 'functions'))

%% ---------------- EEG ----------------
sl = dir(data_path); sl = sl(contains({sl.name},'sub-'));
for b = {'sub-000','sub-005','sub-009'}, sl(strcmp({sl.name},b{1})) = []; end
nSub = numel(sl);

new_order = {'Fp1','Fp2','F1','F2','CZ','C3','C4','PZ','P3','P4','O1','O2'};
subjects = cell(nSub,1); n_trials = zeros(nSub,2);

% sub-011 was re-epoched during the repair and ends one sample short of the
% others (1487 vs 1488). All epochs start at -3000 ms with the same step, so
% trim everyone to the shortest common length rather than assume equal size.
nSamp = inf; t_ref = [];
for i = 1:nSub
    d = load(fullfile(data_path, sl(i).name, 'ERP_EEG_new.mat'), 'crash');
    if numel(d.crash.times) < nSamp
        nSamp = numel(d.crash.times);
        t_ref = d.crash.times(:)';
    end
end
ERP_times = t_ref(1:nSamp);
ERP_avg = nan(nSub, 2, numel(new_order), nSamp);
fprintf('Common epoch length: %d samples (%.0f to %.0f ms)\n\n', ...
    nSamp, ERP_times(1), ERP_times(end));

for i = 1:nSub
    sf = fullfile(data_path, sl(i).name);
    d  = load(fullfile(sf,'ERP_EEG_new.mat'));
    if strcmpi(sl(i).name,'sub-011')
        d2 = load(fullfile(sf,'ERP_EEG2_new.mat'));
        assert(~isequal(d.crash.data, d2.crash.data), ...
            'sub-011 files identical - run fix_sub011_erp_export.m first!');
        d.crash.data    = cat(3, d.crash.data,    d2.crash.data);
        d.no_crash.data = cat(3, d.no_crash.data, d2.no_crash.data);
    end
    [~,idx] = ismember(new_order, {d.chanlocs.labels});
    C = d.crash.data(idx,1:nSamp,:);  N = d.no_crash.data(idx,1:nSamp,:);
    assert(max(abs(d.crash.times(1:nSamp) - ERP_times)) < 1e-6, ...
        'time vector mismatch for %s', sl(i).name);

    ERP_avg(i,1,:,:) = compute_robust_erp(C, 'huber');
    ERP_avg(i,2,:,:) = compute_robust_erp(N, 'huber');
    subjects{i}  = sl(i).name;
    n_trials(i,:) = [size(C,3) size(N,3)];
    fprintf('%s: %d crash / %d no-crash\n', sl(i).name, n_trials(i,1), n_trials(i,2));
end
chan_labels = new_order;

%% ---------------- HEART RATE ----------------
HR_avg = []; HR_subjects = {}; HR_times = [];
for i = 1:nSub
    f = fullfile(data_path, sl(i).name, 'ERP_PPG.mat');
    if ~isfile(f) || strcmpi(sl(i).name,'sub-011'), continue; end   % sub-011 session was split
    h = load(f);
    if ~isfield(h,'crash') || isempty(h.crash), continue; end
    if isempty(HR_times)
        if isfield(h,'times'), HR_times = h.times(:)'; else, HR_times = linspace(-5,5,size(h.crash,1)); end
        HR_avg = nan(nSub, 2, numel(HR_times));
    end
    HR_avg(numel(HR_subjects)+1,1,:) = mean(h.crash,  2,'omitnan');
    HR_avg(numel(HR_subjects)+1,2,:) = mean(h.nocrash,2,'omitnan');
    HR_subjects{end+1,1} = sl(i).name; %#ok<SAGROW>
end
HR_avg = HR_avg(1:numel(HR_subjects),:,:);
fprintf('\nHR available for %d subjects\n', numel(HR_subjects));

%% ---------------- subjects with BOTH modalities ----------------
[~, ia, ib] = intersect(subjects, HR_subjects, 'stable');
both_idx = struct('eeg_rows', ia, 'hr_rows', ib, 'subjects', {subjects(ia)});
fprintf('Subjects with BOTH EEG and HR: %d\n', numel(ia));
disp(subjects(ia)')

%% ---------------- save ----------------
save(out_file, 'ERP_avg','ERP_times','chan_labels','subjects','n_trials', ...
     'HR_avg','HR_times','HR_subjects','both_idx','-v7');
d = dir(out_file);
fprintf('\nWrote %s (%.1f MB)\n', out_file, d.bytes/1e6);
fprintf('EEG: %d subjects x 2 conditions x %d channels x %d samples\n', ...
    nSub, numel(chan_labels), numel(ERP_times));
