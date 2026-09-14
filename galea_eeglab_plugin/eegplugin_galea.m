function vers = eegplugin_galea(fig, trystrs, catchstrs)
% EEGPLUGIN_GALEA  EEGLAB plugin for the Galea multimodal VR headset (OpenBCI).
%
% Adds a single "Galea" entry to the EEGLAB menu bar. It opens one window that
% loads a recording and, optionally, processes each modality.
%
% Install: copy or clone this folder into eeglab/plugins/ and restart EEGLAB.
%
% Cedric Cannard, 2026

vers = 'galea1.2';

if nargin < 3
    error('eegplugin_galea requires 3 arguments');
end

p = fileparts(which('eegplugin_galea'));
addpath(p);
addpath(fullfile(p, 'functions'));

uimenu(fig, 'Label', 'Galea', 'Tag', 'galea', ...
    'userdata', 'startup:on;study:on', ...
    'CallBack', [trystrs.no_check ...
                 '[EEG, LASTCOM] = pop_galea();' ...
                 catchstrs.new_non_empty]);
