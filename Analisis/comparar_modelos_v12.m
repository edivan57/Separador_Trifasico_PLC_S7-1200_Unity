function R = comparar_modelos_v12(carpeta, escenario, carpeta_salida, referencias)


if nargin < 1 || isempty(carpeta), carpeta = fullfile('Datos', 'Modelo_v12'); end
if nargin < 2 || isempty(escenario), escenario = 1; end
if nargin < 3 || isempty(carpeta_salida), carpeta_salida = 'resultados_modelo_v12'; end
if nargin < 4, referencias = []; end
if ~exist(carpeta_salida, 'dir'), mkdir(carpeta_salida); end

M2FT = 3.280839895; Ts = 0.1;
if escenario == 1
    t_cambio = [0 200 300 400 500 600 700 800 900 1000];
    escalones = [0 1; 0 3; 400 1; 400 3; 500 2; 600 1; 600 3; 800 3; 900 2];
else
    t_cambio = 0:100:1000;
    escalones = [0 1; 0 3; 200 3; 300 2; 400 1; 500 3; 600 1; 600 2; 700 3; 800 1; 900 1; 900 2; 900 3];
end
ctrl  = {'PID', 'Fuzzy', 'MPC'};
pref  = {'pid', 'fuzzy', 'mpc'};
sat   = {[1 99], [1 99], [2 99]};
casos = {'v11', 'v12A', 'v12B'};
nomv  = {'H_w', 'H_o', 'P_g'};

R = struct('ctrl', {}, 'caso', {}, 'IAE', {}, 'Mp', {}, 'ts', {}, 'nts', {}, 'sat', {}, 'TV', {});
for i = 1:3
    for k = 1:3
        f = fullfile(carpeta, sprintf('%s_esc%d_%s_flat.mat', pref{i}, escenario, casos{k}));
        if ~exist(f, 'file'), continue; end
        D = leer(f, M2FT);
        m = metricas(D, escalones, t_cambio, Ts, sat{i});
        m.ctrl = ctrl{i}; m.caso = casos{k};
        R(end+1) = orderfields(m, R); %#ok<AGROW>
    end
end
if isempty(R), error('comparar_modelos_v12:vacio', 'No hay corridas en %s', carpeta); end

% --- Reproduccion de las corridas del articulo con el modelo actual
if ~isempty(referencias)
    fprintf('\n===== La corrida v11 frente a la del articulo =====\n');
    for i = 1:3
        if ~isfield(referencias, ctrl{i}), continue; end
        f = fullfile(carpeta, sprintf('%s_esc%d_v11_flat.mat', pref{i}, escenario));
        if ~exist(f, 'file') || ~exist(referencias.(ctrl{i}), 'file'), continue; end
        A = leer(f, M2FT); B = leer(referencias.(ctrl{i}), M2FT);
        n = min(size(A.y, 1), size(B.y, 1));
        fprintf('%-6s salidas: dif. max %.2e | aperturas: dif. max %.2e p.p.\n', ctrl{i}, ...
                max(max(abs(A.y(1:n,:) - B.y(1:n,:)))), max(max(abs(A.u(1:n,:) - B.u(1:n,:)))));
    end
end

% --- Tabla en consola
fprintf('\n===== Efecto del modelo corregido (escenario %d) =====\n', escenario);
fprintf('%-6s %-5s | %-26s | %-20s | %-20s | %-17s | %-17s\n', 'Ctrl', 'Caso', 'IAE Hw / Ho [ft s] / Pg [psi s]', ...
        'Mp max Hw/Ho/Pg [%]', 'ts medio Hw/Ho/Pg [s]', 'Saturacion [%]', 'TV uw/uo/ug [p.p.]');
for r = 1:numel(R)
    fprintf('%-6s %-5s | %6.3f %6.3f %10.1f | %5.1f %5.1f %5.1f | %5.1f %5.1f %5.1f | %4.1f %4.1f %4.1f | %5.0f %5.0f %5.0f\n', ...
            R(r).ctrl, R(r).caso, R(r).IAE, R(r).Mp, R(r).ts, R(r).sat, R(r).TV);
end
fprintf('\nCambio frente a v11 [%%]:\n');
for r = 1:numel(R)
    if strcmp(R(r).caso, 'v11'), continue; end
    b = R(strcmp({R.ctrl}, R(r).ctrl) & strcmp({R.caso}, 'v11'));
    if isempty(b), continue; end
    d = @(x, y) 100 * (x - y) ./ max(abs(y), eps);
    fprintf('%-6s %-5s | IAE %+6.1f %+6.1f %+6.1f | Mp max %+6.1f %+6.1f %+6.1f p.p. | TV %+6.1f %+6.1f %+6.1f\n', ...
            R(r).ctrl, R(r).caso, d(R(r).IAE, b.IAE), R(r).Mp - b.Mp, d(R(r).TV, b.TV));
end

% --- Conclusiones del articulo con cada modelo
fprintf('\n===== Conclusiones del articulo =====\n');
conj = {{'v11'}, {'v12A'}, {'v12A', 'v12B'}};
etq  = {'Modelo actual (v11)', 'Modelo corregido, sin resintonia (v12A)', 'Modelo corregido, MPC regenerado (v12B)'};
R_conc = cell(1, 3);
for q = 1:3
    fila = cell(1, 3); ok = true;
    for i = 1:3
        c = conj{q}; if i < 3, c = c(1); end
        x = [];
        for cc = numel(c):-1:1
            x = R(strcmp({R.ctrl}, ctrl{i}) & strcmp({R.caso}, c{cc}));
            if ~isempty(x), break; end
        end
        if isempty(x), ok = false; break; end
        fila{i} = x;
    end
    if ~ok, continue; end
    I = [fila{1}.IAE; fila{2}.IAE; fila{3}.IAE];
    [~, mejor] = min(I, [], 1);
    MpHo = [fila{1}.Mp(2) fila{2}.Mp(2) fila{3}.Mp(2)]; [~, mHo] = min(MpHo);
    TVt = [sum(fila{1}.TV) sum(fila{2}.TV) sum(fila{3}.TV)];
    c1 = all(mejor(1:2) == 2); c2 = mejor(3) == 1; c3 = mHo == 3;
    fprintf('%s:\n', etq{q});
    fprintf('   Menor IAE: H_w %s, H_o %s, P_g %s\n', ctrl{mejor(1)}, ctrl{mejor(2)}, ctrl{mejor(3)});
    fprintf('   [%s] Fuzzy con el menor IAE en los niveles\n', sino(c1));
    fprintf('   [%s] PID con el menor IAE en la presion\n', sino(c2));
    fprintf('   [%s] MPC con el menor sobreimpulso en H_o (%.1f / %.1f / %.1f %%)\n', sino(c3), MpHo);
    fprintf('   TV total PID / Fuzzy / MPC: %.0f / %.0f / %.0f p.p.\n', TVt);
    R_conc{q} = struct('mejor', mejor, 'MpHo', MpHo, 'c1', c1, 'c2', c2, 'c3', c3);
end

escribir_csv(fullfile(carpeta_salida, 'comparacion_modelo_v12.csv'), R, nomv);
escribir_tex(fullfile(carpeta_salida, 'tabla_modelo_v12.tex'), R, escenario);
fprintf('\nArchivos escritos en %s\n', carpeta_salida);
end

%% ======================= funciones locales =======================
function D = leer(f, M2FT)
S = load(f); t = S.t(:); k = find(t < 1000 - 1e-6);
D.t = t(k);
D.r = [S.hws(k)*M2FT, S.hbs(k)*M2FT, S.pgs(k)];
D.y = [S.hw(k)*M2FT,  S.hb(k)*M2FT,  S.pg(k)];
D.u = [S.vpw(k), S.vpc(k), S.vpg(k)] * 100;
D.r = reshape(D.r, numel(k), 3); D.y = reshape(D.y, numel(k), 3); D.u = reshape(D.u, numel(k), 3);
end

function m = metricas(D, escalones, t_cambio, Ts, lim)
e = D.r - D.y;
m.IAE = Ts * sum(abs(e), 1);
m.TV  = sum(abs(diff(D.u, 1, 1)), 1);
tol = 1e-3;
m.sat = 100 * mean(D.u <= lim(1) + tol | D.u >= lim(2) - tol, 1);
Mp = zeros(1, 3); tsum = zeros(1, 3); nts = zeros(1, 3); nn = zeros(1, 3);
for j = 1:size(escalones, 1)
    v = escalones(j, 2);
    s = escalon(D, v, escalones(j, 1), t_cambio);
    Mp(v) = max(Mp(v), s.Mp);
    if isnan(s.ts), nn(v) = nn(v) + 1; else, tsum(v) = tsum(v) + s.ts; nts(v) = nts(v) + 1; end
end
m.Mp = Mp; m.ts = tsum ./ max(nts, 1); m.nts = nn;
end

function S = escalon(D, v, t0, t_cambio)
% Misma definicion que m_escalon de calcular_resultados_articulo.m
t1 = t_cambio(find(t_cambio > t0 + 1e-9, 1));
k = D.t >= t0 - 1e-6 & D.t < t1 - 1e-6; idx = find(k); i0 = idx(1);
yy = D.y(idx, v); tt = D.t(idx); rn = D.r(i0, v);
if t0 == 0, ro = D.y(1, v); else, ro = D.r(i0-1, v); end
A = rn - ro; s = sign(A);
S.Mp = 100/abs(A)*max(0, max(s*(yy - rn))) + 0;
fuera = find(abs(yy - rn) > 0.02*abs(A));
if isempty(fuera), S.ts = 0; elseif fuera(end) < numel(tt), S.ts = tt(fuera(end)+1) - t0; else, S.ts = NaN; end
end

function s = sino(c)
if c, s = 'se mantiene'; else, s = 'CAMBIA'; end
end

function escribir_csv(f, R, nomv)
fid = fopen(f, 'w');
fprintf(fid, 'controlador,caso');
for j = 1:3, fprintf(fid, ',IAE_%s', nomv{j}); end
for j = 1:3, fprintf(fid, ',Mp_max_%s_pct', nomv{j}); end
for j = 1:3, fprintf(fid, ',ts_medio_%s_s', nomv{j}); end
fprintf(fid, ',sat_uw_pct,sat_uo_pct,sat_ug_pct,TV_uw_pp,TV_uo_pp,TV_ug_pp\n');
for r = 1:numel(R)
    fprintf(fid, '%s,%s,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n', R(r).ctrl, R(r).caso, ...
            R(r).IAE, R(r).Mp, R(r).ts, R(r).sat, R(r).TV);
end
fclose(fid);
end

function escribir_tex(f, R, escenario)
etq = struct('v11', 'Actual', 'v12A', 'Corregido, A', 'v12B', 'Corregido, B');
fid = fopen(f, 'w');
fprintf(fid, '\\begin{table}[H]\n');
fprintf(fid, ['\\caption{Efecto de la coherencia f\\''isica del modelo de la planta, en simulaci\\''on (Simulink), escenario %d. ' ...
              'A: sintonías actuales, sin resintonía. B: MPC con el modelo interno linealizado del modelo corregido y los mismos pesos. ' ...
              'IAE en ft$\\cdot$s y psi$\\cdot$s; $M_p$, m\\''aximo sobre los escalones de cada variable; TV en p.p.}\n'], escenario);
fprintf(fid, '\\label{tab:modelo_v12}\n\\centering\n\\footnotesize\n\\setlength{\\tabcolsep}{3pt}\n');
fprintf(fid, '\\begin{tabular}{llccccccc}\n\\toprule\n');
fprintf(fid, 'Controlador & Modelo & IAE $H_w$ & IAE $H_o$ & IAE $P_g$ & $M_p$ $H_o$ [\\%%] & $M_p$ $P_g$ [\\%%] & TV total & Saturaci\\''on m\\''ax. [\\%%] \\\\\n\\midrule\n');
for r = 1:numel(R)
    fprintf(fid, '%s & %s & %.3f & %.3f & %.1f & %.1f & %.1f & %.0f & %.1f \\\\\n', R(r).ctrl, etq.(R(r).caso), ...
            R(r).IAE, R(r).Mp(2), R(r).Mp(3), sum(R(r).TV), max(R(r).sat));
end
fprintf(fid, '\\bottomrule\n\\end{tabular}\n\\end{table}\n');
fclose(fid);
end
