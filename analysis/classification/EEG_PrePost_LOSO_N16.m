%% Copyright (c) 2026 Demet Yesilbas. GPL-3.0 (see the repository LICENSE).
% Part of the Galea VR driving-hazards study code (Cannard & Yesilbas 2026,
% osf.io/xuw34). Loads its inputs from data/galea_ML_dataset.mat.

%% =========================================================
% 01_EEG_PrePost_LOSO_N16.m
%
% Main EEG classification analysis
%
% N = 16 participants
% Conditions:
%   1 = crash
%   2 = no-crash
%
% Time windows:
%   POST:  0 to +1200 ms
%   PRE:  -1200 to 0 ms
%
% Validation:
%   Leave-One-Subject-Out cross-validation (LOSO)
%
% Required input variables:
%   ERP_avg
%   ERP_times
%   subjects
%
% Required function:
%   runLOSOclassification.m
%% =========================================================

clc;
rng(42);

% ---- data (from data/galea_ML_dataset.mat) ----
D = load(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'data', 'galea_ML_dataset.mat'), 'ERP_avg', 'ERP_times', 'subjects');
ERP_avg   = D.ERP_avg;
ERP_times = D.ERP_times;
subjects  = D.subjects;



%% =========================================================
% SETTINGS
%% =========================================================

crashCond   = 1;
noCrashCond = 2;


%% =========================================================
% SUBJECT INFORMATION
%% =========================================================

erpSubjects = string(subjects(:));

fprintf('\n========================================\n');
fprintf('N=16 EEG CLASSIFICATION\n');
fprintf('========================================\n');

fprintf('Participants: %d\n',numel(erpSubjects));


%% =========================================================
% DEFINE ERP TIME WINDOWS
%% =========================================================

postERPIdx = ERP_times >= 0 & ERP_times <= 1200;

% Exclude zero from the pre-stimulus window so that
% the zero sample is not included in both windows.
preERPIdx = ERP_times >= -1200 & ERP_times < 0;

fprintf('\nPOST window: %.2f to %.2f ms\n', ...
    ERP_times(find(postERPIdx,1,'first')), ...
    ERP_times(find(postERPIdx,1,'last')));

fprintf('PRE window: %.2f to %.2f ms\n', ...
    ERP_times(find(preERPIdx,1,'first')), ...
    ERP_times(find(preERPIdx,1,'last')));


%% =========================================================
% BUILD POST-STIMULUS DATASET
%% =========================================================

[X_EEG_POST,Y16,subjectID16] = buildERPdataset( ...
    ERP_avg, ...
    erpSubjects, ...
    postERPIdx, ...
    crashCond, ...
    noCrashCond);


%% =========================================================
% BUILD PRE-STIMULUS DATASET
%% =========================================================

[X_EEG_PRE,Y16pre,subjectID16pre] = buildERPdataset( ...
    ERP_avg, ...
    erpSubjects, ...
    preERPIdx, ...
    crashCond, ...
    noCrashCond);


%% =========================================================
% SANITY CHECKS
%% =========================================================

assert(isequal(Y16,Y16pre), ...
    'Pre/post labels do not match.');

assert(isequal(subjectID16,subjectID16pre), ...
    'Pre/post subject ordering does not match.');

fprintf('\nObservations: %d\n',numel(Y16));

fprintf('POST EEG features: %d\n',size(X_EEG_POST,2));
fprintf('PRE EEG features : %d\n',size(X_EEG_PRE,2));


%% =========================================================
% LOSO PARTITION
%% =========================================================

uniqueSubjects16 = unique(subjectID16,'stable');

cv16 = cvpartition(numel(uniqueSubjects16),'LeaveOut');


%% =========================================================
% POST-STIMULUS CLASSIFICATION
%% =========================================================

fprintf('\n========================================\n');
fprintf('POST-STIMULUS EEG | N=16 | LOSO\n');
fprintf('========================================\n');

POST_results = runLOSOclassification( ...
    X_EEG_POST, ...
    [], ...
    Y16, ...
    subjectID16, ...
    uniqueSubjects16, ...
    cv16, ...
    "EEG");

disp(POST_results);


%% =========================================================
% PRE-STIMULUS CLASSIFICATION
%% =========================================================

fprintf('\n========================================\n');
fprintf('PRE-STIMULUS EEG | N=16 | LOSO\n');
fprintf('========================================\n');

PRE_results = runLOSOclassification( ...
    X_EEG_PRE, ...
    [], ...
    Y16, ...
    subjectID16, ...
    uniqueSubjects16, ...
    cv16, ...
    "EEG");

disp(PRE_results);


%% =========================================================
% SAVE RESULTS
%% =========================================================

writetable(POST_results, ...
    'Post1200_N16_LOSO.csv');

writetable(PRE_results, ...
    'Pre1200_N16_LOSO.csv');

save('N16_EEG_classification_results.mat', ...
    'POST_results', ...
    'PRE_results');


fprintf('\n========================================\n');
fprintf('N=16 EEG CLASSIFICATION COMPLETE\n');
fprintf('========================================\n');