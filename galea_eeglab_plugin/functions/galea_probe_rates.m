function rates = galea_probe_rates(filename, filepath)
% GALEA_PROBE_RATES  Quick sampling-rate read for a Galea recording.
%
%   >> rates = galea_probe_rates('OpenBCI-RAW-....txt', 'C:\...\sub-012')
%
% The OpenBCI TXT headers state the rate explicitly ("%Sample Rate = 250 Hz"),
% so this reads only the header lines of the main TXT and its AUX twin -
% instant, unlike a full galea_import. Used to display the detected rate next
% to the downsample fields in the GUI.
%
% rates is a struct with fields eeg, ppg, eda, emg, imu (Hz; NaN when the
% stream is absent). PPG/EDA/EMG/IMU share the OpenBCI AUX file at one rate.
%
% Cedric Cannard, 2026

rates = struct('eeg',NaN, 'ppg',NaN, 'eda',NaN, 'emg',NaN, 'imu',NaN);

rates.eeg = header_rate(fullfile(filepath, filename));

% the AUX twin, named after the same session timestamp
hit = dir(fullfile(filepath, 'OpenBCI-RAW-Aux-*.txt'));
if ~isempty(hit)
    aux = fullfile(filepath, hit(1).name);
    r = header_rate(aux);
    rates.ppg = r; rates.eda = r; rates.emg = r; rates.imu = r;
end
end

function r = header_rate(f)
r = NaN;
fid = fopen(f, 'r');
if fid < 0, return; end
for k = 1:20                                   % header is the first few lines
    ln = fgetl(fid);
    if ~ischar(ln), break; end
    tok = regexp(ln, 'Sample\s*Rate\s*=\s*([\d.]+)\s*Hz', 'tokens', 'once');
    if ~isempty(tok)
        r = str2double(tok{1});
        break
    end
    if strncmp(ln, 'Sample', 6), break; end    % reached the data table
end
fclose(fid);
end