function [auxFile, msg] = galea_aux_filename(filename, filepath)
%GALEA_AUX_FILENAME  Companion Aux file for a Galea recording.
%
%   auxFile        = galea_aux_filename(filename, filepath)   errors if missing
%   [auxFile, msg] = galea_aux_filename(...)                  returns '' + why
%
% The name is derived FROM the selected file, never by scanning the folder for
% anything containing "Aux": with two recordings side by side that would
% silently pair the wrong ones.
%
% Cedric Cannard, 2026

auxFile = ''; msg = '';

if contains(filename, 'Aux', 'IgnoreCase', true)
    msg = ['That is the Aux file (' filename '). Select the main recording ' ...
           'instead - its Aux companion is picked up automatically.'];
    if nargout < 2, error('galea_aux_filename:auxSelected', '%s', msg); end
    return
end

[~, base, xt] = fileparts(filename);
cand = { strrep(filename, 'OpenBCI-RAW-', 'OpenBCI-RAW-Aux-'), ...
         strrep(filename, 'OpenBCI-RAW',  'OpenBCI-RAW-Aux'), ...
         [base '-Aux' xt], [base '_Aux' xt] };

for k = 1:numel(cand)
    if ~strcmp(cand{k}, filename) && isfile(fullfile(filepath, cand{k}))
        auxFile = cand{k};
        return
    end
end

msg = ['No Aux file matching ' filename '. The recording needs its companion ' ...
       'file in the same folder, named like one of: ' strjoin(unique(cand), ', ')];
if nargout < 2, error('galea_aux_filename:noAux', '%s', msg); end
end
