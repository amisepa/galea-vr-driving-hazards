function ok = galea_ensure_brainbeats()
% GALEA_ENSURE_BRAINBEATS  Make sure the BrainBeats extension is usable.
%
%   >> ok = galea_ensure_brainbeats()
%
% Returns true when brainbeats_process is callable by the end of the call.
%
% Why not simply plugin_askinstall('BrainBeats', ...)? EEGLAB's
% plugin_askinstall ERRORS ("Cannot find ... extension, use EEGLAB Extension
% Manager to install it") when the call stack is deeper than two frames, which
% is always the case when called from inside another plugin's processing
% chain. This helper therefore:
%   1. returns early if BrainBeats is already on the path;
%   2. looks for an installed-but-not-on-path copy under eeglab/plugins and
%      adds it (covers the "installed but deactivated / path lost" case);
%   3. otherwise downloads and installs BrainBeats through the same EEGLAB
%      mechanism the Extension Manager uses (plugin_getweb + plugin_install),
%      printing progress to the console;
%   4. adds the newly installed folder to the path.
%
% Cedric Cannard, 2026

ok = false;
if exist('brainbeats_process', 'file')
    ok = true; return
end

% 2. installed but not on path: look under every eeglab root we can find
roots = {fileparts(which('eeglab.m'))};
for r = 1:numel(roots)
    cand = dir(fullfile(roots{r}, 'plugins', 'brainbeats*'));
    for c = 1:numel(cand)
        p = fullfile(cand(c).folder, cand(c).name);
        addpath(genpath(p));
        fprintf('  BrainBeats found in %s and added to the path.\n', p);
        if exist('brainbeats_process', 'file'), ok = true; return; end
    end
end

% 3. not installed: download it. plugin_askinstall cannot be used from here
%    (it errors from deep call stacks), so drive plugin_getweb/plugin_install
%    directly - this is exactly what its "download now?" branch does.
fprintf('BrainBeats is not installed. Downloading it (this needs internet)...\n');
try
    plugins = plugin_getweb('plugin_install', []);
    if isempty(plugins), error('extension list unavailable'); end
    ind = strmatch(lower('brainbeats'), lower({plugins.name}), 'exact');
    if isempty(ind), error('BrainBeats not in the extension list'); end
    result = plugin_install(plugins(ind).zip, plugins(ind).name, plugins(ind).version, false);
    if result ~= 1, error('plugin_install returned %d', result); end
catch ME
    warning(['Could not install BrainBeats automatically (%s). Install it from ' ...
        'File > Manage EEGLAB extensions, then run the PPG step again.'], ME.message);
    return
end

% 4. put the fresh install on the path (plugin_install drops it in eeglab/plugins)
root = fileparts(which('eeglab.m'));
cand = dir(fullfile(root, 'plugins', 'brainbeats*'));
for c = 1:numel(cand)
    addpath(genpath(fullfile(cand(c).folder, cand(c).name)));
end
if exist('brainbeats_process', 'file')
    fprintf('  BrainBeats installed and ready.\n');
    ok = true;
else
    % a rebuild is sometimes needed before the new functions resolve
    rehash; rehash toolboxcache;
    ok = exist('brainbeats_process', 'file') > 0;
    if ok, fprintf('  BrainBeats installed and ready.\n'); end
end
end