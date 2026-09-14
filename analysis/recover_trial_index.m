%% Recover which original trial each analysed epoch came from
%
% WHY. Two analyses need to know a trial's POSITION in the 120-trial sequence:
% the preregistered gambler's-fallacy run-length control (q16, q17), and a
% trial-level test of whether the pre-stimulus EEG cluster is volume-conducted
% ocular/muscular activity. Neither is possible at present, because nothing on
% disk links an analysed epoch back to its place in the sequence:
%
%   - ERP_EEG_new.mat predates the pipeline's trialinfo export and carries no
%     trial numbering; crash.epoch holds only event/type/latency/duration and
%     urevent is empty.
%   - Artefact subspace reconstruction removes segments from the continuous
%     data and pop_epoch then drops any epoch spanning a resulting boundary,
%     so the retained set is a non-contiguous subset of the 120.
%   - The ASR sample mask is not saved: sInfo keeps only artifact_portion, a
%     scalar, and the saved .set etc field holds only eeglabvers.
%
% Recovering the alignment arithmetically does not work - the retained
% condition sequence embeds in the true sequence in many ways (8 for sub-001,
% 120 for sub-013, 7.6e7 for sub-002), and run length needs the exact
% predecessor, so a non-unique embedding is useless.
%
% WHAT THIS DOES. Replays only the part of the pipeline that determines which
% epochs survive - filtering, the STORED bad-channel selection, and ASR - and
% reads off the surviving stimulus events. ICA is not replayed: it changes the
% data but not its length and creates no boundaries, so it cannot change which
% epochs pop_epoch keeps. Bad-channel DETECTION is not replayed either; the
% result is stored in sInfo.badChan and is applied directly, which removes the
% only step whose reproducibility would be in doubt.
%
% There is no re-referencing anywhere in the pipeline - it is not possible at
% this channel count - so none is applied here.
%
% READ-ONLY. sInfo.mat is never written. The pipeline saves to it at several
% points; those lines are deliberately not replayed.
%
% SELF-CHECK. Each participant's reproduced artifact_portion is compared with
% the value stored by the original run. That is a four-decimal fingerprint of
% the ASR result, so a replay that diverged for any reason will not match, and
% the script says so rather than emitting a plausible but wrong mapping. The
% surviving trial counts are additionally checked against sInfo.n_crash and
% n_nocrash.
%
% Cedric Cannard, September 2026

clear; close all; clc
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
addpath(paths.eeglab); eeglab nogui;
addpath(paths.pipeline_functions);
addpath(paths.plugin_functions);
data_path   = paths.data;
out_path    = paths.res_tf_causal;
if ~exist(out_path,'dir'), mkdir(out_path); end

% Parameters, verbatim from galea_pipeline_v6_EEG.m
causal_filt  = true;
filt_cutoffs = [0.5 30];
asr_sd       = 100;
epoch_lims   = [-3 3];
EXCLUDE      = {'sub-000','sub-005','sub-009'};

S = load(fullfile(data_path, 'sInfo.mat'));   % never written back
sInfo = S.sInfo;
names = arrayfun(@(s) sprintf('sub-%03d', s.subject), sInfo, 'UniformOutput', false);
sInfo = sInfo(~ismember(names, EXCLUDE));
nFile = numel(sInfo);
fprintf('Recording files to replay: %d\n\n', nFile);

rec = struct('subject', {}, 'file', {}, 'portion_stored', {}, 'portion_replay', {}, ...
             'portion_ok', {}, 'kept_events', {}, 'counts_ok', {}, 'set_ok', {});

for i = 1:nFile
    fprintf('--- sub-%03d : %s\n', sInfo(i).subject, sInfo(i).filename);

    EEG = galea_import('custom', sInfo(i).filename, sInfo(i).filepath);
    EEG = galea_rename_events(EEG);

    % CRITICAL. galea_import was changed after these data were processed: it now
    % snaps the measured rate to the board's nominal 250 Hz, where the original
    % run used the measured 248 Hz. Every filter, the +/-1 s trim, the ASR
    % window and every epoch boundary depend on srate, so leaving it at 250
    % makes the replay diverge from the archived result. Take the rate from the
    % dataset the pipeline actually saved.
    setName = strrep(sInfo(i).filename, '.txt', '.set');
    if isfile(fullfile(sInfo(i).filepath, setName))
        D0 = pop_loadset('filename', setName, 'filepath', sInfo(i).filepath, 'loadmode', 'info');
        if abs(EEG.srate - D0.srate) > 1e-6
            fprintf('    srate: import gives %.4f, archived run used %.4f - overriding\n', ...
                EEG.srate, D0.srate);
            EEG.srate = D0.srate;
        end
    end

    % Trim, exactly as the pipeline does. sInfo.events was stored AFTER this,
    % so its latencies are already in the trimmed frame.
    EEG = pop_select(EEG, 'nopoint', [0 EEG.event(1).latency - EEG.srate*1]);
    EEG = pop_select(EEG, 'nopoint', [EEG.event(end).latency + EEG.srate*1 EEG.pnts]);

    EEG = pop_eegfiltnew(EEG, 'hicutoff', filt_cutoffs(2), 'minphase', causal_filt);
    EEG = pop_eegfiltnew(EEG, 'locutoff', filt_cutoffs(1), 'minphase', causal_filt);
    EEG = fix_polarity(EEG, {'Fp1','Fp2'}, 8, 0.5);

    TMPEEG = pop_eegfiltnew(EEG, 'locutoff', 1, 'minphase', causal_filt);  % the ASR/ICA copy

    % Stored bad channels, not re-detected
    badChan = logical(sInfo(i).badChan(:))';
    assert(numel(badChan) == EEG.nbchan, ...
        'sub-%03d: stored badChan has %d entries but the import gives %d channels', ...
        sInfo(i).subject, numel(badChan), EEG.nbchan);
    if any(badChan)
        labels = {EEG.chanlocs(badChan).labels};
        TMPEEG = pop_select(TMPEEG, 'nochannel', labels);
        EEG    = pop_select(EEG,    'nochannel', labels);
    end

    cleanEEG = clean_asr(TMPEEG, asr_sd, [],[],[],[],[],[],[], false, []);
    mask     = sum(abs(TMPEEG.data - cleanEEG.data), 1) > 1e-10;
    portion  = sum(mask) / length(mask);

    ok = abs(portion - sInfo(i).artifact_portion) < 1e-6;
    fprintf('    artifact_portion  stored %.6f  replay %.6f  %s\n', ...
        sInfo(i).artifact_portion, portion, string(ok));

    % Segments actually removed (the pipeline drops runs of <= 5 samples)
    badData = reshape(find(diff([false mask false])), 2, [])';
    badData(:,2) = badData(:,2) - 1;
    badData(diff(badData,[],2) <= 5, :) = [];

    % Which stimulus events survive epoching: an epoch is dropped if its window
    % overlaps a removed segment or runs off either end of the recording.
    ev      = sInfo(i).events;
    isStim  = ismember({ev.type}, {'tire_pop','no_tire_pop'});
    stimIdx = find(isStim);
    lat     = [ev(isStim).latency];
    half    = EEG.srate * abs(epoch_lims(1));
    nPnts   = numel(mask);

    % Boundaries that already existed BEFORE ASR - from the head and tail trims,
    % and from any discontinuity in the recording itself. pop_epoch drops any
    % epoch containing one of these too, not just the ones ASR creates. sub-012
    % has two such boundaries and loses four trials to them; without this the
    % replay over-counts that participant by exactly four.
    bLat = [ev(strcmp({ev.type}, 'boundary')).latency];

    kept = true(1, numel(lat));
    for t = 1:numel(lat)
        lo = lat(t) - half; hi = lat(t) + EEG.srate*epoch_lims(2);
        if lo < 1 || hi > nPnts, kept(t) = false; continue; end
        if any(badData(:,1) <= hi & badData(:,2) >= lo), kept(t) = false; continue; end
        if any(bLat > lo & bLat < hi), kept(t) = false; end
    end

    % The pipeline then drops sInfo.bad_trials, indexed into the epochs that
    % survived above, in order.
    survivors = find(kept);
    bt = sInfo(i).bad_trials;
    if ~isempty(bt)
        bt = bt(bt >= 1 & bt <= numel(survivors));
        kept(survivors(bt)) = false;
    end

    types  = {ev(stimIdx).type};
    nCrash = sum(kept & strcmp(types, 'tire_pop'));
    nNo    = sum(kept & strcmp(types, 'no_tire_pop'));
    cok    = (nCrash == sInfo(i).n_crash) && (nNo == sInfo(i).n_nocrash);
    fprintf('    trials kept %d crash / %d no-crash   (sInfo %d / %d)  %s\n', ...
        nCrash, nNo, sInfo(i).n_crash, sInfo(i).n_nocrash, string(cok));

    % Third, independent check: the epoched .set saved by the pipeline IS the
    % analysed dataset, so its trial count is ground truth. sub-011's two .set
    % files are what fix_sub011_erp_export.m rebuilt the ERP exports from
    % (66 and 22 epochs), so they are authoritative for that participant too.
    setOK = NaN;
    if isfile(fullfile(sInfo(i).filepath, setName))
        D = pop_loadset('filename', setName, 'filepath', sInfo(i).filepath, 'loadmode', 'info');
        setOK = (D.trials == nCrash + nNo);
        fprintf('    saved .set has %d epochs, replay kept %d  %s\n', ...
            D.trials, nCrash + nNo, string(setOK));
    end
    fprintf('\n');

    rec(end+1) = struct('subject', sInfo(i).subject, 'file', sInfo(i).filename, ...
        'portion_stored', sInfo(i).artifact_portion, 'portion_replay', portion, ...
        'portion_ok', ok, 'kept_events', {{kept, stimIdx, types}}, 'counts_ok', cok, 'set_ok', setOK); %#ok<SAGROW>
end

%% ---- verdict --------------------------------------------------------------
pOK = [rec.portion_ok];  cOK = [rec.counts_ok];
fprintf('\n================== REPLAY VERDICT ==================\n');
fprintf('  artifact_portion matches : %d of %d files\n', sum(pOK), numel(pOK));
fprintf('  trial counts match       : %d of %d files\n', sum(cOK), numel(cOK));
% Usability is decided PER FILE, not all-or-nothing. A file whose ASR portion,
% condition counts and archived .set epoch total all agree has a mapping
% verified three independent ways; one file failing does not contaminate the
% others. Downstream analyses must filter on rec.usable.
%
% A count mismatch is disqualifying even though it looks small: bad_trials is
% indexed into the epoched set, so if the replay retains a different number of
% epochs, those indices land on DIFFERENT trials. The identities are wrong, not
% just the total, and run length depends on the exact predecessor.
for i = 1:numel(rec)
    rec(i).usable = rec(i).portion_ok && rec(i).counts_ok && ...
        (isnan(rec(i).set_ok) || rec(i).set_ok == 1);
end
uOK = [rec.usable];
fprintf('  files with a VERIFIED mapping : %d of %d\n', sum(uOK), numel(uOK));
if ~all(uOK)
    disp('  Not verified - excluded from any trial-level analysis:');
    for i = find(~uOK)
        fprintf('    sub-%03d %s  portion %d  counts %d  set %d\n', ...
            rec(i).subject, rec(i).file, rec(i).portion_ok, rec(i).counts_ok, rec(i).set_ok);
    end
end

save(fullfile(out_path, 'trial_index_recovery.mat'), 'rec');
fprintf('\nwrote %s\n', fullfile(out_path, 'trial_index_recovery.mat'));
