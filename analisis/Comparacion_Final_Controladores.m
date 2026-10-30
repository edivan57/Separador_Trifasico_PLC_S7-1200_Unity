%% ============================================================
%  COMPARACION_FINAL_CONTROLADORES.m
%
%  Compara PID, FUZZY y MPC en el separador trifasico (TPSEP) usando las
%  corridas de Simulink y de PLC + Unity (HIL).
%
%  TABLAS (consola y Excel):
%    T1  Indicadores globales: IAE, ISE y variacion total (TV)
%    T2  Seguimiento de setpoint: tiempo de establecimiento y sobrepaso
%    T3  Rechazo de perturbaciones: desviacion maxima
%    T4  Acople entre lazos: desviacion ante cambios de OTRO lazo
%    T5  Concordancia PLC + Unity frente a Simulink
%    T6  Clasificacion por criterio (PLC + Unity)
%
%  FIGURAS (PNG 300 dpi y .fig):
%    A   Cada controlador: Simulink frente a PLC + Unity (PV y CV)
%    B   Cada lazo y plataforma: los 3 controladores, con su valvula
%    C   Resumen por plataforma: los 3 lazos en una figura
%
%  Requiere MATLAB R2020a o posterior (tiledlayout, exportgraphics).
%% ============================================================

clc
clearvars
close all

%% 0) CONFIGURACION
% archivos.PID   = struct('plc', 'Datos_PID_9.txt',    'sim', 'pid_run22_flat.mat');
% archivos.FUZZY = struct('plc', 'Datos_FUZZY_14.txt', 'sim', 'fuzzy_run23_flat.mat');
% archivos.MPC   = struct('plc', 'Datos_MPC_23.txt',   'sim', 'mpc_run30_flat.mat');  
archivos.PID   = struct('plc', 'Datos_PID_20261024_235306.txt',    'sim', 'pid_run22_flat.mat');
archivos.FUZZY = struct('plc', 'Datos_FUZZY_20261025_001037.txt', 'sim', 'fuzzy_run23_flat.mat');
archivos.MPC   = struct('plc', 'Datos_MPC_20261025_103346.txt',   'sim', 'mpc_run30_flat.mat');  
ctrl = {'PID', 'FUZZY', 'MPC'};

% Limite de velocidad por ejecucion de cada controlador [vpw vpc vpg]
% (se usa para verificar cuantas veces ejecuta el controlador por muestra)
limVel.PID   = [0.030 0.030 0.030];
limVel.FUZZY = [0.100 0.100 0.030];
limVel.MPC   = [0.035 0.015 0.030];

dt   = 0.1;          % [s] periodo de muestreo comun
tFin = 999.9;        % [s] ultimo instante comun a todas las corridas
tIni = 50;           % [s] se excluye el arranque de los indicadores

carpeta        = 'Resultados_Comparacion';
guardarFiguras = true;
exportarExcel  = true;

% Ventanas de zoom para las figuras B (una fila por ventana, en segundos).
% Vacio = sin zoom. Ejemplo: [390 520; 790 920]
ventanasZoom = [];

% Colores
col.PID   = [0.000 0.447 0.741];
col.FUZZY = [0.850 0.325 0.098];
col.MPC   = [0.466 0.674 0.188];
col.sim   = [0.000 0.447 0.741];
col.plc   = [0.850 0.325 0.098];
col.sp    = [0 0 0];

% Nombres de variables
V       = {'hw', 'hb', 'pg'};
SP      = {'hws', 'hbs', 'pgs'};
MV      = {'vpw', 'vpc', 'vpg'};
etiq.V  = {'h_w [m]', 'h_b [m]', 'p_g [psi]'};
etiq.MV = {'v_{pw} [-]', 'v_{pc} [-]', 'v_{pg} [-]'};
etiq.lazo = {'Agua', 'Crudo', 'Gas'};

%% 1) CARGA Y REMUESTREO A UNA MALLA COMUN
tc = (0:round(tFin/dt))' * dt;
N  = numel(tc);
mG = tc >= tIni - 1e-9;

S = struct();
fprintf('===== DATOS =====\n');
for c = 1:numel(ctrl)
    k = ctrl{c};
    S.(k).plc = leerUnity(archivos.(k).plc, tc);
    S.(k).sim = leerSimulink(archivos.(k).sim, tc);
    fprintf('  %-6s PLC: %-20s t = %.1f..%.1f s | Sim: %-22s t = %.1f..%.1f s\n', k, ...
            archivos.(k).plc, S.(k).plc.t0, S.(k).plc.tf, ...
            archivos.(k).sim, S.(k).sim.t0, S.(k).sim.tf);
    if S.(k).sim.t0 > dt/2
        fprintf('         AVISO: la corrida de Simulink empieza en %.1f s (Start time distinto de 0).\n', S.(k).sim.t0);
    end
end

if ~isfolder(carpeta)
    mkdir(carpeta);
end

%% 2) TABLA 1: INDICADORES GLOBALES
G = struct();
filas = {}; M1 = [];
for c = 1:numel(ctrl)
    k = ctrl{c};
    for plat = {'plc', 'sim'}
        g = globales(S.(k).(plat{1}), tc, mG, V, SP, MV);
        G.(k).(plat{1}) = g;
        filas{end+1, 1} = sprintf('%s - %s', k, nombrePlat(plat{1})); %#ok<SAGROW>
        M1(end+1, :) = [g.IAE, g.ISE, g.TV, sum(g.TV)]; %#ok<SAGROW>
    end
end
T1 = array2table(M1, 'RowNames', filas, 'VariableNames', ...
     {'IAE_hw', 'IAE_hb', 'IAE_pg', 'ISE_hw', 'ISE_hb', 'ISE_pg', ...
      'TV_vpw', 'TV_vpc', 'TV_vpg', 'TV_total'});

%% 3) TABLA 2: SEGUIMIENTO DE SETPOINT
%            variable  t0    inicial  final
escalones = {'hw',     400,  0.85,    0.80
             'hw',     600,  0.80,    0.78
             'hb',     500,  0.72,    0.75
             'hb',     900,  0.75,    0.70
             'pg',     400,  35,      40
             'pg',     600,  40,      45
             'pg',     800,  45,      35};
banda   = 0.02;          % banda de establecimiento: 2 % del escalon
ventSeg = 100;           % [s] ventana de analisis

nE = size(escalones, 1);
filasE = cell(nE, 1);
for e = 1:nE
    filasE{e} = sprintf('%s %.4g -> %.4g (%d s)', escalones{e,1}, escalones{e,3}, ...
                        escalones{e,4}, escalones{e,2});
end
TS = struct(); OS = struct();
for plat = {'plc', 'sim'}
    p = plat{1};
    TS.(p) = zeros(nE, numel(ctrl));
    OS.(p) = zeros(nE, numel(ctrl));
    for c = 1:numel(ctrl)
        k = ctrl{c};
        for e = 1:nE
            kw = ventana(escalones{e,2}, ventSeg, dt, N);
            y  = S.(k).(p).(escalones{e,1})(kw);
            tt = tc(kw) - escalones{e,2};
            [TS.(p)(e,c), OS.(p)(e,c)] = establecimiento(y, tt, escalones{e,3}, escalones{e,4}, banda, dt);
        end
    end
end
vn2 = {};
for c = 1:numel(ctrl)
    vn2 = [vn2, {[ctrl{c} '_ts_s'], [ctrl{c} '_sobrepaso_pct']}]; %#ok<AGROW>
end
T2 = struct();
for plat = {'plc', 'sim'}
    p = plat{1};
    M2 = zeros(nE, 2*numel(ctrl));
    M2(:, 1:2:end) = TS.(p);
    M2(:, 2:2:end) = OS.(p);
    T2.(p) = array2table(M2, 'RowNames', filasE, 'VariableNames', vn2);
end

%% 4) TABLA 3: RECHAZO DE PERTURBACIONES
perturb = {200, 'qci 0.0711 -> 0.0725 (200 s)'
           300, 'qgi 0.4906 -> 0.4606 (300 s)'
           700, 'qwi 0.1874 -> 0.1074 (700 s)'};
ventPert = 100;          % [s]
nP = size(perturb, 1);
vn3 = {};
for c = 1:numel(ctrl)
    vn3 = [vn3, {[ctrl{c} '_hw_mm'], [ctrl{c} '_hb_mm'], [ctrl{c} '_pg_psi']}]; %#ok<AGROW>
end
T3 = struct(); DP = struct();
for plat = {'plc', 'sim'}
    p = plat{1};
    M3 = zeros(nP, 3*numel(ctrl));
    for c = 1:numel(ctrl)
        k = ctrl{c};
        for e = 1:nP
            kw = ventana(perturb{e,1}, ventPert, dt, N);
            D  = S.(k).(p);
            M3(e, 3*(c-1) + 1) = 1000*max(abs(D.hws(kw) - D.hw(kw)));
            M3(e, 3*(c-1) + 2) = 1000*max(abs(D.hbs(kw) - D.hb(kw)));
            M3(e, 3*(c-1) + 3) = max(abs(D.pgs(kw) - D.pg(kw)));
        end
    end
    DP.(p) = M3;
    T3.(p) = array2table(M3, 'RowNames', perturb(:,2), 'VariableNames', vn3);
end

%% 5) TABLA 4: ACOPLE ENTRE LAZOS
%          lazo afectado  t0   evento
acople = {'hw', 500, 'hw ante escalon de hbs (500 s)'
          'hw', 800, 'hw ante escalon de pgs (800 s)'
          'hw', 900, 'hw ante escalon de hbs (900 s)'
          'hb', 400, 'hb ante escalones de hws y pgs (400 s)'
          'hb', 600, 'hb ante escalones de hws y pgs (600 s)'
          'hb', 800, 'hb ante escalon de pgs (800 s)'};
ventAc = 60;             % [s]
nA = size(acople, 1);
T4 = struct(); AC = struct();
for plat = {'plc', 'sim'}
    p = plat{1};
    M4 = zeros(nA, numel(ctrl));
    for c = 1:numel(ctrl)
        k = ctrl{c};
        for e = 1:nA
            kw = ventana(acople{e,2}, ventAc, dt, N);
            v  = acople{e,1};
            M4(e, c) = 1000*max(abs(S.(k).(p).([v 's'])(kw) - S.(k).(p).(v)(kw)));
        end
    end
    AC.(p) = M4;
    T4.(p) = array2table(M4, 'RowNames', acople(:,3), ...
             'VariableNames', strcat(ctrl, '_mm'));
end

%% 6) TABLA 5: CONCORDANCIA PLC + UNITY FRENTE A SIMULINK
eventosReac = {400, 'vpw'; 400, 'vpg'; 500, 'vpc'; 600, 'vpw'; 600, 'vpg'; 800, 'vpg'; 900, 'vpc'};
umbralReac  = 0.004;     % cambio de apertura que cuenta como reaccion
nMaxReac    = 40;        % muestras maximas de busqueda

M5 = zeros(numel(ctrl), 17);
FIT = struct();
for c = 1:numel(ctrl)
    k  = ctrl{c};
    Ds = S.(k).sim;
    Dp = S.(k).plc;
    fit = zeros(1,3); rmse = zeros(1,3); tvr = zeros(1,3); dIAE = zeros(1,3);
    for i = 1:3
        y  = Ds.(V{i})(mG);
        yh = Dp.(V{i})(mG);
        fit(i)  = 100*(1 - norm(y - yh)/norm(y - mean(y)));
        rmse(i) = sqrt(mean((y - yh).^2));
        tvr(i)  = G.(k).plc.TV(i)/G.(k).sim.TV(i);
        dIAE(i) = 100*(G.(k).plc.IAE(i) - G.(k).sim.IAE(i))/G.(k).sim.IAE(i);
    end
    FIT.(k) = fit;
    dTV = 100*(sum(G.(k).plc.TV) - sum(G.(k).sim.TV))/sum(G.(k).sim.TV);

    ret = nan(1, size(eventosReac, 1));
    for e = 1:size(eventosReac, 1)
        rp = reaccion(Dp.(eventosReac{e,2}), tc, eventosReac{e,1}, umbralReac, nMaxReac);
        rs = reaccion(Ds.(eventosReac{e,2}), tc, eventosReac{e,1}, umbralReac, nMaxReac);
        ret(e) = rp - rs;
    end

    % Cronometro: ejecuciones por muestra a partir del limitador de velocidad
    cv = [Dp.vpw, Dp.vpc, Dp.vpg];
    cv = cv(all(~isnan(cv), 2), :);
    r  = max(abs(diff(cv))./limVel.(k), [], 2);

    M5(c, :) = [fit, 1000*rmse(1:2), rmse(3), tvr, dIAE, dTV, ...
                mean(ret, 'omitnan'), max(ret), max(r), sum(r > 1.05)];
end
T5 = array2table(M5, 'RowNames', ctrl, 'VariableNames', ...
     {'FIT_hw_pct', 'FIT_hb_pct', 'FIT_pg_pct', 'RMSE_hw_mm', 'RMSE_hb_mm', 'RMSE_pg_psi', ...
      'TVratio_vpw', 'TVratio_vpc', 'TVratio_vpg', 'dIAE_hw_pct', 'dIAE_hb_pct', 'dIAE_pg_pct', ...
      'dTV_pct', 'Retardo_medio_s', 'Retardo_max_s', 'Ejec_por_muestra_max', 'Saltos_dobles'});

%% 7) TABLA 6: CLASIFICACION POR CRITERIO (PLC + UNITY)
iHb = find(strcmp(escalones(:,1), 'hb'));
iPg = find(strcmp(escalones(:,1), 'pg'));
iQw = 3;                                   % fila de qwi en la Tabla 3
valor = @(fun) cellfun(fun, ctrl);
crit = {
    'IAE hw',                         valor(@(k) G.(k).plc.IAE(1)),                    'min'
    'IAE hb',                         valor(@(k) G.(k).plc.IAE(2)),                    'min'
    'IAE pg',                         valor(@(k) G.(k).plc.IAE(3)),                    'min'
    'Esfuerzo de valvulas (TV)',      valor(@(k) sum(G.(k).plc.TV)),                   'min'
    'Acople total [mm]',              sum(AC.plc, 1),                                  'min'
    'Sobrepaso maximo en hb [%]',     max(OS.plc(iHb, :), [], 1),                      'min'
    'Establecimiento medio hb [s]',   mean(TS.plc(iHb, :), 1),                         'min'
    'Establecimiento medio pg [s]',   mean(TS.plc(iPg, :), 1),                         'min'
    'Desviacion de hw ante qwi [mm]', DP.plc(iQw, 1:3:end),                            'min'
    'FIT medio PLC/Simulink [%]',     valor(@(k) mean(FIT.(k))),                       'max'
};
nC = size(crit, 1);
pos = cell(nC, 3);
for i = 1:nC
    x = crit{i,2};
    if strcmp(crit{i,3}, 'min')
        [~, o] = sort(x, 'ascend');
    else
        [~, o] = sort(x, 'descend');
    end
    for j = 1:3
        pos{i,j} = sprintf('%s (%.4g)', ctrl{o(j)}, x(o(j)));
    end
end
T6 = cell2table(pos, 'RowNames', crit(:,1), 'VariableNames', {'Primero', 'Segundo', 'Tercero'});

%% 8) MOSTRAR TABLAS
titulos = {'TABLA 1. Indicadores globales (t >= 50 s)', T1
           'TABLA 2. Seguimiento de setpoint - PLC + Unity (banda 2 %)', T2.plc
           'TABLA 2b. Seguimiento de setpoint - Simulink', T2.sim
           'TABLA 3. Rechazo de perturbaciones - PLC + Unity (100 s)', T3.plc
           'TABLA 3b. Rechazo de perturbaciones - Simulink', T3.sim
           'TABLA 4. Acople entre lazos - PLC + Unity (60 s)', T4.plc
           'TABLA 4b. Acople entre lazos - Simulink', T4.sim
           'TABLA 5. Concordancia PLC + Unity frente a Simulink', T5
           'TABLA 6. Clasificacion por criterio - PLC + Unity', T6};
for i = 1:size(titulos, 1)
    fprintf('\n===== %s =====\n', titulos{i,1});
    disp(titulos{i,2});
end

%% 9) EXPORTAR A EXCEL
if exportarExcel
    xls = fullfile(carpeta, 'Tablas_Comparacion.xlsx');
    if isfile(xls)
        delete(xls);
    end
    hojas = {'T1_Global', 'T2_Seguimiento_PLC', 'T2_Seguimiento_Sim', 'T3_Perturb_PLC', ...
             'T3_Perturb_Sim', 'T4_Acople_PLC', 'T4_Acople_Sim', 'T5_Concordancia', 'T6_Clasificacion'};
    for i = 1:numel(hojas)
        writetable(titulos{i,2}, xls, 'Sheet', hojas{i}, 'WriteRowNames', true);
    end
    fprintf('\nTablas exportadas a %s\n', xls);
end

%% 10) FIGURAS A: CADA CONTROLADOR, SIMULINK FRENTE A PLC + UNITY
for c = 1:numel(ctrl)
    k   = ctrl{c};
    fig = figuraPlataformas(tc, S.(k), k, FIT.(k), [0 1000], V, SP, MV, etiq, col);
    guardar(fig, carpeta, sprintf('A_%s_Simulink_vs_PLC', k), guardarFiguras);
end

%% 11) FIGURAS B: CADA LAZO, LOS 3 CONTROLADORES CON SU VALVULA
% rangos = [0 1000; ventanasZoom];
% for plat = {'plc', 'sim'}
%     p = plat{1};
%     for i = 1:3
%         for r = 1:size(rangos, 1)
%             fig = figuraLazo(tc, S, ctrl, p, i, rangos(r,:), V, SP, MV, etiq, col);
%             nombre = sprintf('B_%s_Lazo_%s', etiquetaArchivo(p), etiq.lazo{i});
%             if r > 1
%                 nombre = sprintf('%s_%g-%gs', nombre, rangos(r,1), rangos(r,2));
%             end
%             guardar(fig, carpeta, nombre, guardarFiguras);
%         end
%     end
% end

%% 12) FIGURAS C: RESUMEN DE LOS 3 LAZOS POR PLATAFORMA
for plat = {'plc', 'sim'}
    p   = plat{1};
    fig = figuraResumen(tc, S, ctrl, p, [0 1000], V, SP, MV, etiq, col);
    guardar(fig, carpeta, sprintf('C_%s_Resumen', etiquetaArchivo(p)), guardarFiguras);
end

if guardarFiguras
    fprintf('Figuras guardadas en la carpeta %s\n', carpeta);
end

%% ============================================================
%  FUNCIONES LOCALES
%% ============================================================
function D = leerUnity(archivo, tc)
% Log de Unity: sp1 pv1 cv1 sp2 pv2 cv2 sp3 pv3 cv3 [t_sim t_real]
    if ~isfile(archivo)
        error('No se encontro %s.', archivo);
    end
    M = readmatrix(archivo, 'FileType', 'text', 'Delimiter', '\t', 'NumHeaderLines', 1);
    if size(M, 2) >= 10
        t = M(:, 10);
    else
        t = (0:size(M,1) - 1)' * 0.1;
    end
    [t, iu] = unique(t);
    nombres = {'hws', 'hw', 'vpw', 'hbs', 'hb', 'vpc', 'pgs', 'pg', 'vpg'};
    D = struct();
    for i = 1:numel(nombres)
        D.(nombres{i}) = interp1(t, M(iu, i), tc, 'linear');
    end
    D.t0 = t(1);
    D.tf = t(end);
end

function D = leerSimulink(archivo, tc)
% .mat plano generado por Exportar_Flat_Simulink
    if ~isfile(archivo)
        error('No se encontro %s.', archivo);
    end
    R = load(archivo);
    t = R.t(:);
    [t, iu] = unique(t);
    nombres = {'hws', 'hw', 'vpw', 'hbs', 'hb', 'vpc', 'pgs', 'pg', 'vpg'};
    D = struct();
    for i = 1:numel(nombres)
        x = R.(nombres{i})(:);
        D.(nombres{i}) = interp1(t, x(iu), tc, 'linear');
    end
    D.t0 = t(1);
    D.tf = t(end);
end

function g = globales(D, tc, m, V, SP, MV)
    g.IAE = zeros(1, 3); g.ISE = zeros(1, 3); g.TV = zeros(1, 3);
    for i = 1:3
        e = D.(SP{i})(m) - D.(V{i})(m);
        g.IAE(i) = trapz(tc(m), abs(e));
        g.ISE(i) = trapz(tc(m), e.^2);
        g.TV(i)  = sum(abs(diff(D.(MV{i})(m))));
    end
end

function kw = ventana(t0, duracion, dt, N)
% Indices de la ventana [t0, t0 + duracion) en la malla comun
    k0 = round(t0/dt) + 1;
    kw = (k0:min(N, k0 + round(duracion/dt) - 1))';
end

function [ts, ov] = establecimiento(y, tt, ini, fin, banda, dt)
% Tiempo hasta que el error queda dentro de la banda, y sobrepaso [%]
    paso  = fin - ini;
    fuera = find(abs(y - fin) > banda*abs(paso));
    if isempty(fuera)
        ts = 0;
    else
        ts = tt(fuera(end)) + dt;
    end
    ov = max(0, max(sign(paso)*(y - fin)))/abs(paso)*100;
end

function r = reaccion(cv, tc, t0, umbral, nMax)
% Tiempo desde t0 hasta que la valvula se aparta de su valor previo
    i0 = find(tc >= t0 - 1e-9, 1);
    r  = NaN;
    if isempty(i0) || i0 < 2
        return
    end
    base = cv(i0 - 1);
    for i = i0:min(numel(cv), i0 + nMax - 1)
        if abs(cv(i) - base) > umbral
            r = tc(i) - t0;
            return
        end
    end
end

function s = nombrePlat(p)
    if strcmp(p, 'plc')
        s = 'PLC + Unity';
    else
        s = 'Simulink';
    end
end

function s = etiquetaArchivo(p)
    if strcmp(p, 'plc')
        s = 'PLC';
    else
        s = 'Simulink';
    end
end

function fig = figuraPlataformas(tc, Sk, nombre, fit, rango, V, SP, MV, etiq, col)
% Un controlador: PV (izquierda) y CV (derecha), Simulink frente a PLC + Unity
    m   = tc >= rango(1) & tc <= rango(2);
    fig = figure('Name', sprintf('%s: Simulink frente a PLC + Unity', nombre), ...
                 'Color', 'w', 'Position', [60 60 1400 850]);
    tl  = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:3
        ax = nexttile(tl, 2*i - 1);
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        plot(ax, tc(m), Sk.plc.(SP{i})(m), '--', 'Color', col.sp, 'LineWidth', 1.0);
        plot(ax, tc(m), Sk.sim.(V{i})(m), '-', 'Color', col.sim, 'LineWidth', 1.3);
        plot(ax, tc(m), Sk.plc.(V{i})(m), '--', 'Color', col.plc, 'LineWidth', 1.3);
        ylabel(ax, etiq.V{i});
        title(ax, sprintf('%s   (FIT = %.2f %%)', etiq.lazo{i}, fit(i)));
        xlim(ax, rango);
        if i == 1
            legend(ax, {'Setpoint', 'Simulink', 'PLC + Unity'}, 'Location', 'best');
        end
        if i == 3
            xlabel(ax, 'Tiempo [s]');
        end

        ax = nexttile(tl, 2*i);
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        plot(ax, tc(m), Sk.sim.(MV{i})(m), '-', 'Color', col.sim, 'LineWidth', 1.1);
        plot(ax, tc(m), Sk.plc.(MV{i})(m), '--', 'Color', col.plc, 'LineWidth', 1.1);
        ylabel(ax, etiq.MV{i});
        title(ax, sprintf('Valvula de %s', lower(etiq.lazo{i})));
        xlim(ax, rango);
        ylim(ax, [0 1]);
        if i == 1
            legend(ax, {'Simulink', 'PLC + Unity'}, 'Location', 'best');
        end
        if i == 3
            xlabel(ax, 'Tiempo [s]');
        end
    end
    title(tl, sprintf('%s: Simulink frente a PLC + Unity', nombre), 'FontWeight', 'bold');
end

function fig = figuraLazo(tc, S, ctrl, p, i, rango, V, SP, MV, etiq, col)
% Un lazo en una plataforma: PV de los 3 controladores (arriba) y su valvula (abajo)
    m   = tc >= rango(1) & tc <= rango(2);
    fig = figure('Name', sprintf('Lazo de %s - %s', lower(etiq.lazo{i}), nombrePlatLocal(p)), ...
                 'Color', 'w', 'Position', [80 80 1200 750]);
    tl  = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile(tl);
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');
    plot(ax1, tc(m), S.(ctrl{1}).plc.(SP{i})(m), '--', 'Color', col.sp, 'LineWidth', 1.0);
    for c = 1:numel(ctrl)
        plot(ax1, tc(m), S.(ctrl{c}).(p).(V{i})(m), '-', 'Color', col.(ctrl{c}), 'LineWidth', 1.3);
    end
    ylabel(ax1, etiq.V{i});
    legend(ax1, [{'Setpoint'}, ctrl], 'Location', 'best');
    xlim(ax1, rango);

    ax2 = nexttile(tl);
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');
    for c = 1:numel(ctrl)
        plot(ax2, tc(m), S.(ctrl{c}).(p).(MV{i})(m), '-', 'Color', col.(ctrl{c}), 'LineWidth', 1.1);
    end
    ylabel(ax2, etiq.MV{i});
    xlabel(ax2, 'Tiempo [s]');
    legend(ax2, ctrl, 'Location', 'best');
    xlim(ax2, rango);
    ylim(ax2, [0 1]);
    linkaxes([ax1 ax2], 'x');

    title(tl, sprintf('Lazo de %s (%s): PID, FUZZY y MPC', lower(etiq.lazo{i}), nombrePlatLocal(p)), ...
          'FontWeight', 'bold');
end

function fig = figuraResumen(tc, S, ctrl, p, rango, V, SP, MV, etiq, col)
% Los 3 lazos en una figura: PV arriba, valvulas abajo
    m   = tc >= rango(1) & tc <= rango(2);
    fig = figure('Name', sprintf('Resumen - %s', nombrePlatLocal(p)), ...
                 'Color', 'w', 'Position', [40 40 1600 800]);
    tl  = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:3
        ax = nexttile(tl, i);
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        plot(ax, tc(m), S.(ctrl{1}).plc.(SP{i})(m), '--', 'Color', col.sp, 'LineWidth', 1.0);
        for c = 1:numel(ctrl)
            plot(ax, tc(m), S.(ctrl{c}).(p).(V{i})(m), '-', 'Color', col.(ctrl{c}), 'LineWidth', 1.2);
        end
        ylabel(ax, etiq.V{i});
        title(ax, etiq.lazo{i});
        xlim(ax, rango);
        if i == 1
            legend(ax, [{'Setpoint'}, ctrl], 'Location', 'best');
        end

        ax = nexttile(tl, i + 3);
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        for c = 1:numel(ctrl)
            plot(ax, tc(m), S.(ctrl{c}).(p).(MV{i})(m), '-', 'Color', col.(ctrl{c}), 'LineWidth', 1.0);
        end
        ylabel(ax, etiq.MV{i});
        xlabel(ax, 'Tiempo [s]');
        xlim(ax, rango);
        ylim(ax, [0 1]);
    end
    title(tl, sprintf('PID, FUZZY y MPC - %s', nombrePlatLocal(p)), 'FontWeight', 'bold');
end

function s = nombrePlatLocal(p)
    if strcmp(p, 'plc')
        s = 'PLC + Unity';
    else
        s = 'Simulink';
    end
end

function guardar(fig, carpeta, nombre, activo)
    if ~activo
        return
    end
    exportgraphics(fig, fullfile(carpeta, [nombre '.png']), 'Resolution', 300);
    savefig(fig, fullfile(carpeta, [nombre '.fig']));
end