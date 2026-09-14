function plot_tf_clusters(mask_clusters, summary_tbl, tvals, time, foi, mcc_type, out_path)
% One diagnostic panel pair per surviving cluster: mean t across the cluster's
% frequency band over time, and mean t across the cluster's time window over
% frequency.
%
% Both traces run the full length of their axis so the cluster is seen in
% context, but the part inside the cluster is drawn solid and the rest faded.
% Without that split, a neighbouring cluster of the opposite sign shows up as a
% large excursion in this cluster's panel and reads as a sign reversal of THIS
% effect. That is exactly what happens here: cluster 1 spans almost the whole
% analysed band, so its time course picks up the later alpha-beta decrease that
% is really cluster 2.


% Headless guard. MATLAB -batch aborts or hangs on figure creation; skip
% plotting when there is no desktop.
if ~usejava('desktop')
    disp('  (headless: skipping plot_tf_clusters)');
    return
end

if isempty(mask_clusters), return; end

foi  = foi(:).';
time = time(:).';

for iClust = 1:length(mask_clusters)
    cmask = mask_clusters{iClust};
    fsel  = any(cmask, 2).';    % frequencies the cluster touches
    tsel  = any(cmask, 1);      % time points the cluster touches

    t_course  = mean(tvals(fsel, :), 1);
    f_profile = mean(tvals(:, tsel), 2).';

    fig = figure('Color','w','Position',[100 100 900 320]);

    % ---- Time course ----------------------------------------------------
    subplot(1,2,1)
    yl = pad_lim(t_course);
    shade_runs(time, tsel, yl, 'x'); hold on
    split_plot(time, t_course, tsel, [0.20 0.40 0.70], 'x');
    yline(0, ':', 'Color', [0.5 0.5 0.5], 'LineWidth', 1); hold off
    xlim([time(1) time(end)]); ylim(yl)
    xlabel('Time (ms)'); ylabel('Mean t-value')
    title(sprintf('Cluster %d time course (%.1f-%.1f Hz)', ...
        iClust, min(foi(fsel)), max(foi(fsel))))

    % ---- Frequency profile ----------------------------------------------
    subplot(1,2,2)
    xl = pad_lim(f_profile);
    % Shade only when the band is a genuine subset of the analysed range. A
    % patch covering the whole axis, which is what a full-band cluster gives,
    % marks nothing and just reads as a grey background.
    full_band = nnz(fsel) >= 0.9 * numel(foi);
    if ~full_band
        shade_runs(foi, fsel, xl, 'y');
    end
    hold on
    split_plot(foi, f_profile, fsel, [0.85 0.33 0.10], 'y');
    xline(0, ':', 'Color', [0.5 0.5 0.5], 'LineWidth', 1); hold off
    xlim(xl); ylim([foi(1) foi(end)])
    ylabel('Frequency (Hz)'); xlabel('Mean t-value')
    if full_band
        title(sprintf('Cluster %d frequency profile (spans analysed band)', iClust))
    else
        title(sprintf('Cluster %d frequency profile', iClust))
    end

    set(findall(fig, 'type', 'axes'), 'FontSize', 11, 'FontWeight', 'normal', ...
        'TickDir', 'out', 'Box', 'off', 'LineWidth', 0.9)
    set(findall(fig, 'type', 'axes'), {'TitleFontWeight'}, {'bold'})

    saveas(fig, fullfile(out_path, sprintf('TF_Clust%d_corr-%d.fig', iClust, mcc_type)));
    print(fig,  fullfile(out_path, sprintf('TF_Clust%d_corr-%d.png', iClust, mcc_type)), '-dpng','-r300');
end
end

% ── PLOT HELPERS ─────────────────────────────────────────────────
function l = pad_lim(v)
% Axis limits with 8% headroom, so a trace never runs into the axis edge.
v = v(isfinite(v));
r = max(v) - min(v);
if r == 0, r = 1; end
l = [min(v) - 0.08*r, max(v) + 0.08*r];
end

function shade_runs(ax_vals, sel, lim_other, orient)
% Grey patch over every CONTIGUOUS run of sel. Looping over runs rather than
% filling from first to last index keeps the shading honest if a cluster is
% split along the plotted axis.
d = diff([false, logical(sel), false]);
starts = find(d == 1);
stops  = find(d == -1) - 1;
for k = 1:numel(starts)
    lo = ax_vals(starts(k));
    hi = ax_vals(stops(k));
    if strcmp(orient, 'x')
        patch([lo hi hi lo], [lim_other(1) lim_other(1) lim_other(2) lim_other(2)], ...
            [0.85 0.85 0.85], 'EdgeColor','none','FaceAlpha',0.5);
    else
        patch([lim_other(1) lim_other(1) lim_other(2) lim_other(2)], [lo lo hi hi], ...
            [0.85 0.85 0.85], 'EdgeColor','none','FaceAlpha',0.5);
    end
end
end

function split_plot(ax_vals, dat, sel, col, orient)
% Full trace faded, the part inside the cluster solid on top.
inside = dat;
inside(~logical(sel)) = NaN;
if strcmp(orient, 'x')
    plot(ax_vals, dat,    'LineWidth', 1.2, 'Color', [col 0.30]);
    plot(ax_vals, inside, 'LineWidth', 2.4, 'Color', col);
else
    plot(dat,    ax_vals, 'LineWidth', 1.2, 'Color', [col 0.30]);
    plot(inside, ax_vals, 'LineWidth', 2.4, 'Color', col);
end
end
