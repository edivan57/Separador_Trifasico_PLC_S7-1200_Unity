function T = contrastar_qp_cotas_todas(carpeta, archivo_scl)

raiz = fileparts(fileparts(mfilename('fullpath')));    % raiz del repositorio si este archivo esta en analisis/
if nargin < 1 || isempty(carpeta), carpeta = fullfile('Datos', 'Nominal', 'MPC'); end
if nargin < 2, archivo_scl = fullfile('plc', 'Simulacion_Trifasico_MPC_v8_M6_caja_S71200.scl'); end
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
nf = numel(archivos);  T = zeros(nf, 6);
for i = 1:nf
    R = contrastar_qp_cotas(archivos{i}, archivo_scl);
    T(i,:) = [numel(R.err_port), max(R.err_port), sum(R.err_port > 1e-3), sum(R.dif_sol > 1e-4), R.n_tope, max(R.dif_sol)];
end
n = sum(T(:,1));
fprintf('\n===== RESUMEN DE %d REPETICIONES =====\n', nf);
fprintf('%-6s %8s %12s %12s %14s %8s %12s\n', 'Rep.', 'Ciclos', 'Err. max', 'Err>1e-3', 'Dif>1e-4', 'Tope', 'Dif. max');
for i = 1:nf, fprintf('%-6d %8d %12.2e %12d %14d %8d %12.2e\n', i, T(i,1), T(i,2), T(i,3), T(i,4), T(i,5), T(i,6)); end
fprintf('Total: %d ciclos | el conjunto activo reproduce el cv registrado (error <= 1e-3) en %.2f %% de los ciclos\n', n, 100*(1 - sum(T(:,3))/n));
fprintf('       ciclos con diferencia > 1e-4 entre el conjunto activo y el exacto: %d (%.2f %%) | ciclos al tope de 6 iteraciones: %d (%.2f %%) | diferencia maxima %.2e = %.1f puntos de apertura\n', sum(T(:,4)), 100*sum(T(:,4))/n, sum(T(:,5)), 100*sum(T(:,5))/n, max(T(:,6)), 100*max(T(:,6)));
end
