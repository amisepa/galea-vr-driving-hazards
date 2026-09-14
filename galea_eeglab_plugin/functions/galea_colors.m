function c = galea_colors()
%GALEA_COLORS  EEGLAB house colours, safe to call from a static workspace.
%
% icadefs is a SCRIPT: it creates variables in whoever calls it. A function
% that contains nested functions has a static workspace, so calling icadefs
% from one throws "Attempt to add EEGOPTION_PATH to a static workspace".
% Calling it in here instead, and returning a struct, avoids that.

try
    icadefs;   %#ok<*NODEF>
    c = struct('back', GUIBACKCOLOR, 'btn', GUIPOPBUTTONCOLOR, 'text', GUITEXTCOLOR);
catch
    c = struct('back', [.66 .76 1], 'btn', [.93 .96 1], 'text', [0 0 .4]);
end
end
