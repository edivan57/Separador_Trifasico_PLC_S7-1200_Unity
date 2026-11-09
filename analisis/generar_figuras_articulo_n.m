
clear; close all; clc;

%% ======================= 1. CONFIGURACION ===============================
GENERAR = [1 2 3 4 5 6 7 8 9 10 11 21];      % figuras a generar (F12 se retiro del articulo)

raiz = fileparts(mfilename('fullpath'));
if isempty(raiz), raiz = pwd; end
if exist(fullfile(raiz, 'Datos'), 'dir'), base = raiz; else, base = fileparts(raiz); end   % raiz del repositorio
D.base          = base;                         % raiz del repositorio
D.carpeta_datos = fullfile(base, 'Datos');       % <- edite si sus datos estan en otro lugar
D.carpeta_fig   = fullfile(raiz, 'figuras');
if ~exist(D.carpeta_fig, 'dir'), mkdir(D.carpeta_fig); end

% Archivos de la configuracion final
D.CTRL     = {'PI', 'Fuzzy', 'MPC'};          % el PID incremental con Td = 0 opera como PI
% D.arch_HIL = {'Archivos Separador Trifasico\Datos\Nominal\PID\Datos_PID_rep02_*',...
%               'Archivos Separador Trifasico\Datos\Nominal\FUZZY\Datos_FUZZY_rep02_*1.txt',...
%               'Archivos Separador Trifasico\Datos\Nominal\PID\Datos_MPC_rep02_*.txt'};
D.arch_HIL = {'PID/Datos_PID_rep02_20261106_034525.txt',...
              'Fuzzy/Datos_FUZZY_rep02_20261106_020424.txt',...
              'MPC/Datos_MPC_rep02_20261106_001402.txt'};
D.arch_SIL = {'pid_run22_flat.mat', 'fuzzy_run23_flat.mat', 'mpc_run30_flat.mat'};
D.arch_FIS = fullfile('..', 'controladores', 'fuzzy', 'fis_tpsep_1block.fis');   % relativo a Datos/

% F11: cortes con retiro real del cable (un Datos y un Diag_Com por controlador, en el orden PID, Fuzzy, MPC)
D.arch_corte      = {'Corte real/Datos_PID_20261107_211405.txt', 'Corte real/Datos_FUZZY_20261107_203924.txt', ...
                     'Corte real/Datos_MPC_20261107_205647.txt'};
D.arch_corte_diag = {'Corte real/Diag_Com_CorteReal_20261107_211401.csv', 'Corte real/Diag_Com_CorteReal_20261107_203920.csv', ...
                     'Corte real/Diag_Com_CorteReal_20261107_205642.csv'};
D.F06_DERIVA = false;            % F06: true = histograma y deriva acumulada; false = solo el histograma
D.FUENTE_MF = 'Times New Roman';  % tipografia (serif) de F09 y F10, como en el escrito
D.FUENTE = '';                  % tipografia de las figuras; '' = la de MATLAB. Para igualar el texto del
                                % escrito use 'Palatino Linotype' (Windows) o 'Palatino' (macOS)
D.corte_antes   = 20;           % [s] mostrados antes del corte
D.corte_despues = 100;          % [s] mostrados despues del inicio del corte

% Constantes
D.Ts   = 0.1;
D.VARS = {'H_w', 'H_o', 'P_g'};                 % variables controladas
D.UNIT = {'ft', 'ft', 'psi'};
D.FT   = 1 / 0.3048;                          % factor m -> ft (1 ft = 0.3048 m)
D.MVS  = {'u_w', 'u_o', 'u_g'};                 % aperturas de valvula
D.COL  = [54/255 0/255 255/255;                    % PID   (#1f77b4)
          232/255 173/255 14/255;                    % Fuzzy (#d62728)
          23/255 110/255 26/255];                   % MPC   (#2ca02c)
% Colores por variable en F11 (H_w y u_w, H_o y u_o, P_g y u_g)
D.COLV = [0 0.4470 0.7410; 0.8500 0.3250 0.0980; 0.4660 0.6740 0.1880];

% Escenario de 1000 s
D.EVENT_T = [0 200 300 400 500 600 700 800 900 1000];
% Escalones de referencia: [t0, variable]  (1 = H_w, 2 = H_o, 3 = P_g)
D.STEPS = [0 1; 0 3; 400 1; 400 3; 500 2; 600 1; 600 3; 800 3; 900 2];
% Perturbaciones de caudal que se grafican en F04
D.DIST_T    = [200 300 700];
D.DIST_NAME = {'Q_{o,in}', 'Q_{g,in}', 'Q_{w,in}'};

% Costo computacional medido en la CPU 1212C con RUNTIME (bloque Diag_Hil) [ms]: Tabla del costo
% computacional del articulo, cinco repeticiones nominales. En el Fuzzy el maximo excluye la primera 
% ejecucion
D.t_medio_ms = [0.071 3.87 5.96];            % PID, Fuzzy, MPC (Diag_HIL, sesiones nominales del 5 y 6 de noviembre)
D.t_max_ms   = [0.108 5.0  34.0];
D.T_OB_ms    = 100;

% Estilo de las figuras
set(groot, 'defaultAxesFontSize', 8, 'defaultTextFontSize', 8, ...
    'defaultLineLineWidth', 0.9, 'defaultAxesXGrid', 'on', 'defaultAxesYGrid', 'on', ...
    'defaultAxesBox', 'on');
if ~isempty(D.FUENTE)
    set(groot, 'defaultAxesFontName', D.FUENTE, 'defaultTextFontName', D.FUENTE, 'defaultLegendFontName', D.FUENTE);
end

%% ======================= 2. CARGA DE DATOS ==============================
% Primera repeticion nominal de cada controlador (solo si se piden F01-F04, F06 o F08).
% HIL: sp1 pv1 cv1 sp2 pv2 cv2 sp3 pv3 cv3 t_sim t_real (1 fila de encabezado)
if any(ismember([1 2 3 4 5 6 8], GENERAR))
    for c = 1:3
        D.HIL{c} = leer_hil(ubicar(D, D.arch_HIL{c}), D);
    end
    D.N = numel(D.HIL{1}.t);
    D.t = D.HIL{1}.t;
    fprintf('Datos cargados: %d muestras por corrida (%.1f s).\n', D.N, D.t(end));
end

% Simulacion de diseno de Simulink (solo F05): t, hw, hws, hb, hbs, pg, pgs, vpw, vpc, vpg (se recortan a N)
if ismember(5, GENERAR)
    for c = 1:3
        S0 = load(ubicar(D, D.arch_SIL{c}));
        k  = 1:D.N;
        D.SIL{c} = struct('t', S0.t(k), 'sp', [S0.hws(k) S0.hbs(k) S0.pgs(k)], ...
                          'y',  [S0.hw(k) S0.hb(k) S0.pg(k)], 'u', [S0.vpw(k) S0.vpc(k) S0.vpg(k)]);
        D.SIL{c}.y(:, 1:2)  = D.SIL{c}.y(:, 1:2)  * D.FT;      % m -> ft
        D.SIL{c}.sp(:, 1:2) = D.SIL{c}.sp(:, 1:2) * D.FT;
        D.SIL{c}.u = D.SIL{c}.u * 100;                          % fraccion -> %
    end
end

% Muestras de la ventana [t0, siguiente evento)
ventana = @(t0) (round(t0 / D.Ts) + 1) : round(min(D.EVENT_T(D.EVENT_T > t0)) / D.Ts);

%% ======================= F01 - Variables controladas ====================
if ismember(1, GENERAR)
    fig = fig_nueva(7, 6.5);
    for i = 1:3
        ax = subplot(3, 1, i); hold(ax, 'on');
        plot(ax, D.t, D.HIL{1}.sp(:, i), 'k--', 'LineWidth', 0.8, 'DisplayName', 'Referencia');
        for c = 1:3
            plot(ax, D.t, D.HIL{c}.y(:, i), 'Color', D.COL(c, :), 'DisplayName', D.CTRL{c});
        end
        ylabel(ax, sprintf('%s [%s]', D.VARS{i}, D.UNIT{i}));
        xlim(ax, [D.t(1) D.t(end)]);
        if i == 1, leyenda(ax, 4, 'FontSize', 6, 'Location', 'northeast'); end
        if i == 3, xlabel(ax, 'Tiempo [s]'); else, set(ax, 'XTickLabel', []); end
    end
    guardar_fig(fig, D, 'F01_respuestas_HIL.pdf');
end

%% ======================= F02 - Aperturas de las valvulas ================
if ismember(2, GENERAR)
    fig = fig_nueva(7, 6.5);
    for j = 1:3
        ax = subplot(3, 1, j); hold(ax, 'on');
        for c = 1:3
            plot(ax, D.t, D.HIL{c}.u(:, j), 'Color', D.COL(c, :), 'DisplayName', D.CTRL{c});
        end
        ylabel(ax, sprintf('%s [%%]', D.MVS{j}));
        ylim(ax, [-2 102]); xlim(ax, [D.t(1) D.t(end)]);
        if j == 1, leyenda(ax, 3, 'FontSize', 6, 'Location', 'northeast'); end
        if j == 3, xlabel(ax, 'Tiempo [s]'); else, set(ax, 'XTickLabel', []); end
    end
    guardar_fig(fig, D, 'F02_senales_control_HIL.pdf');
end

%% ======================= F03 - Ventana de cada escalon ==================
if ismember(3, GENERAR)
    fig = fig_nueva(7.5, 6.5);
    for n = 1:size(D.STEPS, 1)
        t0 = D.STEPS(n, 1); i = D.STEPS(n, 2);
        k  = ventana(t0); tt = D.t(k) - t0;
        ax = subplot(3, 3, n); hold(ax, 'on');
        plot(ax, tt, D.HIL{1}.sp(k, i), 'k--', 'LineWidth', 0.8, 'HandleVisibility', 'off');
        for c = 1:3
            plot(ax, tt, D.HIL{c}.y(k, i), 'Color', D.COL(c, :), 'DisplayName', D.CTRL{c});
        end
        title(ax, sprintf('t = %d s, %s', t0, D.VARS{i}));
        xlabel(ax, sprintf('t - %d [s]', t0), 'FontSize', 7);
        ylabel(ax, sprintf('[%s]', D.UNIT{i}), 'FontSize', 7);
        xlim(ax, [0 tt(end)]);
        if n == 1, leyenda(ax, 1, 'FontSize', 6, 'Location', 'best'); end
    end
    guardar_fig(fig, D, 'F03_zoom_escalones.pdf');
end

%% ======================= F04 - Rechazo de perturbaciones ================
if ismember(4, GENERAR)
    fig = fig_nueva(7.5, 6.5);
    for r = 1:numel(D.DIST_T)
        t0 = D.DIST_T(r); k = ventana(t0); tt = D.t(k) - t0;
        for i = 1:3
            ax = subplot(3, 3, (r - 1) * 3 + i); hold(ax, 'on');
            for c = 1:3
                plot(ax, tt, D.HIL{c}.sp(k, i) - D.HIL{c}.y(k, i), ...
                     'Color', D.COL(c, :), 'DisplayName', D.CTRL{c});
            end
            title(ax, sprintf('%s en %d s: e_{%s}', D.DIST_NAME{r}, t0, D.VARS{i}));
            ylabel(ax, sprintf('[%s]', D.UNIT{i}), 'FontSize', 7);
            xlim(ax, [0 tt(end)]);
            if r == numel(D.DIST_T), xlabel(ax, 't - t_0 [s]', 'FontSize', 7); end
            if r == 1 && i == 1, leyenda(ax, 1, 'FontSize', 6, 'Location', 'best'); end
        end
    end
    guardar_fig(fig, D, 'F04_rechazo_perturbaciones.pdf');
end

%% ======================= F05 - Diferencia HIL - SIL =====================
% Diferencia entre la corrida nominal de la CPU (HIL) y la simulacion de diseno de Simulink (SIL).
% En el MPC, SIL es el MPC completo y HIL el de cotas, de modo que la diferencia incluye el cambio de problema.
if ismember(5, GENERAR)
    fig = fig_nueva(7.5, 6.5);
    fprintf('\n%-6s %-4s %10s %12s\n', 'Ctrl', 'Var', 'FIT [%]', 'Error max');
    for c = 1:3
        for i = 1:3
            ys = D.SIL{c}.y(:, i); yh = D.HIL{c}.y(:, i);
            ax = subplot(3, 3, (c - 1) * 3 + i);
            plot(ax, D.t, yh - ys, 'Color', D.COL(c, :), 'LineWidth', 0.7);
            title(ax, sprintf('%s: %s (HIL - SIL)', D.CTRL{c}, D.VARS{i}));
            ylabel(ax, sprintf('[%s]', D.UNIT{i}), 'FontSize', 7);
            xlim(ax, [D.t(1) D.t(end)]);
            if c == 3, xlabel(ax, 'Tiempo [s]', 'FontSize', 7); else, set(ax, 'XTickLabel', []); end
            fit = 100 * (1 - norm(yh - ys) / norm(ys - mean(ys)));
            fprintf('%-6s %-4s %10.2f %12.3e\n', D.CTRL{c}, D.VARS{i}, fit, max(abs(yh - ys)));
        end
    end
    guardar_fig(fig, D, 'F05_diferencia_SIL_HIL.pdf');
end

%% ======================= F06 - Tiempo real ==============================
if ismember(6, GENERAR)
    if D.F06_DERIVA                      % histograma + deriva acumulada (como en el escrito)
        fig = fig_nueva(7.5, 3);
        ax1 = subplot(1, 2, 1); hold(ax1, 'on');
        ax2 = subplot(1, 2, 2); hold(ax2, 'on');
    else                                 % solo el histograma
        fig = fig_nueva(4.2, 3);
        ax1 = axes(fig); hold(ax1, 'on');
        ax2 = [];
    end
    bordes = linspace(0, 0.45, 91);
    fprintf('\n');
    for c = 1:3
        dt  = diff(D.HIL{c}.treal);
        cnt = histc(dt, bordes); cnt = cnt(1:end-1);      %#ok<HISTC>
        cnt(cnt == 0) = NaN;                                % evita log(0)
        stairs(ax1, bordes, [cnt(:); cnt(end)], 'Color', D.COL(c, :), 'DisplayName', D.CTRL{c});
        if ~isempty(ax2), plot(ax2, D.t, D.HIL{c}.treal - D.t, 'Color', D.COL(c, :), 'DisplayName', D.CTRL{c}); end
        fprintf(['%-6s dt medio = %.4f s  jitter = %.4f s  p99 = %.3f s  ' ...
                 '>1.5Ts = %.1f %%  deriva = %.3f s\n'], D.CTRL{c}, mean(dt), std(dt, 1), ...
                 prctile_simple(dt, 99), 100 * mean(dt > 1.5 * D.Ts), D.HIL{c}.treal(end) - D.t(end));
    end
    yl = ylim(ax1);
    plot(ax1, [D.Ts D.Ts], [1 yl(2)], 'k--', 'LineWidth', 0.8, 'HandleVisibility', 'off');
    set(ax1, 'YScale', 'log'); xlim(ax1, [0 0.45]);
    xlabel(ax1, '\Deltat_{real} [s]'); ylabel(ax1, 'Ciclos');
    leyenda(ax1, 1, 'FontSize', 7);
    if ~isempty(ax2)
        xlabel(ax2, 'Tiempo simulado [s]'); ylabel(ax2, 't_{real} - t_{sim} [s]');
        xlim(ax2, [D.t(1) D.t(end)]);
    end
    guardar_fig(fig, D, 'F06_tiempo_real.pdf');
end

%% ======================= F07 - Costo computacional ======================
if ismember(7, GENERAR)
    fig = fig_nueva(5, 3);
    ax = axes(fig); hold(ax, 'on');
    x = 1:3; w = 0.36;
    bar(ax, x - w/2, D.t_medio_ms, w, 'FaceColor', [0.498 0.498 0.498], 'DisplayName', 'Medio');
    bar(ax, x + w/2, D.t_max_ms,   w, 'FaceColor', [0.251 0.251 0.251], 'DisplayName', 'Máximo observado');
    plot(ax, [0.4 3.6], [D.T_OB_ms D.T_OB_ms], 'r--', 'LineWidth', 0.9, ...
         'DisplayName', 'Periodo del OB (100 ms)');
    set(ax, 'YScale', 'log', 'XTick', x, 'XTickLabel', D.CTRL, 'XGrid', 'off');
    xlim(ax, [0.4 3.6]); ylim(ax, [1e-2 300]);
    ylabel(ax, 'Tiempo por ejecución [ms]');
    leyenda(ax, 1, 'FontSize', 7, 'Location', 'northwest');
    guardar_fig(fig, D, 'F07_costo_computacional.pdf');
end

%% ======================= F08 - IAE global normalizado ===================
if ismember(8, GENERAR)
    IAE = zeros(3, 3);                          % filas: controlador; columnas: variable
    for c = 1:3
        IAE(c, :) = sum(abs(D.HIL{c}.sp - D.HIL{c}.y), 1) * D.Ts;
    end
    IAEn = IAE ./ max(IAE, [], 1);
    fig = fig_nueva(6, 3);
    ax = axes(fig); hold(ax, 'on');
    w = 0.25;
    for c = 1:3
        bar(ax, (1:3) + (c - 2) * w, IAEn(c, :), w, 'FaceColor', D.COL(c, :), 'DisplayName', D.CTRL{c});
    end
    set(ax, 'XTick', 1:3, 'XTickLabel', D.VARS, 'XGrid', 'off');
    xlim(ax, [0.5 3.5]); ylim(ax, [0 1.1]);
    ylabel(ax, 'IAE / IAE máximo [-]');
    leyenda(ax, 1, 'FontSize', 7, 'Location', 'southeast');
    guardar_fig(fig, D, 'F08_IAE_global_normalizado.pdf');
    fprintf('\nIAE global HIL [unidad*s]\n%-6s %10s %10s %10s\n', '', D.VARS{:});
    for c = 1:3, fprintf('%-6s %10.3f %10.3f %10.3f\n', D.CTRL{c}, IAE(c, :)); end
end

%% ======================= F09 - Funciones de pertenencia =================
% Las seis entradas comparten las mismas 7 funciones y las tres salidas las mismas 9.\
if any(ismember([9 10], GENERAR))
    FIS = fis_leer(ubicar(D, D.arch_FIS));
end
if ismember(9, GENERAR)
    xx = linspace(-1, 1, 801);
    fuente = D.FUENTE_MF;
    MFS = {FIS.in(1).mf, FIS.out(1).mf};
    POS = {[0.082 0.637 0.893 0.314], [0.082 0.132 0.893 0.312]};
    TIT = {'(a) Entradas: error y variación del error escalados', '(b) Salida de cada lazo'};
    XLB = {'$x_e,\ x_{\Delta e}$', '$u_{fis}$'};
    xt  = -1:0.25:1;
    xtl = strrep(arrayfun(@(v) sprintf('%.2f', v), xt, 'UniformOutput', false), '-', char(8722));
    fig = fig_nueva(7.5, 4.1);
    for p = 1:2
        ax = axes('Parent', fig, 'Position', POS{p}); hold(ax, 'on');
        for m = 1:numel(MFS{p})
            plot(ax, xx, fis_mf(MFS{p}(m), xx), 'k-', 'LineWidth', 0.9);
            text(ax, centro_mf(MFS{p}(m)), 1.11, MFS{p}(m).name, 'HorizontalAlignment', 'center', ...
                 'VerticalAlignment', 'middle', 'FontName', fuente, 'FontSize', 9);
        end
        set(ax, 'XLim', [-1 1], 'YLim', [0 1.25], 'XTick', xt, 'XTickLabel', xtl, ...
            'YTick', [0 0.5 1], 'YTickLabel', {'0.0', '0.5', '1.0'}, 'FontName', fuente, 'FontSize', 9, ...
            'Box', 'on', 'XGrid', 'on', 'YGrid', 'on', 'GridColor', [0.8 0.8 0.8], 'GridAlpha', 1, ...
            'LineWidth', 0.6, 'Layer', 'bottom');
        text(ax, 0, 1.03, TIT{p}, 'Units', 'normalized', 'VerticalAlignment', 'bottom', ...
             'HorizontalAlignment', 'left', 'FontName', fuente, 'FontSize', 10);
        xlabel(ax, XLB{p}, 'Interpreter', 'latex', 'FontSize', 11);
        ylabel(ax, '$\mu$', 'Interpreter', 'latex', 'FontSize', 11);
    end
    guardar_fig(fig, D, 'F09_funciones_pertenencia.pdf');
end

%% ======================= F10 - Superficie de control del FIS ============
% Lazo 1 (H_w); los tres lazos comparten reglas y funciones.
if ismember(10, GENERAR)
    R1 = FIS.rules(FIS.rules(:, 1) > 0 & FIS.rules(:, 2) > 0 & FIS.rules(:, 7) > 0, [1 2 7]);
    yo = linspace(-1, 1, 101);
    outV = zeros(numel(FIS.out(1).mf), numel(yo));
    for m = 1:size(outV, 1), outV(m, :) = fis_mf(FIS.out(1).mf(m), yo); end
    g = linspace(-1, 1, 41);
    [XE, XD] = meshgrid(g, g);
    UF = zeros(size(XE));
    for n = 1:numel(XE)
        agg = zeros(1, numel(yo));
        for r = 1:size(R1, 1)
            w = min(fis_mf(FIS.in(1).mf(R1(r, 1)), XE(n)), fis_mf(FIS.in(2).mf(R1(r, 2)), XD(n)));
            if w > 0, agg = max(agg, min(w, outV(R1(r, 3), :))); end
        end
        if sum(agg) > 0, UF(n) = sum(agg .* yo) / sum(agg); end
    end
    fig = fig_nueva(4.5, 3.6);
    ax = axes(fig);
    surf(ax, XE, XD, UF, 'EdgeColor', 'k', 'LineWidth', 0.2);
    colormap(ax, parula);
    % xlabel(ax, 'e escalado [-]'); ylabel(ax, '\Deltae escalado [-]'); zlabel(ax, 'u_{fis} [-]');
    xlabel(ax, '$x_e$', 'Interpreter', 'latex', 'FontSize', 13);
    ylabel(ax, '$x_{\Delta e}$', 'Interpreter', 'latex', 'FontSize', 13);
    zlabel(ax, '$u_{fis}$', 'Interpreter', 'latex', 'FontSize', 13);
    view(ax, -45, 25);                   % equivale a view_init(25, -135) de matplotlib
    guardar_fig(fig, D, 'F10_superficie_difusa.pdf');
    fprintf('\nSuperficie: u_min = %.4f, u_max = %.4f, u(0,0) = %.4f\n', min(UF(:)), max(UF(:)), UF(21, 21));

    % Comparacion opcional con la Fuzzy Logic Toolbox (si esta instalada)
    if exist('readfis', 'file') == 2
        try
            fisTB = readfis(ubicar(D, D.arch_FIS));
            entrada = zeros(numel(XE), 6); entrada(:, 1) = XE(:); entrada(:, 2) = XD(:);
            out = evalfis(fisTB, entrada);
            fprintf('Diferencia maxima frente a evalfis (toolbox): %.2e\n', max(abs(out(:, 1) - UF(:))));
        catch err
            fprintf('No se pudo comparar con la toolbox: %s\n', err.message);
        end
    end
end


%% ======================= F21 - Esquema del separador (Figura 2 del texto) ===
% Separador horizontal con la nomenclatura del modelo
if ismember(21, GENERAR)
    R = 1.5;  xvert = 8.0;  xfin = 10.2;  yfondo = -R;      % radio, vertedero, fin del cilindro, fondo
    yhs = -0.3;  yhw = -0.7125;  yha = -0.2463;  yho = -0.7914;   % hs=4 ft, Hw=2.625 ft, Ha=4.179 ft, Ho=2.362 ft
    cGas = [0.97 0.97 0.97];  cAgua = [0.75 0.75 1];  cCrudo = [1 0.825 0.65];  gris = [0.5 0.5 0.5];
    fig = fig_nueva(7.4, 2.45);
    ax = axes('Parent', fig, 'Position', [0 0 1 1]); hold(ax, 'on');
    set(ax, 'XLim', [-5.3 13.9], 'YLim', [-3.55 2.75]); daspect(ax, [1 1 1]); axis(ax, 'off');

    % contorno del recipiente: cilindro de x = 0 a xfin y cabezas hemisfericas
    pr = linspace(pi/2, -pi/2, 80);  pl = linspace(3*pi/2, pi/2, 80);
    cx = [0, xfin + R*cos(pr), xfin, 0, R*cos(pl)];
    cy = [R, R*sin(pr), -R, -R, R*sin(pl)];
    fill(ax, cx, cy, cGas, 'EdgeColor', 'none');
    % agua (x < vertedero): bajo yhw
    fw = pi - asin(yhw/R);  arc = linspace(fw, 3*pi/2, 40);
    fill(ax, [R*cos(arc), xvert, xvert], [R*sin(arc), -R, yhw], cAgua, 'EdgeColor', 'none');
    % crudo (x < vertedero): entre yhw y yha
    fa = pi - asin(yha/R);  arc = linspace(fa, fw, 40);
    fill(ax, [R*cos(arc), xvert, xvert], [R*sin(arc), yhw, yha], cCrudo, 'EdgeColor', 'none');
    % crudo del colector (x > vertedero): bajo yho
    fo = asin(yho/R);  arc = linspace(-pi/2, fo, 40);
    fill(ax, [xvert, xfin + R*cos(arc), xvert], [-R, R*sin(arc), yho], cCrudo, 'EdgeColor', 'none');
    plot(ax, cx, cy, 'k-', 'LineWidth', 1.0);
    % vertedero y deflector
    plot(ax, [xvert xvert], [yfondo yhs], 'k-', 'LineWidth', 2.2);
    plot(ax, [-0.8 -0.8], [-0.05 0.75], 'k-', 'LineWidth', 1.8);
    text(ax, 0.55, 0.5, 'deflector', 'FontSize', 6.5, 'HorizontalAlignment', 'center');
    flecha_esq(ax, [0.05 0.5], [-0.72 0.5], gris, 0.5, false);
    text(ax, xvert, 0.55, 'vertedero', 'FontSize', 6.5, 'HorizontalAlignment', 'center');
    flecha_esq(ax, [xvert 0.42], [xvert yhs + 0.06], gris, 0.5, false);
    % entrada lateral izquierda
    plot(ax, [-1.489 -2.4], [0.18 0.18], 'k-', 'LineWidth', 1.0);
    plot(ax, [-1.440 -2.4], [0.42 0.42], 'k-', 'LineWidth', 1.0);
    flecha_esq(ax, [-3.1 0.3], [-1.35 0.3], 'k', 1.0, false);
    text(ax, -1.65, 0.50, '\itQ_{\itw,in}\rm, \itQ_{\ito,in}\rm, \itQ_{\itg,in}', ...
         'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'FontSize', 8);
    text(ax, -1.65, 0.90, 'Entrada:', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'FontSize', 8);
    % salida de gas
    plot(ax, [9.4 9.4 11.3], [1.5 2.1 2.1], 'k-', 'LineWidth', 1.0);
    valvula_esq(ax, 10.35, 2.1);   text(ax, 10.35, 2.3, '\itu_{\itg}', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
    flecha_esq(ax, [11.3 2.1], [11.7 2.1], 'k', 0.8, false);  text(ax, 11.8, 2.1, 'gas', 'VerticalAlignment', 'middle', 'FontSize', 8);
    % salida de agua
    plot(ax, [6.8 6.8 5.3], [-1.5 -2.1 -2.1], 'k-', 'LineWidth', 1.0);
    valvula_esq(ax, 6.0, -2.1);    text(ax, 6.0, -2.3, '\itu_{\itw}', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 8);
    flecha_esq(ax, [5.3 -2.1], [4.9 -2.1], 'k', 0.8, false);  text(ax, 4.8, -2.1, 'agua', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', 'FontSize', 8);
    % salida de crudo
    plot(ax, [9.6 9.6 11.3], [-1.5 -2.1 -2.1], 'k-', 'LineWidth', 1.0);
    valvula_esq(ax, 10.35, -2.1);  text(ax, 10.35, -2.3, '\itu_{\ito}', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 8);
    flecha_esq(ax, [11.3 -2.1], [11.7 -2.1], 'k', 0.8, false); text(ax, 11.8, -2.1, 'crudo', 'VerticalAlignment', 'middle', 'FontSize', 8);
    % rotulos de fases
    text(ax, 4.4, 0.7, 'Gas, \itP_{\itg}', 'HorizontalAlignment', 'center', 'FontSize', 8);
    text(ax, 4.4, (yhw + yha)/2, 'Crudo', 'HorizontalAlignment', 'center', 'FontSize', 8);
    text(ax, 4.4, (yfondo + yhw)/2, 'Agua', 'HorizontalAlignment', 'center', 'FontSize', 8);
    % cotas de niveles
    flecha_esq(ax, [2.1 yfondo], [2.1 yhw], 'k', 0.6, true);   text(ax, 2.0, (yfondo + yhw)/2, '\itH_{\itw}', 'HorizontalAlignment', 'right', 'FontSize', 8);
    flecha_esq(ax, [2.1 yhw],    [2.1 yha], 'k', 0.6, true);   text(ax, 2.0, (yhw + yha)/2,   '\itH_{\itc}', 'HorizontalAlignment', 'right', 'FontSize', 8);
    flecha_esq(ax, [2.9 yfondo], [2.9 yha], 'k', 0.6, true);   text(ax, 3.0, (yfondo + yha)/2, '\itH_{\ita}', 'HorizontalAlignment', 'left',  'FontSize', 8);
    flecha_esq(ax, [7.6 yfondo], [7.6 yhs], 'k', 0.6, true);   text(ax, 7.5, (yfondo + yhs)/2, '\ith_{\its}', 'HorizontalAlignment', 'right', 'FontSize', 8);
    flecha_esq(ax, [8.45 yfondo], [8.45 yho], 'k', 0.6, true); text(ax, 8.55, (yfondo + yho)/2, '\itH_{\ito}', 'HorizontalAlignment', 'left', 'FontSize', 8);
    % cotas de longitudes y del diametro
    plot(ax, [0 0], [-1.55 -3.05], '--', 'Color', gris, 'LineWidth', 0.5);
    plot(ax, [xvert xvert], [-2.6 -3.05], '--', 'Color', gris, 'LineWidth', 0.5);
    plot(ax, [xfin xfin], [-2.6 -3.05], '--', 'Color', gris, 'LineWidth', 0.5);
    flecha_esq(ax, [0 -2.9], [xvert -2.9], 'k', 0.6, true);
    text(ax, xvert/2, -3.05, '\itL_{\ita}\rm (cámara de separación)', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 8);
    flecha_esq(ax, [xvert -2.9], [xfin -2.9], 'k', 0.6, true);
    text(ax, (xvert + xfin)/2, -3.05, '\itL_{\itb}\rm (colector)', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 8);
    plot(ax, [xfin 13.0], [R R], '--', 'Color', gris, 'LineWidth', 0.5);
    plot(ax, [xfin 13.0], [-R -R], '--', 'Color', gris, 'LineWidth', 0.5);
    flecha_esq(ax, [12.9 -R], [12.9 R], 'k', 0.6, true);
    text(ax, 13.05, 0, '\itD_{\its}', 'HorizontalAlignment', 'left', 'FontSize', 8);
    guardar_fig(fig, D, 'F21_esquema_separador.pdf');
end

%% ======================= F11 - Cortes con retiro real del cable =========
% Material suplementario, Figura S2. Un corte por controlador, retirando a mano el cable Ethernet
% alrededor de los 450 s. La banda gris es el intervalo en que la planta no recibio acciones
% nuevas del PLC; se obtiene de las filas 'sintetico' del Diag_Com de cada corrida.
if ismember(11, GENERAR)
    fig = fig_nueva(7.4, 7.6);
    nom = {'PI', 'Fuzzy', 'MPC'};
    ancho = 0.2517; sep = 0.07; x0 = 0.09;           % rejilla de 4 filas x 3 columnas
    alto = 0.185; salto = 0.02; ytop = 0.90;
    for c = 1:3
        R = leer_hil(ubicar(D, D.arch_corte{c}), D);
        [t0, t1] = detectar_corte(ubicar(D, D.arch_corte_diag{c}), D.Ts);
        k = R.t >= t0 - D.corte_antes & R.t <= t0 + D.corte_despues;
        xl = [t0 - D.corte_antes, t0 + D.corte_despues];
        fprintf('  %-6s corte de %.1f s, de %.1f a %.1f s\n', nom{c}, t1 - t0, t0, t1);
        xp = x0 + (c - 1) * (ancho + sep);
        for i = 1:3
            ax = axes('Parent', fig, 'Position', [xp, ytop - i * alto - (i - 1) * salto, ancho, alto]); hold(ax, 'on');
            plot(ax, R.t(k), R.sp(k, i), 'k--', 'LineWidth', 0.7);
            plot(ax, R.t(k), R.y(k, i), 'Color', D.COLV(i, :), 'LineWidth', 1.1);
            xlim(ax, xl); set(ax, 'XTickLabel', []);
            ylabel(ax, sprintf('%s [%s]', D.VARS{i}, D.UNIT{i}));
            banda(ax, t0, t1);
            if i == 1
                title(ax, sprintf('%s\ncorte de %.1f s desde %.1f s', nom{c}, t1 - t0, t0), 'FontSize', 8);
            end
        end
        ax = axes('Parent', fig, 'Position', [xp, ytop - 4 * alto - 3 * salto, ancho, alto]); hold(ax, 'on');
        for j = 1:3
            plot(ax, R.t(k), R.u(k, j), 'Color', D.COLV(j, :), 'LineWidth', 1.1);
        end
        xlim(ax, xl); ylim(ax, [-3 103]);
        xlabel(ax, 't [s]'); ylabel(ax, 'Apertura [%]');
        banda(ax, t0, t1);
    end
    % Leyenda comun, debajo de las tres columnas
    axL = axes('Parent', fig, 'Position', [0 0 1 0.03], 'Visible', 'off'); hold(axL, 'on');
    h(1) = plot(axL, NaN, NaN, 'Color', D.COLV(1, :), 'LineWidth', 1.2);
    h(2) = plot(axL, NaN, NaN, 'Color', D.COLV(2, :), 'LineWidth', 1.2);
    h(3) = plot(axL, NaN, NaN, 'Color', D.COLV(3, :), 'LineWidth', 1.2);
    h(4) = plot(axL, NaN, NaN, 'k--', 'LineWidth', 0.8);
    h(5) = plot(axL, NaN, NaN, 's', 'MarkerFaceColor', [0.82 0.82 0.82], 'MarkerEdgeColor', 'none', 'MarkerSize', 8);
    lg = legend(axL, h, {'H_w y u_w', 'H_o y u_o', 'P_g y u_g', 'Referencia', 'Sin acción nueva en la planta'});
    set(lg, 'Orientation', 'horizontal', 'Box', 'off', 'FontSize', 7, 'Units', 'normalized', 'Position', [0.06 0.004 0.88 0.03]);
    guardar_fig(fig, D, 'F11_corte_real_cable.pdf');
end

fprintf('\nListo. Figuras en: %s\n', D.carpeta_fig);

%% ======================= FUNCIONES AUXILIARES ===========================
% (En MATLAB las funciones locales de un script van siempre al final del archivo.)

function fig = fig_nueva(ancho_in, alto_in)
% Figura con tamano fisico en pulgadas .
fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 ancho_in alto_in], ...
             'PaperUnits', 'inches', 'PaperSize', [ancho_in alto_in], ...
             'PaperPosition', [0 0 ancho_in alto_in]);
end

function guardar_fig(fig, D, nombre)
% Exporta la figura como PDF vectorial en D.carpeta_fig.
f = fullfile(D.carpeta_fig, nombre);
if exist('exportgraphics', 'file') == 2 || exist('exportgraphics', 'builtin') == 5
    exportgraphics(fig, f, 'ContentType', 'vector');      % R2020a o posterior
else
    print(fig, f, '-dpdf', '-painters');                   % R2018a - R2019b
end
fprintf('  guardada: %s\n', nombre);
end

function lg = leyenda(ax, ncol, varargin)
% Leyenda con numero de columnas y propiedades (FontSize, Location...).
lg = legend(ax, 'show');
set(lg, 'NumColumns', ncol, varargin{:});
end

function p = prctile_simple(x, q)
% Percentil con interpolacion lineal (igual que numpy.percentile), sin Statistics Toolbox.
x = sort(x(:)); n = numel(x);
pos = 1 + (n - 1) * q / 100; lo = floor(pos); hi = min(lo + 1, n);
p = x(lo) + (pos - lo) * (x(hi) - x(lo));
end

function F = fis_leer(archivo)
% Lee un archivo .fis sin Fuzzy Logic Toolbox.
%   F.in(k).mf / F.out(k).mf : name, type, params de cada funcion de pertenencia
%   F.rules : [NumInputs + NumOutputs] indices de cada regla (sin peso ni conector)
txt = strrep(fileread(archivo), sprintf('\r'), '');
F.in = struct('mf', {}); F.out = struct('mf', {}); F.rules = [];
secciones = regexp(txt, '\[(\w+)\]\n(.*?)(?=\n\[|\s*$)', 'tokens');
for s = 1:numel(secciones)
    nom = secciones{s}{1}; blk = secciones{s}{2};
    if strncmp(nom, 'Input', 5) || strncmp(nom, 'Output', 6)
        t = regexp(blk, 'MF\d+=''(\w+)'':''(\w+)'',\[([^\]]+)\]', 'tokens');
        mf = struct('name', {}, 'type', {}, 'params', {});
        for m = 1:numel(t)
            mf(m).name = t{m}{1}; mf(m).type = t{m}{2};
            mf(m).params = sscanf(t{m}{3}, '%f')';
        end
        if strncmp(nom, 'Input', 5)
            F.in(str2double(nom(6:end))).mf = mf;
        else
            F.out(str2double(nom(7:end))).mf = mf;
        end
    elseif strcmp(nom, 'Rules')
        lineas = strsplit(strtrim(blk), sprintf('\n'));
        nIO = numel(F.in) + numel(F.out);
        F.rules = zeros(numel(lineas), nIO);
        for r = 1:numel(lineas)
            v = sscanf(regexprep(lineas{r}, '[,():]', ' '), '%f')';
            F.rules(r, :) = v(1:nIO);
        end
    end
end
end

function y = fis_mf(mf, x)
% trimf / trapmf con el mismo criterio que la toolbox y el SCL generado
% (hombros con a == b o c == d valen 1 en el extremo).
p = mf.params;
switch mf.type
    case 'trimf',  a = p(1); b = p(2); c = p(2); d = p(3);
    case 'trapmf', a = p(1); b = p(2); c = p(3); d = p(4);
    otherwise, error('fis_mf: tipo %s no soportado', mf.type);
end
if b > a, izq = (x - a) / (b - a); else, izq = double(x >= a); end
if d > c, der = (d - x) / (d - c); else, der = double(x <= d); end
y = max(min(min(izq, 1), der), 0);
end


function flecha_esq(ax, p1, p2, col, lw, doble)
% Segmento con punta(s) de flecha rellena(s), en unidades de datos (los ejes deben ser iguales en X e Y).
d = p2 - p1;  L = norm(d);  u = d / L;  n = [-u(2) u(1)];
la = 0.18;  wa = 0.06;                                   % largo y semiancho de la punta
a = p1 + doble * la * u;  b = p2 - la * u;
plot(ax, [a(1) b(1)], [a(2) b(2)], '-', 'Color', col, 'LineWidth', lw);
T = [p2; b + wa * n; b - wa * n];
fill(ax, T(:, 1), T(:, 2), col, 'EdgeColor', col, 'LineWidth', 0.3);
if doble
    T = [p1; a + wa * n; a - wa * n];
    fill(ax, T(:, 1), T(:, 2), col, 'EdgeColor', col, 'LineWidth', 0.3);
end
end

function xc = centro_mf(mf)
% Posicion para rotular una funcion de pertenencia: la cima del triangulo o el centro de la meseta del
% trapecio, sin salirse del cuadro (los conjuntos de los extremos se rotulan en +-0.93).
p = mf.params;
if strcmp(mf.type, 'trimf'), xc = p(2); else, xc = (p(2) + p(3)) / 2; end
xc = min(max(xc, -0.93), 0.93);
end

function U = fis_superficie(FIS, R1, XE, XD, yo)
% Salida del lazo 1 del FIS en cada par (XE, XD): Mamdani min-max y centroide sobre los puntos yo.
outV = zeros(numel(FIS.out(1).mf), numel(yo));
for m = 1:size(outV, 1), outV(m, :) = fis_mf(FIS.out(1).mf(m), yo); end
U = zeros(size(XE));
for n = 1:numel(XE)
    agg = zeros(1, numel(yo));
    for r = 1:size(R1, 1)
        w = min(fis_mf(FIS.in(1).mf(R1(r, 1)), XE(n)), fis_mf(FIS.in(2).mf(R1(r, 2)), XD(n)));
        if w > 0, agg = max(agg, min(w, outV(R1(r, 3), :))); end
    end
    if sum(agg) > 0, U(n) = sum(agg .* yo) / sum(agg); end
end
end

function C = viridis_mapa(n)
% Mapa de colores viridis (MATLAB no lo trae): 32 puntos de matplotlib, interpolados a n colores.
T = [
    0.2670 0.0049 0.3294;
    0.2770 0.0503 0.3757;
    0.2823 0.0950 0.4173;
    0.2829 0.1359 0.4534;
    0.2780 0.1804 0.4867;
    0.2693 0.2188 0.5096;
    0.2573 0.2561 0.5266;
    0.2431 0.2921 0.5385;
    0.2259 0.3308 0.5473;
    0.2105 0.3637 0.5522;
    0.1959 0.3954 0.5553;
    0.1823 0.4262 0.5571;
    0.1681 0.4600 0.5581;
    0.1563 0.4896 0.5579;
    0.1448 0.5191 0.5566;
    0.1337 0.5485 0.5535;
    0.1235 0.5817 0.5474;
    0.1194 0.6111 0.5390;
    0.1248 0.6405 0.5271;
    0.1433 0.6695 0.5112;
    0.1807 0.7014 0.4882;
    0.2264 0.7289 0.4628;
    0.2815 0.7552 0.4326;
    0.3441 0.7800 0.3974;
    0.4219 0.8058 0.3519;
    0.4966 0.8264 0.3064;
    0.5756 0.8446 0.2564;
    0.6576 0.8602 0.2031;
    0.7519 0.8750 0.1432;
    0.8353 0.8860 0.1026;
    0.9162 0.8961 0.1007;
    0.9932 0.9062 0.1439
    ];
C = interp1(linspace(0, 1, size(T, 1)), T, linspace(0, 1, n));
end

function valvula_esq(ax, xc, yc)
% Simbolo de valvula (dos triangulos opuestos) centrado en (xc, yc), como en el esquema del escrito.
fill(ax, xc + [-0.15 0.15 0.15 -0.15], yc + [-0.13 0.13 -0.13 0.13], 'w', 'EdgeColor', 'k', 'LineWidth', 0.8);
end
function ruta = ubicar(D, rel)
%UBICAR  Ruta completa de un archivo de datos.
%   Lo busca primero donde dice la configuracion (carpeta Datos + ruta relativa, con comodines si los hay). Si no esta ahi,
%   lo busca por nombre en las subcarpetas de Datos y, si tampoco, en las de la raiz del repositorio. Si hay varios, usa el
%   mas reciente por nombre (las fechas van en el nombre) y avisa.
[~, nom, ext] = fileparts(rel);  nombre = [nom ext];
cand = dir(fullfile(D.carpeta_datos, rel));  cand = cand(~[cand.isdir]);
hallados = {};
for j = 1:numel(cand), hallados{end+1} = fullfile(cand(j).folder, cand(j).name); end %#ok<AGROW>
buscado = {D.carpeta_datos};
if isempty(hallados)
    for raiz_busqueda = {D.carpeta_datos, D.base}
        buscado{end+1} = raiz_busqueda{1}; %#ok<AGROW>
        carpetas = strsplit(genpath(raiz_busqueda{1}), pathsep);
        for i = 1:numel(carpetas)
            if isempty(carpetas{i}), continue; end
            f = dir(fullfile(carpetas{i}, nombre));  f = f(~[f.isdir]);
            for j = 1:numel(f), hallados{end+1} = fullfile(f(j).folder, f(j).name); end %#ok<AGROW>
        end
        if ~isempty(hallados), break; end
    end
end
if isempty(hallados)
    error('No se encontro %s. Se busco en %s y en sus subcarpetas, y en la raiz %s.', rel, D.carpeta_datos, D.base);
end
hallados = unique(hallados);                                  % ordenados por ruta; las fechas van en el nombre
if numel(hallados) > 1
    warning('ubicar:varios', 'Se encontraron %d archivos para %s; se usa el ultimo: %s', numel(hallados), rel, hallados{end});
end
ruta = hallados{end};
end

function R = leer_hil(archivo, D)
% Lee un registro HIL de Unity: sp1 pv1 cv1 sp2 pv2 cv2 sp3 pv3 cv3 t_sim t_real (1 fila de encabezado).
% Niveles de m a ft (Unity y el PLC trabajan en SI; las figuras se presentan en pies) y aperturas
% de fraccion (0-1) a porcentaje (0-100 %).
M = leer_numerico(archivo, sprintf('\t'), 1);
M = M(all(isfinite(M(:, 1:11)), 2), 1:11);
R = struct('t', M(:, 10), 'sp', M(:, [1 4 7]), 'y', M(:, [2 5 8]), 'u', M(:, [3 6 9]), 'treal', M(:, 11));
R.y(:, 1:2)  = R.y(:, 1:2)  * D.FT;
R.sp(:, 1:2) = R.sp(:, 1:2) * D.FT;
R.u = R.u * 100;
end

function M = leer_numerico(archivo, delim, nEncabezado)
% Matriz numerica de un archivo de texto con delimitador y lineas de encabezado.
if ~exist(archivo, 'file'), error('No se encontro el archivo: %s', archivo); end
try
    M = readmatrix(archivo, 'FileType', 'text', 'Delimiter', delim, 'NumHeaderLines', nEncabezado);
catch
    M = dlmread(archivo, delim, nEncabezado, 0);       %#ok<DLMRD> versiones antiguas
end
end

function [t0, t1] = detectar_corte(archivo, Ts)
M = leer_numerico(archivo, ';', 1);
ciclo = M(:, 1);  salt = M(:, 11);  idx = find(M(:, 12) == 1);
if isempty(idx), error('detectar_corte: %s no tiene filas sinteticas (no hubo corte)', archivo); end
lim = [0; find(diff(idx) > 1); numel(idx)];          % bloques contiguos de ciclos sinteticos
[~, b] = max(diff(lim));                              % el mas largo es el corte
a = idx(lim(b) + 1);  z = idx(lim(b + 1));
t0 = (ciclo(a) - 2 + sum(salt(1:a - 1))) * Ts;
t1 = (ciclo(z) - 2 + sum(salt(1:z)) + 1) * Ts;
end

function banda(ax, t0, t1)
yl = ylim(ax);
h = patch(ax, [t0 t1 t1 t0], [yl(1) yl(1) yl(2) yl(2)], [0.82 0.82 0.82], 'EdgeColor', 'none');
ylim(ax, yl);
ch = get(ax, 'Children');
set(ax, 'Children', [ch(ch ~= h); h]);               % la banda al fondo
end

function h = hist_densidad(ax, x, bordes, relleno, borde, nombre)
x = x(isfinite(x) & x >= bordes(1) & x < bordes(end));
n = histc(x(:), bordes);  n = n(1:end - 1);          %#ok<HISTC>
dens = n(:)' / (sum(n) * (bordes(2) - bordes(1)));
xs = reshape([bordes(1:end - 1); bordes(2:end)], 1, []);
ys = reshape([dens; dens], 1, []);
fill(ax, [xs(1) xs xs(end)], [0 ys 0], relleno, 'FaceAlpha', 0.7, 'EdgeColor', borde, 'LineWidth', 0.8, ...
     'HandleVisibility', 'off');
h = plot(ax, NaN, NaN, 'Color', borde, 'LineWidth', 1.5, 'DisplayName', nombre);
end
