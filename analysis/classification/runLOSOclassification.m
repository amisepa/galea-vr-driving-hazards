%% Copyright (c) 2026 Demet Yesilbas. GPL-3.0 (see the repository LICENSE).
% Helper for the Galea VR driving-hazards classification analyses
% (Cannard & Yesilbas 2026, osf.io/xuw34).

function results = runLOSOclassification( ...
    X1,X2,Y,subjectID,uniqueSubjects,cv,analysisType)

% =========================================================
% LEAVE-ONE-SUBJECT-OUT (LOSO) CLASSIFICATION
%
% Labels:
%   1 = crash
%   0 = no-crash
%
% analysisType:
%   "EEG"
%   "HR"
%   "FUSION"
%
% For FUSION:
%   EEG and HR are standardized separately using training
%   data only, then concatenated (early fusion).
%
% Classifiers:
%   SVM
%   KNN
%   Naive Bayes
%   Random Forest
%   Decision Tree
%   ANN
% =========================================================


%% =========================================================
% CLASSIFIERS
%% =========================================================

classifierNames = ...
    {'SVM','KNN','NaiveBayes', ...
     'RandomForest','DecisionTree','ANN'};

nClassifiers = numel(classifierNames);


%% =========================================================
% CONVERT LABELS TO NUMERIC 0/1
%% =========================================================

if iscategorical(Y) || isstring(Y) || iscellstr(Y)

    Ystr = string(Y(:));

    Y_numeric = nan(size(Ystr));

    Y_numeric(Ystr == "crash")    = 1;
    Y_numeric(Ystr == "nocrash")  = 0;
    Y_numeric(Ystr == "no_crash") = 0;
    Y_numeric(Ystr == "no-crash") = 0;

    if any(isnan(Y_numeric))
        error('Some class labels could not be converted to numeric 0/1.');
    end

    Y = Y_numeric;

else

    Y = double(Y(:));

end


if ~all(ismember(unique(Y),[0 1]))
    error('Labels must contain only 0 and 1.');
end


%% =========================================================
% INITIALIZE OUTPUT STORAGE
%% =========================================================

predictions = struct();
scores      = struct();

for c = 1:nClassifiers

    predictions.(classifierNames{c}) = nan(size(Y));
    scores.(classifierNames{c})      = nan(size(Y));

end


%% =========================================================
% LOSO LOOP
%% =========================================================

for fold = 1:cv.NumTestSets

    trainSubjectMask = training(cv,fold);
    testSubjectMask  = test(cv,fold);

    trainSubjects = uniqueSubjects(trainSubjectMask);
    testSubjects  = uniqueSubjects(testSubjectMask);

    trainIdx = ismember(subjectID,trainSubjects);
    testIdx  = ismember(subjectID,testSubjects);

    yTrain = Y(trainIdx);


    % -------------------------------------------------------
    % Safety check
    % -------------------------------------------------------

    if numel(unique(yTrain)) ~= 2
        error( ...
            'Fold %d training data does not contain both classes.', ...
            fold);
    end


    fprintf('%s LOSO Fold %d/%d | Test: %s\n', ...
        analysisType, ...
        fold, ...
        cv.NumTestSets, ...
        char(testSubjects));


    %% =====================================================
    % TRAINING-FOLD-ONLY STANDARDIZATION
    %% =====================================================

    if analysisType == "FUSION"

        % ---------------------------------------------------
        % Modality 1: EEG
        % ---------------------------------------------------

        train1 = X1(trainIdx,:);
        test1  = X1(testIdx,:);

        mu1 = mean(train1,1);
        sd1 = std(train1,[],1);

        sd1(sd1 == 0 | isnan(sd1)) = 1;

        train1 = (train1 - mu1) ./ sd1;
        test1  = (test1  - mu1) ./ sd1;


        % ---------------------------------------------------
        % Modality 2: HR
        % ---------------------------------------------------

        train2 = X2(trainIdx,:);
        test2  = X2(testIdx,:);

        mu2 = mean(train2,1);
        sd2 = std(train2,[],1);

        sd2(sd2 == 0 | isnan(sd2)) = 1;

        train2 = (train2 - mu2) ./ sd2;
        test2  = (test2  - mu2) ./ sd2;


        % ---------------------------------------------------
        % Early fusion
        % ---------------------------------------------------

        XTrain = [train1 train2];
        XTest  = [test1 test2];


    else

        XTrain = X1(trainIdx,:);
        XTest  = X1(testIdx,:);

        mu = mean(XTrain,1);
        sd = std(XTrain,[],1);

        sd(sd == 0 | isnan(sd)) = 1;

        XTrain = (XTrain - mu) ./ sd;
        XTest  = (XTest  - mu) ./ sd;

    end


    %% =====================================================
    % 1. SVM
    %% =====================================================

    mdl = fitcsvm( ...
        XTrain, ...
        yTrain, ...
        'KernelFunction','rbf', ...
        'KernelScale','auto', ...
        'BoxConstraint',1, ...
        'Standardize',false, ...
        'ClassNames',[0 1]);

    [pred,score] = predict(mdl,XTest);

    predictions.SVM(testIdx) = pred;

    classNames = mdl.ClassNames;
    positiveColumn = find(classNames == 1,1);

    if isempty(positiveColumn)
        error('Could not identify positive class in SVM.');
    end

    scores.SVM(testIdx) = score(:,positiveColumn);


    %% =====================================================
    % 2. KNN
    %% =====================================================

    mdl = fitcknn( ...
        XTrain, ...
        yTrain, ...
        'NumNeighbors',3, ...
        'Distance','cosine', ...
        'DistanceWeight','inverse', ...
        'Standardize',false);

    [pred,score] = predict(mdl,XTest);

    predictions.KNN(testIdx) = pred;

    classNames = mdl.ClassNames;
    positiveColumn = find(classNames == 1,1);

    if isempty(positiveColumn)
        error('Could not identify positive class in KNN.');
    end

    scores.KNN(testIdx) = score(:,positiveColumn);


    %% =====================================================
    % 3. NAIVE BAYES
    %% =====================================================

    mdl = fitcnb( ...
        XTrain, ...
        yTrain, ...
        'DistributionNames','normal', ...
        'Prior','empirical', ...
        'ClassNames',[0 1]);

    [pred,score] = predict(mdl,XTest);

    predictions.NaiveBayes(testIdx) = pred;

    classNames = mdl.ClassNames;
    positiveColumn = find(classNames == 1,1);

    if isempty(positiveColumn)
        error('Could not identify positive class in Naive Bayes.');
    end

    scores.NaiveBayes(testIdx) = score(:,positiveColumn);


    %% =====================================================
    % 4. RANDOM FOREST
    %% =====================================================

    nPred = max(1,round(sqrt(size(XTrain,2))));

    mdl = TreeBagger( ...
        100, ...
        XTrain, ...
        yTrain, ...
        'Method','classification', ...
        'MinLeafSize',5, ...
        'NumPredictorsToSample',nPred, ...
        'OOBPrediction','off');

    [predCell,score] = predict(mdl,XTest);

    pred = str2double(predCell);

    predictions.RandomForest(testIdx) = pred;

    classNames = string(mdl.ClassNames);

    positiveColumn = find(classNames == "1",1);

    if isempty(positiveColumn)
        error('Could not identify positive class in Random Forest.');
    end

    scores.RandomForest(testIdx) = score(:,positiveColumn);


    %% =====================================================
    % 5. DECISION TREE
    %% =====================================================

    mdl = fitctree( ...
        XTrain, ...
        yTrain, ...
        'MaxNumSplits',10, ...
        'MinLeafSize',5, ...
        'SplitCriterion','deviance', ...
        'ClassNames',[0 1]);

    [pred,score] = predict(mdl,XTest);

    predictions.DecisionTree(testIdx) = pred;

    classNames = mdl.ClassNames;
    positiveColumn = find(classNames == 1,1);

    if isempty(positiveColumn)
        error('Could not identify positive class in Decision Tree.');
    end

    scores.DecisionTree(testIdx) = score(:,positiveColumn);


    %% =====================================================
    % 6. ANN / MLP
    %% =====================================================

    mdl = fitcnet( ...
        XTrain, ...
        yTrain, ...
        'LayerSizes',5, ...
        'Activations','relu', ...
        'Lambda',0.1, ...
        'IterationLimit',300, ...
        'ClassNames',[0 1]);

    [pred,score] = predict(mdl,XTest);

    predictions.ANN(testIdx) = pred;

    classNames = mdl.ClassNames;
    positiveColumn = find(classNames == 1,1);

    if isempty(positiveColumn)
        error('Could not identify positive class in ANN.');
    end

    scores.ANN(testIdx) = score(:,positiveColumn);

end


%% =========================================================
% CALCULATE OVERALL LOSO METRICS
%% =========================================================

results = table();

for c = 1:nClassifiers

    name = classifierNames{c};

    yPred  = predictions.(name);
    yScore = scores.(name);


    % -------------------------------------------------------
    % Safety check
    % -------------------------------------------------------

    if any(isnan(yPred))
        error( ...
            'Missing predictions detected for classifier %s.', ...
            name);
    end

    if any(isnan(yScore))
        error( ...
            'Missing scores detected for classifier %s.', ...
            name);
    end


    % -------------------------------------------------------
    % Confusion matrix components
    % -------------------------------------------------------

    TP = sum((Y == 1) & (yPred == 1));
    TN = sum((Y == 0) & (yPred == 0));
    FP = sum((Y == 0) & (yPred == 1));
    FN = sum((Y == 1) & (yPred == 0));


    % -------------------------------------------------------
    % Performance metrics
    % -------------------------------------------------------

    Accuracy = (TP + TN) / numel(Y);

    Sensitivity = ...
        TP / max(TP + FN,eps);

    Specificity = ...
        TN / max(TN + FP,eps);

    Precision = ...
        TP / max(TP + FP,eps);

    F1 = ...
        2 * Precision * Sensitivity / ...
        max(Precision + Sensitivity,eps);

    [~,~,~,AUC] = ...
        perfcurve(Y,yScore,1);


    % -------------------------------------------------------
    % Results table
    % -------------------------------------------------------

    row = table( ...
        {name}, ...
        Accuracy, ...
        Sensitivity, ...
        Specificity, ...
        Precision, ...
        F1, ...
        AUC, ...
        'VariableNames', ...
        {'Classifier', ...
         'Accuracy', ...
         'Sensitivity', ...
         'Specificity', ...
         'Precision', ...
         'F1', ...
         'AUC'});

    results = [results; row];

end

end