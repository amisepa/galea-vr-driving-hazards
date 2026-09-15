%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function capture_gui_screenshots(outdir, scale)
%CAPTURE_GUI_SCREENSHOTS  Publication-resolution captures of the plugin GUIs.
%
%   capture_gui_screenshots()             -> ./doc/figures, native size
%   capture_gui_screenshots(outdir, scale)
%
% Two things make this less obvious than it looks.
%
% 1. MATLAB will not rasterise a figure containing UI components at a chosen
%    resolution: print/exportgraphics reject the -r flag for such figures, so
%    the only faithful capture is exportapp(), which grabs the window at
%    whatever size it occupies on screen. At default size the import dialog is
%    634 x 227 px, which is about 180 dpi at a 3.5 inch column - too coarse to
%    print. SCALE enlarges the figure and every font inside it by the same
%    factor, which multiplies the pixel count. BUT checkbox and radio-button
%    indicators are drawn by the OS at a fixed pixel size and do not follow
%    FontSize, so scaling gives large text beside tiny tick boxes. SCALE
%    therefore defaults to 1 and the capture is native size.
%
%    To get genuinely more pixels with the proportions intact, raise the
%    WINDOWS display scaling (Settings > System > Display > Scale) to 200-250%%,
%    restart MATLAB, then capture at scale 1. That enlarges every control,
%    glyphs included, and the capture comes back correspondingly larger.
%
% 2. Both dialogs are built with EEGLAB's inputgui(), which calls uiwait and
%    blocks. So the capture cannot run after the call. A timer is armed first;
%    the dialog opens and blocks, the timer fires underneath it, resizes,
%    captures and closes it, which releases uiwait and lets the script move on.
%
% Run from the MATLAB desktop with EEGLAB on the path, and do not touch the
% mouse or keyboard while it runs - dismissing a dialog early aborts its
% capture.
%
% Cedric Cannard, August 2026

if nargin < 1 || isempty(outdir)
    outdir = fullfile(fileparts(mfilename('fullpath')), 'figures');
end
if nargin < 2 || isempty(scale), scale = 1; end   % see note above

if ~usejava('desktop')
    error('capture_gui_screenshots:headless', ...
        'The dialogs must be rendered on screen. Run this from the MATLAB desktop.');
end
if ~exist('eeglab', 'file')
    error('capture_gui_screenshots:noEeglab', 'EEGLAB is not on the path.');
end
if ~exist(outdir, 'dir'), mkdir(outdir); end

% Both dialogs need an EEG variable to open against.
if evalin('base', '~exist(''EEG'', ''var'') || isempty(EEG)')
    evalin('base', 'EEG = eeg_emptyset;');
end

% pop_galea_preprocess does "if nargin < 1, help ...; return", so it must be
% called WITH the EEG argument or it prints its help and never opens.
% Peripheral dialog: the command is assembled at runtime (a struct of the
% defaults), avoiding fragile multi-line string continuations inside the
% cell array.
periphArgs = strjoin({ ...
    '''ppg'',true', '''ppglocut'',0.5', '''ppghicut'',3', '''rrcorrect'',''pchip''', ...
    '''hrvtime'',true', '''hrvfreq'',true', '''hrvnonlin'',false', '''visppg'',true', ...
    '''eda'',true', '''edalocut'',0.01', '''edahicut'',1', '''edaresample'',8', ...
    '''edaphasic'',false', '''viseda'',true', ...
    '''emg'',true', '''emglocut'',20', '''emgenvelope'',true', '''visemg'',true', ...
    '''imu'',true', '''imuhicut'',10', '''imumagnitude'',true', '''visimu'',true'}, ', ');
periphCmd = sprintf('per = galea_periph_gui(struct(%s))', periphArgs);
targets = { ...
    'Import Galea data',    'pop_galea_import;',         'gui_import.png'; ...
    'Preprocess Galea EEG', 'pop_galea_preprocess(EEG);', 'gui_preprocess.png'; ...
    'Galea peripheral signals', periphCmd, 'gui_periph.png'};

for k = 1:size(targets, 1)
    titleFrag = targets{k, 1};
    cmd       = targets{k, 2};
    outfile   = fullfile(outdir, targets{k, 3});

    before = findall(0, 'Type', 'figure');
    t = timer('StartDelay', 2.5, 'ExecutionMode', 'singleShot', ...
        'TimerFcn', @(~, ~) grab(before, titleFrag, outfile, scale));
    start(t);
    try
        evalin('base', cmd);      % blocks until grab() closes the dialog
    catch ME
        fprintf(2, '  %s did not open: %s\n', titleFrag, ME.message);
    end
    stop(t); delete(t);

    if isfile(outfile)
        info = imfinfo(outfile);
        fprintf('wrote %-20s %d x %d px  (%d dpi at a 3.5 inch column)\n', ...
            targets{k, 3}, info.Width, info.Height, round(info.Width / 3.5));
    else
        fprintf(2, 'FAILED to capture %s\n', titleFrag);
    end
end

end

% ---------------------------------------------------------------------------
function grab(before, titleFrag, outfile, scale)

new = setdiff(findall(0, 'Type', 'figure'), before);

fig = [];
for h = new(:)'
    if contains(get(h, 'Name'), titleFrag, 'IgnoreCase', true), fig = h; break; end
end
if isempty(fig) && ~isempty(new), fig = new(1); end
if isempty(fig)
    fprintf(2, 'grab: no new figure found for "%s"\n', titleFrag);
    return
end

try
    if scale == 1
        drawnow expose; pause(0.4);
        exportapp(fig, outfile);
        if isvalid(fig), close(fig); end
        return
    end

    % Enlarge the window and scale every font to match. Note this leaves
    % checkbox and radio glyphs at their original pixel size.
    set(fig, 'Units', 'pixels');
    pos = get(fig, 'Position');
    scr = get(0, 'ScreenSize');
    s = min([scale, 0.92 * scr(3) / pos(3), 0.92 * scr(4) / pos(4)]);
    if s < scale
        fprintf(2, 'note: screen limits scale to %.2fx for %s\n', s, titleFrag);
    end

    kids = findall(fig, '-property', 'FontSize');
    old = get(kids, 'FontSize');
    if ~iscell(old), old = {old}; end
    for i = 1:numel(kids)
        set(kids(i), 'FontSize', old{i} * s);
    end

    set(fig, 'Position', [max(1, pos(1) - (s - 1) * pos(3) / 2), ...
                          max(1, pos(2) - (s - 1) * pos(4) / 2), ...
                          pos(3) * s, pos(4) * s]);

    drawnow expose; pause(0.6);   % let the dialog relayout at the new size
    exportapp(fig, outfile);
catch ME
    fprintf(2, 'grab: capture failed - %s\n', ME.message);
end

if isvalid(fig), close(fig); end   % releases uiwait so the caller resumes

end
