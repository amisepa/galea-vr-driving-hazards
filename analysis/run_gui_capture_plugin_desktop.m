%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

% Desktop wrapper that refreshes the PLUGIN's own GUI screenshots
% (galea_eeglab_plugin/figures/). The manuscript captures live in
% manuscript/figures; this one keeps the repo set in sync with the current
% GUI code.
%
% Differences from run_gui_capture_desktop.m:
%   - captures into galea_eeglab_plugin/figures/ instead of manuscript/figures
%   - loads the plugin sample recording first, so the dialogs show the
%     detected sampling rates and the PPG branch instead of "detected: -"
%   - adds the main one-window Galea GUI (pop_galea) as a fourth capture
%
% Run with -r (desktop), not -batch: the dialogs must render on screen.
% Do not touch the mouse or keyboard while it runs (~30 s); each dialog
% closes itself.

% galea_set_paths lives in the repository ROOT, one level up from this
% script; -r starts in an arbitrary folder, so add it before anything else.
addpath(fileparts(fileparts(mfilename('fullpath'))));

paths = galea_set_paths();
addpath(genpath(paths.eeglab));
warning('off', 'all');
rmpath(genpath(paths.eeglab_fieldtrip_compat));
rmpath(genpath(paths.eeglab_biosig_stubs));
addpath(genpath(paths.plugin));
rehash;

diary(fullfile(paths.root, 'matlab_gui_capture_plugin.log'));
fprintf('--- plugin GUI capture start %s ---\n', datestr(now));

% Load the sample recording so the dialogs display real detected rates and
% the PPG/EDA/EMG/IMU branches appear enabled.
try
    assignin('base', 'EEG', []);
    evalin('base', ['EEG = pop_galea_import(''montage'',''default'', ' ...
        '''filename'',''Sample-Data-OpenBCI-RAW.txt'', ' ...
        '''filepath'',''' strrep(paths.plugin_sample_data, '\', '\\') ''');']);
catch ME
    disp(getReport(ME));
end

try
    capture_gui_screenshots(paths.plugin_figures);
catch ME
    disp(getReport(ME));
end

% Extra target the manuscript does not need: the main one-window GUI.
try
    before = findall(0, 'Type', 'figure');
    t = timer('StartDelay', 2.5, 'ExecutionMode', 'singleShot', ...
        'TimerFcn', @(~, ~) grab_main(before, fullfile(paths.plugin_figures, 'gui_main.png')));
    start(t);
    evalin('base', 'pop_galea(EEG);');
    stop(t); delete(t);
catch ME
    disp(getReport(ME));
end

fprintf('--- plugin GUI capture end %s ---\n', datestr(now));
diary off;
exit;

% ---------------------------------------------------------------------------
function grab_main(before, outfile)
% Close-and-capture for the main Galea window (same pattern as
% capture_gui_screenshots/grab, kept local so the shared function stays
% untouched for the manuscript captures).

new = setdiff(findall(0, 'Type', 'figure'), before);
fig = [];
for h = new(:)'
    if strcmp(get(h, 'Name'), 'Galea'), fig = h; break; end
end
if isempty(fig) && ~isempty(new), fig = new(1); end
if isempty(fig)
    fprintf(2, 'grab_main: no new figure found\n');
    return
end
try
    drawnow expose; pause(0.4);
    exportapp(fig, outfile);
    info = imfinfo(outfile);
    fprintf('wrote gui_main.png %d x %d px\n', info.Width, info.Height);
catch
    fprintf(2, 'grab_main: capture failed\n');
end
delete(fig);
end