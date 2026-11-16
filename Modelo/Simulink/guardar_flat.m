function S = guardar_flat(out, archivo, tend, ts)


if nargin < 3 || isempty(tend), tend = 1000; end
if nargin < 4 || isempty(ts), ts = 0.1; end
t = (0:ts:tend)';
tref = tiempo_general(out);

S = struct('t', t);
faltan = {};
% Referencias primero (escenario en el espacio base o registradas en el modelo)
refs = {'hws', 'hbs', 'pgs'}; ali_r = {{'hws','hws_'}, {'hbs','hbs_'}, {'pgs','pgs_'}};
for i = 1:3
    [v, de] = buscar(out, ali_r{i});
    if isempty(v), faltan{end+1} = refs{i}; continue; end %#ok<AGROW>
    [tv, xv] = a_columnas(v, tref, de);
    S.(refs{i}) = remuestrear(tv, xv(:,end), t);
end
% Mediciones: si la senal tiene varias columnas (p. ej. un Mux [referencia medicion]),
% se toma la columna que no coincide con la referencia
meds = {'hw', 'hb', 'pg'}; ali_m = {{'hw','hw_'}, {'hb','hb_'}, {'pg','pg_'}};
for i = 1:3
    [v, de] = buscar(out, ali_m{i});
    if isempty(v), faltan{end+1} = meds{i}; continue; end %#ok<AGROW>
    [tv, xv] = a_columnas(v, tref, de);
    col = 1;
    if size(xv, 2) > 1
        if isfield(S, refs{i})
            r = S.(refs{i}); dif = zeros(1, size(xv, 2));
            for c = 1:size(xv, 2)
                y = remuestrear(tv, xv(:,c), t);
                dif(c) = max(abs(y - r));
            end
            [~, col] = max(dif);                        % la que mas se aparta de la referencia es la medicion
            fprintf('  %s: %d columnas en %s; se usa la columna %d como medicion\n', meds{i}, size(xv, 2), de, col);
        else
            col = size(xv, 2);
            fprintf('  %s: %d columnas en %s; se usa la ultima como medicion\n', meds{i}, size(xv, 2), de);
        end
    end
    S.(meds{i}) = remuestrear(tv, xv(:,col), t);
end
S = orderfields(S, {'t', 'hw', 'hws', 'hb', 'hbs', 'pg', 'pgs'});
% Aperturas: primero la entrada real de la planta (u_planta_ = [qwi qci qgi vpw vpc vpg]),
% si el modelo la registra; si no, la senal de las aperturas (cvs_) o las tres separadas
ap = {'vpw', 'vpc', 'vpg'};
[v, de] = buscar(out, {'u_planta_'});
if ~isempty(v)
    [tv, xv] = a_columnas(v, tref, de);
    if size(xv, 2) < 6, error('guardar_flat:u_planta', '%s tiene %d columnas; se esperaban 6.', de, size(xv, 2)); end
    for j = 1:3, S.(ap{j}) = remuestrear(tv, xv(:,3+j), t); end
    fprintf('  aperturas: entrada real de la planta (u_planta_, columnas 4 a 6)\n');
    [v, de] = deal([], '');
    usado_planta = true;
else
    usado_planta = false;
    [v, de] = buscar(out, {'cvs_', 'cvs', 'cv_', 'cv'});
end
if usado_planta
    % ya asignadas
elseif ~isempty(v)
    [tv, xv] = a_columnas(v, tref, de);
    if size(xv, 2) < 3, error('guardar_flat:cvs', '%s tiene %d columnas; se esperaban 3 aperturas.', de, size(xv, 2)); end
    for j = 1:3, S.(ap{j}) = remuestrear(tv, xv(:,j), t); end
else
    for j = 1:3
        [v, de] = buscar(out, {ap{j}});
        if isempty(v), faltan{end+1} = ap{j}; continue; end %#ok<AGROW>
        [tv, xv] = a_columnas(v, tref, de);
        S.(ap{j}) = remuestrear(tv, xv(:,1), t);
    end
end
if ~isempty(faltan)
    error('guardar_flat:faltan', ['No encuentro las senales: %s.\nDisponibles en la salida de sim: %s\n' ...
          'Registrelas con bloques To Workspace o con Signal Logging, o deje las referencias en el espacio base.'], ...
          strjoin(faltan, ', '), lista_disponibles(out));
end

% Unidades: presion en psi, niveles en m, aperturas en por unidad
for nm = {'pg', 'pgs'}
    if median(S.(nm{1})) > 1000
        S.(nm{1}) = S.(nm{1}) / 6894.757; fprintf('  %s: convertido de Pa a psi\n', nm{1});
    end
end
for nm = {'hw', 'hws', 'hb', 'hbs'}
    if median(S.(nm{1})) > 1.6
        S.(nm{1}) = S.(nm{1}) * 0.3048; fprintf('  %s: convertido de ft a m\n', nm{1});
    end
end
for j = 1:3
    if max(S.(ap{j})) > 1.5
        S.(ap{j}) = S.(ap{j}) / 100; fprintf('  %s: convertido de %% a por unidad\n', ap{j});
    end
end

carpeta = fileparts(archivo);
if ~isempty(carpeta) && ~exist(carpeta, 'dir'), mkdir(carpeta); end
save(archivo, '-struct', 'S');
fprintf('  Guardado %s (%d muestras)\n', archivo, numel(t));
end

%% ======================= funciones locales =======================
function tref = tiempo_general(out)
tref = [];
nm = {'t1', 'tout'};
for i = 1:numel(nm)
    [v, ~] = buscar(out, nm(i));
    if isa(v, 'timeseries'), tref = v.Time(:); return; end
    if ~isempty(v) && isnumeric(v), tref = v(:); return; end
end
end

function [v, de] = buscar(out, nombres)
v = []; de = '';
for i = 1:numel(nombres)
    nm = nombres{i};
    % 1) salida de sim (Simulink.SimulationOutput) o estructura
    try
        if isstruct(out) && isfield(out, nm), v = out.(nm); de = nm; return; end
        if ~isstruct(out) && any(strcmp(out.who, nm)), v = out.get(nm); de = nm; return; end
    catch
    end
    % 2) logsout
    try
        if ~isstruct(out) && any(strcmp(out.who, 'logsout'))
            L = out.get('logsout'); e = L.getElement(nm);
            if ~isempty(e), v = e.Values; de = ['logsout.' nm]; return; end
        end
    catch
    end
    % 3) espacio de trabajo base
    try
        if evalin('base', sprintf('exist(''%s'', ''var'')', nm))
            v = evalin('base', nm); de = ['base.' nm]; return;
        end
    catch
    end
end
end

function [tv, xv] = a_columnas(v, tref, de)
if isa(v, 'timeseries')
    tv = v.Time(:); xv = squeeze(v.Data);
    if size(xv, 1) ~= numel(tv), xv = xv.'; end
elseif isstruct(v) && isfield(v, 'signals')
    xv = v.signals.values;
    if isfield(v, 'time') && ~isempty(v.time), tv = v.time(:); else, tv = tref; end
elseif isnumeric(v)
    if size(v, 1) == 1 && size(v, 2) > 3, v = v.'; end
    if size(v, 2) == 2 && abs(v(1,1)) < 1e-12 && all(diff(v(:,1)) >= 0) && v(end,1) > 1
        tv = v(:,1); xv = v(:,2);               % formato [t valor] de los escenarios
    elseif numel(tref) == size(v, 1)
        tv = tref; xv = v;
    else
        error('guardar_flat:tiempo', '%s tiene %d filas y no hay un vector de tiempo de la misma longitud (t1 o tout).', de, size(v, 1));
    end
else
    error('guardar_flat:tipo', 'Tipo de senal no reconocido en %s: %s', de, class(v));
end
xv = double(xv);
if size(xv, 1) ~= numel(tv), xv = xv.'; end
end

function y = remuestrear(tv, xv, t)
% Ultimo valor registrado en cada instante (las senales discretas se repiten en los cambios)
dt = t(min(2, numel(t))) - t(1);
if tv(1) > t(1) + dt/2 || tv(end) < t(end) - dt/2
    error('guardar_flat:cobertura', ['La senal cubre de %.2f a %.2f s y la corrida va de %.2f a %.2f s. ' ...
          'Revise el StartTime del modelo: no se extrapola.'], tv(1), tv(end), t(1), t(end));
end
[tu, iu] = unique(tv(:), 'last');
y = interp1(tu, xv(iu), t, 'linear', 'extrap');
end

function s = lista_disponibles(out)
s = '';
try
    if isstruct(out), s = strjoin(fieldnames(out)', ', '); else, s = strjoin(out.who', ', '); end
catch
end
end
