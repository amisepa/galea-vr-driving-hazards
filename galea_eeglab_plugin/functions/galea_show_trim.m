function galea_show_trim(EEGori, EEG, trimPad)
% GALEA_SHOW_TRIM  Overview figure showing what the trim step removed.
%
%   >> galea_show_trim(EEG_before_trim, EEG_after_trim, trimPad)
%
% One panel per signal (EEG plus any auxiliary streams present), showing the
% WHOLE recording zoomed out: a representative trace (EEG: robust envelope /
% RMS across channels; aux streams: every channel), the first and last event
% as vertical markers, the kept span, and the two trimmed periods shaded red.
% Lets the user verify at a glance that the trim removed only the artefact-
% filled head and tail of the recording.
%
% Cedric Cannard, 2026

if ~usejava('desktop'), return; end

% event times in seconds, from the original (untrimmed) EEG
lat = [EEGori.event.latency];
evT = (lat - 1) / EEGori.srate;
firstEv = min(evT); lastEv = max(evT);
T = EEGori.pnts / EEGori.srate;

streams = {{'EEG', EEGori, EEG}};
if isfield(EEGori.etc, 'galea')
    for an = {'PPG','EDA','EMG','IMU'}
        nm = an{1};
        if isfield(EEGori.etc.galea, nm) && ~isempty(EEGori.etc.galea.(nm)) && ...
                EEGori.etc.galea.(nm).nbchan > 0 && isfield(EEG.etc.galea, nm)
            streams{end+1} = {nm, EEGori.etc.galea.(nm), EEG.etc.galea.(nm)}; %#ok<AGROW>
        end
    end
end

figure('Color','w', 'Name','Trim overview', 'NumberTitle','off');
nS = numel(streams);
for s = 1:nS
    nm   = streams{s}{1};
    ori  = streams{s}{2};
    kept = streams{s}{3};
    ax = subplot(nS, 1, s); hold(ax, 'on'); box(ax, 'off');
    if s == 1, axFirst = ax; end   % top panel; titled after the loop

    T0 = ori.pnts / ori.srate;
    t  = (0:ori.pnts-1) / ori.srate;

    % trace: robust across-channel envelope for EEG, raw traces for aux
    if strcmpi(nm, 'EEG')
        env = sqrt(movmean(ori.data.^2, round(0.25*ori.srate), 2));
        env = squeeze(mean(env, 1));
        lo = -5*std(env(:)); hi = 5*std(env(:));
    else
        env = squeeze(mean(ori.data, 1));
        if isvector(env), env = env(:)'; end
        lo = min(env); hi = max(env);
        pad = 0.1 * max(abs([lo hi])) + eps;
        lo = lo - pad; hi = hi + pad;
    end

    % kept span (from the post-trim dataset's own time axis)
    t0k = kept.xmin; t1k = t0k + kept.pnts / kept.srate;

    % trimmed regions shaded red
    if t0k > 0,      patch(ax, [0 t0k t0k 0], [lo lo hi hi], [1 .82 .82], 'EdgeColor','none'); end
    if t1k < T0,     patch(ax, [t1k T0 T0 t1k], [lo lo hi hi], [1 .82 .82], 'EdgeColor','none'); end

    % the signal
    plot(ax, t, env, 'Color', [0.25 0.4 0.7]);

    % event markers: first and last event, plus every event as a faint tick
    yl = ylim(ax);
    plot(ax, [firstEv firstEv], yl, 'Color', [0 0.55 0], 'LineWidth', 1);
    plot(ax, [lastEv lastEv], yl, 'Color', [0.9 0.4 0], 'LineWidth', 1);
    if numel(evT) <= 130
        plot(ax, [evT evT], [yl(1) yl(1) + 0.08*(yl(2)-yl(1))], 'Color', [.6 .6 .6]);
    end

    text(ax, firstEv, hi, sprintf(' first event (t=%.1f s)', firstEv), ...
        'FontSize', 8, 'Color', [0 0.55 0], 'VerticalAlignment','bottom');
    text(ax, lastEv, hi, sprintf(' last event (t=%.1f s)', lastEv), ...
        'FontSize', 8, 'Color', [0.9 0.4 0], 'VerticalAlignment','bottom','HorizontalAlignment','right');
    % trimmed labels sit at the BOTTOM of the panel so they can never collide
    % with the first/last event labels at the top (they collide when the pad
    % is small and the last event sits right next to the trimmed region)
    if t0k > 0
        text(ax, t0k/2, lo, sprintf('trimmed %.1f s', t0k), 'FontSize',8, ...
            'Color',[.6 0 0], 'HorizontalAlignment','center','VerticalAlignment','top');
    end
    if t1k < T0
        text(ax, (t1k+T0)/2, lo, sprintf('trimmed %.1f s', T0-t1k), 'FontSize',8, ...
            'Color',[.6 0 0], 'HorizontalAlignment','center','VerticalAlignment','top');
    end
    xlim(ax, [0 T0]); ylim(ax, [lo hi]);
    ylabel(ax, nm, 'FontWeight','bold', 'Interpreter','none');
    if s == nS, xlabel(ax, 'Time (s)'); end
    set(ax, 'TickDir','out');
end
% note about the pad (subplot allows at most ONE output, so the previous
% [~, h] = subplot(...) call failed with "Too many output arguments" after
% the figure was drawn; keep the axes handle from the loop instead)
title(axFirst, sprintf('Recording before vs after trimming (pad %.0f s kept around the first/last event; red = removed)', trimPad), ...
    'FontSize', 9, 'Interpreter','none');
end