%% Trial-level test: is the pre-stimulus EEG cluster peripheral activity?
%
% The causal time-frequency analysis leaves a broadband 3-30 Hz pre-stimulus
% cluster (-641 to -464 ms). The ocular and muscular channels show a
% same-direction broadband increase in the same window on all six electrodes.
% Eye and muscle activity volume-conduct to scalp electrodes, so the two cannot
% be separated by inspection.
%
% WHY THIS SUPERSEDES diagnose_prestim_mediation.m. That script had to work
% between participants, because at the time nothing on disk linked an analysed
% EEG epoch back to its position in the delivered sequence: artefact subspace
% reconstruction removed segments from the continuous EEG and pop_epoch then
% dropped epochs spanning the resulting boundaries, while the peripheral
% streams never went through ASR. analysis/recover_trial_index.m replays the
% pipeline and recovers that link, verified three independent ways per file, so
% the two streams can now be matched TRIAL BY TRIAL. With N = 16 the
% between-participant correlation had a confidence interval wide enough to be
% uninformative either way; the trial-level version has ~100 observations per
% participant and actually has power.
%
% ALIGNMENT, WHICH IS THE WHOLE DIFFICULTY.
%   - Peripheral epochs are cut MANUALLY at the latencies in sInfo.events,
%     after applying the same two trims the pipeline applied, so the sample
%     frame matches the one the trial index was recovered in.
%   - pop_epoch is deliberately NOT used. It would drop first/last epochs by
%     its own end-of-recording rule, which differs here because the peripheral
%     stream is not shortened by ASR, and the sets would silently desynchronise.
%   - sInfo.bad_trials is likewise NOT applied to the peripheral data. Those
%     indices are relative to the POST-ASR epoch set; applied to a longer set
%     they remove different trials. diagnose_ocular_muscle.m does exactly this,
%     which is tolerable for a group mean but fatal for a trial-level join.
%     Trials are instead selected by the recovered kept-mask, which already has
%     bad_trials folded in.
%   - The 248 Hz srate override from recover_trial_index.m is repeated, for the
%     same reason: every latency depends on it.
%
% WHAT MEDIATION CAN AND CANNOT SHOW HERE. Peripheral activity is not
% randomised, so a mediation model is descriptive, not causal. If the direct
% effect collapses once peripheral power is in the model, the cluster is
% plausibly volume conduction. If it survives with the peripheral path itself
% significant, the two are related but the EEG effect is not reducible to them.
% Neither outcome is proof; the direction and magnitude of the change is the
% evidence.
%
% Cedric Cannard, September 2026

clear; close all; clc
rng(2026,'twister')
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
addpath(paths.eeglab); eeglab nogui;
addpath(paths.pipeline_functions);
addpath(paths.plugin_functions);
addpath(paths.analysis);
data_path = paths.data;
RES       = paths.res_tf_causal;

WIN        = [-641 -464];       % the causal cluster window, ms
CUTOFFS    = [0.5 30];
EPOCH_LIMS = [-3 3];

S  = load(fullfile(RES,'none','pre-stim','TF_stats_pre.mat'), 'mask','time','foi');
C  = load(fullfile(RES,'causal_power_cache.mat'), 'RAW_CRASH','RAW_NOCRASH','times_ref');
R  = load(fullfile(RES,'trial_index_recovery.mat'), 'rec');
SI = load(fullfile(data_path,'sInfo.mat'));  sInfo = SI.sInfo;
rec = R.rec;

box  = logical(S.mask);
tsel = ismember(round(C.times_ref,3), round(S.time,3));
assert(sum(tsel) == numel(S.time), 'cluster time axis does not align to the cache');

usable   = [rec.usable];
subjOf   = [rec.subject];
uSub     = unique(subjOf(usable));
cacheSub = unique(subjOf);                 % cache cells follow this order
fprintf('Participants with a verified trial index: %d\n\n', numel(uSub));

%% ---- build the trial table ----------------------------------------------
T = table();
for k = 1:numel(uSub)
    s  = uSub(k);
    ci = find(cacheSub == s, 1);

    % EEG cluster power, one value per retained trial, crash then no-crash
    cP = 10*log10(C.RAW_CRASH{ci}(:, tsel, :));
    nP = 10*log10(C.RAW_NOCRASH{ci}(:, tsel, :));
    powC = zeros(1,size(cP,3));
    for t = 1:size(cP,3), sl = cP(:,:,t); powC(t) = mean(sl(box)); end
    powN = zeros(1,size(nP,3));
    for t = 1:size(nP,3), sl = nP(:,:,t); powN(t) = mean(sl(box)); end

    cond = []; perAll = []; chanNames = {};
    for f = find(subjOf == s & usable)
        fi = find(arrayfun(@(x) strcmp(x.filename, rec(f).file), sInfo), 1);

        [EEGraw, EOG, EMG] = galea_import('custom', sInfo(fi).filename, sInfo(fi).filepath);
        EEGraw = galea_rename_events(EEGraw);
        EOG.event = EEGraw.event;
        AUX = EOG;
        if ~isempty(EMG) && EMG.nbchan > 0
            EMG.event    = EEGraw.event;
            AUX.data     = [EOG.data; EMG.data];
            AUX.nbchan   = EOG.nbchan + EMG.nbchan;
            AUX.chanlocs = [EOG.chanlocs, EMG.chanlocs];
        end

        % srate override - identical reason to recover_trial_index.m
        setName = strrep(sInfo(fi).filename, '.txt', '.set');
        if isfile(fullfile(sInfo(fi).filepath, setName))
            D0 = pop_loadset('filename', setName, 'filepath', sInfo(fi).filepath, ...
                'loadmode', 'info');
            AUX.srate = D0.srate;  EEGraw.srate = D0.srate;
        end

        % The pipeline's two trims, so latencies match sInfo.events. The second
        % trim must read AUX's OWN event latencies AFTER the first one: the head
        % trim shifts every latency, so using the untrimmed values overshoots the
        % end of the data. recover_trial_index.m does the same and this must
        % match it sample for sample.
        AUX = eeg_checkset(AUX, 'eventconsistency');
        AUX = pop_select(AUX, 'nopoint', [0 AUX.event(1).latency - AUX.srate*1]);
        AUX = pop_select(AUX, 'nopoint', [AUX.event(end).latency + AUX.srate*1 AUX.pnts]);

        AUX = pop_eegfiltnew(AUX, 'hicutoff', CUTOFFS(2), 'minphase', true);
        AUX = pop_eegfiltnew(AUX, 'locutoff', CUTOFFS(1), 'minphase', true);
        if isempty(chanNames), chanNames = {AUX.chanlocs.labels}; end

        ev      = sInfo(fi).events;
        isStim  = ismember({ev.type}, {'tire_pop','no_tire_pop'});
        lat     = [ev(isStim).latency];
        types   = {ev(isStim).type};
        kept    = rec(f).kept_events{1};

        % manual epoching, cluster window only
        w0 = round(AUX.srate * WIN(1)/1000);
        w1 = round(AUX.srate * WIN(2)/1000);
        idx = find(kept);
        P = nan(AUX.nbchan, numel(idx));
        for t = 1:numel(idx)
            a = round(lat(idx(t))) + w0;  b = round(lat(idx(t))) + w1;
            assert(a >= 1 && b <= AUX.pnts, ...
                'sub-%03d trial %d: cluster window falls outside the recording', s, idx(t));
            seg = AUX.data(:, a:b);
            P(:,t) = mean(seg.^2, 2);                   % broadband power
        end
        perAll = [perAll, 10*log10(P)];                 %#ok<AGROW>
        cond   = [cond, strcmp(types(idx),'tire_pop')]; %#ok<AGROW>
    end

    % EEG values are stored crash-first; scatter them back into sequence order
    pow = nan(1, numel(cond));
    assert(sum(cond==1) == numel(powC) && sum(cond==0) == numel(powN), ...
        'sub-%03d: %d/%d retained vs %d/%d cached', s, sum(cond==1), sum(cond==0), ...
        numel(powC), numel(powN));
    pow(cond==1) = powC;  pow(cond==0) = powN;

    ocular = mean(perAll(1:2,:), 1);                    % VEOG, HEOG
    muscle = mean(perAll(3:end,:), 1);                  % EMG
    T = [T; table(repmat(s,numel(cond),1), pow(:), double(cond(:)), ...
        mean(perAll,1)', ocular(:), muscle(:), ...
        'VariableNames', {'sub','eeg','cond','per','ocular','muscle'})]; %#ok<AGROW>
    fprintf('  sub-%03d: %d trials (%d collision / %d no-collision)\n', ...
        s, numel(cond), sum(cond==1), sum(cond==0));
end
fprintf('\nTotal trials: %d\n\n', height(T));

%% ---- within-participant coupling ----------------------------------------
% Before any mediation: are the two streams related at all, trial to trial,
% once condition is partialled out? If they are not, mediation cannot do
% anything and the peripheral explanation is dead on arrival.
fprintf('===== TRIAL-LEVEL COUPLING (condition partialled out) =====\n');
COUP = {};
for src = {'per','ocular','muscle'}
    v = src{1};  rr = nan(numel(uSub),1);
    for k = 1:numel(uSub)
        d = T(T.sub == uSub(k), :);
        ey = d.eeg - [ones(height(d),1) d.cond]*([ones(height(d),1) d.cond]\d.eeg);
        ex = d.(v) - [ones(height(d),1) d.cond]*([ones(height(d),1) d.cond]\d.(v));
        rr(k) = corr(ey, ex);
    end
    z = atanh(rr);  [~,pz,~,sz] = ttest(z);
    fprintf('  %-8s mean partial r = %+.3f   t(%d) = %.2f, p = %.4f   [%d of %d positive]\n', ...
        v, tanh(mean(z)), sz.df, sz.tstat, pz, sum(rr>0), numel(rr));
    COUP(end+1,:) = {v, tanh(mean(z)), sz.tstat, sz.df, pz, sum(rr>0), numel(rr)}; %#ok<SAGROW>
end
% Exported because build_manuscript.js quotes this coupling value in Section 3.5.
% Any statistic the prose names must come from a file, never from a number typed
% into the text: a re-run that moves it would otherwise leave the paper wrong
% with nothing to catch it.
writetable(cell2table(COUP, 'VariableNames', ...
    {'stream','partial_r','t','df','p','n_positive','n'}), ...
    fullfile(RES,'prestim_coupling.csv'));

%% ---- mediation ----------------------------------------------------------
fprintf('\n===== TRIAL-LEVEL MEDIATION =====\n');
out = {};
for src = {'per','ocular','muscle'}
    v = src{1};
    cTot = nan(numel(uSub),1); cDir = nan(numel(uSub),1);
    aPath = nan(numel(uSub),1); bPath = nan(numel(uSub),1);
    for k = 1:numel(uSub)
        d = T(T.sub == uSub(k), :);
        one = ones(height(d),1);
        bt = [one d.cond] \ d.eeg;      cTot(k)  = bt(2);      % total effect
        ba = [one d.cond] \ d.(v);      aPath(k) = ba(2);      % condition -> peripheral
        bf = [one d.cond d.(v)] \ d.eeg;
        cDir(k) = bf(2);  bPath(k) = bf(3);                    % direct, peripheral -> EEG
    end
    ind = cTot - cDir;
    [~,pT,~,sT] = ttest(cTot);   [~,pD,~,sD] = ttest(cDir);
    [~,pA,~,sA] = ttest(aPath);  [~,pB,~,sB] = ttest(bPath);
    [~,pI,~,sI] = ttest(ind);
    fprintf('  --- mediator: %s ---\n', v);
    fprintf('    total  effect of condition on EEG   c  = %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
        mean(cTot), sT.df, sT.tstat, pT);
    fprintf('    direct effect, peripheral in model  c'' = %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
        mean(cDir), sD.df, sD.tstat, pD);
    fprintf('    path a  condition -> peripheral        = %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
        mean(aPath), sA.df, sA.tstat, pA);
    fprintf('    path b  peripheral -> EEG              = %+.3f,    t(%d) = %.2f, p = %.4f\n', ...
        mean(bPath), sB.df, sB.tstat, pB);
    fprintf('    indirect (c - c'')                      = %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
        mean(ind), sI.df, sI.tstat, pI);
    fprintf('    proportion of c removed                = %.1f%%\n\n', ...
        100*mean(ind)/mean(cTot));
    out(end+1,:) = {v, mean(cTot), pT, mean(cDir), pD, mean(aPath), pA, ...
        mean(bPath), pB, mean(ind), pI, 100*mean(ind)/mean(cTot)}; %#ok<SAGROW>
end

writetable(cell2table(out, 'VariableNames', {'Mediator','c','c_p','c_direct', ...
    'c_direct_p','a','a_p','b','b_p','indirect','indirect_p','pct_removed'}), ...
    fullfile(RES,'prestim_mediation_trial.csv'));
writetable(T, fullfile(RES,'prestim_trial_table.csv'));
fprintf('wrote prestim_mediation_trial.csv and prestim_trial_table.csv\n');
