% Desktop wrapper for capture_gui_screenshots (run from -r, not -batch).
% Path surgery mirrors rerun_aperiodic_figs.m: EEGLAB plugin stubs
% (Biosig 'maybe-missing', FieldTrip compat) shadow base MATLAB functions
% (any.m, contains.m, isfile.m) and break findall/graphics code.
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
addpath(genpath(paths.eeglab));
warning('off', 'all');
rmpath(genpath(paths.eeglab_fieldtrip_compat));
rmpath(genpath(paths.eeglab_biosig_stubs));
addpath(paths.plugin);
rehash;

diary(fullfile(paths.root, 'matlab_gui_capture.log'));
fprintf('--- GUI capture start %s ---\n', datestr(now));
try
    capture_gui_screenshots(paths.manuscript_figures);
catch ME
    disp(getReport(ME));
end
fprintf('--- GUI capture end %s ---\n', datestr(now));
diary off;