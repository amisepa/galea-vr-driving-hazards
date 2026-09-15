%% Copyright (c) 2026 Demet Yesilbas. GPL-3.0 (see the repository LICENSE).
% Helper for the Galea VR driving-hazards classification analyses
% (Cannard & Yesilbas 2026, osf.io/xuw34).

function pValues = permutationLOSO( ...
    X1,X2,Y,subjectID,uniqueSubjects,cv, ...
    analysisType,observedAccuracy,nPerm)

% =========================================================
% WITHIN-SUBJECT LABEL PERMUTATION TEST
%
% Output:
%   pValues = empirical permutation p-value for each classifier
%
% Labels are forced to numeric:
%   crash    = 1
%   nocrash  = 0
% =========================================================

nClassifiers = numel(observedAccuracy);
nullAccuracy = zeros(nPerm,nClassifiers);


%% =========================================================
% CONVERT LABELS TO NUMERIC 0/1
%% =========================================================

if iscategorical(Y) || isstring(Y) || iscellstr(Y)

    Ystr = string(Y(:));

    Y_original = nan(size(Ystr));

    Y_original(Ystr == "crash")   = 1;
    Y_original(Ystr == "nocrash") = 0;

    % Allow alternative spelling just in case
    Y_original(Ystr == "no_crash") = 0;
    Y_original(Ystr == "no-crash") = 0;

else

    Y_original = double(Y(:));

end


% Check conversion
if any(isnan(Y_original))
    error('Some class labels could not be converted to numeric 0/1.');
end

if ~all(ismember(unique(Y_original),[0 1]))
    error('Labels must contain only 0 and 1.');
end


fprintf('Running %d within-subject label permutations...\n',nPerm);


%% =========================================================
% PERMUTATION LOOP
%% =========================================================

for p = 1:nPerm

    % IMPORTANT:
    % Always start from original labels
    Yperm = Y_original;


    %% -----------------------------------------------------
    % Randomly swap the two labels WITHIN each participant
    %% -----------------------------------------------------

    for s = 1:numel(uniqueSubjects)

        idx = find(ismember(subjectID,uniqueSubjects(s)));

        if numel(idx) ~= 2
            error( ...
                'Subject %s has %d observations instead of 2.', ...
                char(uniqueSubjects(s)),numel(idx));
        end

        if rand > 0.5

            tmp = Yperm(idx(1));
            Yperm(idx(1)) = Yperm(idx(2));
            Yperm(idx(2)) = tmp;

        end

    end


    %% -----------------------------------------------------
    % Safety checks
    %% -----------------------------------------------------

    if sum(Yperm == 1) ~= numel(uniqueSubjects)
        error('Permutation %d has incorrect number of crash labels.',p);
    end

    if sum(Yperm == 0) ~= numel(uniqueSubjects)
        error('Permutation %d has incorrect number of nocrash labels.',p);
    end


    %% -----------------------------------------------------
    % Run exactly the same LOSO classifier
    %% -----------------------------------------------------

    permResults = runLOSOclassification_final( ...
        X1, ...
        X2, ...
        Yperm, ...
        subjectID, ...
        uniqueSubjects, ...
        cv, ...
        analysisType);


    nullAccuracy(p,:) = permResults.Accuracy';


    if mod(p,100) == 0
        fprintf('Permutation %d/%d complete\n',p,nPerm);
    end

end


%% =========================================================
% EMPIRICAL PERMUTATION P VALUES
%% =========================================================

pValues = zeros(nClassifiers,1);

for c = 1:nClassifiers

    pValues(c) = ...
        (1 + sum(nullAccuracy(:,c) >= observedAccuracy(c))) ...
        / (nPerm + 1);

end


fprintf('Permutation test complete.\n');

end