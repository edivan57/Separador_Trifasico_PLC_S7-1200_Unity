function info = crear_modelos_comun_v12(variantes, base, archivo_mpc)


if nargin < 1 || isempty(variantes), variantes = {'comun'}; end
if ischar(variantes), variantes = {variantes}; end
if nargin < 2 || isempty(base)
    base = struct('PID', 'Simulacion_Trifasico_PID_v8', 'Fuzzy', 'Simulacion_Trifasico_Fuzzy_v10');
end
if nargin < 3 || isempty(archivo_mpc), archivo_mpc = 'TPSEP_MPC_diseno_P_M6.mat'; end
M = load(archivo_mpc, 'mveq'); mveq = M.mveq(:);
fprintf('Apertura inicial comun (mveq de %s): %s %%\n', archivo_mpc, mat2str(100*mveq', 4));

info = struct('modelo', {}, 'cambios', {});
ctrls = {'PID', 'Fuzzy'};
for v = 1:numel(variantes)
    var = variantes{v};
    if ~any(strcmp(var, {'comun','arranque','limites','memoria'}))
        error('crear_modelos_comun_v12:variante', 'Variante desconocida: %s', var);
    end
    for c = 1:2
        ctrl = ctrls{c};
        if strcmp(var, 'memoria') && strcmp(ctrl, 'Fuzzy'), continue; end   % el Fuzzy ya guarda el valor limitado
        origen = [base.(ctrl) '_v12'];
        nuevo  = [base.(ctrl) '_' var '_v12'];
        f = which(origen);
        if isempty(f), error('crear_modelos_comun_v12:origen', 'No encuentro %s (corra antes crear_modelos_v12).', origen); end
        [carpeta, ~, ext] = fileparts(f);
        load_system(origen);
        if bdIsLoaded(nuevo), close_system(nuevo, 0); end
        save_system(origen, fullfile(carpeta, [nuevo ext]));     % la copia queda cargada con el nombre nuevo
        ch = sfroot().find('-isa', 'Stateflow.EMChart');
        hecho = false; lista = {};
        for k = 1:numel(ch)
            if ~startsWith(ch(k).Path, [nuevo '/']), continue; end
            sc = ch(k).Script;
            if strcmp(ctrl, 'PID') && ~isempty(regexp(sc, 'function\s+mv\s*=\s*PID_Controller', 'once'))
                [sc, lista] = cambios_pid(sc, var, mveq);
            elseif strcmp(ctrl, 'Fuzzy') && ~isempty(regexp(sc, 'function\s+mv\s*=\s*Fuzzy_MV', 'once'))
                [sc, lista] = cambios_fuzzy(sc, var, mveq);
            else
                continue
            end
            ch(k).Script = sc; hecho = true;
        end
        if ~hecho, error('crear_modelos_comun_v12:bloque', 'No encontre el bloque del controlador en %s', nuevo); end
        save_system(nuevo);
        fprintf('\n%s -> %s\n', origen, nuevo);
        fprintf('  %s\n', lista{:});
        info(end+1) = struct('modelo', nuevo, 'cambios', {lista}); %#ok<AGROW>
    end
end
end

function [sc, l] = cambios_pid(sc, var, mveq)
l = {};
if any(strcmp(var, {'comun','arranque'}))
    [sc, l] = reemplazar(sc, 'mv0\s*=\s*\[[^\]]*\];', sprintf('mv0      = [%.6f; %.6f; %.6f];   %% condicion comun: mveq del MPC', mveq), 'arranque mv0', l);
end
if any(strcmp(var, {'comun','limites'}))
    [sc, l] = reemplazar(sc, 'mv_min\s*=\s*0\.01;', 'mv_min   = 0.02;   % condicion comun', 'saturacion inferior 0.02', l);
    [sc, l] = reemplazar(sc, 'rate_max\s*=\s*\[[^\]]*\];', 'rate_max = [0.035; 0.015; 0.030];   % condicion comun', 'limitador 0.035/0.015/0.030', l);
end
if any(strcmp(var, {'comun','memoria'}))
    [sc, l] = reemplazar(sc, '(\n[ \t]*)last_mv = mv;', '$1u = mv;   % condicion comun: la memoria guarda el valor limitado$1last_mv = mv;', 'memoria = valor limitado', l);
end
end

function [sc, l] = cambios_fuzzy(sc, var, mveq)
l = {};
if any(strcmp(var, {'comun','arranque'}))
    [sc, l] = reemplazar(sc, 'cv0\s*=\s*\[[^\]]*\];', sprintf('cv0 = [%.6f; %.6f; %.6f];   %% condicion comun: mveq del MPC', mveq), 'arranque cv0', l);
end
if any(strcmp(var, {'comun','limites'}))
    [sc, l] = reemplazar(sc, 'MV_MIN\s*=\s*0\.01;', 'MV_MIN = 0.02;   % condicion comun', 'saturacion inferior 0.02', l);
    [sc, l] = reemplazar(sc, 'RATE_ENABLE\s*=\s*\w+;', 'RATE_ENABLE = true;', 'limitador activo', l);
    [sc, l] = reemplazar(sc, 'RATE_MAX\s*=\s*\[[^\]]*\];', 'RATE_MAX    = [0.035; 0.015; 0.03];   % condicion comun', 'limitador 0.035/0.015/0.03', l);
end
end

function [sc, l] = reemplazar(sc, patron, nuevo, nombre, l)
n = numel(regexp(sc, patron));
if n ~= 1
    error('crear_modelos_comun_v12:patron', 'Cambio "%s": se esperaba 1 coincidencia y hay %d.', nombre, n);
end
sc = regexprep(sc, patron, nuevo, 'once');
l{end+1} = nombre;
end
