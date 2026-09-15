%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function Y_smooth = causal_smooth_trials(Y, win_samples)
    % Y: [nChan x nTime x nTrials]
    % Causal moving average: only looks backward in time
    % Uses MATLAB's filter() which is inherently causal
    
    b = ones(1, win_samples) / win_samples;  % FIR coefficients
    a = 1;
    
    Y_smooth = zeros(size(Y), 'single');
    for tr = 1:size(Y, 3)
        for ch = 1:size(Y, 1)
            Y_smooth(ch, :, tr) = filter(b, a, Y(ch, :, tr));
        end
    end
end