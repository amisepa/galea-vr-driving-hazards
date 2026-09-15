%% Copyright (c) 2026 Demet Yesilbas. GPL-3.0 (see the repository LICENSE).
% Helper for the Galea VR driving-hazards classification analyses
% (Cannard & Yesilbas 2026, osf.io/xuw34).

%% =========================================================
% LOCAL FUNCTION: BUILD ERP DATASET
%% =========================================================

function [X,Y,subjectID] = buildERPdataset( ...
    ERP_avg,subjects,timeIdx,crashCond,noCrashCond)

N = numel(subjects);

nFeatures = size(ERP_avg,3) * sum(timeIdx);

X = zeros(N*2,nFeatures);
Y = zeros(N*2,1);
subjectID = strings(N*2,1);

row = 1;

for s = 1:N

    % Crash
    tmp = squeeze(ERP_avg(s,crashCond,:,timeIdx));

    X(row,:) = tmp(:)';
    Y(row) = 1;
    subjectID(row) = subjects(s);

    row = row + 1;

    % No-crash
    tmp = squeeze(ERP_avg(s,noCrashCond,:,timeIdx));

    X(row,:) = tmp(:)';
    Y(row) = 0;
    subjectID(row) = subjects(s);

    row = row + 1;

end

end