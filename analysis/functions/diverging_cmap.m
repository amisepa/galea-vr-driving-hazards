%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function cmap = diverging_cmap(n)
%DIVERGING_CMAP  Simple diverging colormap (blue -> white -> red).
%
%   cmap = diverging_cmap;        % 256 colours
%   cmap = diverging_cmap(n);
%
% Used by the time-frequency grand-average and cluster plots.
%
% Cedric Cannard, 2026

if nargin < 1, n = 256; end
half = floor(n/2);
r = [linspace(0,1,half), ones(1,n-half)];
g = [linspace(0,1,half), linspace(1,0,n-half)];
b = [ones(1,half), linspace(1,0,n-half)];
cmap = [r(:), g(:), b(:)];
end