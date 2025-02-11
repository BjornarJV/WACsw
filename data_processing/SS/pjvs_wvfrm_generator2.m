% Simulates step waveform generated by PJVS. First a reference waveform is
% constructed and PJVS voltages are generated as quantized mean of reference
% waveform (in specific time span). Next the PJVS voltages are generated for
% every sample. Time series of samples does not have to be equidistant. PJVS
% steps will be always equidistant. Noncoherency between signal, sampling and
% PJVS steps is permitted and correctly calculated (for sine function). If
% sample happens at the exact time of PJVS step change, the machine precision
% decides if the voltage of the sample will be of the previous or the next step.
%
% Imperfection: for triangular, sawtooth and rectangular waveforms: if time span
% of a PJVS step covers break (discontinuity of derivation), the mean value of
% the function is not calculated correctly and voltage of the PJVS step is not
% optimal.
%
% Any input quantity can be set to empty value []. Default value will be set for
% this quantity. Either specify 't' and keep 'L' and 'fs' empty or keep 't'
% empty and specify 'L' and 'fs'. If both 't' and 'L','fs' will be specified,
% 't' got preference.
%
% Inputs:
% fs - frequency of the samples (sampling frequency) (Hz), scalar.
% L - number of samples (record length), scalar.
% t - time of samples (s), vector.
% f - frequency of the reference waveform (Hz), scalar.
% A - amplitude of the reference waveform (V), scalar.
% ph - phase of the reference waveform (rad), scalar.
% fstep - frequency of the PJVS steps (Hz), scalar.
% phstep - phase of the PJVS steps (rad), scalar.
% fm - microwave frequency (Hz), scalar.
% waveformtype - 1: sine, 2: triangular, 3: sawtooth, 4: rectangular.
%
% Outputs:
% y - samples of the quantized reference waveform (V).
% n - quantum numbers in every PJVS step (int).
% Upjvs - PJVS voltages of all PJVS steps (V).
% Upjvs1period - PJVS voltages of PJVS steps in one period of reference waveform (V).
% Spjvs - indexes of samples of PJVS switches - switch happen before or at the sample.
% tsamples - times of samples of y (s).
%
% Example:
% [y, n, Upjvs, Upjvs1period, Spjvs, tsamples] = pjvs_wvfrm_generator2();
% plot(t, y);

function [y, n, Upjvs, Upjvs1period, Spjvs, tsamples] = pjvs_wvfrm_generator2(fs, L, t, f, A, ph, fstep, phstep, fm, waveformtype)
    % Constants %<<<1
    % for debugging:
    % (do not use for large/long waveforms, the plot will take forever to
    % render!)
    DEBUG = 0;

    % the only possible waveform types:
    % 1: sime, 2: triangular 3: saw 4: square
    possiblewaveformtypes = [1 2 3 4];

    % Josephson constant, 2e/h:
    h = 6.62607015e-34;
    e = 1.602176634e-19;
    KJ = 2*e/h; % (Hz/V)

    % treat user inputs %<<<1
    % set default values
    if ~exist('fs', 'var') fs = []; end
    if ~exist('L', 'var') L = []; end
    if ~exist('t', 'var') t = []; end
    if ~exist('f', 'var') f = []; end
    if ~exist('A', 'var') A = []; end
    if ~exist('ph', 'var') ph = []; end
    if ~exist('fstep', 'var') fstep = []; end
    if ~exist('phstep', 'var') phstep = []; end
    if ~exist('fm', 'var') fm = []; end
    if ~exist('waveformtype', 'var') waveformtype = []; end
    if isempty(t)
        % time series was not provided
        if isempty(fs) fs = 100; end
        if isempty(L) L = 200; end
    else
        L = [];
        fs = [];
    end
    if isempty(f) f = 1; end
    if isempty(A) A = 1; end
    if isempty(ph) ph = 0; end
    if isempty(fstep) fstep = 10; end
    if isempty(phstep) phstep = -0.3142; end
    if isempty(fm) fm = 75e9; end
    if isempty(waveformtype) waveformtype = possiblewaveformtypes(1); end % sine

    if isempty(t)
        if L <= 0
            error('pjvs_wvfrm_generator: Number of samples `L` must be greater than zero!')
        end
        if fs <= 0
            error('pjvs_wvfrm_generator: Frequency of the samples `fs` must be greater than zero!')
        end
    else
        if numel(t) == 0
            error('pjvs_wvfrm_generator: Time of samples `t` must contain at least one value!')
        end
    end % if isempty(t)
    if any([fs f fstep fm] <= 0)
        error('pjvs_wvfrm_generator: All frequencies (`fs`, `f`, `fstep`, `fm`) must be greater than zero!')
    end
    if A <= 0
        error('pjvs_wvfrm_generator: Amplitude `A` must be greater than zero!')
    end
    if ~any(waveformtype == possiblewaveformtypes)
        error(sprintf('pjvs_wvfrm_generator: unknown waveform type %d. Only possible values are: [%s]', waveformtype, num2str(possiblewaveformtypes)))
    end

    % initialize values %<<<1
    % wrap phase:
    % (remove additional 2*pi multiples from user input phases)
    phstep = rem(phstep, 2*pi);
    if phstep < 0
        phstep = phstep + 2*pi;
    end
    ph = rem(ph, 2*pi);
    if ph < 0
        ph = ph + 2*pi;
    end
    % minimum voltage step for actual microwave frequency:
    VS = fm/KJ;
    % period of reference function:
    T = 1/f;
    % period of PJVS steps:
    Tseg = 1/fstep;
    % time of samples:
    if isempty(t)
        % create time series based on fs and L:
        tsamples = [0 : 1 : L-1]./fs;
    else
        % time series was provided as input:
        tsamples = t;
    end % if

    % find out times of PJVS step changes %<<<1
    % (independent on timestamps of samples)
    % maximum time:
    tmax = tsamples(end);
    % calculate initial time delay given by the phase of PJVS steps:
    tdel = Tseg * phstep./(2*pi);
    % times of step changes:
    % (element 2*abs(tdel) is added only to be sure the tstepchange cover wide
    % enought interval)
    tstepchange = tdel + [0 : Tseg : tmax + 2*abs(tdel)];
    % remove all times larger than tmax or smaller than 0, that could have been
    % caused by large tdel:
    tstepchange = tstepchange(tstepchange <= tmax);
    tstepchange = tstepchange(tstepchange >= 0);
    % and now ensure there is exactly one more step change time at beginning and
    % at end so partial steps are also correctly calculated:
    tstepchange = [tstepchange(1) - Tseg, tstepchange, tstepchange(end) + Tseg];
    % PJVS steps as interval start/stop:
    t1 = tstepchange(1:end-1);
    t2 = tstepchange(2:end);
    % time of middle of the PJVS steps:
    tstepmiddle = (t2-t1)./2 + t1;

    % PJVS steps values and reference waveforms %<<<1
    w = 2*pi*f;
    if waveformtype == 1 % sine waveform
        % samples of reference waveform at sample times:
        Usamples = A*sin(w*tsamples + ph);
        % average voltages of reference waveform at time of middle of the step:
        U = A.*(cos(w.*t1 + ph) - cos(w.*t2 + ph))./(w.*(t2-t1));
    elseif waveformtype == 2 % triangle waveform
        % samples of reference waveform at sample times:
        Usamples = 2*A*abs(mod((w.*tsamples    + ph)/pi, 2) - 1) - 2*A/2;
        % average voltages of reference waveform at time of middle of the PJVS step:
        % XXX! the U value is incorrect for PJVS step where triangle change
        % the slope! There should be integral, as in sine function, but I have
        % no idea how to integrate floor function without resorting to a
        % piecewise calculation.
        U =        2*A*abs(mod((w.*tstepmiddle + ph)/pi, 2) - 1) - 2*A/2;
    elseif waveformtype == 3 % saw waveform
        % get time delay from phase:
        delay = ph./(2*pi);
        % samples of reference waveform at sample times:
        Usamples = A*2*(tsamples/T - floor(tsamples/T + 1/2));
        % average voltages of reference waveform at time of middle of the PJVS step:
        % XXX! the U value is incorrect for PJVS step where sawtooth change
        % the polarity! There should be integral, as in sine function, but I
        % have no idea how to integrate floor function without resorting to a
        % piecewise calculation.
        U        = A*2*(tstepmiddle/T - floor(tstepmiddle/T + 1/2));
    elseif waveformtype == 4 % square waveform
        w = 2*pi*f;
        % samples of reference waveform at sample times:
        Usamples = sign(A*sin(w*tsamples + ph));
        % average voltages of reference waveform at time of middle of the PJVS step:
        % XXX! the U value is incorrect for PJVS step where square change
        % the polarity! There should be integral, as in sine function, but I have
        % no idea how to integrate sign function without resorting to a
        % piecewise calculation.
        U        = sign(A*sin(w*tstepmiddle + ph));
    else
        error(sprintf('pjvs_wvfrm_generator: unknown waveform type %d. Only possible values are: [%s]', waveformtype, num2str(possiblewaveformtypes)))
    end % if waveformtype

    % quantize PJVS voltage %<<<1
    % find quantum numbers for every PJVS step:
    nstep = round(U./VS);
    % mutliply quantum numbers to get quantized voltages:
    Ustep = nstep.*VS;

    % quantize samples %<<<1
    % initialize output voltage variable:
    y = NaN.*ones(size(tsamples));
    % initialize number of samples per one PJVS step:
    samplesperstep = zeros(size(nstep));
    % initialize indexes of step starts:
    Spjvs = [];
    % initialize PJVS voltages of used PJVS steps:
    Upjvs = [];
    % initialize PJVS voltages of used PJVS steps for only 1 period of reference
    % waveform:
    Upjvs1period = [];
    % initialize quantum numbers of used PJVS steps:
    n = [];
    % create quantized samples for every time section of PJVS steps:
    for j = 1 : numel(tstepchange)-1
        % extremely slow method, caused by searching in next two lines
        leftlimit = tsamples >= tstepchange(j);
        rightlimit = tsamples < tstepchange(j+1);
        idx = and(leftlimit, rightlimit);
        if sum(idx) ~= 0
            % actual PJVS step is to be used because at least one sample lies on
            % the step.
            % quantized samples:
            y(idx) = Ustep(j);
            % count samples per step for debug:
            samplesperstep(j) = sum(idx);
            % get index of a first sample in this interval of actual PJVS step:
            tmp = find(idx);
            Spjvs = [Spjvs tmp(1)];
            % save PJVS voltages:
            Upjvs = [Upjvs Ustep(j)];
            % Get quantum number:
            n = [n nstep(j)];
            % And check if the PJVS voltage is in first period of reference
            % waveform. If so, save it:
            if tsamples(idx) < T% time of first index
                Upjvs1period = [Upjvs1period Ustep(j)];
            end
        end
        % Following part is to make samples at step change in the middle of the
        % step. While it seems to be correct behaviour, it is really only issue
        % of machine precission and, as I believe, it is not really important to
        % implement.
            % epsilon = eps(tstepchange(j));
            % idx = and(tsamples > tstepchange(j) - epsilon, tsamples < tstepchange(j) + epsilon) ;
            % if ~isempty(idx)
            %     disp('sample on the step')
            %     % keyboard
            %     if j > 1;
            %         y(idx) = mean([Ustep(j-1), Ustep(j)]);
            %     end
            % end
            % idx = tsamples == tstepchange(j);
            % if ~isempty(idx)
                % y(idx) = mean([Ustep(j), Ustep(j)]);
            % end
    end % for

    % Ensure Spjvs proper values
    %
    % ensure start and ends of record as PJVS segments
    Spjvs(Spjvs < 1) = [];
    Spjvs(Spjvs > numel(y) + 1) = [];
    if Spjvs(1) ~= 1
        Spjvs = [1 Spjvs];
    end
    if Spjvs(end) ~= numel(y) + 1
        % because Spjvs marks start of step, next
        % step is after the last data sample
        Spjvs(end+1) = numel(y) + 1;
    end
        %

    % DEBUG - part only for debugging or detailed inspection %<<<1
    if DEBUG
        % print out some information
        if isempty(t)
            no = L;
        else
            no = numel(t);
        end
        disp('---')
        disp('pjvs_wvfrm_generator2 DEBUG informations:')
        printf('Change of quantum number by 1 is equal to: %.4g V\n', VS);
        % To move phase of steps by half sample: that is ratio of 0.5*sampling
        % period to step period times 2*pi.
        tmp = (0.5./fs)./(1./fstep).*2.*pi;
        printf('PJVS phase to shift steps by half sample time: %.4f rad\n', tmp);
        disp('Number of samples per PJVS steps:')
        disp(samplesperstep)
        printf('Total number of all samples in all PJVS steps:: %d\n', sum(samplesperstep));
        printf('Mean samples per PJVS step (step before t=0 not accounted): %d\n', mean(samplesperstep(2:end)));
        if isempty(t)
            printf('Expected samples per PJVS step (fs/fstep): %f\n', fs./fstep);
            delta = mean(samplesperstep(2:end)) - fs./fstep;
        else
            printf('Expected samples per PJVS step (mean(1/diff(t))/fstep): %f\n', mean(1./diff(t))./fstep);
            delta = mean(samplesperstep(2:end)) - mean(1./diff(t))./fstep;
        end
        printf('Difference of expected to mean samples per step to expected samples per step: %g\n', delta)
        printf('Required no. of samples: %d\n', L);
        printf('Output no. of samples: %d\n', no);
        printf('No. of calculated PJVS steps: %d\n', numel(Ustep));
        printf('No. of used PJVS steps: %d\n', numel(Upjvs));
        printf('No. of used PJVS steps in one period of reference waveform: %d\n', numel(Upjvs1period));

        % overview plot
        figure()
        hold on
        plot(tsamples, Usamples, '+-g')
        % plot(tU, y, 'o-r')
        plot(tstepmiddle, Ustep, 'or', 'markersize', 10, 'linewidth', 2)
        plot(tsamples, y, 'x-b')
        plot(tsamples(Spjvs(1:end-1)), y(Spjvs(1:end-1)), 'ok', 'markersize', 6, 'linewidth', 2)
        ylims = ylim;
        % plot times of step change
        for j = 1:numel(tstepchange)
            plot([tstepchange(j) tstepchange(j)], ylims, ':k')
        end
        % plot steps
        for j = 2:numel(tstepchange)
            plot([tstepchange(j-1) tstepchange(j)], [Ustep(j-1) Ustep(j-1)], '-r')
        end
        legend('reference waveform at samples', 'PJVS at middle of the step', 'PJVS at samples', 'Step switch at samples', 'time of a step change')
        hold off
        xlabel('t (s)')
        ylabel('voltage (V)')
        title(sprintf('pjvs_wvfrm_generator2.m'), 'interpreter', 'none')
    end % if DEBUG

end % function

% tests  %<<<1
% XXX more tests should be present
%!test
%!shared fs, L, t, f, A, ph, fstep, phstep, fm, waveformtype, y, n, Upjvs, Upjvs1period, Spjvs, tsamples
%! fs = 1000;
%! L = 1000;
%! t = [];
%! f = 1;
%! A = 1;
%! ph = 0*pi;
%! fstep = 10;
%! phstep = 0;
%! fm = 75e9;
%! waveformtype = 1;
%! [y, n, Upjvs, Upjvs1period, Spjvs, tsamples] = pjvs_wvfrm_generator2(fs, L, t, f, A, ph, fstep, phstep, fm, waveformtype);
%!assert(size(y, 2) == L);
%!assert(size(n, 2) == 10);
%!assert(size(Upjvs, 2) == 10);
%!assert(size(Upjvs1period, 2) == 10);
%!assert(size(Spjvs, 2) == 10);
%!assert(size(tsamples, 2) == L);
%!assert(all(n == [1960 5131 6342 5131 1960 -1960 -5131 -6342 -5131 -1960]))
%! A=2;
%! [y, n, Upjvs, Upjvs1period, Spjvs, tsamples] = pjvs_wvfrm_generator2(fs, L, t, f, A, ph, fstep, phstep, fm, waveformtype);
%!assert(n(1) == 2*1960)
%! phstep = pi;
%! [y, n, Upjvs, Upjvs1period, Spjvs, tsamples] = pjvs_wvfrm_generator2(fs, L, t, f, A, ph, fstep, phstep, fm, waveformtype);
%!assert(size(n, 2) == 11);

% demo %<<<1
% terrible inputs and nice figure:
%!demo
%! fs = 100;
%! L = 200;
%! f = 1;
%! A = 1;
%! ph = 0;
%! fstep = 10;
%! phstep = 0;
%! fm = 75e9;
%! waveformtype = 1;
%! [y, n, Upjvs, Upjvs1period, Spjvs, tsamples] = pjvs_wvfrm_generator2(fs, L, [], f, A, ph, fstep, phstep, fm, waveformtype);
%! plot(tsamples, y, '-x')
%! xlabel('t (s)')
%! ylabel('sampled PJVS voltage (V)')
%! title('PJVS steps')

% vim settings modeline: vim: foldmarker=%<<<,%>>> fdm=marker fen ft=octave textwidth=80 tabstop=4 shiftwidth=4
