function V = eventos_escenario2(raiz, carpeta_salida, modelo)


if nargin < 1 || isempty(raiz), raiz = '..'; end
if nargin < 3 || isempty(modelo), modelo = 'v11'; end
if nargin < 2 || isempty(carpeta_salida), carpeta_salida = 'resultados_escenario2'; end
E = cronograma_escenario2(raiz, carpeta_salida, modelo);
M2FT = 3.280839895; Ts = E.ts;
t_cambio = [E.t_ini' E.tend];                % 0:100:1000: la ventana de cada evento termina en el siguiente cambio de fase
nomv = {'H_w','H_o','P_g'}; unid = {'ft','ft','psi'}; esc_v = [M2FT M2FT 1];

% Corridas de Simulink del segundo escenario (mismas que calcular_resultados_articulo.m)
if strcmp(modelo, 'v12')   % escritas por correr_comparacion_v12 (planta v12, controladores sin resintonia)
corr = {'PID',                 'pid_esc2_v12A_flat.mat',         true;
        'Fuzzy',              'fuzzy_esc2_v12A_flat.mat',       true;
        'MPC completo',       'mpc_esc2_v12A_flat.mat',         true;    % P = 200
        'MPC completo P=100', 'mpc_esc2_v12A_P100_flat.mat',    false;
        'MPC completo P=50',  'mpc_esc2_v12A_P50_flat.mat',     false;
        'PID comun',           'pid_esc2_v12A_comun_flat.mat',   false;
        'Fuzzy comun',        'fuzzy_esc2_v12A_comun_flat.mat', false};
else
corr = {'PID',                 'pid_run25_flat.mat',   true;
        'Fuzzy',              'fuzzy_run25_flat.mat', true;
        'MPC completo',       'mpc_run15_flat.mat',   true;    % P = 200
        'MPC completo P=100', 'mpc_run18_flat.mat',   false;
        'MPC completo P=50',  'mpc_run14_flat.mat',   false;
        'PID comun',           'pid_run27_flat.mat',   false;
        'Fuzzy comun',        'fuzzy_run27_flat.mat', false};
end

%% 1) Eventos derivados del cronograma
ev = zeros(0, 2);                            % [t0 variable]
for v = 1:3
    r = E.esc(:, 3+v);
    if abs(r(1) - E.x0(v)) > 1e-3 * max(1, abs(r(1))), ev(end+1,:) = [0 v]; end %#ok<AGROW>
    for f = 2:E.nF
        if abs(r(f) - r(f-1)) > 1e-12, ev(end+1,:) = [E.t_ini(f) v]; end %#ok<AGROW>
    end
end
ev = sortrows(ev, [1 2]);
V.eventos = ev;
V.eventos_script_resultados = [0 1; 0 3; 200 3; 300 2; 400 1; 500 3; 600 1; 600 2; 700 3; 800 1; 900 1; 900 2; 900 3];
ne = size(ev, 1);

%% 2) Metricas por corrida y evento
nc = size(corr, 1);
TS = nan(nc, ne); TR = nan(nc, ne); MP = nan(nc, ne); AMP = nan(1, ne); ok = false(1, nc);
err_ref = nan(1, nc); err_x0 = nan(1, nc);
for i = 1:nc
    try
        f = ubicar(corr{i,2}, raiz);
    catch
        if corr{i,3}, error('eventos_escenario2:falta', 'Falta la corrida obligatoria %s', corr{i,2}); end
        continue
    end
    R = leer_flat(f, M2FT);
    ok(i) = true;
    % Comprobaciones: referencias = cronograma y condicion inicial = la declarada
    idx = min(floor(round(R.t / Ts) / round(E.Tfase / Ts)) + 1, E.nF);
    rr = E.esc(idx, 4:6) .* repmat(esc_v, numel(idx), 1);
    err_ref(i) = max(abs(R.r(:) - rr(:)));
    err_x0(i)  = max(abs(R.y(1,:) - E.x0 .* esc_v));
    for j = 1:ne
        m = m_escalon(R, ev(j,2), ev(j,1), t_cambio, Ts);
        TS(i,j) = m.ts; TR(i,j) = m.tr; MP(i,j) = m.Mp;
        if i == 1, AMP(j) = m.A; end
    end
end
V.corridas = corr(:,1)'; V.ok = ok; V.TS = TS; V.TR = TR; V.MP = MP; V.A = AMP;
V.err_ref = err_ref; V.err_x0 = err_x0; V.E = E;

% Controlador mas lento: un tiempo NaN (no se establece antes del siguiente cambio) cuenta como el mas lento
V.lento     = mas_lento(TS([1 2 3], :));     % PID, Fuzzy, MPC completo
V.lento_com = [];
if ok(6) && ok(7), V.lento_com = mas_lento(TS([6 7 3], :)); end

%% 3) Salidas
nom3 = {'PID','Fuzzy','MPC completo'};
fprintf('\n===== Eventos del segundo escenario (%d) =====\n', ne);
fprintf('%-3s %-6s %-5s %-24s %9s %9s %9s  %s\n', 'N', 't0 [s]', 'Var', 'Referencia', 'ts PID', 'ts Fuzzy', 'ts MPC', 'Mas lento');
for j = 1:ne
    v = ev(j,2);
    fprintf('%-3d %-6g %-5s %-24s %9s %9s %9s  %s\n', j, ev(j,1), nomv{v}, desc_ref(E, ev(j,:), v, esc_v, unid), ...
            fmt_ts(TS(1,j)), fmt_ts(TS(2,j)), fmt_ts(TS(3,j)), nom3{V.lento(j)});
end
fprintf('MPC completo: el mas lento en %d de %d eventos | PID en %d | Fuzzy en %d\n', ...
        sum(V.lento == 3), ne, sum(V.lento == 1), sum(V.lento == 2));
if ~isempty(V.lento_com)
    fprintf('Con condiciones comunes (PID comun, Fuzzy comun, MPC completo): MPC el mas lento en %d de %d, PID en %d, Fuzzy en %d\n', ...
            sum(V.lento_com == 3), ne, sum(V.lento_com == 1), sum(V.lento_com == 2));
end
fprintf('Referencias de las corridas frente al cronograma: error maximo %.2e | condicion inicial: error maximo %.2e\n', ...
        max(err_ref(ok)), max(err_x0(ok)));

escribir_csv(fullfile(carpeta_salida, 'eventos_escenario2.csv'), V, E, nomv, unid, esc_v);
escribir_tex_eventos(fullfile(carpeta_salida, 'tabla_S7_eventos.tex'), V, E, nomv, unid, esc_v);
escribir_seccion(fullfile(carpeta_salida, 'S7_segundo_escenario.tex'), V, E, carpeta_salida);
fprintf('Archivos escritos en %s\n', carpeta_salida);
end

%% ======================= funciones locales =======================
function R = leer_flat(f, M2FT)
% Igual que leer_flat de calcular_resultados_articulo.m: niveles en ft, presion en psi, t < 1000 s.
S = load(f); tt = S.t(:); k = find(tt < 1000 - 1e-6);
R.t = tt(k);
R.r = [S.hws(k)*M2FT, S.hbs(k)*M2FT, S.pgs(k)];
R.y = [S.hw(k)*M2FT,  S.hb(k)*M2FT,  S.pg(k)];
R.r = reshape(R.r, numel(k), 3); R.y = reshape(R.y, numel(k), 3);
end

function S = m_escalon(R, v, t0, t_cambio, Ts)
% Misma definicion que calcular_resultados_articulo.m
t1 = t_cambio(find(t_cambio > t0 + 1e-9, 1));
k = R.t >= t0 - 1e-6 & R.t < t1 - 1e-6; idx = find(k); i0 = idx(1);
yy = R.y(idx, v); tt = R.t(idx); rn = R.r(i0, v);
if t0 == 0, ro = R.y(1, v); else, ro = R.r(i0-1, v); end
A = rn - ro; s = sign(A);
S.A = A;
S.Mp = 100/abs(A)*max(0, max(s*(yy - rn))) + 0;
k10 = find(s*(yy - (ro + 0.1*A)) >= 0, 1); k90 = find(s*(yy - (ro + 0.9*A)) >= 0, 1);
S.tr = NaN; if ~isempty(k10) && ~isempty(k90), S.tr = tt(k90) - tt(k10); end
fuera = find(abs(yy - rn) > 0.02*abs(A));
if isempty(fuera), S.ts = 0; elseif fuera(end) < numel(tt), S.ts = tt(fuera(end)+1) - t0; else, S.ts = NaN; end
S.iae = Ts*sum(abs(rn - yy));
end

function im = mas_lento(T)
T(isnan(T)) = Inf;
[~, im] = max(T, [], 1);
end

function s = fmt_ts(x)
if isnan(x), s = 'no estab.'; else, s = sprintf('%.1f', x); end
end

function s = desc_ref(E, e, v, esc_v, unid)
f = find(abs(E.t_ini - e(1)) < 1e-9);
if e(1) == 0, a = E.x0(v); else, a = E.esc(f-1, 3+v); end
b = E.esc(f, 3+v);
s = sprintf('%.3f->%.3f %s', a*esc_v(v), b*esc_v(v), unid{v});
end

function f = ubicar(nombre, raiz)
if exist(fullfile(raiz, nombre), 'file') == 2, f = fullfile(raiz, nombre); return; end
p = strsplit(genpath(raiz), pathsep);
for i = 1:numel(p)
    if ~isempty(p{i}) && exist(fullfile(p{i}, nombre), 'file') == 2
        f = fullfile(p{i}, nombre); return;
    end
end
error('ubicar:no', 'No encuentro %s dentro de %s', nombre, raiz);
end

function escribir_csv(f, V, E, nomv, unid, esc_v)
fid = fopen(f, 'w');
fprintf(fid, 'evento,t0_s,variable,referencia,amplitud,unidad');
for i = find(V.ok), fprintf(fid, ',ts_%s_s,tr_%s_s,Mp_%s_pct', strrep(V.corridas{i},' ','_'), strrep(V.corridas{i},' ','_'), strrep(V.corridas{i},' ','_')); end
fprintf(fid, ',mas_lento\n');
nom3 = {'PID','Fuzzy','MPC completo'};
for j = 1:size(V.eventos, 1)
    v = V.eventos(j,2);
    fprintf(fid, '%d,%g,%s,"%s",%.4f,%s', j, V.eventos(j,1), nomv{v}, desc_ref(E, V.eventos(j,:), v, esc_v, unid), V.A(j), unid{v});
    for i = find(V.ok), fprintf(fid, ',%.1f,%.1f,%.2f', V.TS(i,j), V.TR(i,j), V.MP(i,j)); end
    fprintf(fid, ',%s\n', nom3{V.lento(j)});
end
fclose(fid);
end

function escribir_tex_eventos(f, V, E, nomv, unid, esc_v)
nom3 = {'PID','Fuzzy','MPC'}; ne = size(V.eventos, 1);
fid = fopen(f, 'w');
fprintf(fid, '\\begin{table}[H]\n');
fprintf(fid, ['\\caption{Eventos del segundo escenario y tiempo de establecimiento $t_s$ [s] de cada controlador, en simulaci\\''on. ' ...
              'Un evento es un cambio de referencia; los dos de 0~s son los escalones de arranque. ' ...
              '$t_s$ se mide desde el cambio hasta que la variable queda dentro de $\\pm2$~\\%% de la amplitud, sin salir hasta el fin de la fase. ' ...
              '«No estab.» indica que no se establece antes del siguiente cambio de fase y cuenta como el m\\''as lento. ' ...
              'MPC: MPC completo de dise\\~no ($P=200$), no el MPC de cotas de la CPU.}\n']);
fprintf(fid, '\\label{tab:esc2_eventos}\n\\centering\n\\footnotesize\n\\begin{tabular}{rrlccccl}\n\\toprule\n');
fprintf(fid, 'N.\\textordmasculine & $t$ [s] & Variable & Referencia & PID & Fuzzy & MPC & M\\''as lento \\\\\n\\midrule\n');
for j = 1:ne
    v = V.eventos(j,2);
    ref = strrep(desc_ref(E, V.eventos(j,:), v, esc_v, unid), '->', '$\to$');
    fprintf(fid, '%d & %g & $%s$ & %s & %s & %s & %s & %s \\\\\n', j, V.eventos(j,1), nomv{v}, ref, ...
            tex_ts(V.TS(1,j)), tex_ts(V.TS(2,j)), tex_ts(V.TS(3,j)), nom3{V.lento(j)});
end
fprintf(fid, '\\bottomrule\n\\end{tabular}\n\\end{table}\n');
fclose(fid);
end

function s = tex_ts(x)
if isnan(x), s = 'No estab.'; else, s = sprintf('%.1f', x); end
end

function escribir_seccion(f, V, E, carpeta)
ne = size(V.eventos, 1); n3 = sum(V.lento == 3); n1 = sum(V.lento == 1);
evPI = V.eventos(V.lento == 1, 2);
nomvar = {'$H_w$','$H_o$','$P_g$'};
if ~isempty(evPI) && all(evPI == evPI(1))
    txtPI = sprintf('el PID, en los %d de %s', n1, nomvar{evPI(1)});
else
    txtPI = sprintf('el PID, en %d', n1);
end
fid = fopen(f, 'w');
fprintf(fid, '\\section*{S7. Segundo escenario}\n\n');
fprintf(fid, ['El segundo escenario est\\''a definido en \\texttt{Escenario\\_Trifasico\\_2.m} (SHA-256 \\texttt{%s}, con finales de l\\''inea LF) y se evalu\\''o solo en simulaci\\''on, ' ...
              'en Simulink con ode3 y paso de 0.01~s. Los controladores usan las sintonías del escenario de ajuste, sin retocar. ' ...
              'Tiene %d fases de %g~s y los cambios ocurren al inicio de cada fase (Tabla~\\ref{tab:esc2_cronograma}). ' ...
              'La planta parte de $H_w=%.2f$~m, $H_o=%.2f$~m y $P_g=%g$~psi. Como las referencias de la fase 1 son %.2f~m y %g~psi, ' ...
              'el arranque incluye dos escalones de referencia.\n\n'], ...
        E.sha256(1:min(16, numel(E.sha256))), E.nF, E.Tfase, E.x0(1), E.x0(2), E.x0(3), E.esc(1,4), E.esc(1,6));
fprintf(fid, ['Un evento es un cambio de referencia de una variable controlada. Hay %d: %d al inicio de las fases y los %d escalones de arranque ' ...
              '(Tabla~\\ref{tab:esc2_eventos}). Los cambios de caudal no se cuentan como eventos; su efecto entra en el IAE. ' ...
              'En cada evento se mide el tiempo de establecimiento al 2~\\%% de la amplitud, dentro de la fase. ' ...
              'Los niveles se reportan en ft y la presi\\''on en psi, como en el art\\''iculo.\n\n'], ...
        ne, sum(V.eventos(:,1) > 0), sum(V.eventos(:,1) == 0));
fprintf(fid, ['El MPC de esta comparaci\\''on es el MPC completo de dise\\~no, en simulaci\\''on; no es el MPC de cotas que corre en la CPU 1212C. ' ...
              'El MPC completo fue el m\\''as lento en %d de los %d eventos, y %s.'], n3, ne, txtPI);
if ~isempty(V.lento_com)
    fprintf(fid, [' Con condiciones comunes en el PID y el Fuzzy, el MPC completo fue el m\\''as lento en %d de los %d eventos.'], sum(V.lento_com == 3), ne);
end
fprintf(fid, '\n\n%% --- Tablas generadas por cronograma_escenario2.m y eventos_escenario2.m ---\n');
fclose(fid);
% Anexar las dos tablas al final de la seccion
anexar(f, fullfile(carpeta, 'tabla_S7_cronograma.tex'));
anexar(f, fullfile(carpeta, 'tabla_S7_eventos.tex'));
end

function anexar(destino, origen)
fi = fopen(origen, 'r'); txt = fread(fi, Inf, '*char')'; fclose(fi);
fo = fopen(destino, 'a'); fprintf(fo, '\n%s', txt); fclose(fo);
end
