%% Copyright (c) 2026 Demet Yesilbas. GPL-3.0 (see the repository LICENSE).
% Part of the Galea VR driving-hazards study code (Cannard & Yesilbas 2026,
% osf.io/xuw34). Loads its inputs from data/galea_ML_dataset.mat.

%% =========================================================
% 03_EEG_HR_Multimodal_LOSO_N14
%
% Matched-subject multimodal classification analysis
%
% Analyses:
%   1. EEG only
%   2. HR only
%   3. EEG + HR early fusion
%
% EEG window:
%   Post-stimulus 0 to +1200 ms
%
% HR features:
%   All 11 PPG-derived heart-rate values from -5 to +5 s
%
% Classification:
%   Leave-One-Subject-Out cross-validation
%
% Labels:
%   1 = crash
%   0 = no-crash
%
% Required workspace variables:
%   ERP_avg
%   ERP_times
%   subjects
%   HR_avg
%   HR_subjects
%   HR_times
%
% Required function:
%   runLOSOclassification.m
% =========================================================

clc;

rng(42);

% ---- data (from data/galea_ML_dataset.mat) ----
D = load(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'data', 'galea_ML_dataset.mat'), 'ERP_avg', 'ERP_times', 'subjects', 'HR_avg', 'HR_times', 'HR_subjects');
ERP_avg     = D.ERP_avg;   ERP_times   = D.ERP_times;   subjects    = D.subjects;
HR_avg      = D.HR_avg;    HR_times    = D.HR_times;    HR_subjects = D.HR_subjects;


fprintf('\n========================================\n');
fprintf('N=14 MATCHED EEG + HR CLASSIFICATION\n');
fprintf('========================================\n');


%% =========================================================
% DEFINE CONDITION MAPPING
%% =========================================================

% IMPORTANT:
% Verify that condition 1 = crash and condition 2 = no-crash
% in both ERP_avg and HR_avg before public release.

crashCond   = 1;
noCrashCond = 2;


%% =========================================================
% DEFINE EEG POST-STIMULUS WINDOW
%% =========================================================

postMask = ERP_times >= 0 & ERP_times <= 1200;

postTimes = ERP_times(postMask);

fprintf('\nEEG POST window: %.2f to %.2f ms\n', ...
    postTimes(1),postTimes(end));


%% =========================================================
% IDENTIFY MATCHED EEG-HR PARTICIPANTS
%% =========================================================

subjects     = string(subjects(:));
HR_subjects  = string(HR_subjects(:));

commonSubjects = intersect(subjects,HR_subjects,'stable');

nSubjects = numel(commonSubjects);

fprintf('Matched participants: %d\n',nSubjects);

if nSubjects ~= 14
    warning('Expected 14 matched participants but found %d.',nSubjects);
end


%% =========================================================
% INITIALIZE DATA MATRICES
%% =========================================================

X_EEG = [];
X_HR  = [];

Y = [];

subjectID = strings(0,1);


%% =========================================================
% BUILD MATCHED N=14 DATASET
%% =========================================================

for s = 1:nSubjects

    subjectName = commonSubjects(s);

    eegIdx = find(subjects == subjectName,1);
    hrIdx  = find(HR_subjects == subjectName,1);


    if isempty(eegIdx)
        error('EEG data not found for %s.',subjectName);
    end

    if isempty(hrIdx)
        error('HR data not found for %s.',subjectName);
    end


    %% -----------------------------------------------------
    % EEG: crash
    %% -----------------------------------------------------

    crashEEG = squeeze(ERP_avg( ...
        eegIdx, ...
        crashCond, ...
        :, ...
        postMask));

    crashEEG = crashEEG(:)';


    %% -----------------------------------------------------
    % EEG: no-crash
    %% -----------------------------------------------------

    noCrashEEG = squeeze(ERP_avg( ...
        eegIdx, ...
        noCrashCond, ...
        :, ...
        postMask));

    noCrashEEG = noCrashEEG(:)';


    %% -----------------------------------------------------
    % HR: crash
    %% -----------------------------------------------------

    crashHR = squeeze(HR_avg( ...
        hrIdx, ...
        crashCond, ...
        :));

    crashHR = crashHR(:)';


    %% -----------------------------------------------------
    % HR: no-crash
    %% -----------------------------------------------------

    noCrashHR = squeeze(HR_avg( ...
        hrIdx, ...
        noCrashCond, ...
        :));

    noCrashHR = noCrashHR(:)';


    %% -----------------------------------------------------
    % Append observations
    %% -----------------------------------------------------

    X_EEG = [
        X_EEG
        crashEEG
        noCrashEEG
        ];

    X_HR = [
        X_HR
        crashHR
        noCrashHR
        ];

    Y = [
        Y
        1
        0
        ];

    subjectID = [
        subjectID
        subjectName
        subjectName
        ];

end


%% =========================================================
% DATASET CHECKS
%% =========================================================

fprintf('\n========================================\n');
fprintf('MATCHED DATASET\n');
fprintf('========================================\n');

fprintf('Observations: %d\n',size(X_EEG,1));
fprintf('EEG features: %d\n',size(X_EEG,2));
fprintf('HR features : %d\n',size(X_HR,2));

fprintf('Crash observations   : %d\n',sum(Y == 1));
fprintf('No-crash observations: %d\n',sum(Y == 0));


if size(X_EEG,1) ~= 2*nSubjects
    error('Unexpected number of EEG observations.');
end

if size(X_HR,1) ~= 2*nSubjects
    error('Unexpected number of HR observations.');
end

if numel(Y) ~= 2*nSubjects
    error('Unexpected number of labels.');
end

if numel(subjectID) ~= 2*nSubjects
    error('Unexpected number of subject IDs.');
end


%% =========================================================
% LOSO CROSS-VALIDATION
%% =========================================================

uniqueSubjects = unique(subjectID,'stable');

cv = cvpartition(numel(uniqueSubjects),'LeaveOut');


%% =========================================================
% 1. EEG-ONLY CLASSIFICATION
%% =========================================================

fprintf('\n========================================\n');
fprintf('EEG ONLY | N=%d | LOSO\n',nSubjects);
fprintf('========================================\n');

EEG_results = runLOSOclassification( ...
    X_EEG, ...
    [], ...
    Y, ...
    subjectID, ...
    uniqueSubjects, ...
    cv, ...
    "EEG");

disp(EEG_results);


%% =========================================================
% 2. HR-ONLY CLASSIFICATION
%% =========================================================

fprintf('\n========================================\n');
fprintf('HR ONLY | N=%d | LOSO\n',nSubjects);
fprintf('========================================\n');

HR_results = runLOSOclassification( ...
    X_HR, ...
    [], ...
    Y, ...
    subjectID, ...
    uniqueSubjects, ...
    cv, ...
    "HR");

disp(HR_results);


%% =========================================================
% 3. EEG + HR EARLY FUSION
%% =========================================================

fprintf('\n========================================\n');
fprintf('EEG + HR FUSION | N=%d | LOSO\n',nSubjects);
fprintf('========================================\n');

FUSION_results = runLOSOclassification( ...
    X_EEG, ...
    X_HR, ...
    Y, ...
    subjectID, ...
    uniqueSubjects, ...
    cv, ...
    "FUSION");

disp(FUSION_results);


%% =========================================================
% CREATE COMPARISON TABLE
%% =========================================================

comparisonTable = table();

for i = 1:height(EEG_results)

    comparisonTable = [
        comparisonTable

        table( ...
            "EEG", ...
            string(EEG_results.Classifier{i}), ...
            EEG_results.Accuracy(i), ...
            EEG_results.Sensitivity(i), ...
            EEG_results.Specificity(i), ...
            EEG_results.Precision(i), ...
            EEG_results.F1(i), ...
            EEG_results.AUC(i), ...
            'VariableNames', ...
            {'Modality', ...
             'Classifier', ...
             'Accuracy', ...
             'Sensitivity', ...
             'Specificity', ...
             'Precision', ...
             'F1', ...
             'AUC'})

        table( ...
            "HR", ...
            string(HR_results.Classifier{i}), ...
            HR_results.Accuracy(i), ...
            HR_results.Sensitivity(i), ...
            HR_results.Specificity(i), ...
            HR_results.Precision(i), ...
            HR_results.F1(i), ...
            HR_results.AUC(i), ...
            'VariableNames', ...
            {'Modality', ...
             'Classifier', ...
             'Accuracy', ...
             'Sensitivity', ...
             'Specificity', ...
             'Precision', ...
             'F1', ...
             'AUC'})

        table( ...
            "EEG+HR", ...
            string(FUSION_results.Classifier{i}), ...
            FUSION_results.Accuracy(i), ...
            FUSION_results.Sensitivity(i), ...
            FUSION_results.Specificity(i), ...
            FUSION_results.Precision(i), ...
            FUSION_results.F1(i), ...
            FUSION_results.AUC(i), ...
            'VariableNames', ...
            {'Modality', ...
             'Classifier', ...
             'Accuracy', ...
             'Sensitivity', ...
             'Specificity', ...
             'Precision', ...
             'F1', ...
             'AUC'})
        ];

end


%% =========================================================
% DISPLAY COMPARISON
%% =========================================================

fprintf('\n========================================\n');
fprintf('MATCHED N=14 COMPARISON\n');
fprintf('========================================\n');

disp(comparisonTable);


%% =========================================================
% SAVE RESULTS
%% =========================================================

writetable( ...
    comparisonTable, ...
    'Matched_N14_EEG_HR_Comparison.csv');

save( ...
    'Matched_N14_EEG_HR_results.mat', ...
    'EEG_results', ...
    'HR_results', ...
    'FUSION_results', ...
    'comparisonTable', ...
    'commonSubjects');


fprintf('\n========================================\n');
fprintf('N=14 MULTIMODAL CLASSIFICATION COMPLETE\n');
fprintf('========================================\n');