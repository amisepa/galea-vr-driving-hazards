%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

% Minimal refresh of the PLUGIN screenshots: identical to the Sep-11
% manuscript capture (eeg_emptyset, no sample-data pre-load) but writing to
% galea_eeglab_plugin/figures/. Sample-data pre-load (run_gui_capture_plugin_desktop.m)
% hung under -r; do not use it.

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

evalin('base', 'clear EEG');
diary(fullfile(paths.root, 'matlab_gui_capture_plugin.log'));
fprintf('--- plugin GUI capture start %s ---\n', datestr(now));
try
    capture_gui_screenshots(paths.plugin_figures);
catch ME
    disp(getReport(ME));
end
fprintf('--- plugin GUI capture end %s ---\n', datestr(now));
diary off;
exit;
