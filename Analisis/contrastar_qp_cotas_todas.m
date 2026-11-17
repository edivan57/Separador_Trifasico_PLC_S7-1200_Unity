function T = contrastar_qp_cotas_todas(carpeta, archivo_scl)
%CONTRASTAR_QP_COTAS_TODAS  Ejecuta contrastar_qp_cotas en todas las repeticiones nominales del MPC de cotas y resume.
%   T = contrastar_qp_cotas_todas()                                   % usa Datos/Nominal_v12/MPC y PLC/...caja_S71200.scl
%   T = contrastar_qp_cotas_todas('Datos/Nominal_v12/MPC', 'PLC/Simulacion_Trifasico_MPC_v8_M6_caja_S71200.scl')
%   T = contrastar_qp_cotas_todas({'ruta/rep01.txt', 'ruta/rep02.txt', ...}, 'PLC/...scl')   % lista explicita de archivos
%   Columnas de T: ciclos | error maximo frente al cv registrado | ciclos con error > 1e-3 | ciclos con diferencia > 1e-4
%                  entre el conjunto activo y la referencia | ciclos al tope de 6 iteraciones | diferencia maxima (fraccion de apertura)
raiz = fileparts(fileparts(mfilename('fullpath')));    % raiz del repositorio si este archivo esta en Analisis/
if nargin < 1 || isempty(carpeta), carpeta = fullfile('Datos', 'Nominal_v12', 'MPC'); end   % campana nominal con el modelo corregido
if nargin < 2, archivo_scl = fullfile('PLC', 'Simulacion_Trifasico_MPC_v8_M6_caja_S71200.scl'); end
if iscell(carpeta)
    archivos = carpeta(:)';
else
    if exist(carpeta, 'dir') ~= 7 && exist(fullfile(raiz, carpeta), 'dir') == 7, carpeta = fullfile(raiz, carpeta); end   % ruta relativa a la raiz
    if exist(carpeta, 'dir') ~= 7
        error('La carpeta no existe: %s (carpeta actual de MATLAB: %s; raiz supuesta: %s)', carpeta, pwd, raiz);
    end
    d = dir(carpeta);  d = d(~[d.isdir]);
    nombres = {d.name};
    ok = ~cellfun(@isempty, regexpi(nombres, '^Datos_MPC_rep\d+.*\.txt$', 'once'));
    if ~any(ok)
        fprintf('Carpeta revisada: %s\n', fullfile(pwd, carpeta));
        fprintf('Archivos que contiene (%d):\n', numel(nombres)); fprintf('  [%s]\n', nombres{:});
        error('No hay archivos Datos_MPC_rep*.txt en %s; revise que los nombres de la lista de arriba empiecen por Datos_MPC_rep y terminen en .txt', carpeta);
    end
    nombres = sort(nombres(ok));
    archivos = cellfun(@(x) fullfile(carpeta, x), nombres, 'UniformOutput', false);
end
nf = numel(archivos);  T = zeros(nf, 6);  V = zeros(nf, 10);  flags = [];  err_port = [];
for i = 1:nf
    R = contrastar_qp_cotas(archivos{i}, archivo_scl);
    T(i,:) = [numel(R.err_port), max(R.err_port), sum(R.err_port > 1e-3), sum(R.dif_sol > 1e-4), R.n_tope, max(R.dif_sol)];
    ok = R.flag_ref > 0;  c = ok & R.conv;
    V(i,:) = [R.n_noconv_ref, max(R.res_fact(ok)), max(R.opt1(ok)), max([R.dz_vec(c); 0]), max([abs(R.dJ_rel(c)); 0]), R.eps_max, ...
              max([R.dJ_rel(ok & ~R.conv); 0]), max(R.itr), R.dif_tope, R.dif_sin_tope];
    flags = [flags; R.flag_ref]; %#ok<AGROW>
    err_port = [err_port; R.err_port]; %#ok<AGROW>
end
n = sum(T(:,1));
fprintf('\n===== RESUMEN DE %d REPETICIONES =====\n', nf);
fprintf('%-6s %8s %12s %12s %14s %8s %12s\n', 'Rep.', 'Ciclos', 'Err. max', 'Err>1e-3', 'Dif>1e-4', 'Tope', 'Dif. max');
for i = 1:nf, fprintf('%-6d %8d %12.2e %12d %14d %8d %12.2e\n', i, T(i,1), T(i,2), T(i,3), T(i,4), T(i,5), T(i,6)); end
fprintf('Total: %d ciclos | el conjunto activo reproduce el cv registrado (error <= 1e-3) en %.2f %% de los ciclos\n', n, 100*(1 - sum(T(:,3))/n));
fprintf('       ciclos con diferencia > 1e-4 entre el conjunto activo y la referencia: %d (%.2f %%) | ciclos al tope de 6 iteraciones: %d (%.2f %%) | diferencia maxima %.2e = %.1f puntos de apertura\n', sum(T(:,4)), 100*sum(T(:,4))/n, sum(T(:,5)), 100*sum(T(:,5))/n, max(T(:,6)), 100*max(T(:,6)));
fprintf('\n===== VECTOR COMPLETO (19 variables) =====\n');
fprintf('%-6s %10s %12s %12s %14s %12s %10s %14s %8s\n', 'Rep.', 'Ref. mal', 'Incumpl.', 'Optimalidad', 'dz sin tope', 'dJ sin tope', 'Holgura', 'dJ con tope', 'Iter.');
for i = 1:nf, fprintf('%-6d %10d %12.2e %12.2e %14.2e %12.2e %10.2e %14.2e %8d\n', i, V(i,1), V(i,2), V(i,3), V(i,4), V(i,5), V(i,6), V(i,7), V(i,8)); end
% ---------------- cifras que usa el articulo ----------------
cods = unique(flags);  txt = '';
for cc = cods', txt = [txt sprintf('%d en %d ciclos; ', cc, sum(flags == cc))]; end %#ok<AGROW>
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    prog = ['GNU Octave ' version];
else
    prog = ['MATLAB ' version];  vo = ver('optim');
    if ~isempty(vo), prog = [prog ' | Optimization Toolbox ' vo(1).Version]; end
end
fprintf('\n===== CIFRAS PARA EL ARTICULO =====\n');
fprintf('Programa: %s\n', prog);
fprintf('Solucionador de referencia: %s | %s\n', R.solver, R.opciones);
fprintf('Codigos de salida de la referencia: %s\n', txt);
fprintf('Ciclos con la referencia no aceptada (codigo <= 0): %d de %d\n', sum(V(:,1)), n);
fprintf('Mayor incumplimiento de cotas de la referencia: %.2e\n', max(V(:,2)));
fprintf('Mayor %s de la referencia: %.2e | iteraciones maximas: %d\n', R.nombre_opt, max(V(:,3)), max(V(:,8)));
fprintf('Holgura maxima de la referencia: %.2e\n', max(V(:,6)));
fprintf('Conjunto activo frente a la apertura registrada: error maximo %.2e (fraccion de apertura)\n', max(err_port));
fprintf('Ciclos sin tope: %d | |z_activo - z_ref| maximo en los 18 movimientos %.2e | diferencia relativa de costo maxima %.2e\n', n - sum(T(:,5)), max(V(:,4)), max(V(:,5)));
fprintf('Ciclos con tope: %d (%.2f %%) | aumento relativo de costo maximo %.2e\n', sum(T(:,5)), 100*sum(T(:,5))/n, max(V(:,7)));
fprintf('Primer movimiento: ciclos con diferencia > 1e-4: %d (con tope %d, sin tope %d) | diferencia maxima %.2e = %.1f puntos de apertura\n', ...
        sum(T(:,4)), sum(V(:,9)), sum(V(:,10)), max(T(:,6)), 100*max(T(:,6)));
end
