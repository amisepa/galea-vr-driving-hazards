%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Preregistered pre-stimulus control analyses (OSF xuw34, q16 and q17)
%
% Two analyses were registered and never run. The manuscript says they were
% "conditioned on a pre-stimulus effect to characterise", which OVERSTATES the
% registration: only the block analysis carries a conditioning clause, and it
% is a circularity guard on WINDOW SELECTION, not a precondition for running.
% The run-length control is registered unconditionally.
%
% REGISTERED, q17 "Gambler's fallacy control", verbatim:
%   "For each trial, we will compute run length (number of consecutive
%   preceding trials of the same condition: 0, 1, 2, 3, 4, 5+). We will test
%   whether pre-stimulus EEG activity is modulated by run length using a GLM
%   with run length as a predictor, with trial type retained in the model, and
%   evaluate effects using within-subject permutation testing. As a
%   complementary analysis, we will compare pre-stimulus EEG activity for
%   trials preceded by long runs (4+ same condition) versus short runs (0-1
%   same condition)..."
%
% REGISTERED, q17 "CNV and time-on-task dissociation", verbatim:
%   "trials will be divided into three blocks: early (trials 1-40), middle
%   (41-80), and late (81-120)... block comparisons will use a pre-stimulus
%   electrode and time window defined from the primary pre-stimulus analysis...
%   CNV or learning accounts predict increasing anticipatory negativity across
%   blocks, whereas PAA accounts predict stability."
%
% TWO AMBIGUITIES, DECLARED RATHER THAN RESOLVED SILENTLY
%   1. "consecutive preceding trials of the same condition" does not say same
%      as WHAT. Primary reading here: the run of identical outcomes ENDING at
%      trial i-1, a property of the history alone. The alternative reading
%      (run of trials matching the CURRENT trial) makes the predictor a
%      function of the trial's own condition, which is partly the thing being
%      controlled for. Both are computed and both are reported.
%   2. The registration enumerates discrete levels (0,1,2,3,4,5+), so run
%      length is DUMMY coded, not continuous.
%
% EXCLUSIONS
%   - Trial index from analysis/recover_trial_index.m; only files verified
%     three ways are used (sub-012 failed and is excluded).
%   - BLOCK ANALYSIS ONLY: sub-017 aligns to true trials 30-120 so has no
%     complete early block; sub-011's session restarted after a headset
%     disconnection and its second recording replays sequence positions 1-24,
%     so block membership is undefined. Both are kept everywhere else. Run
%     length is unaffected: it is computed within each recording from that
%     recording's own history.
%
% Cedric Cannard, September 2026

clear; close all; clc
rng(2026,'twister')
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
addpath(paths.analysis);
RES = paths.res_tf_causal;
BLOCK_EXCLUDE = [11 17];
nPerm = 10000;                      % cheap here: the DV is one number per trial

%% ---- cluster window and per-trial power ---------------------------------
S = load(fullfile(RES,'none','pre-stim','TF_stats_pre.mat'), 'mask','time','foi');
C = load(fullfile(RES,'causal_power_cache.mat'), 'RAW_CRASH','RAW_NOCRASH','times_ref');
R = load(fullfile(RES,'trial_index_recovery.mat'), 'rec');
rec = R.rec;

box  = logical(S.mask);
tsel = ismember(round(C.times_ref,3), round(S.time,3));
assert(sum(tsel) == numel(S.time), 'cluster time axis does not align to the cache');
fprintf('Cluster window: %g-%g Hz, %g to %g ms (%d points)\n', ...
    min(S.foi(any(box,2))), max(S.foi(any(box,2))), ...
    min(S.time(any(box,1))), max(S.time(any(box,1))), sum(box(:)));

usable = [rec.usable];  subjOf = [rec.subject];
uSub   = unique(subjOf(usable));
fprintf('Verified files: %d of %d, participants: %d\n\n', sum(usable), numel(usable), numel(uSub));

% Cache order is one cell per PARTICIPANT, built from the same ERP exports the
% trial index was recovered against, with crash trials first then no-crash and
% sequence order preserved within each. So the k-th retained crash trial in
% sequence order is the k-th trial of RAW_CRASH.
cacheSub = unique(subjOf);                       % cache cells follow this order
T = table();
for k = 1:numel(uSub)
    s  = uSub(k);
    ci = find(cacheSub == s, 1);
    cP = 10*log10(C.RAW_CRASH{ci}(:, tsel, :));
    nP = 10*log10(C.RAW_NOCRASH{ci}(:, tsel, :));
    powC = zeros(1, size(cP,3));
    for t = 1:size(cP,3), sl = cP(:,:,t); powC(t) = mean(sl(box)); end
    powN = zeros(1, size(nP,3));
    for t = 1:size(nP,3), sl = nP(:,:,t); powN(t) = mean(sl(box)); end

    seqPos = []; cond = []; rl = []; rlOwn = []; fileId = [];
    for f = find(subjOf == s & usable)
        kept  = rec(f).kept_events{1};
        types = rec(f).kept_events{3};
        isC   = strcmp(types, 'tire_pop');       % full delivered sequence
        n = numel(isC); a = nan(1,n); b = nan(1,n);
        for i = 2:n
            j = i-1; L = 1;
            while j > 1 && isC(j-1) == isC(j), L = L + 1; j = j - 1; end
            a(i) = min(L,5);
            j = i-1; M = 0;
            while j >= 1 && isC(j) == isC(i), M = M + 1; j = j - 1; end
            b(i) = min(M,5);
        end
        idx = find(kept);
        seqPos = [seqPos, idx];              %#ok<AGROW>
        cond   = [cond,   isC(idx)];         %#ok<AGROW>
        rl     = [rl,     a(idx)];           %#ok<AGROW>
        rlOwn  = [rlOwn,  b(idx)];           %#ok<AGROW>
        fileId = [fileId, repmat(f,1,numel(idx))]; %#ok<AGROW>
    end

    pow = nan(1, numel(cond));
    pow(cond==1)  = powC(1:sum(cond==1));
    pow(cond==0)  = powN(1:sum(cond==0));
    assert(sum(cond==1) == numel(powC) && sum(cond==0) == numel(powN), ...
        'sub-%03d: %d/%d retained vs %d/%d cached', s, sum(cond==1), sum(cond==0), ...
        numel(powC), numel(powN));

    T = [T; table(repmat(s,numel(cond),1), pow(:), double(cond(:)), rl(:), rlOwn(:), ...
        seqPos(:), fileId(:), 'VariableNames', ...
        {'sub','pow','cond','runlen','runlenOwn','pos','file'})]; %#ok<AGROW>
end
T = T(~isnan(T.runlen), :);      % first trial of each recording has no history
fprintf('Trials entering the controls: %d across %d participants\n\n', height(T), numel(uSub));

%% ---- 1. run-length GLM, condition retained ------------------------------
%
% HOW RUN-LENGTH MODULATION IS TESTED, AND WHY NOT THE OBVIOUS WAY.
% An earlier version summarised the run-length block as mean(abs(beta)) and
% t-tested that against zero. That statistic is meaningless: |beta| >= 0 by
% construction, so the test is significant whenever the betas are merely noisy,
% and it cannot distinguish modulation from estimation error. Three signed or
% properly-null-referenced statistics replace it:
%
%   (a) PARTIAL F per participant for the whole run-length block (full model
%       versus condition-only), which is the registered "modulated by run
%       length" question. Combined across participants with Fisher's method.
%   (b) LINEAR TREND: run length entered as a single continuous predictor, so
%       the coefficient is signed and a group t-test on it is interpretable.
%   (c) PER-LEVEL betas tested at the group level with FDR, which shows where
%       any modulation sits rather than collapsing it.
%
% The condition coefficient is unchanged - it was always signed and correctly
% tested, and it is the number the control exists to produce.
fprintf('===== REGISTERED CONTROL 1: run-length GLM =====\n');
res = {}; SUMROWS = {};
add = @(name, v, t, df, p, n) {name, v, t, df, p, n};
for variant = {{'runlen','history only (primary reading)'}, ...
               {'runlenOwn','matching the current trial (alternative reading)'}}
    v = variant{1}{1};  lbl = variant{1}{2};
    bCond = nan(numel(uSub),1); bSlope = nan(numel(uSub),1);
    pF = nan(numel(uSub),1); Fstat = nan(numel(uSub),1);
    bLev = nan(numel(uSub),5);                        % levels 1..5+ vs level 0
    for k = 1:numel(uSub)
        d = T(T.sub == uSub(k), :);
        lev = min(d.(v),5);
        D = dummyvar(categorical(lev));               % 0..5+ levels present
        D = D(:, 2:end);                              % first level as reference
        X  = [ones(height(d),1), d.cond, D];
        Xr = [ones(height(d),1), d.cond];             % reduced: no run length
        b = X \ d.pow;   bCond(k) = b(2);

        rF = d.pow - X *b;             dfF = height(d) - size(X,2);
        rR = d.pow - Xr*(Xr\d.pow);    q   = size(X,2) - size(Xr,2);
        if dfF > 0 && q > 0
            Fstat(k) = ((sum(rR.^2) - sum(rF.^2))/q) / (sum(rF.^2)/dfF);
            pF(k)    = 1 - fcdf(Fstat(k), q, dfF);
        end

        Xl = [ones(height(d),1), d.cond, lev];        % linear trend
        bl = Xl \ d.pow;  bSlope(k) = bl(3);

        present = unique(lev);  present = present(2:end);   % levels beyond ref
        bLev(k, present) = b(3:end)';
    end
    [~,pC,~,sC] = ttest(bCond);
    [~,pT,~,sT] = ttest(bSlope);
    good = ~isnan(pF);
    chi2 = -2*sum(log(max(pF(good), realmin)));       % Fisher combination
    pFisher = 1 - chi2cdf(chi2, 2*sum(good));

    fprintf('  %s\n', lbl);
    fprintf('    condition effect with run length in the model : %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
        mean(bCond), sC.df, sC.tstat, pC);
    fprintf('    run-length block, partial F per participant  : %d of %d with p < .05', ...
        sum(pF(good) < 0.05), sum(good));
    fprintf('   (Fisher chi2(%d) = %.1f, p = %.4f)\n', 2*sum(good), chi2, pFisher);
    fprintf('    run-length linear trend (signed)             : %+.3f dB/level, t(%d) = %.2f, p = %.4f\n', ...
        mean(bSlope), sT.df, sT.tstat, pT);
    pLev = nan(1,5);
    for L = 1:5
        x = bLev(~isnan(bLev(:,L)), L);
        if numel(x) >= 5, [~,pLev(L)] = ttest(x); end
    end
    okL = ~isnan(pLev);
    qLev = nan(1,5);
    if any(okL)
        % Benjamini-Hochberg. An earlier version divided the sorted p-values by
        % (m:-1:1), the REVERSED rank, which hands the smallest p-value a
        % divisor of m instead of 1 and so returns q = p where it should return
        % m*p - anti-conservative exactly where it matters. The rank must ascend
        % with the sorted p-values. Monotonicity is then enforced from the
        % largest rank downwards, which is what makes q non-decreasing in p.
        pv = pLev(okL); m = numel(pv);
        [ps, ord] = sort(pv(:), 'ascend');
        adj = m * ps ./ (1:m)';
        adj = flipud(cummin(flipud(adj)));      % running min from the top rank down
        adj = min(adj, 1);
        tmp = nan(1, m); tmp(ord) = adj; qLev(okL) = tmp;
    end
    fprintf('    per-level betas vs run length 0 (FDR q):');
    for L = 1:5
        if isnan(pLev(L)), fprintf('  L%d --', L);
        else, fprintf('  L%d %+.2f (q=%.3f)', L, mean(bLev(~isnan(bLev(:,L)),L)), qLev(L)); end
    end
    fprintf('\n\n');
    tag = strtok(v, ' ');
    SUMROWS(end+1,:) = add(['cond_with_runlen_' tag], mean(bCond), sC.tstat, sC.df, pC, numel(uSub)); %#ok<SAGROW>
    SUMROWS(end+1,:) = add(['runlen_trend_' tag], mean(bSlope), sT.tstat, sT.df, pT, numel(uSub)); %#ok<SAGROW>
    SUMROWS(end+1,:) = add(['runlen_block_fisher_' tag], sum(pF(good)<0.05), chi2, 2*sum(good), pFisher, sum(good)); %#ok<SAGROW>
    res(end+1,:) = {lbl, mean(bCond), sC.tstat, pC, mean(bSlope), sT.tstat, pT, pFisher}; %#ok<SAGROW>
end

%% ---- 2. long-run vs short-run contrast ----------------------------------
fprintf('===== REGISTERED CONTROL 2: long (4+) vs short (0-1) runs =====\n');
dLong = nan(numel(uSub),1); dShort = nan(numel(uSub),1);
for k = 1:numel(uSub)
    d = T(T.sub == uSub(k), :);
    L = d(d.runlen >= 4, :);  Sh = d(d.runlen <= 1, :);
    if height(L) >= 4 && any(L.cond==1) && any(L.cond==0)
        dLong(k) = mean(L.pow(L.cond==1)) - mean(L.pow(L.cond==0));
    end
    if height(Sh) >= 4 && any(Sh.cond==1) && any(Sh.cond==0)
        dShort(k) = mean(Sh.pow(Sh.cond==1)) - mean(Sh.pow(Sh.cond==0));
    end
end
ok = ~isnan(dLong) & ~isnan(dShort);
[~,pL,~,sL] = ttest(dLong(ok));
[~,pS,~,sS] = ttest(dShort(ok));
[~,pD,~,sD] = ttest(dLong(ok) - dShort(ok));
fprintf('  participants with both cells: %d of %d\n', sum(ok), numel(uSub));
fprintf('    condition effect after LONG runs  : %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
    mean(dLong(ok)), sL.df, sL.tstat, pL);
fprintf('    condition effect after SHORT runs : %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
    mean(dShort(ok)), sS.df, sS.tstat, pS);
fprintf('    difference (long - short)         : %+.3f dB, t(%d) = %.2f, p = %.4f\n\n', ...
    mean(dLong(ok)-dShort(ok)), sD.df, sD.tstat, pD);
SUMROWS(end+1,:) = add('long_runs',  mean(dLong(ok)),  sL.tstat, sL.df, pL, sum(ok));
SUMROWS(end+1,:) = add('short_runs', mean(dShort(ok)), sS.tstat, sS.df, pS, sum(ok));
SUMROWS(end+1,:) = add('long_minus_short', mean(dLong(ok)-dShort(ok)), sD.tstat, sD.df, pD, sum(ok));

%% ---- 3. early / middle / late blocks ------------------------------------
fprintf('===== REGISTERED CONTROL 3: early / middle / late blocks =====\n');
keepB = ~ismember(uSub, BLOCK_EXCLUDE);
fprintf('  excluded: sub-011 (sequence restarted) and sub-017 (starts at trial 30)\n');
fprintf('  participants: %d\n', sum(keepB));
BL = [1 40; 41 80; 81 120]; names = {'early','middle','late'};
bEff = nan(numel(uSub), 3);
for k = find(keepB(:)')
    d = T(T.sub == uSub(k), :);
    for bIdx = 1:3
        dd = d(d.pos >= BL(bIdx,1) & d.pos <= BL(bIdx,2), :);
        if height(dd) >= 6 && any(dd.cond==1) && any(dd.cond==0)
            bEff(k,bIdx) = mean(dd.pow(dd.cond==1)) - mean(dd.pow(dd.cond==0));
        end
    end
end
for bIdx = 1:3
    x = bEff(:,bIdx); x = x(~isnan(x));
    [~,pb,~,sb] = ttest(x);
    fprintf('    %-7s n = %2d  effect %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
        names{bIdx}, numel(x), mean(x), sb.df, sb.tstat, pb);
    SUMROWS(end+1,:) = add(['block_' names{bIdx}], mean(x), sb.tstat, sb.df, pb, numel(x)); %#ok<SAGROW>
end
full = all(~isnan(bEff),2);
if sum(full) >= 5
    [~,pLin,~,sLin] = ttest(bEff(full,3) - bEff(full,1));
    fprintf('    late minus early (monotonic increase predicted by CNV/learning):\n');
    fprintf('      %+.3f dB, t(%d) = %.2f, p = %.4f   [n = %d with all three blocks]\n', ...
        mean(bEff(full,3)-bEff(full,1)), sLin.df, sLin.tstat, pLin, sum(full));
    SUMROWS(end+1,:) = add('block_late_minus_early', mean(bEff(full,3)-bEff(full,1)), ...
        sLin.tstat, sLin.df, pLin, sum(full));
end

%% ---- 4. per-participant breakdown ---------------------------------------
%
% Not registered. It exists because a group mean of 16 can be produced either by
% a shift present in most people or by two or three extreme participants, and
% those two situations warrant completely different confidence. Reported as a
% description, not a test.
fprintf('\n===== PER-PARTICIPANT BREAKDOWN OF THE CLUSTER =====\n');
perSub = nan(numel(uSub),1); nTr = nan(numel(uSub),2);
for k = 1:numel(uSub)
    d = T(T.sub == uSub(k), :);
    perSub(k) = mean(d.pow(d.cond==1)) - mean(d.pow(d.cond==0));
    nTr(k,:)  = [sum(d.cond==1), sum(d.cond==0)];
    fprintf('  sub-%03d  %+.3f dB   (%d collision / %d no-collision)\n', ...
        uSub(k), perSub(k), nTr(k,1), nTr(k,2));
end
[~,pPS,~,sPS] = ttest(perSub);
nPos  = sum(perSub > 0);
pSign = 2*min(binocdf(nPos,numel(perSub),0.5), 1-binocdf(nPos-1,numel(perSub),0.5));
fprintf('  group: %+.3f dB, t(%d) = %.2f, p = %.4f   [circular: window was selected]\n', ...
    mean(perSub), sPS.df, sPS.tstat, pPS);
fprintf('  direction: %d of %d positive, sign test p = %.4f\n', nPos, numel(perSub), pSign);
fprintf('  range %+.3f to %+.3f dB; median %+.3f\n', ...
    min(perSub), max(perSub), median(perSub));
% Is the group mean carried by a few people? Drop the largest contributor.
[~,iMax] = max(abs(perSub - mean(perSub)));
leave1 = perSub; leave1(iMax) = [];
[~,pL1,~,sL1] = ttest(leave1);
fprintf('  dropping the most extreme participant (sub-%03d): %+.3f dB, t(%d) = %.2f, p = %.4f\n', ...
    uSub(iMax), mean(leave1), sL1.df, sL1.tstat, pL1);
SUMROWS(end+1,:) = add('persub_effect', mean(perSub), sPS.tstat, sPS.df, pPS, numel(perSub));
SUMROWS(end+1,:) = add('persub_positive', nPos, NaN, NaN, pSign, numel(perSub));
SUMROWS(end+1,:) = add('persub_drop_extreme', mean(leave1), sL1.tstat, sL1.df, pL1, numel(leave1));
writetable(table(uSub(:), perSub, nTr(:,1), nTr(:,2), ...
    'VariableNames', {'sub','effect_dB','n_collision','n_nocollision'}), ...
    fullfile(RES,'prestim_persubject.csv'));

%% ---- tidy summary for the manuscript ------------------------------------
% build_manuscript.js reads this rather than having the numbers typed into it,
% so a re-run cannot leave the text disagreeing with the results.
SUM = cell2table(SUMROWS, 'VariableNames', {'stat','value','t','df','p','n'});
writetable(SUM, fullfile(RES,'prestim_controls_summary.csv'));

%% ---- save ---------------------------------------------------------------
Tres = cell2table(res, 'VariableNames', ...
    {'Reading','Cond_beta','Cond_t','Cond_p','Trend_beta','Trend_t','Trend_p','RunBlock_pFisher'});
writetable(Tres, fullfile(RES,'prereg_runlength.csv'));
writetable(table(uSub(:), dLong, dShort, bEff(:,1), bEff(:,2), bEff(:,3), ...
    'VariableNames', {'sub','long_run','short_run','early','middle','late'}), ...
    fullfile(RES,'prereg_blocks.csv'));
fprintf('\nwrote prereg_runlength.csv and prereg_blocks.csv\n');
