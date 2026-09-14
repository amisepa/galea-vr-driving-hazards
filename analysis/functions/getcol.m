function v = getcol(raw, match_idx, pat)
%GETCOL  Read one questionnaire column for a set of matched participants.
%
%   v = getcol(raw, match_idx, pat)
%
%   raw        table read from subjects_questionnaires_data.xlsx
%   match_idx  row indices of the analysed participants, in analysis order
%   pat        substring matched (case-insensitive) against the column names
%
% Numeric-typed string columns are converted to double so the values can be
% entered directly into a design matrix.
%
% Used by run_final_EEG_covariates.m and run_final_TF_covariates.m.
%
% Cedric Cannard, 2026

k = find(contains(raw.Properties.VariableNames, pat, 'IgnoreCase', true), 1);
assert(~isempty(k), 'No questionnaire column matching "%s". Check the sheet headers.', pat);
v = raw{match_idx, k};
if iscell(v)
    num = str2double(v);
    if all(isnan(num) | cellfun(@(x) isempty(strtrim(x)), v)), return; end
    v = num;
end
end