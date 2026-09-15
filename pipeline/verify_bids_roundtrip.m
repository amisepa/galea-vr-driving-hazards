%% Verify the BIDS-rebuilt ERP exports against the originals
%
% For every subject, loads ERP_from_BIDS/<sub>/ERP_EEG_new.mat and the
% original <study data>/<sub>/ERP_EEG_new.mat (legacy layout) and checks
% that crash / no-crash data, channel locations and time vectors are
% identical. sub-011 also compares the run-2 files.
%
% Known round-trip differences (documented, both outside the analysed windows):
% 1. The BIDS .set drops the original's single trailing sample at ~+2996 ms
%    (1488 -> 1487 samples per epoch) when bids_export re-saves the dataset.
% 2. The time vector is recomputed from the sampling rate on load, so it can
%    differ from the saved one by float rounding at the same step and start.
% The analyses never use data beyond +/-1200 ms, so equivalence is defined as:
% identical data over the shared samples, identical chanlocs, same time step
% and start (times compared with a 1e-3 ms tolerance).
%
% Cedric Cannard, 2026

paths = galea_set_paths();
legacy_root = paths.data;
bids_root   = fullfile(fileparts(paths.data), 'ERP_from_BIDS');

d = dir(fullfile(bids_root, 'sub-*'));
d = d([d.isdir]);
subs = {d.name};
nSub = numel(subs);

nSame = 0; nDiff = 0; nNoRef = 0; report = cell(nSub, 1);
for iSub = 1:nSub
    sub = subs{iSub};
    f_new_file = fullfile(bids_root, sub, 'ERP_EEG_new.mat');
    if ~isfile(f_new_file)
        f_new_file = fullfile(bids_root, sub, 'ERP_EEG_new1.mat');  % split-session subject
    end
    f_new = load(f_new_file);
    f_old_file = fullfile(legacy_root, sub, 'ERP_EEG_new.mat');
    if ~isfile(f_old_file)
        report{iSub} = sprintf('%s  NO ORIGINAL (subject excluded from analyses)', sub);
        nNoRef = nNoRef + 1;
        continue
    end
    f_old = load(f_old_file);

    same = isequal(f_new.chanlocs, f_old.chanlocs) && ...
           abs(f_new.times(1) - f_old.times(1)) < 1e-3 && ...
           abs(mean(diff(f_new.times)) - mean(diff(f_old.times))) < 1e-3;

    % data: identical over the shared window (BIDS may lack the trailing sample)
    nb = size(f_new.crash.data, 2);
    same = same && isequal(size(f_old.crash.data, 1), size(f_new.crash.data, 1)) && ...
                   isequal(size(f_old.crash.data, 3), size(f_new.crash.data, 3));
    if same
        old_cr = f_old.crash.data(:, 1:nb, :); old_nc = f_old.no_crash.data(:, 1:nb, :);
        same = same && isequal(f_new.crash.data, old_cr) && ...
                       isequal(f_new.no_crash.data, old_nc);
    end
    same = same && abs(f_new.times(end) - f_old.times(nb)) < 1e-3;

    % sub-011's second session
    f2_new = fullfile(bids_root, sub, 'ERP_EEG_new2.mat');
    f2_old = fullfile(legacy_root, sub, 'ERP_EEG2_new.mat');
    if isfile(f2_new) && isfile(f2_old)
        g_new = load(f2_new); g_old = load(f2_old);
        nb2 = size(g_new.crash.data, 2);
        same = same && isequal(g_new.crash.data, g_old.crash.data(:, 1:nb2, :)) && ...
                       isequal(g_new.no_crash.data, g_old.no_crash.data(:, 1:nb2, :));
    end

    if same
        truncated = size(f_old.crash.data, 2) > size(f_new.crash.data, 2);
        if truncated
            report{iSub} = sprintf('%s  IDENTICAL (original had 1 extra trailing sample, outside analysed windows)', sub);
        else
            report{iSub} = sprintf('%s  IDENTICAL', sub);
        end
        nSame = nSame + 1;
    else
        msg = sprintf('%s  DIFFER:', sub);
        if ~isequal(size(f_new.crash.data), size(f_old.crash.data(:, 1:size(f_new.crash.data, 2), :)))
            msg = [msg sprintf(' crash size %s vs %s', mat2str(size(f_new.crash.data)), mat2str(size(f_old.crash.data)))];
        else
            old_cr = f_old.crash.data(:, 1:size(f_new.crash.data, 2), :);
            msg = [msg sprintf(' crash maxdiff %.3g', max(abs(f_new.crash.data(:) - old_cr(:)), [], 'all'))];
        end
        report{iSub} = msg;
        nDiff = nDiff + 1;
    end
end
fprintf('%s\n', strjoin(report, newline));
fprintf('\nVERDICT: %d identical, %d different, %d without original (of %d)\n', nSame, nDiff, nNoRef, nSub);