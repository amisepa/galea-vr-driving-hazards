%% Copyright (c) 2026 Demet Yesilbas. GPL-3.0 (see the repository LICENSE).
%
% LOSO classification of the Galea VR driving-hazards dataset
% (Cannard & Yesilbas 2026, osf.io/xuw34). Three analyses:
%
%   01  EEG_PrePost_LOSO_N16.m          N = 16, EEG, pre/post windows
%   02  EEG_PrePost_Permutation_N16.m   N = 16, within-subject label
%                                       permutation nulls for 01
%   03  EEG_HR_Multimodal_LOSO_N14.m    N = 14 matched participants, EEG vs
%                                       HR vs EEG+HR fusion
%
% DATA
%   All three scripts load data/galea_ML_dataset.mat (see its header for the
%   variable list: ERP_avg, ERP_times, subjects and HR_avg, HR_times,
%   HR_subjects). The dataset is rebuilt from the study data by
%   pipeline/rebuild_erp_from_bids.m and analysis/export_for_ML.m.
%
% Reproduces the classification results in the manuscript (Table S3 and the
% reported accuracies; the CSV summary the document builder reads is
% results_final/ML/coauthor_classification.csv).

%% 01  EEG, N = 16 --------------------------------------------------------
run('analysis/classification/EEG_PrePost_LOSO_N16.m')

%% 02  permutation nulls for 01
run('analysis/classification/EEG_PrePost_Permutation_N16.m')

%% 03  multimodal EEG + HR, N = 14
run('analysis/classification/EEG_HR_Multimodal_LOSO_N14.m')