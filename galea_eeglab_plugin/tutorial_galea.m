%% Galea plugin tutorial
%
% From a raw Galea recording to an ERP, in seven sections. Run one at a time
% (Ctrl+Enter, or "Run Section" in the editor).
%
% A recording is a PAIR of text files written by the Galea / OpenBCI GUI, both
% needed and both in the same folder:
%
%     OpenBCI-RAW-<date>.txt        EEG, EOG, EMG      <- point RAWFILE here
%     OpenBCI-RAW-Aux-<date>.txt    PPG, EDA, IMU      <- found automatically
%
% Everything through step 4 works on CONTINUOUS data. Epoching and ERPs use the
% standard EEGLAB functions, shown in steps 5-7.
%
% Cedric Cannard, August 2026

%% 1. Set up
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
% Edit these three paths.

EEGLAB_PATH = paths.eeglab;
PLUGIN_PATH = paths.plugin;
RAWFILE     = fullfile(paths.plugin_sample_data, 'Sample-Data-OpenBCI-RAW.txt');

% genpath so functions/ comes along too - galea_import lives there. Set
% PLUGIN_PATH explicitly: mfilename returns empty when you run a section from
% the editor, so deriving the path from it silently adds nothing.
addpath(EEGLAB_PATH);
addpath(genpath(PLUGIN_PATH));
eeglab nogui;

assert(isfile(RAWFILE), 'RAWFILE not found: %s', RAWFILE);
[filepath, name, ext] = fileparts(RAWFILE);
fprintf('Ready: %s%s\n', name, ext);


%% 2. Load
% 'default' is the stock 10-channel layout. Use 'custom' for 12 channels, where
% the two EMG disc electrodes are treated as Fp1/Fp2.
% Non-EEG streams are kept in EEG.etc.galea (PPG, EDA, IMU, EOG, EMG).

EEG = pop_galea_import('montage','default', 'filename',[name ext], 'filepath',filepath);

fprintf('\n%d channels, %.1f min, %g Hz\n', EEG.nbchan, EEG.pnts/EEG.srate/60, EEG.srate);
fprintf('%s\n', strjoin({EEG.chanlocs.labels}, ' '));

% Same thing by clicking:  Galea > Load Galea data...


%% 3. Events
% Numeric triggers were mapped to labels during import (only for the VR driving
% paradigm; any other code set is left alone).

types = unique({EEG.event.type});
fprintf('\n%d events\n', numel(EEG.event));
for k = 1:numel(types)
    fprintf('   %-16s %d\n', types{k}, sum(strcmp({EEG.event.type}, types{k})));
end


%% 4. Preprocess
% Downsample, causal filter, polarity check, bad channels, ASR, and ICA with
% the ocular component removed. Causal filtering matters if you will look at
% the PRE-stimulus period: a zero-phase filter smears post-stimulus activity
% backwards and can manufacture an anticipatory effect.
%
% Add 'ppg',true to also run the PPG through BrainBeats.

EEG = pop_galea_preprocess(EEG, 'resample',250, 'locut',0.5, 'hicut',30, ...
    'causal',true, 'badchan',true, 'asr',100, 'ica',true);

% Same thing by clicking:  Galea > Preprocess (Cannard 2026)...


%% 5. Epoch
% Cut around the tyre blowout. No baseline correction, so the pre- and
% post-stimulus periods stay comparable.

EPOCH_WINDOW = [-1.5 1.5];                       % seconds
CONDITIONS   = {'tire_pop', 'no_tire_pop'};      % collision, no-collision

have = intersect(CONDITIONS, unique({EEG.event.type}));
assert(~isempty(have), 'None of %s present - edit CONDITIONS.', strjoin(CONDITIONS,'/'));

EPO = pop_epoch(EEG, have, EPOCH_WINDOW, 'epochinfo','yes');
fprintf('\n%d epochs of %g s\n', EPO.trials, diff(EPOCH_WINDOW));


%% 6. Average by condition
% Split the epoched set with pop_select, then average over trials.

ERP = cell(1, numel(CONDITIONS));
for k = 1:numel(CONDITIONS)
    idx = find(cellfun(@(t) any(strcmp(t, CONDITIONS{k})), {EPO.epoch.eventtype}));
    SET = pop_select(EPO, 'trial', idx);
    ERP{k} = mean(SET.data, 3);                   % [channels x time]
    disp(sprintf('%-14s %d epochs', CONDITIONS{k}, numel(idx)))
end
times = EPO.times;


%% 7. Plot
% One participant, so this is a descriptive picture, not a test: the shaded
% band is the spread across channels, not a confidence interval on an effect.
% Set CHANS to a single site to look at one electrode instead.

CHANS = 1:EPO.nbchan;      % e.g. find(strcmpi({EPO.chanlocs.labels}, 'CZ'))
cols  = [0.85 0.33 0.10; 0.20 0.40 0.70];

figure('Color','w'); hold on
for k = 1:numel(CONDITIONS)
    m  = mean(ERP{k}(CHANS,:), 1);
    se = std(ERP{k}(CHANS,:), 0, 1) ./ sqrt(numel(CHANS));
    if numel(CHANS) > 1
        fill([times fliplr(times)], [m-se fliplr(m+se)], cols(k,:), ...
            'FaceAlpha',0.2, 'EdgeColor','none', 'HandleVisibility','off');
    end
    plot(times, m, 'Color',cols(k,:), 'LineWidth',1.5, 'DisplayName',CONDITIONS{k});
end
xline(0,'k:'); yline(0,'k:');
xlabel('Time from tyre blowout (ms)'); ylabel('Amplitude (\muV)');
if numel(CHANS) > 1
    title(sprintf('ERP, mean +/- SEM across %d channels (one participant)', numel(CHANS)));
else
    title(sprintf('ERP at %s (one participant)', EPO.chanlocs(CHANS).labels));
end
legend('Location','best'); box off; set(gca,'TickDir','out')

% Group level: loop steps 1-6 over participants, collect each one into
% allERP(subject, condition, channel, time), then average over subjects and
% test across them. analysis/rerun_final_stats.m does exactly that.