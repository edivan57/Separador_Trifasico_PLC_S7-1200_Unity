function lista = correr_comparacion_v12(cfg)


c.modelos    = struct('PID', 'Simulacion_Trifasico_PID_v8', 'Fuzzy', 'Simulacion_Trifasico_Fuzzy_v10', ...
                      'MPC', 'Simulacion_Trifasico_MPC_v6');
c.sufijo     = '_v12';
c.escenarios = {'Escenario_Trifasico'};            % agregue 'Escenario_Trifasico_2' para el segundo escenario
c.casos      = {'v11', 'v12A', 'v12B'};
c.mpc_v11    = 'TPSEP_MPC_diseno_P_M6.mat';        % MPC de diseno del articulo (P = 200, M = 6)
c.mpc_v12    = 'TPSEP_MPC_v12.mat';                % controlador con modelo interno v12 (condicion B)
c.preparar   = struct('PID', '', 'Fuzzy', '', 'MPC', '');   % script de inicializacion propio de cada modelo, si lo usa
c.carpeta    = fullfile('Datos', 'Modelo_v12');
c.controladores = {'PID', 'Fuzzy', 'MPC'};       % p. ej. {'MPC'} para correr solo el MPC
c.etiqueta  = '';                                 % texto extra en el nombre, p. ej. 'P100' o 'comun' -> mpc_esc2_v12A_P100_flat.mat
if nargin >= 1 && ~isempty(cfg)
    f = fieldnames(cfg);
    for i = 1:numel(f), c.(f{i}) = cfg.(f{i}); end
end
% Acepta nombres de campo antiguos (PI) o nuevos (PID)
c.modelos  = alias_pid(c.modelos);
c.preparar = alias_pid(c.preparar);
if ~isfield(c.preparar, 'Fuzzy'), c.preparar.Fuzzy = ''; end
if ~isfield(c.preparar, 'MPC'),   c.preparar.MPC   = ''; end
if ~exist(c.carpeta, 'dir'), mkdir(c.carpeta); end

ctrls = intersect({'PID', 'Fuzzy', 'MPC'}, c.controladores, 'stable');
lista = {};
visible = get(0, 'DefaultFigureVisible');
set(0, 'DefaultFigureVisible', 'off');           % los escenarios grafican; no abrir ventanas
limpiar = onCleanup(@() set(0, 'DefaultFigureVisible', visible));

for e = 1:numel(c.escenarios)
    esc = c.escenarios{e};
    netiq = 1 + strcmp(esc, 'Escenario_Trifasico_2');
    for i = 1:numel(ctrls)
        ctrl = ctrls{i};
        for k = 1:numel(c.casos)
            caso = c.casos{k};
            if strcmp(caso, 'v12B') && ~strcmp(ctrl, 'MPC'), continue; end
            mdl = c.modelos.(ctrl);
            if ~strcmp(caso, 'v11'), mdl = [mdl c.sufijo]; end
            fprintf('\n[%s | %s | %s] modelo %s\n', esc, ctrl, caso, mdl);

            % Mismo orden que el flujo habitual: primero el controlador, al final el escenario
            % (asi ninguna variable del .mat del MPC sobrescribe las del escenario)
            if strcmp(ctrl, 'MPC')
                if strcmp(caso, 'v12B'), fmpc = c.mpc_v12; else, fmpc = c.mpc_v11; end
                cargar_en_base(fmpc);
                fprintf('  Controlador MPC: %s (P = %d, M = %s)\n', fmpc, evalin('base', 'mpc1.PredictionHorizon'), ...
                        mat2str(evalin('base', 'mpc1.ControlHorizon')));
            end
            if ~isempty(c.preparar.(ctrl)), evalin('base', [c.preparar.(ctrl) ';']); end
            evalin('base', [esc ';']);
            tend = evalin('base', 'tend');

            load_system(mdl);
            t0m = get_param(mdl, 'StartTime');
            if ~strcmp(strtrim(t0m), '0'), fprintf('  Aviso: el modelo tenia StartTime = %s; se simula desde 0\n', t0m); end
            out = sim(mdl, 'StartTime', '0', 'StopTime', num2str(tend), 'ReturnWorkspaceOutputs', 'on');
            if isempty(c.etiqueta), et = ''; else, et = ['_' c.etiqueta]; end
            archivo = fullfile(c.carpeta, sprintf('%s_esc%d_%s%s_flat.mat', lower(ctrl), netiq, caso, et));
            guardar_flat(out, archivo, tend);
            lista{end+1} = archivo; %#ok<AGROW>
            close all force
        end
    end
end
fprintf('\nCorridas guardadas en %s: %d archivos\n', c.carpeta, numel(lista));
end

function cargar_en_base(archivo)
% Carga todas las variables del .mat del MPC (mpc1, xmpc0, xeq, mveq, ...) en el espacio base
if ~exist(archivo, 'file'), error('correr_comparacion_v12:mpc', 'No encuentro %s', archivo); end
S = load(archivo);
f = fieldnames(S);
for i = 1:numel(f), assignin('base', f{i}, S.(f{i})); end
end

function s = alias_pid(s)
% Copia el campo PI a PID si solo existe el nombre antiguo
if isfield(s, 'PI') && ~isfield(s, 'PID'), s.PID = s.PI; end
if ~isfield(s, 'PID'), s.PID = ''; end
end
