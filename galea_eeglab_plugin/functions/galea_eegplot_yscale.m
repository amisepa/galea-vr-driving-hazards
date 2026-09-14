function ok = galea_eegplot_yscale(val)
% GALEA_EEGPLOT_YSCALE  Set the vertical scale of the open eegplot figure.
%
%   >> galea_eegplot_yscale(100)
%
% EEGLAB's eegplot window shows the scale in the 'ESpacing' edit box; the
% automatic default (3 trimmed SDs of the data) is usually too small on a
% 12-channel dry montage with large blink artefacts, and the traces saturate.
% This sets the box to VAL and fires the same callback eegplot itself runs
% when the box is edited, so the figure redraws exactly as if the user had
% typed it.
%
% Cedric Cannard, 2026

ok = false;
if nargin < 1, val = 100; end
fig = gcf;

h = findall(fig, 'style', 'edit', 'tag', 'ESpacing');
if isempty(h), return; end

set(h, 'string', sprintf('%g', val));
% fire the box's own callback ('eegplot(''draws'',0)') to redraw with the new scale
cb = get(h, 'callback');
fired = false;
if ischar(cb)
    try
        evalin('base', cb);   % eegplot callbacks are written for the base workspace
        fired = true;
    catch
    end
end
if ~fired
    try
        eegplot('draws', 0);  % figure-local redraw, same entry point
        fired = true;
    catch
    end
end
drawnow;
ok = fired;
end