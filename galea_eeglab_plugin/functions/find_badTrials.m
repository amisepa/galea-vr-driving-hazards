%% Scan data to find bad trials using amplitude and high-frequency power
%
% INPUT:
%   EEG - EEG stucture (EEGLAB)
%   method  - 'grubbs' (default, more aggressive), 'mean' (more lax)
%
% OUTPUT:
%   badTrials
%
% Cedric Cannard, Dec 2022

function badTrials = find_badTrials(EEG,method,vis)

disp('Detecting bad trials...')
b = design_fir(100,[2*[0 45 50]/EEG.srate 1],[1 1 0 0]);
sig_amp = nan(1,size(EEG.data,3));
sig_snr = nan(1,size(EEG.data,3));
for iEpoch = 1:size(EEG.data,3)
    sig_amp(:,iEpoch) = rms(rms(squeeze(EEG.data(:,:,iEpoch)),2));
    tmp = filtfilt_fast(b,1, squeeze(EEG.data(:,:,iEpoch))');
    sig_snr(:,iEpoch) = rms(mad(squeeze(EEG.data(:,:,iEpoch)) - tmp'));
end
badRMS = isoutlier(sig_amp,method);
badSNR = isoutlier(sig_snr,method);
badTrials = unique([find(badRMS) find(badSNR)]);

if ~isempty(badTrials) && vis
   eegplot(EEG.data(:,:,badTrials),'srate',EEG.srate,'events',EEG.event, ...
        'eloc_file',EEG.chanlocs,'spacing', 100,'title','Bad epochs removed','plottitle','Bad epochs removed');
end

fprintf('Trials detected: %g \n', length(badTrials));


%% SUBFUNCTIONS

function B = design_fir(N,F,A,nfft,W)
% B = design_fir(N,F,A,nFFT,W)
% Design an FIR filter using the frequency-sampling method.
%
% The frequency response is interpolated cubically between the specified
% frequency points.
%
% In:
%   N : order of the filter
%
%   F : vector of frequencies at which amplitudes shall be defined
%       (starts with 0 and goes up to 1; try to avoid too 
%        sharp transitions)
%
%   A : vector of amplitudes, one value per specified frequency
%
%   nFFT : optionally number of FFT bins to use
%
%   W : optionally the window function to use (default: Hamming)
%
% Out:
%   B : designed filter kernel
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2013-08-14

% Copyright (C) Christian Kothe, SCCN, 2013, ckothe@ucsd.edu
%
% This program is free software; you can redistribute it and/or modify it under the terms of the GNU
% General Public License as published by the Free Software Foundation; either version 2 of the
% License, or (at your option) any later version.
%
% This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
% even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
% General Public License for more details.
%
% You should have received a copy of the GNU General Public License along with this program; if not,
% write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307
% USA

if nargin < 4 || isempty(nfft)
    nfft = max(512,2^ceil(log(N)/log(2))); end
if nargin < 5
    W = 0.54 - 0.46*cos(2*pi*(0:N)/N); end

% calculate interpolated frequency response
F = interp1(round(F*nfft),A,(0:nfft),'pchip');

% set phase & transform into time domain
F = F .* exp(-(0.5*N)*sqrt(-1)*pi*(0:nfft)./nfft);
B = real(ifft([F conj(F(end-1:-1:2))]));

% apply window to kernel
B = B(1:N+1).*W(:)';

function X = filtfilt_fast(varargin)
% Like filtfilt(), but faster when filter and signal are long (and A=1).
% Y = filtfilt_fast(B,A,X)
%
% Uses FFT convolution (needs fftfilt). The function is faster than filter when approx.
% length(B)>256 and size(X,Dim)>1024, otherwise slower (due size-testing overhead).
%
% Note:
%  Can also be called with four arguments, as Y = filtfilt_fast(N,F,A,X), in which case an Nth order
%  FIR filter is designed that has the desired frequency response A at normalized frequencies F; F
%  must be a vector of numbers increasing from 0 to 1.
%
% See also: 
%   filtfilt, filter
% 
%                           Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                           2010-07-14

% Copyright (C) Christian Kothe, SCCN, 2010, ckothe@ucsd.edu
%
% This program is free software; you can redistribute it and/or modify it under the terms of the GNU
% General Public License as published by the Free Software Foundation; either version 2 of the
% License, or (at your option) any later version.
%
% This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
% even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
% General Public License for more details.
%
% You should have received a copy of the GNU General Public License along with this program; if not,
% write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307
% USA

if nargin == 3
    [B A X] = deal(varargin{:});
elseif nargin == 4
    [N F M X] = deal(varargin{:});
    B = design_fir(N,F,sqrt(M)); A = 1; % note: we use the sqrt() because we run forward and backward
else
    help filtfilt_fast;
    return;
end

if A == 1
    was_single = strcmp(class(X),'single');
    w = length(B); t = size(X,1);    
    % extrapolate
    X = double([bsxfun(@minus,2*X(1,:),X(1+mod(((w+1):-1:2)-1,t),:)); X; bsxfun(@minus,2*X(t,:),X(1+mod(((t-1):-1:(t-w))-1,t),:))]);
    % filter, reverse
    X = filter_fast(B,A,X); X = X(length(X):-1:1,:);
    % filter, reverse
    X = filter_fast(B,A,X); X = X(length(X):-1:1,:);
    % remove extrapolated pieces
    X([1:w t+w+(1:w)],:) = [];
    if was_single
        X = single(X); end    
else    
    % fall back to filtfilt for the IIR case
    X = filtfilt(B,A,X);
end


function [X,Zf] = filter_fast(B,A,X,Zi,dim)
% Like filter(), but faster when both the filter and the signal are long.
% [Y,Zf] = filter_fast(B,A,X,Zi,Dim)
%
% Uses FFT convolution. The function is faster than filter when approx. length(B)>256 and
% size(X,Dim)>1024, otherwise slower (due size-testing overhead).
%
% See also:
%   filter, fftfilt
%
%                           Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                           2010-07-09
%
%                           contains fftfilt.m from Octave:
%                           Copyright (C) 1996-1997 John W. Eaton


% Copyright (C) Christian Kothe, SCCN, 2010, ckothe@ucsd.edu
%
% This program is free software; you can redistribute it and/or modify it under the terms of the GNU
% General Public License as published by the Free Software Foundation; either version 2 of the
% License, or (at your option) any later version.
%
% This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
% even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
% General Public License for more details.
%
% You should have received a copy of the GNU General Public License along with this program; if not,
% write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307
% USA


if nargin <= 4
    dim = find(size(X)~=1,1); end
if nargin <= 3
    Zi = []; end

lenx = size(X,dim);
lenb = length(B);
if lenx == 0
    % empty X
    Zf = Zi;
elseif lenb < 256 || lenx<1024 || lenx <= lenb || lenx*lenb < 4000000 || ~isequal(A,1)
    % use the regular filter
    if nargout > 1
        [X,Zf] = filter(B,A,X,Zi,dim);
    else
        X = filter(B,A,X,Zi,dim);
    end
else
    was_single = strcmp(class(X),'single');
    % fftfilt can be used
    if isempty(Zi)
        % no initial conditions to take care of
        if nargout < 2
            % and no final ones
            X = unflip(oct_fftfilt(B,flip(double(X),dim)),dim);
        else
            % final conditions needed
            X = flip(X,dim);
            [dummy,Zf] = filter(B,1,X(end-length(B)+1:end,:),Zi,1); %#ok<ASGLU>
            X = oct_fftfilt(B,double(X));
            X = unflip(X,dim);
        end
    else
        % initial conditions available
        X = flip(X,dim);
        % get a Zi-informed piece
        tmp = filter(B,1,X(1:length(B),:),Zi,1);
        if nargout > 1
            % also need final conditions
            [dummy,Zf] = filter(B,1,X(end-length(B)+1:end,:),Zi,1); %#ok<ASGLU>
        end
        X = oct_fftfilt(B,double(X));
        % incorporate the piece
        X(1:length(B),:) = tmp;
        X = unflip(X,dim);
    end
    if was_single
        X = single(X); end
end

function X = flip(X,dim)
if dim ~= 1
    order = 1:ndims(X);
    order = order([dim 1]);
    X = permute(X,order);
end

function X = unflip(X,dim)
if dim ~= 1
    order = 1:ndims(X);
    order = order([dim 1]);
    X = ipermute(X,order);
end


function y = oct_fftfilt(b, x, N)
% Copyright (C) 1996, 1997 John W. Eaton
%
% This file is part of Octave.
%
% Octave is free software; you can redistribute it and/or modify it
% under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2, or (at your option)
% any later version.
%
% Octave is distributed in the hope that it will be useful, but
% WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
% General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Octave; see the file COPYING.  If not, write to the Free
% Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
% 02110-1301, USA.
%
% -*- texinfo -*-
% @deftypefn {Function File} {} fftfilt (@var{b}, @var{x}, @var{n})
%
% With two arguments, @code{fftfilt} filters @var{x} with the FIR filter
% @var{b} using the FFT.
%
% Given the optional third argument, @var{n}, @code{fftfilt} uses the
% overlap-add method to filter @var{x} with @var{b} using an N-point FFT.
%
% If @var{x} is a matrix, filter each column of the matrix.
% @end deftypefn
%
% Author: Kurt Hornik <Kurt.Hornik@wu-wien.ac.at>
% Created: 3 September 1994
% Adapted-By: jwe

% If N is not specified explicitly, we do not use the overlap-add
% method at all because loops are really slow.  Otherwise, we only
% ensure that the number of points in the FFT is the smallest power
% of two larger than N and length(b).  This could result in length
% one blocks, but if the user knows better ...
transpose = (size(x,1) == 1);

if transpose
    x = x.'; end

[r_x,c_x] = size(x);
[r_b,c_b] = size(b);
if min([r_b, c_b]) ~= 1
    error('octave:fftfilt','fftfilt: b should be a vector'); end

l_b = r_b*c_b;
b = reshape(b,l_b,1);

if nargin == 2
    % Use FFT with the smallest power of 2 which is >= length (x) +
    % length (b) - 1 as number of points ...
    N = 2^(ceil(log(r_x+l_b-1)/log(2)));
    B = fft(b,N);
    y = ifft(fft(x,N).*B(:,ones(1,c_x)));
else
    % Use overlap-add method ...
    if ~isscalar(N)
        error ('octave:fftfilt','fftfilt: N has to be a scalar'); end
    N = 2^(ceil(log(max([N,l_b]))/log(2)));
    L = N - l_b + 1;
    B = fft(b, N);
    B = B(:,ones(c_x,1));
    R = ceil(r_x / L);
    y = zeros(r_x, c_x);
    for r = 1:R
        lo = (r - 1) * L + 1;
        hi = min(r * L, r_x);
        tmp = zeros(N, c_x);
        tmp(1:(hi-lo+1),:) = x(lo:hi,:);
        tmp = ifft(fft(tmp).*B);
        hi = min(lo+N-1, r_x);
        y(lo:hi,:) = y(lo:hi,:) + tmp(1:(hi-lo+1),:);
    end
end

y = y(1:r_x,:);
if transpose
    y = y.'; end

% Final cleanups: if both x and b are real respectively integer, y
% should also be
if isreal(b) && isreal(x)
    y = real(y); end
if ~any(b - round(b))
    idx = ~any(x - round(x));
    y(:,idx) = round(y(:,idx));
end
