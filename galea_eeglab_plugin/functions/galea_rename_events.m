%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Rename events for the VR driving with intuition project.
%
% The numeric codes below are written by the Unity application used in THIS
% study, not by the Galea hardware. Applying them to any other recording would
% invent labels that mean nothing. So the map is applied only when the codes
% present in the file are a subset of this paradigm's set; otherwise the events
% are left as they are and the caller is told why.

function EEG = galea_rename_events(EEG)

% Rename events
fs = EEG.srate;
nEv = length(EEG.event);
if nEv > 0
    PARADIGM_CODES = {'1','2','3','5','6','7','8'};
    present = unique(cellfun(@num2str, {EEG.event.type}, 'UniformOutput', false));
    unknown = setdiff(present, PARADIGM_CODES);
    if ~isempty(unknown)
        disp(['Event codes ' strjoin(unknown, ', ') ' are not part of the ' ...
              'VR driving paradigm, so the trigger labels were left unchanged.'])
        return
    end

    for iEv = 1:nEv
        if iEv > 1, prevType = EEG.event(iEv-1).type; else, prevType = ''; end
        if strcmpi(EEG.event(iEv).type, '1')
            EEG.event(iEv).type = 'BSL';            % Baseline block starts
        elseif strcmpi(EEG.event(iEv).type, '2')
            EEG.event(iEv).type = 'bsl_start';      % Baseline trial starts
        elseif strcmpi(EEG.event(iEv).type, '3')
            EEG.event(iEv).type = 'bsl_dev';  % Baseline trial deviation
        elseif strcmpi(EEG.event(iEv).type, '5')
            EEG.event(iEv).type = 'EXP';            % Experimental block starts
        elseif strcmpi(EEG.event(iEv).type, '6') && strcmpi(prevType, 'crash_start')
            EEG.event(iEv).type = 'tire_pop';      % Experiment trial tire pop
        elseif strcmpi(EEG.event(iEv).type, '6') && strcmpi(prevType, 'no_crash_start')
            EEG.event(iEv).type = 'no_tire_pop';    % Experiment trial no tire pop
        elseif strcmpi(EEG.event(iEv).type, '7')
            EEG.event(iEv).type = 'no_crash_start';  % Experiment no-crash trial start
        elseif strcmpi(EEG.event(iEv).type, '8')
            EEG.event(iEv).type = 'crash_start';    % Experiment crash trial start
        end
    end
    
    % Count # of trials 
    bsl_trials = contains({EEG.event.type}, 'bsl_start');
    bsl_deviations = strcmp({EEG.event.type}, 'bsl_dev');
    % exp_deviations = contains({EEG.event.type}, 'exp_deviation');
    % crash_trials = contains({EEG.event.type}, 'exp_crash_start');
    % nocrash_trials = contains({EEG.event.type}, 'exp_nocrash_start');
    crash_trials = strcmp({EEG.event.type}, 'tire_pop');
    nocrash_trials = strcmp({EEG.event.type}, 'no_tire_pop');

    % Report
    % fprintf('# baseline trials: %g \n', sum(bsl_trials))
    fprintf('%g baseline trials. \n', sum(bsl_deviations))
    fprintf('%g experimental trials: %g crash  and %g no-crash \n', sum(crash_trials)+sum(nocrash_trials), sum(crash_trials), sum(nocrash_trials))
    % fprintf('# of crash trials: %g \n', sum(crash_trials))
    % fprintf('# of no-crash trials: %g \n', sum(nocrash_trials))
    
    % Check time (in s) between trial starts and deviation
    % [EEG.event(exp_deviations).latency] - [EEG.event(crash_trials).latency] / fs
    bsl_prestim_period = nan(nEv-1,1);
    bsl_posttim_period = nan(nEv-1,1);
    exp_crash_prestim_period = nan(nEv-1,1);
    exp_nocrash_prestim_period = nan(nEv-1,1);
    exp_crash_posttim_period = nan(nEv-1,1);
    exp_nocrash_posttim_period = nan(nEv-1,1);
    nEv = length(EEG.event);
    for iEv = 1:nEv-1  % ignore baseline and 1st deviation
    
        % Baseline task
        if strcmpi(EEG.event(iEv).type, 'bsl_dev')
    
            prev_marker = EEG.event(iEv-1).type;
            
            % Skip if 1st baseline trial as pause time may be different
            if strcmpi(prev_marker, 'BSL')
                continue
            end

            % Check previous trial is bsl_start as should be
            if ~strcmpi(prev_marker, 'bsl_start')
                warning("Event %g should be bsl_start but is %s instead!", iEv-1, EEG.event(iEv-1).type)
            end
    
            % Baseline pre-stim period: between trial starting and deviation
            bsl_prestim_period(iEv,:) = EEG.event(iEv).latency/fs - EEG.event(iEv-1).latency/fs;
    
            % Baseline post-stim period: between deviation and beginning of next trial
            if strcmpi(EEG.event(iEv+1).type, 'EXP')
                continue % skip if last baseline trial as pause time may be different
            end
            bsl_posttim_period(iEv,:) = EEG.event(iEv+1).latency/fs -EEG.event(iEv).latency/fs;
    
        elseif strcmpi(EEG.event(iEv).type, 'tire_pop') || strcmpi(EEG.event(iEv).type, 'no_tire_pop')
    
            prev_marker = EEG.event(iEv-1).type;

            % skip if first exp trial as there may be different wait time
            % with instructions
            if strcmpi(prev_marker, 'EXP') 
                continue
            end
            
            % Check previous trial is exp_start as should be
            if ~strcmpi(prev_marker, 'no_crash_start') && ~strcmpi(prev_marker, 'crash_start') 
                warning("Event %g should be crash_start or no_crash_start but is %s instead!", iEv-1, prev_marker)
            end
    
            % Experiment pre-stim period: between crash trial starting and deviation
            if strcmpi(prev_marker, 'crash_start')
                exp_crash_prestim_period(iEv,:) = round( EEG.event(iEv).latency/fs - EEG.event(iEv-1).latency/fs, 3);
            elseif strcmpi(prev_marker, 'no_crash_start')
                exp_nocrash_prestim_period(iEv,:) = round( EEG.event(iEv).latency/fs - EEG.event(iEv-1).latency/fs, 3);
            end
            
            % Experiment post-stim period: between deviation and beginning of next trial
            if strcmpi(prev_marker, 'crash_start')
                exp_crash_posttim_period(iEv,:) = round( EEG.event(iEv+1).latency/fs -EEG.event(iEv).latency/fs, 3);
            elseif strcmpi(prev_marker, 'no_crash_start')
                exp_nocrash_posttim_period(iEv,:) = round( EEG.event(iEv+1).latency/fs -EEG.event(iEv).latency/fs, 3);
            end
    
        end
    end
    
    % remove zeros
    bsl_prestim_period(isnan(bsl_prestim_period)) = [];
    bsl_posttim_period(isnan(bsl_posttim_period)) = [];
    exp_crash_prestim_period(isnan(exp_crash_prestim_period)) = [];
    exp_nocrash_prestim_period(isnan(exp_nocrash_prestim_period)) = [];
    exp_crash_posttim_period(isnan(exp_crash_posttim_period)) = [];
    exp_nocrash_posttim_period(isnan(exp_nocrash_posttim_period)) = [];
    
    % % report
    % figure('color','w'); 
    % subplot(3,2,1)
    % histogram(bsl_prestim_period); title('Baseline pre-stim period')
    % subplot(3,2,2)
    % histogram(bsl_posttim_period); title('Baseline post-stim period')
    % subplot(3,2,3)
    % histogram(exp_crash_prestim_period); title('Experiment pre-stim period (crash trial)')
    % subplot(3,2,4)
    % histogram(exp_nocrash_prestim_period); title('Experiment pre-stim period (no-crash trial)')
    % subplot(3,2,5)
    % xlabel('Time (s)')
    % histogram(exp_crash_posttim_period); title('Experiment post-stim period (crash trial)')
    % subplot(3,2,6)
    % histogram(exp_nocrash_posttim_period); title('Experiment post-stim period (no-crash trial)')
    % xlabel('Time (s)')
else
    warning("No Events in this file")
end
