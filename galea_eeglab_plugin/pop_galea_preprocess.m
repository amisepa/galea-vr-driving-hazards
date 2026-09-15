%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function [EEG, com] = pop_galea_preprocess(EEG, varargin)
% POP_GALEA_PREPROCESS  Clean continuous Galea data (Cannard 2026 methods).
%
% Runs on CONTINUOUS data. Epoching and ERPs come afterwards from the standard
% EEGLAB menus; tutorial_galea.m shows the whole route.
%
% EEG steps, each optional:
%   0. Trim. Drop the data before the first event (minus a pad, default 3 s)
%      and after the last event (plus the same pad). The head and tail of a
%      Galea recording are often full of adjustment artefacts that bias ASR
%      and ICA. Applies to the EEG AND all auxiliary streams (PPG, EDA, EMG,
%      IMU), each at its own sampling rate.
%   1. Downsample.
%   2. Bandpass. Optionally minimum-phase CAUSAL, which keeps the pre-stimulus
%      period free of post-stimulus leakage. Only needed for anticipation
%      analyses, so it is off by default.
%   3. Polarity check on the two prefrontal disc electrodes, which the Galea
%      amplifier sometimes records with inverted leads. Off by default; turn it
%      on if you are using the custom montage with Fp1/Fp2.
%   4. Bad-channel detection tuned for a sparse dry montage, then interpolation.
%   5. ASR, run leniently so it removes bursts without flattening the data.
%   6. ICA with the ocular component removed, after you confirm which one.
%      Only sensible for EYES-OPEN recordings: the step assumes blinks dominate
%      the variance, which is not true of eyes-closed or resting-state data.
%   7. Optional second, stricter ASR pass AFTER ICA (default threshold 20, off
%      by default) to mop up residual artefacts once the ocular source has been
%      subtracted.
%
% PPG is handled separately, through the BrainBeats plugin.
%
% Usage:
%   >> EEG = pop_galea_preprocess(EEG);                       % GUI
%   >> EEG = pop_galea_preprocess(EEG, 'asr', 100, 'ica', true);
%
% EEG key/value (defaults in brackets):
%   'trim'     trim around first/last event, seconds (0 = keep); applies to
%              all signals                                [3]
%   'resample' target Hz, 0 = keep                  [0]
%   'locut'    high-pass cutoff, Hz                 [0.5]
%   'hicut'    low-pass cutoff, Hz                  [30]
%   'causal'   minimum-phase causal filter          [false]
%   'polarity' fix Fp1/Fp2 polarity                 [false]
%   'badchan'  detect bad channels                     [true]
%   'mincorr'  correlation threshold (paper=.55, aggressive=.75, medium=.5, lax=.35) [0.55]
%   'maxtol'   max fraction of flagged windows      [0.30]
%   'interpchan' interpolate the detected bad channels [false]
%   'asr'      ASR SD threshold, 0 = skip           [100]
%   'asrmode'  'reconstruct' (default: ASR interpolates the bad segments) or
%              'remove' (the affected segments are deleted, and any event
%              markers that fell inside them are listed in the console) ['reconstruct']
%   'ica'      ICA, remove the ocular component     [true]
%   'icaconfirm' ask before removing the component  [true]
%   'asr2'     second ASR pass after ICA, 0 = skip  [0]
%   'asr2mode' 'reconstruct' (default) or 'remove' for the second pass
%   'viseeg'   plot the EEG before / after          [true]
%
% PPG key/value:
%   'ppg'       process PPG with BrainBeats         [true if a PPG stream exists]
%   'ppglocut'  PPG high-pass, Hz                   [0.5]
%   'ppghicut'  PPG low-pass, Hz                    [3]
%   'rrcorrect' RR artefact interpolation           ['pchip']
%               pchip | linear | spline | makima | nearest | remove
%   'hrvtime' / 'hrvfreq' / 'hrvnonlin'  feature sets   [true/true/false]
%   'visppg'    BrainBeats cleaning and output plots [true]
%
% Cedric Cannard, 2026

com = '';
if nargin < 1, help pop_galea_preprocess; return; end

hasPPG = isfield(EEG.etc,'galea') && isfield(EEG.etc.galea,'PPG') && ...
         ~isempty(EEG.etc.galea.PPG) && EEG.etc.galea.PPG.nbchan > 0;
hasEvents = ~isempty(EEG.event);

g = struct('eeg',true, 'trim',3, 'resample',0, 'locut',0.5, 'hicut',30, 'causal',false, ...
           'polarity',false, 'badchan',true, 'mincorr',0.55, 'maxtol',0.30, 'interpchan',false, ...
           'asr',100, 'asrmode','remove', 'ica',true, 'icaconfirm',true, 'asr2',0, 'asr2mode','reconstruct', 'viseeg',true, ...
           'ppg',hasPPG, 'ppglocut',0.5, 'ppghicut',3, 'rrcorrect','pchip', ...
           'hrvtime',true, 'hrvfreq',true, 'hrvnonlin',false, 'visppg',true, ...
           'eda',false, 'edalocut',0.01, 'edahicut',1, 'edaresample',8, ...
           'edaphasic',false, 'viseda',true, ...
           'emg',false, 'emglocut',20, 'emgenvelope',true, 'visemg',true, ...
           'imu',false, 'imuhicut',10, 'imumagnitude',true, 'visimu',true);

if nargin > 1
    for i = 1:2:numel(varargin)
        g.(lower(varargin{i})) = varargin{i+1};
    end
else
    g = galea_preproc_gui(g, hasPPG, hasEvents, EEG.srate);
    if isempty(g), return; end
end

oriEEG = EEG;

% ---- 0. trim head/tail around the first and last event (ALL signals) ----
% The EEG and every auxiliary stream are cut to the same time span, each at
% its own sampling rate. Done first so ASR and ICA never see the artefact-
% filled head and tail of the recording.
if g.trim > 0 && hasEvents
    lat = [EEG.event.latency];
    pad = round(g.trim * EEG.srate);
    lo = max(1, min(lat) - pad);
    hi = min(EEG.pnts, max(lat) + pad);
    if lo > 1 || hi < EEG.pnts
        fprintf('Trimming EEG to samples %d-%d (first/last event +- %g s)...\n', lo, hi, g.trim);
        before = EEG.pnts;
        EEG = pop_select(EEG, 'point', [lo hi]);
        fprintf('  removed %.1f s (%.1f%% of the recording).\n', ...
            (before - EEG.pnts)/EEG.srate, 100*(before - EEG.pnts)/before);
        % same span, in seconds, for the auxiliary streams
        t0 = (lo - 1) / EEG.srate;
        t1 = (hi - 1) / EEG.srate;
        for auxName = {'PPG','EDA','EMG','IMU'}
            an = auxName{1};
            if isfield(EEG.etc,'galea') && isfield(EEG.etc.galea, an) && ...
                    ~isempty(EEG.etc.galea.(an)) && EEG.etc.galea.(an).nbchan > 0
                A = EEG.etc.galea.(an);
                alo = max(1, round(t0 * A.srate) + 1);
                ahi = min(A.pnts, round(t1 * A.srate) + 1);
                if alo > 1 || ahi < A.pnts
                    beforeA = A.pnts;
                    A = pop_select(A, 'point', [alo ahi]);
                    fprintf('  trimmed %s: %d -> %d samples\n', an, beforeA, A.pnts);
                    EEG.etc.galea.(an) = A;
                end
            end
        end
        % overview figure: what was removed (oriEEG still holds the untrimmed data)
        galea_show_trim(oriEEG, EEG, g.trim);
    end
end

if g.eeg
% ---- 1. downsample ----
if g.resample > 0 && g.resample ~= EEG.srate
    fprintf('Resampling %g -> %g Hz...\n', EEG.srate, g.resample);
    EEG = pop_resample(EEG, g.resample);
end

% ---- 2. filter ----
if g.causal, filt = 'minimum-phase causal'; else, filt = 'zero-phase'; end
fprintf('Filtering %.2f-%.2f Hz (%s)...\n', g.locut, g.hicut, filt);
EEG = pop_eegfiltnew(EEG, 'hicutoff', g.hicut, 'minphase', g.causal);
EEG = pop_eegfiltnew(EEG, 'locutoff', g.locut, 'minphase', g.causal);

% ---- 3. prefrontal polarity ----
if g.polarity
    labs = {EEG.chanlocs.labels};
    suspect = labs(ismember(lower(labs), {'fp1','fp2'}));
    if ~isempty(suspect)
        EEG = fix_polarity(EEG, suspect, 8, 0.5);
    else
        warning('No Fp1/Fp2 channels found; skipping polarity correction.');
    end
end

% ---- 4. bad channels ----
badChan = [];
if g.badchan
    badChan = flag_bad_eeg_channels_window(EEG.data, EEG.srate, g.mincorr, 0.2, g.maxtol);
    if any(badChan)
        fprintf('Bad channels (correlation threshold %.2f): %s\n', g.mincorr, ...
            strjoin({EEG.chanlocs(badChan).labels}, ', '));
        if g.interpchan
            EEG = pop_select(EEG, 'nochannel', find(badChan));
            EEG = pop_interp(EEG, oriEEG.chanlocs, 'spherical');
            fprintf('  bad channels removed and interpolated.\n');
        else
            fprintf('  flagged only (interpolation is a separate option); continuing with them.\n');
            badChan = [];
        end
    else
        fprintf('No bad channels detected.\n');
    end
end

% Reference for the final before/after: the state going INTO artefact removal.
preClean = EEG;

% ---- 5. ASR ----
% clean_asr always RECONSTRUCTS (interpolates) the segments it flags. Two
% modes here:
%   'reconstruct' - keep the ASR output as is (pipeline convention);
%   'remove'      - compute the affected-sample mask, delete those segments
%                   entirely (same convention as galea_pipeline_v6_EEG.m:
%                   pop_select 'nopoint' + drop segments <= 5 samples), and
%                   report which event markers fell inside them.
if g.asr > 0
    fprintf('ASR (threshold %g, mode %s)...\n', g.asr, g.asrmode);
    before = EEG.pnts;
    cleanEEG = clean_asr(EEG, g.asr, [], [], [], [], [], [], [], false, []);
    if strcmpi(g.asrmode, 'remove')
        mask = sum(abs(EEG.data - cleanEEG.data), 1) > 1e-10;
        pct  = 100 * mean(mask);
        fprintf('  %.2f%% of samples flagged by ASR; removing those segments.\n', pct);
        % segment list, small gaps <= 5 samples merged away (pipeline convention)
        badData = reshape(find(diff([false mask false])), 2, [])';
        badData(:,2) = badData(:,2) - 1;
        badData(diff(badData,[],2) <= 5, :) = [];
        % which event markers fall inside the removed segments?
        if ~isempty(EEG.event) && ~isempty(badData)
            lat = [EEG.event.latency];
            inBad = false(size(lat));
            for iSeg = 1:size(badData,1)
                inBad = inBad | (lat >= badData(iSeg,1) & lat <= badData(iSeg,2));
            end
            if any(inBad)
                dropped = EEG.event(inBad);
                fprintf('  WARNING: %d event marker(s) inside removed segments:\n', sum(inBad));
                for iE = 1:sum(inBad)
                    fprintf('    t=%.2f s  type=%s\n', ...
                        (dropped(iE).latency-1)/EEG.srate, dropped(iE).type);
                end
                EEG.etc.galea_asr_dropped_events = ...
                    struct('type',{{dropped.type}}, 'latency',[dropped.latency]);
            end
        end
        if ~isempty(badData)
            EEG = pop_select(EEG, 'nopoint', badData);
        end
        fprintf('  %.1f%% of the recording removed (%.1f s).\n', ...
            100*(1 - EEG.pnts/before), (before - EEG.pnts)/EEG.srate);
    else
        EEG = cleanEEG;
        fprintf('  %.2f%% of samples reconstructed.\n', 100*(1 - EEG.pnts/before));
    end
end

% ---- 6. ICA ----
icaInfo = [];
if g.ica
    [EEG, icaInfo] = galea_remove_ocular_ic(EEG, g.icaconfirm);
end

% ---- 7. optional second, stricter ASR pass after ICA ----
% After the ocular source is subtracted, a stricter pass can safely remove
% smaller residual artefacts that the lenient pre-ICA pass deliberately left
% alone. Off by default.
if g.asr2 > 0
    fprintf('Second ASR pass (threshold %g, mode %s), after ICA...\n', g.asr2, g.asr2mode);
    before = EEG.pnts;
    cleanEEG = clean_asr(EEG, g.asr2, [], [], [], [], [], [], [], false, []);
    if strcmpi(g.asr2mode, 'remove')
        mask = sum(abs(EEG.data - cleanEEG.data), 1) > 1e-10;
        pct  = 100 * mean(mask);
        fprintf('  %.2f%% of samples flagged; removing those segments.\n', pct);
        badData = reshape(find(diff([false mask false])), 2, [])';
        badData(:,2) = badData(:,2) - 1;
        badData(diff(badData,[],2) <= 5, :) = [];
        if ~isempty(EEG.event) && ~isempty(badData)
            lat = [EEG.event.latency];
            inBad = false(size(lat));
            for iSeg = 1:size(badData,1)
                inBad = inBad | (lat >= badData(iSeg,1) & lat <= badData(iSeg,2));
            end
            if any(inBad)
                dropped = EEG.event(inBad);
                fprintf('  WARNING: %d event marker(s) inside removed segments:\n', sum(inBad));
                for iE = 1:sum(inBad)
                    fprintf('    t=%.2f s  type=%s\n', ...
                        (dropped(iE).latency-1)/EEG.srate, dropped(iE).type);
                end
                EEG.etc.galea_asr_dropped_events = ...
                    struct('type',{{dropped.type}}, 'latency',[dropped.latency]);
            end
        end
        if ~isempty(badData)
            EEG = pop_select(EEG, 'nopoint', badData);
        end
        fprintf('  %.1f%% of the recording removed (%.1f s).\n', ...
            100*(1 - EEG.pnts/before), (before - EEG.pnts)/EEG.srate);
    else
        EEG = cleanEEG;
        fprintf('  %.2f%% of samples reconstructed.\n', 100*(1 - EEG.pnts/before));
    end
end

% ---- before / after ----
if g.viseeg && (g.asr > 0 || g.ica || g.asr2 > 0)
    % vis_artifacts overlays the two datasets, so it needs identical sample
    % counts; ASR in 'remove' mode shortens the data, then fall back to the
    % plain scrolling plot of the cleaned data.
    if exist('vis_artifacts','file') && EEG.pnts == preClean.pnts
        vis_artifacts(EEG, preClean);
        set(gcf, 'Name', 'Before (red) vs after ASR + ICA (blue)');
    else
        pop_eegplot(EEG, 1, 1, 1);
        galea_eegplot_yscale(100);
    end
end

end  % if g.eeg

% ---- other modalities, one at a time ----
if g.ppg, EEG = galea_process_ppg(EEG, g); end
if g.eda, EEG = galea_process_stream(EEG, 'EDA', g); end
if g.emg, EEG = galea_process_stream(EEG, 'EMG', g); end
if g.imu, EEG = galea_process_stream(EEG, 'IMU', g); end

EEG.etc.galea_preprocess = g;
EEG.etc.galea_preprocess.badChan = badChan;
EEG.etc.galea_preprocess.ica = icaInfo;
EEG = eeg_checkset(EEG);

com = sprintf(['EEG = pop_galea_preprocess(EEG, ''trim'',%g, ''resample'',%g, ''locut'',%g, ''hicut'',%g, ' ...
    '''causal'',%d, ''polarity'',%d, ''badchan'',%d, ''mincorr'',%g, ''maxtol'',%g, ' ...
    '''asr'',%g, ''asrmode'',''%s'', ''ica'',%d, ''asr2'',%g, ''asr2mode'',''%s'', ''ppg'',%d);'], ...
    g.trim, g.resample, g.locut, g.hicut, g.causal, g.polarity, g.badchan, ...
    g.mincorr, g.maxtol, g.asr, g.asrmode, g.ica, g.asr2, g.asr2mode, g.ppg);

end

% ===========================================================================
function g = galea_preproc_gui(g, hasPPG, hasEvents, srate)
% Custom figure rather than inputgui(), so the window can be wide enough to
% read and the PPG block can be visibly separate from the EEG one. Each
% modality has a "process" checkbox; unchecking it greys out (disables) that
% whole section, checking it re-enables the section.
%
% The window sizes itself to its content and clamps to the screen, so nothing
% is cropped on any display: layout is built from the top, the final content
% height is known, and H is set from it before the figure properties are
% applied.

c = galea_colors();   % EEGLAB house colours (icadefs is a script and cannot run in a static workspace)

W = 680;
scr = get(0, 'ScreenSize');

% ---- layout pass: measure the content height first ----
H = measure_layout(hasPPG, hasEvents, srate);
H = min(H, scr(4) - 80);          % never taller than the screen

f = figure('Name','Preprocess Galea data', 'NumberTitle','off', 'MenuBar','none', ...
    'ToolBar','none', 'Resize','off', 'Color',c.back, ...
    'Position',[(scr(3)-W)/2 max(20,(scr(4)-H)/2) W H], 'WindowStyle','modal');

    function h = txt(str, pos, varargin)
        h = uicontrol(f,'style','text','string',str,'position',pos, ...
            'horizontalalignment','left','backgroundcolor',c.back, ...
            'foregroundcolor',c.text, varargin{:});
    end
    function h = ed(str, pos)
        h = uicontrol(f,'style','edit','string',str,'position',pos, ...
            'backgroundcolor',c.btn);
    end
    function h = cb(str, val, pos, varargin)
        h = uicontrol(f,'style','checkbox','string',str,'value',val,'position',pos, ...
            'backgroundcolor',c.back,'foregroundcolor',c.text, varargin{:});
    end
    function sep(y)
        uicontrol(f,'style','frame','position',[20 y W-40 1], ...
            'foregroundcolor',[.4 .45 .6],'backgroundcolor',[.4 .45 .6]);
    end

eegKids  = gobjects(0);   % controls gated by the EEG "process" box

% ---------------- trim (global, all signals) ----------------
y = H - 40;
txt('Trim', [20 y 120 22], 'fontweight','bold','fontsize',11);
y = y - 28;
if hasEvents
    txt('Data before the first event and after the last event, plus the pad, is', [20 y W-40 20]);
    y = y - 18;
    txt('removed. Applies to the EEG and ALL auxiliary signals (PPG, EDA, EMG, IMU).', [20 y W-40 20]);
    y = y - 22;
    txt('Trim pad (s, 0 = keep all):', [20 y 250 20]);  hTrim = ed('3', [300 y 70 24]);
else
    txt('No events in this dataset; nothing to trim.', [20 y W-40 20], 'fontangle','italic');
    hTrim = ed('0', [300 y 70 24]);
    set(hTrim, 'enable', 'off');
end
y = y - 20; sep(y);

% ---------------- EEG ----------------
y = y - 26;
hEegBox = cb('Process EEG', 1, [20 y 200 22], 'fontweight','bold','fontsize',11, ...
    'callback',@(~,~) gateEEG());
y = y - 26;
txt('Downsample to (Hz, 0 = keep):', [40 y 250 20]);  hRes  = ed('0', [300 y 70 24]);
eegKids(end+1) = hRes;
txt(sprintf('current rate: %g Hz', srate), [378 y 110 20], 'fontangle', 'italic', 'fontsize', 8);
hDiv = uicontrol(f,'style','popupmenu','position',[494 y 60 24], 'backgroundcolor', c.btn, ...
    'string', {'/1','/2','/4'}, 'value', 1, ...
    'tooltipstring', ['Fill the Downsample box with the current rate divided by 1, 2 or 4 '
    '(e.g. 500 > 250 > 125). Dividing the rate avoids resampling artefacts at non-integer ratios.'], ...
    'callback', @(h,~) onDiv());
eegKids(end+1) = hDiv;
    function onDiv()
        % Fill the Downsample box with srate / 1, / 2 or / 4 (integer division
        % keeps downsampling artefact-free).
        d = [1 2 4];
        set(hRes, 'string', sprintf('%g', srate / d(get(hDiv, 'value'))));
    end %#ok<*AGROW>
y = y - 26;
txt('Bandpass (Hz):', [40 y 250 20]);
hLo = ed('0.5', [300 y 70 24]);  txt('to', [376 y 20 20]);  hHi = ed('30', [400 y 70 24]);
eegKids(end+1) = hLo; eegKids(end+1) = hHi;
y = y - 24;
hCaus = cb('Minimum-phase causal filter (only for pre-stimulus analyses)', 0, [40 y W-70 22]);
eegKids(end+1) = hCaus;
y = y - 22;
hPol  = cb('Correct Fp1/Fp2 polarity (custom montage with disc electrodes)', 0, [40 y W-70 22]);
eegKids(end+1) = hPol;

y = y - 28;
hBad = cb('Detect bad channels', 1, [40 y 200 22]);
eegKids(end+1) = hBad;
hInterp = cb('Interpolate them', 0, [250 y 160 22]);
eegKids(end+1) = hInterp;
y = y - 24;
txt('Bad-channel correlation threshold:', [40 y 250 20]);
hCorr = ed('0.55', [300 y 70 24]);
eegKids(end+1) = hCorr;
y = y - 24;
txt('max fraction of flagged windows tolerated:', [40 y 250 20]);
hMaxTol = ed('0.30', [300 y 70 24]);
eegKids(end+1) = hMaxTol;
y = y - 26;
txt('ASR threshold (0 = skip):', [40 y 250 20]);     hAsr = ed('100', [300 y 70 24]);
eegKids(end+1) = hAsr;
txt('mode:', [376 y 40 20]);
hAsrMode = uicontrol(f,'style','popupmenu','position',[415 y 110 24], ...
    'backgroundcolor',c.btn, 'string',{'reconstruct','remove'},'value',2, ...
    'tooltipstring', ['remove: flagged segments are deleted (default; event markers inside them are ' ...
    'listed and stored). reconstruct: flagged segments are interpolated instead.']);
eegKids(end+1) = hAsrMode;
y = y - 20;
txt('     Before ICA, a lenient threshold deletes only the worst segments while', [40 y W-70 18], ...
    'fontangle','italic','fontsize',8);
y = y - 16;
txt('     leaving blinks largely intact, so ICA can separate the eye-blink', [40 y W-70 18], ...
    'fontangle','italic','fontsize',8);
y = y - 16;
txt('     source cleanly. A strict threshold here would eat part of the', [40 y W-70 18], ...
    'fontangle','italic','fontsize',8);
y = y - 16;
txt('     blinks and the ICA decomposition would no longer be clean.', [40 y W-70 18], ...
    'fontangle','italic','fontsize',8);

y = y - 22;
hIca  = cb('ICA, remove the ocular component', 1, [40 y 300 22]);
eegKids(end+1) = hIca;
y = y - 22;
hConf = cb('ask me to confirm which component first (recommended)', 1, [60 y W-90 22]);
eegKids(end+1) = hConf;
y = y - 22;
txt('ASR pass after ICA (0 = skip):', [40 y 250 20]);  hAsr2 = ed('0', [300 y 70 24]);
eegKids(end+1) = hAsr2;
txt('mode:', [376 y 40 20]);
hAsr2Mode = uicontrol(f,'style','popupmenu','position',[415 y 110 24], ...
    'backgroundcolor',c.btn, 'string',{'reconstruct','remove'},'value',1, ...
    'tooltipstring', ['reconstruct: flagged segments are interpolated (default, safest for ' ...
    'continuous data). remove: the segments are deleted and any event markers inside them are lost.']);
eegKids(end+1) = hAsr2Mode;
y = y - 20;
txt('     Optional stricter cleanup (e.g. 20) once the eye-blink source has', [40 y W-70 18], ...
    'fontangle','italic','fontsize',8);
y = y - 16;
txt('     been subtracted and can no longer be damaged.', [40 y W-70 18], ...
    'fontangle','italic','fontsize',8);
y = y - 20;
hVisE = cb('Plot the EEG before / after cleaning', 1, [40 y 300 22]);
eegKids(end+1) = hVisE;

y = y - 18; sep(y);

% ---------------- peripheral signals (separate dialog) ----------------
y = y - 26;
uicontrol(f,'style','pushbutton','string','Set PPG / EDA / EMG / IMU options...', ...
    'position',[20 y W-40 28],'backgroundcolor',c.btn,'callback',@(~,~) openPeriph());
if ~hasPPG
    txt('no PPG stream in this dataset', [20 y-24 300 20], 'fontangle','italic');
end
perOpt = [];   % options returned by the peripheral dialog ([] = keep g's values)

% ---------------- gating ----------------
    function gateEEG()
        set(eegKids(isgraphics(eegKids)), 'enable', onoff(get(hEegBox,'value')));
    end

    function openPeriph()
        % Parameters for the auxiliary streams live in their own dialog, so
        % this window stays readable. Starts from the current values.
        def = struct('ppg',g.ppg, 'ppglocut',g.ppglocut, 'ppghicut',g.ppghicut, ...
            'rrcorrect',g.rrcorrect, 'hrvtime',g.hrvtime, 'hrvfreq',g.hrvfreq, ...
            'hrvnonlin',g.hrvnonlin, 'visppg',g.visppg, ...
            'eda',g.eda, 'edalocut',g.edalocut, 'edahicut',g.edahicut, ...
            'edaresample',g.edaresample, 'edaphasic',g.edaphasic, 'viseda',g.viseda, ...
            'emg',g.emg, 'emglocut',g.emglocut, 'emgenvelope',g.emgenvelope, 'visemg',g.visemg, ...
            'imu',g.imu, 'imuhicut',g.imuhicut, 'imumagnitude',g.imumagnitude, 'visimu',g.visimu);
        if ~isempty(perOpt), def = perOpt; end
        res = galea_periph_gui(def, hasPPG);
        if ~isempty(res), perOpt = res; end
    end

% ---------------- buttons ----------------
out = [];
uicontrol(f,'style','pushbutton','string','Help','position',[20 18 80 30], ...
    'backgroundcolor',c.btn, 'callback','pophelp(''pop_galea_preprocess'');');
uicontrol(f,'style','pushbutton','string','Cancel','position',[W-200 18 80 30], ...
    'backgroundcolor',c.btn, 'callback','close(gcbf)');
uicontrol(f,'style','pushbutton','string','Run','position',[W-105 18 85 30], ...
    'fontweight','bold','backgroundcolor',c.btn, 'callback',@(~,~) onRun());

uiwait(f);
g = out;

    function onRun()
        out = g;
        out.eeg        = logical(get(hEegBox,'value'));
        out.trim       = str2double(get(hTrim,'string'));
        out.resample   = str2double(get(hRes,'string'));
        out.locut      = str2double(get(hLo,'string'));
        out.hicut      = str2double(get(hHi,'string'));
        out.causal     = logical(get(hCaus,'value'));
        out.polarity   = logical(get(hPol,'value'));
        out.badchan    = logical(get(hBad,'value'));
        out.interpchan = logical(get(hInterp,'value'));
        out.mincorr    = str2double(get(hCorr,'string'));
        out.maxtol     = str2double(get(hMaxTol,'string'));
        out.asr        = str2double(get(hAsr,'string'));
        asrModes = get(hAsrMode,'string');
        out.asrmode    = asrModes{get(hAsrMode,'value')};
        out.ica        = logical(get(hIca,'value'));
        out.icaconfirm = logical(get(hConf,'value'));
        out.asr2       = str2double(get(hAsr2,'string'));
        asr2Modes = get(hAsr2Mode,'string');
        out.asr2mode   = asr2Modes{get(hAsr2Mode,'value')};
        out.viseeg     = logical(get(hVisE,'value'));
        % peripheral (PPG/EDA/EMG/IMU) options come from the separate dialog;
        % until it is opened, keep the values this call was made with.
        if ~isempty(perOpt)
            pnames = fieldnames(perOpt);
            for iP = 1:numel(pnames)
                out.(pnames{iP}) = perOpt.(pnames{iP});
            end
        end
        close(f);
    end
end

% ---------------------------------------------------------------------------
function s = onoff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

% ---------------------------------------------------------------------------
% ---------------------------------------------------------------------------
function H = measure_layout(hasPPG, hasEvents, srate) %#ok<INUSD>
% Mirror of the GUI layout arithmetic in galea_preproc_gui: same rows, same
% heights, in the same order, so the figure is sized to fit everything before
% it is created. Keep in sync with the layout code above. (srate is accepted
% for signature symmetry with galea_preproc_gui; row heights do not vary.)
if ~isfinite(srate), srate = 0; end  %#ok<NASGU>
H = 0;  %#ok<NASGU> 

y = 0;
y = y + 40;                    % top margin
y = y + 28;                    % 'Trim' title
if hasEvents
    y = y + 18 + 22;           % 2 explanation lines + trim-pad row
else
    y = y + 22;                % 'no events' line (+ disabled edit)
end
y = y + 20 + 1;                % separator
y = y + 26;                    % 'Process EEG'
y = y + 26;                    % downsample (+ current-rate label + division popup on same row)
y = y + 26;                    % bandpass
y = y + 24;                    % causal
y = y + 22;                    % polarity
y = y + 28;                    % bad channels + interpolate
y = y + 24;                    % sensitivity preset
y = y + 24;                    % correlation threshold
y = y + 26;                    % ASR threshold + mode
y = y + 20 + 16 + 16 + 16 + 16;% ASR explanation lines
y = y + 22;                    % ICA
y = y + 22;                    % confirm components
y = y + 22;                    % ASR pass 2
y = y + 20 + 16 + 16;          % ASR2 explanation lines
y = y + 20;                    % plot before/after
y = y + 18 + 1;                % separator
y = y + 26;                    % peripheral-signals launcher button
y = y + 56;                    % buttons + bottom margin
H = y;
end
function [EEG, info] = galea_remove_ocular_ic(EEG, confirm)
% ICA on a 1 Hz high-passed copy (ICA does poorly below 1 Hz), weights
% transferred back.
%
% IMPORTANT: this ASSUMES the first component is ocular. That has held on every
% Galea recording we have looked at, because blinks dominate the variance on
% this montage, but it is an assumption and not a classification: with 10-12 dry
% channels ICLabel is not reliable enough to decide. So the components are
% plotted and the user is asked to confirm before anything is subtracted.
%
% It also assumes an EYES-OPEN task. In eyes-closed or resting-state recordings
% there are few or no blinks, so IC1 will be something else entirely - most
% likely alpha - and removing it would delete real brain activity. Skip the ICA
% step for those, or pick the component by hand.

fprintf('ICA...\n');
TMP = pop_eegfiltnew(EEG, 'locutoff', 1);
dataRank = sum(eig(cov(double(TMP.data'))) > 1e-7);
TMP = pop_runica(TMP, 'icatype', 'picard', 'mode', 'standard', 'pca', dataRank);

EEG.icaweights  = TMP.icaweights;
EEG.icasphere   = TMP.icasphere;
EEG.icawinv     = TMP.icawinv;
EEG.icachansind = TMP.icachansind;
EEG = eeg_checkset(EEG);

badComp = 1;
if confirm && usejava('desktop')
    EEG.reject.gcompreject = false(1, dataRank);
    EEG.reject.gcompreject(1) = true;

    pop_selectcomps(EEG, 1:dataRank);          % topographies, IC1 flagged
    set(gcf, 'Name', 'Component topographies - IC1 is the proposed ocular one');
    pop_eegplot(EEG, 0, 1, 1);                 % component time series
    galea_eegplot_yscale(100);                 % default vertical scale 100 uV
    set(gcf, 'Name', 'Component time series - check IC1 for blinks');
    drawnow

    % user can flag components in the pop_selectcomps window (click to flag);
    % whatever is flagged there prefills the edit box (default: IC1)
    fl = find([EEG.reject.gcompreject]);
    if isempty(fl), fl = 1; EEG.reject.gcompreject(1) = true; end
    prefill = strtrim(sprintf('%d ', fl));

    uilist = { ...
        {'style','text','string', ...
         ['The plugin assumes IC1 is the ocular component. That has been reliable on ' ...
          'this montage, but it is an assumption: with 10-12 dry channels automatic ' ...
          'classification is not trustworthy.']} ...
        {'style','text','string', ...
         ['This only holds for EYES-OPEN tasks, where blinks dominate the variance. ' ...
          'In eyes-closed or resting-state data IC1 is likely alpha, not an artefact - ' ...
          'removing it would delete real brain activity. Leave the box blank to keep ' ...
          'everything.'], 'foregroundcolor',[0.6 0 0]} ...
        {'style','text','string', ...
         ['Check the two figures. A blink component looks frontal in the topography and ' ...
          'shows slow, large deflections in the time series. You can flag any number of ' ...
          'components in the topography window (click); they appear below.']} ...
        {} ...
        {'style','text','string','Component(s) to remove (blank = none):'} ...
        {'style','edit','string',prefill} };
    [res, ~, ~, o] = inputgui('geometry', {1 1 1 1 [3 1]}, 'geomvert', [3 3 2 1 1], ...
        'uilist', uilist, 'title', 'Confirm ocular component');
    if isempty(res)
        fprintf('  cancelled: no component removed.\n');
        info = struct('dataRank', dataRank, 'removed', []);
        return
    end
    % inputgui's output shape differs between EEGLAB versions (the 4th output is
    % a cell here but has been numeric/char elsewhere), so read the edit-box
    % text defensively instead of brace-indexing whatever came back.
    txtVal = [];
    if iscell(res) && ~isempty(res)
        txtVal = res{end};
    elseif ischar(res)
        txtVal = res;
    elseif iscell(o) && ~isempty(o)
        txtVal = o{1};
    elseif isnumeric(o) || islogical(o)
        txtVal = o;
    end
    if isnumeric(txtVal)
        badComp = txtVal;
        if isscalar(badComp) && badComp == 0, badComp = []; end %#ok<SCAL>
    else
        txtVal = strtrim(char(txtVal));
        if isempty(txtVal)
            badComp = [];
        else
            badComp = str2num(txtVal); %#ok<ST2NM>
            if isempty(badComp) || any(~isfinite(badComp))
                warning('Could not read the component list "%s"; no component removed.', txtVal);
                badComp = [];
            end
        end
    end
    if isnumeric(badComp) && isscalar(badComp)
        badComp = double(badComp);
    end
end

if isempty(badComp)
    fprintf('  no component removed.\n');
else
    fprintf('  removing IC%s.\n', mat2str(badComp));
    EEG = pop_subcomp(EEG, badComp, 0);
end
info = struct('dataRank', dataRank, 'removed', badComp);
end

% ---------------------------------------------------------------------------
function EEG = galea_process_ppg(EEG, g)
% Filter the PPG, then hand it to BrainBeats for beat detection and HRV.

if ~isfield(EEG.etc,'galea') || ~isfield(EEG.etc.galea,'PPG') || isempty(EEG.etc.galea.PPG)
    warning('No PPG stream in EEG.etc.galea; skipping.');
    return
end

if ~exist('brainbeats_process','file')
    % find it on disk, install it on the fly, or give up with clear guidance
    if ~galea_ensure_brainbeats(), return; end
end

PPG = EEG.etc.galea.PPG;
fprintf('PPG: %d channel(s) @ %g Hz, bandpass %.2f-%.2f Hz\n', ...
    PPG.nbchan, PPG.srate, g.ppglocut, g.ppghicut);
PPG = pop_eegfiltnew(PPG, 'locutoff', g.ppglocut, 'hicutoff', g.ppghicut, 'minphase', true);

feats = {};
if g.hrvtime,   feats{end+1} = 'time';      end
if g.hrvfreq,   feats{end+1} = 'frequency'; end
if g.hrvnonlin, feats{end+1} = 'nonlinear'; end

try
    PPG = brainbeats_process(PPG, 'analysis','features', ...
        'heart_signal','ppg', 'heart_channels',{PPG.chanlocs.labels}, ...
        'clean_eeg', 0, ...                        % EEG is cleaned above, not here
        'rr_correct', g.rrcorrect, ...
        'hrv_features', feats, ...
        'vis_cleaning', double(g.visppg), 'vis_outputs', double(g.visppg), ...
        'save', 0);
    EEG.etc.galea.PPG = PPG;
    if isfield(PPG.etc,'features')
        EEG.etc.galea.HRV = PPG.etc.features;
        fprintf('  HRV features stored in EEG.etc.galea.HRV\n');
    end
catch ME
    warning('BrainBeats failed: %s', ME.message);
end
end

% ---------------------------------------------------------------------------
function EEG = galea_process_stream(EEG, name, g)
% EDA, EMG and IMU. Each is filtered in its own band, optionally given a
% derived channel, and stored back in EEG.etc.galea. They are not merged into
% the EEG dataset: the sampling rates and units differ.
%
% EDA follows the published pipeline (0.01-1 Hz, downsampled to 8 Hz; a 0.05 Hz
% high-pass isolates the phasic component). EMG and IMU settings are sensible
% defaults rather than a validated pipeline - note the Aux stream is only 50 Hz,
% so EMG here is a coarse activity index, not a conventional EMG measurement.

if ~isfield(EEG.etc,'galea') || ~isfield(EEG.etc.galea, name) || isempty(EEG.etc.galea.(name))
    disp(sprintf('No %s stream in this recording; skipping.', name));
    return
end

D = EEG.etc.galea.(name);
if D.nbchan == 0, return; end
raw = D;

switch name
    case 'EDA'
        disp(sprintf('EDA: %.3f-%.2f Hz, downsample to %g Hz', g.edalocut, g.edahicut, g.edaresample));
        D = pop_eegfiltnew(D, 'hicutoff', g.edahicut);
        D = pop_eegfiltnew(D, 'locutoff', g.edalocut);
        if g.edaresample > 0 && g.edaresample ~= D.srate
            D = pop_resample(D, g.edaresample);
        end
        if g.edaphasic
            P = pop_eegfiltnew(D, 'locutoff', 0.05);   % phasic = fast component
            D.etc.eda_phasic = P.data;
            D.etc.eda_tonic  = D.data - P.data;
            disp('  tonic and phasic stored in .etc.eda_tonic / .etc.eda_phasic');
        end
        vis = g.viseda;

    case 'EMG'
        disp(sprintf('EMG: high-pass %g Hz', g.emglocut));
        D = pop_eegfiltnew(D, 'locutoff', g.emglocut);
        if g.emgenvelope
            D.data = abs(D.data);                       % rectify
            win = max(1, round(0.1 * D.srate));         % 100 ms moving average
            D.data = movmean(D.data, win, 2);
            disp('  rectified and 100 ms envelope applied');
        end
        vis = g.visemg;

    case 'IMU'
        disp(sprintf('IMU: low-pass %g Hz', g.imuhicut));
        D = pop_eegfiltnew(D, 'hicutoff', g.imuhicut);
        if g.imumagnitude
            acc = find(contains(lower({D.chanlocs.labels}), 'acc'));
            if numel(acc) >= 3
                mag = sqrt(sum(D.data(acc(1:3),:).^2, 1));
                D.data(end+1,:) = mag;
                D.nbchan = size(D.data,1);
                D.chanlocs(end+1).labels = 'ACC_MAG';
                D = eeg_checkset(D);
                disp('  ACC_MAG channel added');
            end
        end
        vis = g.visimu;
end

EEG.etc.galea.(name) = D;

if vis && usejava('desktop')
    figure('Color','w','Name',[name ' - raw (grey) vs processed']);
    tt = (0:D.pnts-1) / D.srate;
    tr = (0:raw.pnts-1) / raw.srate;
    n = min(D.nbchan, 4);
    for k = 1:n
        subplot(n,1,k); hold on
        if k <= raw.nbchan
            plot(tr, raw.data(k,:), 'Color',[.7 .7 .7]);
        end
        plot(tt, D.data(k,:), 'Color',[0.20 0.40 0.70], 'LineWidth',1);
        ylabel(D.chanlocs(k).labels, 'Interpreter','none');
        box off; set(gca,'TickDir','out')
    end
    xlabel('Time (s)');
end
end
