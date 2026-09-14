function out = galea_periph_gui(def, hasPPG)
% GALEA_PERIPH_GUI  Parameters for the Galea auxiliary signals (PPG/EDA/EMG/IMU).
%
%   >> out = galea_periph_gui(def, hasPPG)
%
% Separate window so the main Galea dialogs stay compact: PPG, EDA, EMG and
% IMU each have their own section here, with its own "process" checkbox and
% its own parameters. DEF holds the current values (any subset; missing keys
% keep their defaults below); OUT returns the full set, or [] if cancelled.
% HASPPG (default true) greys the PPG section out when the recording carries
% no PPG stream.
%
% Cedric Cannard, 2026

if nargin < 2, hasPPG = true; end

d = struct('ppg',true, 'ppglocut',0.5, 'ppghicut',3, 'rrcorrect','pchip', ...
           'hrvtime',true, 'hrvfreq',true, 'hrvnonlin',false, 'visppg',true, ...
           'eda',true, 'edalocut',0.01, 'edahicut',1, 'edaresample',8, ...
           'edaphasic',false, 'viseda',true, ...
           'emg',true, 'emglocut',20, 'emgenvelope',true, 'visemg',true, ...
           'imu',true, 'imuhicut',10, 'imumagnitude',true, 'visimu',true);
fn = fieldnames(def);
for iF = 1:numel(fn)
    d.(fn{iF}) = def.(fn{iF});          % keep current values
end

c = galea_colors();
W = 580;
scr = get(0, 'ScreenSize');
% measure-first: same decrements as the layout code below
H = 36 + 30 ...
  + 26 + 26 + 26 + 24 + 20 ...        % PPG
  + 26 + 26 + 24 + 20 ...             % EDA
  + 26 + 26 + 20 ...                  % EMG
  + 26 + 26 ...                       % IMU
  + 56;                               % buttons + bottom margin
H = min(H, scr(4) - 80);
f = figure('Name','Galea peripheral signals', 'NumberTitle','off', 'MenuBar','none', ...
    'ToolBar','none', 'Resize','off', 'Color',c.back, 'WindowStyle','modal', ...
    'Position',[(scr(3)-W)/2 max(20,(scr(4)-H)/2) W H]);

    function h = txt(str, pos, varargin)
        h = uicontrol(f,'style','text','string',str,'position',pos, ...
            'horizontalalignment','left','backgroundcolor',c.back, ...
            'foregroundcolor',c.text, varargin{:});
    end
    function h = ed(str, pos)
        h = uicontrol(f,'style','edit','string',str,'position',pos, ...
            'backgroundcolor',c.btn);
    end
    function h = cb(str, val, pos, varargin)
        h = uicontrol(f,'style','checkbox','string',str,'value',val,'position',pos, ...
            'backgroundcolor',c.back,'foregroundcolor',c.text, varargin{:});
    end
    function h = box(str, val, pos)
        h = uicontrol(f,'style','checkbox','string',str,'value',val,'position',pos, ...
            'fontweight','bold','fontsize',11,'backgroundcolor',c.back,'foregroundcolor',c.text);
    end
    function sep(yy)
        uicontrol(f,'style','frame','position',[20 yy W-40 1], ...
            'foregroundcolor',[.4 .45 .6],'backgroundcolor',[.4 .45 .6]);
    end

pg = gobjects(0);   % PPG controls (gated by the PPG box and hasPPG)

y = H - 36;
txt('Peripheral signal processing', [20 y 300 24], 'fontweight','bold','fontsize',12);
y = y - 30;

% ---------------- PPG ----------------
hPpg = box('PPG (cardiac)', double(d.ppg), [20 y 260 24]);
y = y - 26;
txt('Bandpass (Hz):', [40 y 130 20]);
hPLo = ed(sprintf('%g', d.ppglocut), [175 y 60 24]);
txt('to', [242 y 20 20]);
hPHi = ed(sprintf('%g', d.ppghicut), [268 y 60 24]);
txt('RR artefact correction:', [340 y 150 20]);
hRR = uicontrol(f,'style','popupmenu','position',[495 y 70 24], 'backgroundcolor',c.btn, ...
    'string',{'pchip','linear','spline','makima','nearest','remove'}, ...
    'value', find(strcmp({'pchip','linear','spline','makima','nearest','remove'}, d.rrcorrect)));
pg(end+1) = hPLo; pg(end+1) = hPHi; pg(end+1) = hRR; %#ok<*AGROW>
y = y - 26;
txt('HRV features:', [40 y 100 20]);
hHt = cb('time', double(d.hrvtime), [145 y 70 22]);
hHf = cb('frequency', double(d.hrvfreq), [220 y 90 22]);
hHn = cb('nonlinear', double(d.hrvnonlin), [315 y 90 22]);
pg(end+1) = hHt; pg(end+1) = hHf; pg(end+1) = hHn;
y = y - 24;
hVisP = cb('Plot heartbeat detection and HRV outputs', double(d.visppg), [40 y W-70 22]);
pg(end+1) = hVisP;
y = y - 20; sep(y);

% ---------------- EDA ----------------
hEda = box('EDA (skin conductance)', double(d.eda), [20 y 260 24]);
y = y - 26;
txt('Bandpass (Hz):', [40 y 130 20]);
hELo = ed(sprintf('%g', d.edalocut), [175 y 60 24]);
txt('to', [242 y 20 20]);
hEHi = ed(sprintf('%g', d.edahicut), [268 y 60 24]);
txt('Downsample (Hz):', [340 y 120 20]);
hERes = ed(sprintf('%g', d.edaresample), [495 y 60 24]);
y = y - 24;
hPhasic = cb('Split tonic / phasic (cvxEDA)', double(d.edaphasic), [40 y 250 22]);
hVisD   = cb('Plot EDA', double(d.viseda), [300 y 130 22]);
y = y - 20; sep(y);

% ---------------- EMG ----------------
hEmg = box('EMG (facial)', double(d.emg), [20 y 260 24]);
y = y - 26;
txt('High-pass (Hz):', [40 y 130 20]);
hMLo = ed(sprintf('%g', d.emglocut), [175 y 60 24]);
hEnv = cb('Rectify + envelope', double(d.emgenvelope), [268 y 180 22]);
hVisM = cb('Plot EMG', double(d.visemg), [460 y 110 22]);
y = y - 20; sep(y);

% ---------------- IMU ----------------
hImu = box('IMU (head motion)', double(d.imu), [20 y 260 24]);
y = y - 26;
txt('Low-pass (Hz):', [40 y 130 20]);
hIHi = ed(sprintf('%g', d.imuhicut), [175 y 60 24]);
hMag = cb('Add acceleration magnitude', double(d.imumagnitude), [268 y 220 22]);
hVisI = cb('Plot IMU', double(d.visimu), [500 y 70 22]);

% grey the whole PPG section out when there is no PPG stream
if ~hasPPG
    txt('no PPG stream in this dataset', [300 y+58 240 20], 'fontangle','italic');
    set(pg(isgraphics(pg)), 'enable', 'off');
    set(hPpg, 'enable', 'off');
end

% ---------------- buttons ----------------
out = [];
uicontrol(f,'style','pushbutton','string','Cancel','position',[W-200 18 80 30], ...
    'backgroundcolor',c.btn,'callback','close(gcbf)');
uicontrol(f,'style','pushbutton','string','OK','position',[W-105 18 85 30], ...
    'fontweight','bold','backgroundcolor',c.btn,'callback',@(~,~) onOK());

uiwait(f);

    function onOK()
        rrOpts = get(hRR,'string');
        out = d;
        out.ppg          = logical(get(hPpg,'value')) && hasPPG;
        out.ppglocut     = str2double(get(hPLo,'string'));
        out.ppghicut     = str2double(get(hPHi,'string'));
        out.rrcorrect    = rrOpts{get(hRR,'value')};
        out.hrvtime      = logical(get(hHt,'value'));
        out.hrvfreq      = logical(get(hHf,'value'));
        out.hrvnonlin    = logical(get(hHn,'value'));
        out.visppg       = logical(get(hVisP,'value'));
        out.eda          = logical(get(hEda,'value'));
        out.edalocut     = str2double(get(hELo,'string'));
        out.edahicut     = str2double(get(hEHi,'string'));
        out.edaresample  = str2double(get(hERes,'string'));
        out.edaphasic    = logical(get(hPhasic,'value'));
        out.viseda       = logical(get(hVisD,'value'));
        out.emg          = logical(get(hEmg,'value'));
        out.emglocut     = str2double(get(hMLo,'string'));
        out.emgenvelope  = logical(get(hEnv,'value'));
        out.visemg       = logical(get(hVisM,'value'));
        out.imu          = logical(get(hImu,'value'));
        out.imuhicut     = str2double(get(hIHi,'string'));
        out.imumagnitude = logical(get(hMag,'value'));
        out.visimu       = logical(get(hVisI,'value'));
        close(f);
    end
end