function E = cronograma_escenario2(raiz, carpeta_salida, modelo)


if nargin < 1 || isempty(raiz), raiz = '..'; end
if nargin < 3 || isempty(modelo), modelo = 'v11'; end
if nargin < 2 || isempty(carpeta_salida), carpeta_salida = 'resultados_escenario2'; end
if ~exist(carpeta_salida, 'dir'), mkdir(carpeta_salida); end
M2FT  = 3.280839895;          % m -> ft
PSI2PA = 6894.757;            % psi -> Pa
HS    = 1.2192;               % altura del vertedero [m] (tpsep_v11)

raiz = absoluta(raiz);         % todas las rutas quedan absolutas desde aqui
f_esc = ubicar('Escenario_Trifasico_2.m', raiz);
preparar_modelo(raiz, modelo);   % tpsep_v11 o tpsep_v12, hemivols, hemivolt y hemihead en la ruta
planta = str2func(['tpsep_' modelo]);

%% 1) Leer el cronograma del archivo publico (secciones 1 y 2), sin graficar
fid = fopen(f_esc, 'r'); bytes = fread(fid, Inf, '*uint8')'; fclose(fid);
txt = char(bytes);
i1 = strfind(txt, '%% 1) TIEMPO');
i3 = strfind(txt, '%% 3)');
if isempty(i1) || isempty(i3)
    error('cronograma_escenario2:formato', 'No encuentro las secciones 1 y 2 en %s', f_esc);
end
ts = []; Tfase = []; nF = []; tend = []; t = []; N = []; Nf = []; esc = []; %#ok<NASGU>
eval(txt(i1(1):i3(1)-1));     % define ts, Tfase, nF, tend, t, N, Nf y esc

E = struct();
E.archivo = f_esc;
E.modelo = modelo;
E.sha256  = sha256_bytes(bytes(bytes ~= 13));   % sin CR: el mismo hash en Windows y en Linux (finales de linea LF)
E.ts = ts; E.Tfase = Tfase; E.nF = nF; E.tend = tend; E.N = N;
E.esc = esc;                                  % [qwi qci qgi hws hbs pgs] en m3/s, m y psi
E.t_ini = (0:nF-1)' * Tfase;
E.t_fin = E.t_ini + Tfase;
E.x0 = [0.80 0.72 37];                        % condicion inicial de la planta: Hw [m], Ho [m], Pg [psi]
E.nombres_var = {'Q_{w,in}','Q_{o,in}','Q_{g,in}','H_{w,sp}','H_{o,sp}','P_{g,sp}'};

%% 2) Aperturas de equilibrio de cada fase (niveles y presion en su referencia)
ueq = nan(nF, 3); hceq = nan(nF, 1);
for f = 1:nF
    qwi = esc(f,1); qci = esc(f,2); qgi = esc(f,3);
    hw = esc(f,4); hb = esc(f,5); pg = esc(f,6) * PSI2PA;
    u5 = [0.5 0.5 0.5];
    % altura total tal que el rebose sobre el vertedero iguala la entrada de crudo
    gha = @(ha) salida(planta([qwi qci qgi u5], [ha-hw hw hb pg]), 2) - qci;
    ha = fzero(gha, [HS+1e-6, HS+0.5]);
    hceq(f) = ha - hw;
    x = [hceq(f) hw hb pg];
    ueq(f,1) = raiz_apertura(@(u) salida(planta([qwi qci qgi u 0.5 0.5], x), 1) - qwi);
    ueq(f,2) = raiz_apertura(@(u) salida(planta([qwi qci qgi 0.5 u 0.5], x), 3) - qci);
    ueq(f,3) = raiz_apertura(@(u) salida(planta([qwi qci qgi 0.5 0.5 u], x), 4) - qgi);
end
E.ueq = 100 * ueq;                            % [%]
E.hceq = hceq;

% Valores escritos en el encabezado del archivo, para contrastar
tok = regexp(txt, 'fase\s+(\d+):\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', 'tokens');
E.ueq_archivo = nan(nF, 3);
for i = 1:numel(tok)
    k = str2double(tok{i}{1});
    if k >= 1 && k <= nF
        E.ueq_archivo(k,:) = [str2double(tok{i}{2}) str2double(tok{i}{3}) str2double(tok{i}{4})];
    end
end

%% 3) Que cambia en cada fase
E.cambios = cell(nF, 1); E.cambios_tex = cell(nF, 1);
ntex = {'$Q_{w,in}$','$Q_{o,in}$','$Q_{g,in}$','$H_{w,sp}$','$H_{o,sp}$','$P_{g,sp}$'};
for f = 1:nF
    if f == 1
        E.cambios{f} = sprintf('Base; arranque: H_w %.2f->%.2f m, P_g %g->%g psi', ...
                               E.x0(1), esc(1,4), E.x0(3), esc(1,6));
        E.cambios_tex{f} = sprintf('Base; arranque: $H_w$ %.2f$\\to$%.2f~m, $P_g$ %g$\\to$%g~psi', ...
                               E.x0(1), esc(1,4), E.x0(3), esc(1,6));
    else
        c = find(abs(esc(f,:) - esc(f-1,:)) > 1e-12);
        E.cambios{f} = strjoin(E.nombres_var(c), ', ');
        E.cambios_tex{f} = strjoin(ntex(c), ', ');
    end
end

%% 4) Salidas
escribir_csv(fullfile(carpeta_salida, 'cronograma_escenario2.csv'), E, M2FT);
escribir_tex(fullfile(carpeta_salida, 'tabla_S7_cronograma.tex'), E, M2FT);

fprintf('\n===== Cronograma del segundo escenario (planta tpsep_%s) =====\n', modelo);
fprintf('Archivo: %s\nSHA-256: %s\n', E.archivo, E.sha256);
fprintf('%d fases de %g s, ts = %g s, %d muestras\n', nF, Tfase, ts, N);
fprintf('%-5s %-10s %8s %8s %8s %6s %6s %6s %18s  %s\n', 'Fase', 'Tramo [s]', 'Qwi', 'Qci', 'Qgi', 'Hw', 'Ho', 'Pg', 'u_eq w/o/g [%]', 'Cambia');
for f = 1:nF
    fprintf('%-5d %4g-%-5g %8.4f %8.4f %8.4f %6.2f %6.2f %6.1f %6.1f %5.1f %5.1f  %s\n', f, E.t_ini(f), E.t_fin(f), ...
            esc(f,1:3), esc(f,4:6), E.ueq(f,:), E.cambios{f});
end
fprintf('Aperturas de equilibrio: entre %.1f y %.1f %%\n', min(E.ueq(:)), max(E.ueq(:)));
if strcmp(modelo, 'v11')
    fprintf('Diferencia maxima con los valores del encabezado del archivo: %.2f puntos\n', max(abs(E.ueq(:) - E.ueq_archivo(:))));
else
    fprintf('El encabezado del archivo trae las aperturas de tpsep_v11; con tpsep_v12 cambian en promedio %.1f puntos\n', mean(abs(E.ueq(:) - E.ueq_archivo(:))));
end
end

%% ======================= funciones locales =======================
function v = salida(d, k)
v = d(k);
end

function u = raiz_apertura(g)
% Apertura en [0, 1] que anula g; NaN si la valvula no alcanza el caudal (saturaria).
if g(0) * g(1) > 0
    u = NaN;
else
    u = fzero(g, [0 1]);
end
end

function preparar_modelo(raiz, modelo)
% Pone en la ruta las cuatro funciones del modelo. Si hay varias copias de tpsep_v11.m,
% prefiere la carpeta que tiene tambien hemivols, hemivolt y hemihead.
dep = {['tpsep_' modelo '.m'], 'hemivols.m', 'hemivolt.m', 'hemihead.m'};
cand = ubicar_todos(dep{1}, raiz);
elegida = '';
for i = 1:numel(cand)
    c = fileparts(cand{i}); completa = true;
    for j = 2:numel(dep)
        if exist(fullfile(c, dep{j}), 'file') ~= 2, completa = false; end
    end
    if completa, elegida = c; break; end
end
if ~isempty(elegida)
    addpath(absoluta(elegida));
else
    faltan = {};
    for j = 1:numel(dep)
        lst = ubicar_todos(dep{j}, raiz);
        if isempty(lst), faltan{end+1} = dep{j}; else, addpath(absoluta(fileparts(lst{1}))); end %#ok<AGROW>
    end
    if ~isempty(faltan)
        error('cronograma_escenario2:modelo', ['Faltan %s dentro de %s. Copie tpsep_v11.m, hemivols.m, ' ...
              'hemivolt.m y hemihead.m en Modelo/Matlab del repositorio.'], strjoin(faltan, ', '), absoluta(raiz));
    end
end
for j = 1:numel(dep)
    [~, nb] = fileparts(dep{j});
    if exist(nb, 'file') ~= 2
        error('cronograma_escenario2:ruta', 'No se pudo poner %s en la ruta de MATLAB.', dep{j});
    end
end
end

function lst = ubicar_todos(nombre, raiz)
% Todas las copias de un archivo dentro de raiz y sus subcarpetas.
lst = {};
p = [{raiz}, strsplit(genpath(raiz), pathsep)];
for i = 1:numel(p)
    if ~isempty(p{i}) && exist(fullfile(p{i}, nombre), 'file') == 2
        f = absoluta(fullfile(p{i}, nombre));
        if ~any(strcmp(lst, f)), lst{end+1} = f; end %#ok<AGROW>
    end
end
end

function a = absoluta(p)
% Ruta absoluta respecto de la carpeta actual de MATLAB (pwd).
% Java resolveria una ruta relativa desde la carpeta en que arranco MATLAB,
% por eso primero se antepone pwd y solo despues se normaliza.
if exist('OCTAVE_VERSION', 'builtin')
    a = make_absolute_filename(p);
    return
end
if isempty(regexp(p, '^([A-Za-z]:[\\/]|[\\/])', 'once'))
    p = fullfile(pwd, p);
end
a = char(java.io.File(p).getCanonicalPath());
end

function f = ubicar(nombre, raiz)
% Busca un archivo por nombre en raiz y en todas sus subcarpetas.
if exist(fullfile(raiz, nombre), 'file') == 2, f = fullfile(raiz, nombre); return; end
p = strsplit(genpath(raiz), pathsep);
for i = 1:numel(p)
    if ~isempty(p{i}) && exist(fullfile(p{i}, nombre), 'file') == 2
        f = fullfile(p{i}, nombre); return;
    end
end
error('ubicar:no', 'No encuentro %s dentro de %s', nombre, raiz);
end

function h = sha256_bytes(b)
try
    if exist('OCTAVE_VERSION', 'builtin')
        h = hash('sha256', char(b));
    else
        md = java.security.MessageDigest.getInstance('SHA-256');
        d = typecast(md.digest(uint8(b(:))), 'uint8');
        h = lower(sprintf('%02x', d));
    end
catch
    h = 'no disponible';
end
end

function escribir_csv(f, E, M2FT)
fid = fopen(f, 'w');
fprintf(fid, 'fase,t_ini_s,t_fin_s,Qwi_m3s,Qci_m3s,Qgi_m3s_std,Hw_sp_m,Hw_sp_ft,Ho_sp_m,Ho_sp_ft,Pg_sp_psi,uw_eq_pct,uo_eq_pct,ug_eq_pct,cambia\n');
for k = 1:E.nF
    e = E.esc(k,:);
    fprintf(fid, '%d,%g,%g,%.4f,%.4f,%.4f,%.2f,%.4f,%.2f,%.4f,%.1f,%.1f,%.1f,%.1f,"%s"\n', k, E.t_ini(k), E.t_fin(k), ...
            e(1), e(2), e(3), e(4), e(4)*M2FT, e(5), e(5)*M2FT, e(6), E.ueq(k,:), E.cambios{k});
end
fclose(fid);
end

function escribir_tex(f, E, M2FT)
fid = fopen(f, 'w');
fprintf(fid, '\\begin{table}[H]\n');
fprintf(fid, ['\\caption{Cronograma del segundo escenario, tomado de \\texttt{Escenario\\_Trifasico\\_2.m} ' ...
              '(SHA-256 \\texttt{%s}, con finales de l\\''inea LF). Cada fase dura %g~s y los cambios ocurren al inicio de la fase. ' ...
              'Niveles en m y, entre par\\''entesis, en ft (1~m = 3.2808~ft). $Q_{g,in}$ en condiciones est\\''andar. ' ...
              'Las aperturas de equilibrio se calculan con el modelo de la planta (\\texttt{tpsep\\_%s}), con los niveles y la presi\\''on en su referencia.}\n'], ...
        E.sha256(1:min(16, numel(E.sha256))), E.Tfase, E.modelo);
fprintf(fid, '\\label{tab:esc2_cronograma}\n\\centering\n\\footnotesize\n\\setlength{\\tabcolsep}{3pt}\n');
fprintf(fid, '\\resizebox{\\textwidth}{!}{%%\n\\begin{tabular}{ccccccccl}\n\\toprule\n');
fprintf(fid, 'Fase & Tramo & $Q_{w,in}$ & $Q_{o,in}$ & $Q_{g,in}$ & $H_{w,sp}$ & $H_{o,sp}$ & $P_{g,sp}$ & Cambia al inicio \\\\\n');
fprintf(fid, ' & [s] & [m$^3$/s] & [m$^3$/s] & [m$^3$/s] & [m (ft)] & [m (ft)] & [psi] & (apertura de equilibrio $u_w/u_o/u_g$ [\\%%]) \\\\\n\\midrule\n');
for k = 1:E.nF
    e = E.esc(k,:);
    cam = E.cambios_tex{k};
    fprintf(fid, '%d & %g--%g & %.4f & %.4f & %.4f & %.2f (%.3f) & %.2f (%.3f) & %.1f & %s (%.1f/%.1f/%.1f) \\\\\n', ...
            k, E.t_ini(k), E.t_fin(k), e(1), e(2), e(3), e(4), e(4)*M2FT, e(5), e(5)*M2FT, e(6), cam, E.ueq(k,:));
end
fprintf(fid, '\\bottomrule\n\\end{tabular}}\n\\end{table}\n');
fclose(fid);
end
