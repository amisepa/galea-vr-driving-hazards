%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function paths = galea_set_paths(eeglab_path, robust_path, ascent_path, data_path)
%GALEA_SET_PATHS  Configure the paths used by every Galea study script.
%
%   paths = galea_set_paths;
%
% This is the single place where machine-specific locations are configured.
% Edit the four defaults below to match your installation; the analysis and
% pipeline scripts call this function and derive everything else from it.
%
% paths.data must point at the study data folder, which holds one folder per
% participant (sub-000, sub-001, ...) containing the OpenBCI RAW recordings,
% their Aux companions, and the per-subject ERP/PPG exports.
%
% The companion repositories are available at:
%   github.com/amisepa/eeg_robust_statistics
%   github.com/amisepa/Ascent
%
% Cedric Cannard, 2026

% ----- EDIT THESE PATHS FOR YOUR MACHINE ----------------------------------
if nargin < 1 || isempty(eeglab_path)
    eeglab_path = 'C:\Users\ccann\Documents\MATLAB\eeglab';                % EEGLAB
end
if nargin < 2 || isempty(robust_path)
    robust_path = 'C:\Users\ccann\Documents\MATLAB\eeg_robust_statistics'; % robust statistics toolbox
end
if nargin < 3 || isempty(ascent_path)
    ascent_path = 'C:\Users\ccann\Documents\MATLAB\Ascent';                % aperiodic fitting
end
if nargin < 4 || isempty(data_path)
    data_path = 'C:\Users\ccann\Proton Drive\ccannard\My files\DATA\IONS_Galea_VR_study\study_data';
end
% --------------------------------------------------------------------------

% Repository root: the folder that contains analysis/, pipeline/, etc.
% (mfilename('fullpath') = <root>\galea_set_paths, so one fileparts gets <root>)
paths.root = fileparts(mfilename('fullpath'));

% User-configured locations
paths.eeglab = eeglab_path;
paths.robust = robust_path;
paths.ascent = ascent_path;
paths.data   = data_path;

% Robust-Correlations toolbox (github.com/amisepa/Robust-Correlations), used
% by analysis/run_final_H4_tf_symmetry.m. Expected one level up from this
% repository; override here if yours lives elsewhere.
paths.robust_correlations = fullfile(fileparts(paths.root), 'Robust-Correlations');

% Repository subfolders
paths.analysis           = fullfile(paths.root, 'analysis');
paths.analysis_functions = fullfile(paths.root, 'analysis', 'functions');
paths.pipeline_functions = fullfile(paths.root, 'pipeline', 'functions');
% EEGLAB plugin (github.com/amisepa/galea-eeglab-plugin). Developed and
% released separately; expected cloned next to this repository. If you
% installed it into eeglab/plugins/ instead, point paths.plugin there.
paths.plugin             = fullfile(fileparts(paths.root), 'galea-eeglab-plugin');
paths.plugin_functions   = fullfile(paths.plugin, 'functions');
paths.plugin_sample_data = fullfile(paths.plugin, 'sample_data');
paths.plugin_figures     = fullfile(paths.plugin, 'figures');
if ~isfolder(paths.plugin)
    % fall back to an EEGLAB extension-manager install (eeglab/plugins/galea<version>)
    d = dir(fullfile(paths.eeglab, 'plugins', 'galea*'));
    d = d([d.isdir]);
    if ~isempty(d)
        paths.plugin = fullfile(d(end).folder, d(end).name);
    end
    paths.plugin_functions   = fullfile(paths.plugin, 'functions');
    paths.plugin_sample_data = fullfile(paths.plugin, 'sample_data');
    paths.plugin_figures     = fullfile(paths.plugin, 'figures');
end
paths.figures            = fullfile(paths.root, 'figures');
paths.data_repo          = fullfile(paths.root, 'data');

% Results folders (written by the run_final_* scripts, read by make_figures.m)
results = fullfile(paths.root, 'results_final');
paths.results        = results;
paths.res_time       = fullfile(results, 'EEG_time');
paths.res_tf_causal  = fullfile(results, 'EEG_tf_causal');
paths.res_alday      = fullfile(results, 'EEG_alday');
paths.res_covariates = fullfile(results, 'EEG_covariates');
paths.res_cardiac    = fullfile(results, 'EEG_cardiac');
paths.res_ml         = fullfile(results, 'ML');

% Data files
paths.ml_dataset    = fullfile(paths.data_repo, 'galea_ML_dataset.mat');
paths.questionnaires = fullfile(paths.data, 'participant_data', 'subjects_questionnaires_data.xlsx');

% EEGLAB plugin folders whose stub functions shadow MATLAB built-ins in batch
% runs; remove them from the path if a built-in is shadowed.
paths.eeglab_fieldtrip_compat = fullfile(paths.eeglab, 'plugins', 'Fieldtrip-lite250523', 'compat');
paths.eeglab_biosig_stubs     = fullfile(paths.eeglab, 'plugins', 'Biosig3.8.5', 'biosig', 'maybe-missing');

% Put the repository code and the dependencies on the MATLAB path
addpath(paths.pipeline_functions, paths.plugin_functions, paths.analysis_functions, ...
        paths.plugin, paths.analysis, paths.eeglab, paths.robust, ...
        fullfile(paths.robust, 'functions'), paths.ascent, ...
        fullfile(paths.ascent, 'functions'));

end