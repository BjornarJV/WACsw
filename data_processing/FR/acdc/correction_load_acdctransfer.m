function [acdctransfer] = correction_load_acdctransfer(file, meas)
        % XXX
        % range_names
        % range_count
        %
        %
    % Loader of the AC/DC transfer standard correction file.
    % It will always return all standard parameters even if they are not found.
    % In that case it will load 'neutral' defaults (unity AC/DC difference, ...).
    %
    % Inputs:
    %   file - absolute file path to the transducers header INFO file.
    %          Set '' or not assigned to load default 'blank' correction.
    %   meas     - loaded measurement header, required fields:
%               channel_names, channels_count%
    % Outputs:
    %   acdctransfer.type - string defining AC/DC transfer standard 'acdctransfer'
    %   acdctransfer.name - string with standards's name
    %   acdctransfer.sn - string with standards's serial
    %   acdctransfer.acdc_diff - 2D table of AC/DC difference values
    %   acdctransfer.allow_interp - if zero, interpolation of acdc_diff table is forbidden.

    % load default values only?
    is_default = ~exist('file','var') || isempty(file);

    if ~is_default
        % root folder of the correction
        root_fld = [fileparts(file) filesep()];
        % try to load the correction file
        acdcinf = infoload(file);
        % parse info file (speedup):
        acdcinf = infoparse(acdcinf);
        % get correction type id
        t_type = infogettext(acdcinf, 'type');
        % try to identify correction type
        id = strcmpi(t_type, 'acdctransfer');
        if ~numel(id)
            error(sprintf('AC/DC transfer standard data loader: Data type ''%s'' not recognized!'), t_type);
        end
    else
        % defaults:
        t_type = 'acdctransfer';
    end

    % store transducer type
    acdctransfer.type = t_type;

    if ~is_default
        % transducer correction name
        acdctransfer.name = infogettext(acdcinf,'name');
        % transducer serial number
        acdctransfer.sn = infogettext(acdcinf,'serial number');
        % get if interpolation is possible
        allow_interp = infogettext(acdcinf, 'allow interpolation');
        if any(strcmpi(allow_interp, {'1', 'yes', 'true'}))
            acdctransfer.allow_interp = true;
        end
    else
        % defaults:
        acdctransfer.name = 'blank ac/dc transfer standard';
        acdctransfer.sn = 'n/a';
        acdctransfer.allow_interp = 'n/a';
    end

        % load list of the acdctransfer ranges from the correction file:
        ranges_names = infogettextmatrix(acdcinf, 'range identifiers');

        % check if the correction file matches to the measurement header instruments:
        if meas.ranges_count == 1
            % ONLY ONE CHANNEL - try to find the channel in correction file:
            cid = find(strcmpi(ranges_names, meas.range_names));
            if isempty(cid)
                error('Digitizer correction loader: Instrument''s channel name not found in the correction file! This correction file cannot be used for this measurement.');
            end
            % channel index to search
            range_ids = cid(1);
        end

        % load channel correction paths:
        range_paths = infogettextmatrix(acdcinf, 'range correction paths');
        % convert filepaths for linux or for windows if needed. dos notation ('\') is kept because of
        % labview:
        range_paths = path_dos2unix(range_paths);
        % check consistency:
        if numel(range_paths) ~= numel(ranges_names)
            error('Digitizer correction loader: Number of digitizer''s channels does not match.');
        end


    % --- LOAD AC/DC DIFFERENCES ---
    rng = {};
    for r = 1:meas.ranges_count
        % for each range:
        if ~is_default
            % build path to range differences file
            fdep_file = fullfile(root_fld, range_paths{range_ids(r)});
        else
            % defaults:
            % default (acdcdifference, unc.)
            fdep_file = {[],[],1.0,0.0};
        end
        % load range correction file
        acdctransfer.acdc_diff = correction_load_table(fdep_file,'u_rms',{'f','acdc_diff','u_acdc_diff'});
        % load relative frequency/rms dependence (acdc difference):
        acdctransfer.acdc_diff.qwtb = qwtb_gen_naming('acdc_diff','f','u_rms',{'acdc_diff'},{'u_acdc_diff'},{''});

    end % for meas.ranges_count


    % this is a list of the correction that will be passed to the QWTB algorithm
    % note: any correction added to this list will be passed to the QWTB
    %       but it must contain the 'qwtb' record in the table (see eg. above)
    acdctransfer.qwtb_list = {};
    % autobuild of the list of loaded correction:
    fnm = fieldnames(acdctransfer);
    for k = 1:numel(fnm)
        item = getfield(acdctransfer,fnm{k});
        if isfield(item,'qwtb')
            acdctransfer.qwtb_list{end+1} = fnm{k};
        end
    end

end

% get info text, if found and empty generate error
function [file_name] = correction_load_transducer_get_file_key(inf,key)
    file_name = infogettext(inf,key);
    if isempty(file_name)
        error('File name empty!');
    end
    % convert filepaths for linux or for windows if needed. dos notation ('\') is kept because of
    % labview:
    file_name = path_dos2unix(file_name);
end


function [qw] = qwtb_gen_naming(c_name,ax_prim,ax_sec,v_list,u_list,v_names)
% Correction table structure cannot be directly passed into the QWTB.
% So this will prepare names of the QWTB variables that will be used
% for passing the table to the QWTB algorithm.
%
% Parameters:
%   c_name  - core name of the correction data
%   ax_prim - name of the primary axis suffix (optional)
%   ax_sec  - name of the secondary axis suffix (optional)
%   v_list  - cell array of the table's quantities to store
%   u_list  - cell array of the table's uncertainties to store
%   v_names - names of the suffixes for each item in the 'v_list'
%
% Example 1:
%   qw = qwtb_gen_naming('adc_gain','f','a',{'gain'},{'u_gain'},{''}):
%   qw.c_name = 'adc_gain'
%   qw.v_names = 'adc_gain'
%   qw.ax_prim = 'adc_gain_f'
%   qw.ax_sec = 'adc_gain_a'
%   qw.v_list = {'gain'}
%   qw.u_list = {'u_gain'}
%   this will be passed to the QWTB list:
%     di.adc_gain.v - the table quantity 'gain'
%     di.adc_gain.u - the table quantity 'u_gain' (uncertainty)
%     di.adc_gain_f.v - primary axis of the table
%     di.adc_gain_a.v - secondary axis of the table
%
% Example 2:
%   qw = qwtb_gen_naming('Yin','f','',{'Rp','Cp'},{'u_Rp','u_Cp'},{'rp','cp'}):
%   qw.c_name = 'Yin'
%   qw.v_names = {'Yin_Rp','Yin_Cp'}
%   qw.ax_prim = 'Yin_f'
%   qw.ax_sec = ''
%   qw.v_list = {'Rp','Cp'}
%   qw.u_list = {'u_Rp','u_Cp'}
%   this will be passed to the QWTB list:
%     di.Yin_rp.v - the table quantity 'Rp'
%     di.Yin_rp.u - the table quantity 'u_Rp' (uncertainty)
%     di.Yin_cp.v - the table quantity 'Cp'
%     di.Yin_cp.u - the table quantity 'u_Cp' (uncertainty)
%     di.adc_gain_f.v - primary axis of the table


    V = numel(v_names);
    if V > 1
        % create variable names: 'c_name'_'v_names{:}':
        qw.v_names = {};
        for k = 1:V
            qw.v_names{k} = [c_name '_' v_names{k}];
        end
    else
        % variable name: 'c_name':
        qw.v_names = {c_name};
    end

    if ~isempty(ax_prim)
        qw.ax_prim = [c_name '_' ax_prim];
    else
        qw.ax_prim = '';
    end
    if ~isempty(ax_sec)
        qw.ax_sec = [c_name '_' ax_sec];
    else
        qw.ax_sec = '';
    end
    qw.c_name = c_name;
    qw.v_list = v_list;
    qw.u_list = u_list;

end

