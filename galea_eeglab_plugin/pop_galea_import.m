function [EEG, com] = pop_galea_import(varargin)
% POP_GALEA_IMPORT  Import raw Galea (OpenBCI) recordings into EEGLAB.
%
% Splits the multiplexed streams (EEG, EOG, EMG, PPG, EDA, IMU), sets the
% sampling rate from the board's nominal rate, and maps the numeric triggers to
% readable labels when the file comes from the VR driving paradigm.
%
% File format: the plain-text files written by the Galea / OpenBCI GUI. A
% recording is a PAIR and both must sit in the same folder:
%     OpenBCI-RAW-<date>.txt        EEG, EOG, EMG        (select this one)
%     OpenBCI-RAW-Aux-<date>.txt    PPG, EDA, IMU        (found automatically)
%
% Usage:
%   >> EEG = pop_galea_import;                          % GUI
%   >> EEG = pop_galea_import('montage','custom');       % script
%
% Optional key/value:
%   'montage'    - 'default' (10 EEG channels, stock Galea layout) or 'custom'
%                  (12 EEG; the two EMG disc electrodes become Fp1/Fp2).
%                  Default 'default'.
%   'preprocess' - true|false, run pop_galea_preprocess straight after the
%                  import. Default false.
%   'filename','filepath' - skip the file dialog.
%
% Non-EEG streams are kept in EEG.etc.galea (.EOG .EMG .PPG .EDA .IMU .AUX).
%
% Cedric Cannard, 2026

EEG = []; com = '';

g = struct('montage','default','preprocess',false,'filename','','filepath','');
if nargin > 0
    for i = 1:2:numel(varargin)
        g.(lower(varargin{i})) = varargin{i+1};
    end
else
    g = galea_import_gui(g);
    if isempty(g), return; end          % cancelled
end

% ---------------- import ----------------
fprintf('Importing Galea data (montage: %s)...\n', g.montage);
if ~isempty(g.filename)
    [EEG, EOG, EMG, PPG, EDA, IMU, AUX] = galea_import(g.montage, g.filename, g.filepath);
else
    [EEG, EOG, EMG, PPG, EDA, IMU, AUX] = galea_import(g.montage);
end
if isempty(EEG)
    error('pop_galea_import: import returned no EEG data.');
end

EEG.etc.galea = struct('EOG',EOG, 'EMG',EMG, 'PPG',PPG, ...
                       'EDA',EDA, 'IMU',IMU, 'AUX',AUX, ...
                       'montage',g.montage, 'plugin_version','galea1.1');

% Trigger labels. Applied only if the codes match the VR driving paradigm.
EEG = galea_rename_events(EEG);
EEG = eeg_checkset(EEG);

fprintf('Imported %d channels, %.1f min at %g Hz.\n', ...
    EEG.nbchan, EEG.pnts/EEG.srate/60, EEG.srate);

com = sprintf('EEG = pop_galea_import(''montage'', ''%s'');', g.montage);

% ---------------- optional preprocessing ----------------
if g.preprocess
    [EEG, pcom] = pop_galea_preprocess(EEG);
    if ~isempty(pcom), com = [com ' ' pcom]; end
end

end

% ===========================================================================
function g = galea_import_gui(g)
% Small custom dialog, so the logos can sit alongside the controls. EEGLAB's
% inputgui() cannot hold images.

c = galea_colors();   % EEGLAB house colours (icadefs is a script and cannot run in a static workspace)

W = 600; H = 310;
scr = get(0, 'ScreenSize');
f = figure('Name','Load Galea data', 'NumberTitle','off', 'MenuBar','none', ...
    'ToolBar','none', 'Resize','off', 'Color',c.back, ...
    'Position',[(scr(3)-W)/2 (scr(4)-H)/2 W H], 'WindowStyle','modal');

% ---- logos ----
logodir = fullfile(fileparts(mfilename('fullpath')), 'figures');
show_logo(f, fullfile(logodir,'galea_headset.png'), [20 165 110 110]);
show_logo(f, fullfile(logodir,'openbci_logo.png'),  [20 105 110  50]);

uicontrol(f,'style','text','string','Galea', 'fontsize',15,'fontweight','bold', ...
    'horizontalalignment','left','backgroundcolor',c.back,'foregroundcolor',c.text, ...
    'position',[150 258 420 26]);
uicontrol(f,'style','text','string', ...
    'Import a raw recording from the Galea multimodal VR headset.', ...
    'horizontalalignment','left','backgroundcolor',c.back,'foregroundcolor',c.text, ...
    'position',[150 236 430 20]);

% ---- file format note ----
uicontrol(f,'style','text','string', ...
    ['Expects the text files written by the Galea / OpenBCI GUI. Select the ' ...
     'main file; its Aux twin in the same folder is picked up automatically:'], ...
    'horizontalalignment','left','backgroundcolor',c.back,'foregroundcolor',c.text, ...
    'position',[150 192 430 34]);
uicontrol(f,'style','text','string', ...
    sprintf('OpenBCI-RAW-<date>.txt        EEG, EOG, EMG\nOpenBCI-RAW-Aux-<date>.txt    PPG, EDA, IMU'), ...
    'horizontalalignment','left','fontname','Courier New','fontsize',8, ...
    'backgroundcolor',c.back,'foregroundcolor',c.text, 'position',[150 152 430 34]);

% ---- montage ----
uicontrol(f,'style','text','string','Montage:','horizontalalignment','left', ...
    'backgroundcolor',c.back,'foregroundcolor',c.text,'position',[150 116 60 20]);
hMont = uicontrol(f,'style','popupmenu','position',[215 118 365 22], ...
    'backgroundcolor',c.btn, ...
    'string',{'default (10 EEG)', 'custom (12 EEG, Fp1/Fp2 from disc electrodes)'});

% ---- preprocess ----
hPre = uicontrol(f,'style','checkbox','value',0,'position',[150 84 430 22], ...
    'backgroundcolor',c.back,'foregroundcolor',c.text, ...
    'string','Preprocess with customized methods (Cannard 2026)');
uicontrol(f,'style','text','string', ...
    'Opens the preprocessing options after the file is loaded.', ...
    'horizontalalignment','left','fontangle','italic','fontsize',8, ...
    'backgroundcolor',c.back,'foregroundcolor',c.text,'position',[170 66 410 18]);

% ---- buttons ----
out = [];
uicontrol(f,'style','pushbutton','string','Help','backgroundcolor',c.btn,'position',[20 20 80 28], ...
    'callback','pophelp(''pop_galea_import'');');
uicontrol(f,'style','pushbutton','string','Cancel','backgroundcolor',c.btn,'position',[400 20 80 28], ...
    'callback','close(gcbf)');
uicontrol(f,'style','pushbutton','string','Load','backgroundcolor',c.btn,'position',[490 20 90 28], ...
    'fontweight','bold','callback',@(~,~) onLoad());

uiwait(f);
g = out;

    function onLoad()
        montages = {'default','custom'};
        out = g;
        out.montage    = montages{get(hMont,'Value')};
        out.preprocess = logical(get(hPre,'Value'));
        close(f);
    end
end

% ---------------------------------------------------------------------------
function show_logo(parent, file, pos)
% Draw a logo if the file is there; stay silent if it is not, so a missing
% asset never blocks the dialog.
if ~isfile(file), return; end
try
    [img, ~, alpha] = imread(file);
    ax = axes('Parent', parent, 'Units','pixels', 'Position', pos);
    h = image(ax, img); axis(ax,'image','off');
    if ~isempty(alpha), set(h, 'AlphaData', alpha); end
catch
    % ignore unreadable logo
end
end
