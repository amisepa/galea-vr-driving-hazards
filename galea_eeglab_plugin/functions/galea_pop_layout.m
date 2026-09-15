%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function H = galea_pop_layout(~)
% GALEA_POP_LAYOUT  Content height of the main Galea window.
%
%   >> H = galea_pop_layout(true)
%
% Mirror of the layout arithmetic in pop_galea.m's figure construction. Keep
% the two in sync: every y decrement in the layout code must appear in the
% steps vector below, so the window is sized to fit all of its content and
% nothing is cropped on any display. PPG/EDA/EMG/IMU parameters moved to
% galea_periph_gui.m in September 2026, so the main window only carries the
% "Peripheral signals" launcher row (a pushbutton, 26 px).
%
% Derivation: the layout code starts at y = H - 130 and steps up to the TOP
% edge of the last control row; add that row's height and the 48 px button
% strip at the bottom.
%
% Cedric Cannard, 2026

steps = [26 26 30 30 28 24 30 26 24 22 22 40 20 48 18 18 22 28];

H = 130 + sum(steps) + 26 + 48;   % offset + last row (button) + button strip
end