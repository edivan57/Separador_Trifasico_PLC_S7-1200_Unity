function D = comparar_hil_simulink(archivo_hil, archivo_simulink, etiqueta)


if nargin < 3, etiqueta = ''; end
M2FT = 3.280839895; Ts = 0.1;

% Corrida HIL: acepta el nombre exacto o un patron con * (se usa el mas reciente)
archivo_hil = resolver(archivo_hil);
archivo_simulink = resolver(archivo_simulink);
d = dir(archivo_hil);
fprintf('\nCorrida HIL: %s (modificada %s)\n', archivo_hil, d.date);
fprintf('Corrida Simulink: %s\n', archivo_simulink);
X = leer_txt(archivo_hil);
th = X(:,10);
H.r = [X(:,1)*M2FT, X(:,4)*M2FT, X(:,7)];
H.y = [X(:,2)*M2FT, X(:,5)*M2FT, X(:,8)];
H.u = [X(:,3), X(:,6), X(:,9)] * 100;

% Corrida de Simulink
S = load(archivo_simulink); ts = S.t(:);
k = ts < 1000 - 1e-6;
F.r = [S.hws(k)*M2FT, S.hbs(k)*M2FT, S.pgs(k)]; F.r = reshape(F.r, [], 3);
F.y = [S.hw(k)*M2FT,  S.hb(k)*M2FT,  S.pg(k)];  F.y = reshape(F.y, [], 3);
F.u = [S.vpw(k), S.vpc(k), S.vpg(k)] * 100;     F.u = reshape(F.u, [], 3);
ts = ts(k);

% Alinear por tiempo simulado (muestras de 0.1 s)
[~, ih, is] = intersect(round(th*10), round(ts*10));
n = numel(ih);
iae = @(r, y) Ts * sum(abs(r - y), 1);
IH = iae(H.r(ih,:), H.y(ih,:)); IS = iae(F.r(is,:), F.y(is,:));
D.n = n;
D.IAE_hil = IH; D.IAE_sim = IS;
D.dIAE_pct = 100 * (IH - IS) ./ IS;
D.dy_max = max(abs(H.y(ih,:) - F.y(is,:)), [], 1);
D.du_max = max(abs(H.u(ih,:) - F.u(is,:)), [], 1);
D.dr_max = max(abs(H.r(ih,:) - F.r(is,:)), [], 1);

fprintf('\n===== HIL frente a Simulink %s =====\n', etiqueta);
fprintf('Muestras comparadas: %d (HIL %d, Simulink %d)\n', n, size(X,1), numel(ts));
fprintf('Referencias: diferencia maxima %.2e / %.2e ft / %.2e psi (deben ser 0: mismo escenario)\n', D.dr_max);
fprintf('IAE  HIL     : %.4f / %.4f ft s / %.2f psi s\n', IH);
fprintf('IAE  Simulink: %.4f / %.4f ft s / %.2f psi s\n', IS);
fprintf('Diferencia   : %+.3f / %+.3f / %+.3f %%\n', D.dIAE_pct);
fprintf('Salidas: diferencia maxima %.4f / %.4f ft / %.4f psi\n', D.dy_max);
fprintf('Aperturas: diferencia maxima %.3f / %.3f / %.3f p.p.\n', D.du_max);
if max(abs(D.dIAE_pct)) <= 0.05
    fprintf('-> PASA: la planta de Unity reproduce la de Simulink (IAE dentro de 0.05 %%).\n');
elseif max(abs(D.dIAE_pct)) <= 1
    fprintf('-> REVISAR: diferencias de IAE entre 0.05 y 1 %%; compare la configuracion de Unity con la de Simulink.\n');
else
    fprintf('-> FALLA: diferencias de IAE mayores que 1 %%. Revise que Unity tenga Modelo Corregido V12 marcado.\n');
end
end

function f = resolver(f)
% Nombre exacto, o patron con * o con el marcador <fecha>; busca en la carpeta actual y en subcarpetas
f = strrep(f, '<fecha>', '*');
if exist(f, 'file') == 2 && isempty(strfind(f, '*')), return; end
[carpeta, nombre, ext] = fileparts(f);
if isempty(carpeta), carpeta = pwd; end
lista = dir(fullfile(carpeta, [nombre ext]));
if isempty(lista)
    try, lista = dir(fullfile(carpeta, '**', [nombre ext])); catch, end
end
lista = lista(~[lista.isdir]);
if isempty(lista)
    error('comparar_hil_simulink:archivo', ['No encuentro %s.\nUse el nombre real del registro que escribio Unity, ' ...
          'por ejemplo Datos_PID_rep01_20261114_101500.txt, o un patron como Datos_PID_rep01_*.txt.'], f);
end
% El mas reciente segun la fecha del nombre (AAAAMMDD_HHMMSS ordena igual que el tiempo);
% la fecha de modificacion cambia al copiar archivos
[~, orden] = sort({lista.name}); i = orden(end);
if isfield(lista, 'folder'), f = fullfile(lista(i).folder, lista(i).name); else, f = fullfile(carpeta, lista(i).name); end
if numel(lista) > 1
    fprintf('(%d archivos cumplen el patron; se usa el de fecha mas reciente en el nombre)\n', numel(lista));
end
end

function X = leer_txt(f)
fid = fopen(f, 'r');
if fid < 0, error('comparar_hil_simulink:abrir', 'No se pudo abrir %s', f); end
fgetl(fid);                                      % encabezado
X = fscanf(fid, '%f', [11 Inf])'; fclose(fid);
end
