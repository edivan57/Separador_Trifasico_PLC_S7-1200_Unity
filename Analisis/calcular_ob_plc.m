function calcular_ob_plc(archivo_csv)

if nargin < 1, archivo_csv = fullfile('Datos', 'OB_PLC', 'medir_ob_nominal_20261107.csv'); end
carpeta = fileparts(archivo_csv);

fid = fopen(archivo_csv, 'r');
if fid < 0, error('No se pudo abrir %s', archivo_csv); end
fgetl(fid);                                                    % encabezado
T = textscan(fid, ['%s %s %s %s %s %s' repmat(' %f', 1, 14)], 'Delimiter', ',');
fclose(fid);
corrida = T{1}; activo = T{2}; ob = T{3}; ctrl = T{4}; datos_unity = T{6};
num = @(k) T{6 + k};                                           % columnas numericas 1..14
n_int = num(2); n_desc = num(3); mn = num(4); mx = num(5); s1 = num(6); s2 = num(7);
f01 = num(8); f05 = num(9); f1 = num(10); f5 = num(11);

media = 100 + s1 ./ n_int;                                     % periodo medio [ms]
sd = sqrt(max(s2 ./ n_int - (s1 ./ n_int).^2, 0));             % desviacion estandar [ms]
dmax = max(100 - mn, mx - 100);                                % desviacion maxima respecto de 100 ms [ms]
es_activo = strcmp(ctrl, activo);                              % el OB del controlador que se estaba midiendo

% Comprobacion contra lo que calculo el propio PLC (media_ms, sd_ms y pct_fuera_1ms leidos en TIA Portal)
dif = [max(abs(media - num(12))), max(abs(sd - num(13))), max(abs(100*f1./n_int - num(14)))];
fprintf('Diferencia maxima con lo leido en TIA: media %.1e ms, sd %.1e ms, pct fuera de 1 ms %.1e\n', dif(1), dif(2), dif(3));

nombres = {}; g = zeros(numel(corrida), 1);                         % agrupa las filas por corrida (compatible con Octave)
for k = 1:numel(corrida)
    p = find(strcmp(nombres, corrida{k}), 1);
    if isempty(p), nombres{end+1} = corrida{k}; p = numel(nombres); end %#ok<AGROW>
    g(k) = p;
end
fprintf('\n');
for c = 1:max(g)
    idx = find(g == c);
    fprintf('Corrida %s (controlador activo: %s)\n', corrida{idx(1)}, activo{idx(1)});
    fprintf('  %-5s %-7s %8s %6s %10s %8s %8s %8s %9s %8s %8s %8s\n', 'OB', 'Ctrl', 'n_int', 'n_desc', 'media[ms]', 'sd[ms]', 'min', 'max', 'dmax[ms]', '>0.1ms', '>0.5ms', '>1ms');
    for k = idx(:)'
        marca = ' '; if es_activo(k), marca = '*'; end
        fprintf(' %s%-5s %-7s %8d %6d %10.4f %8.4f %8.3f %8.3f %9.3f %7.1f%% %7.1f%% %7.1f%%\n', marca, ob{k}, ctrl{k}, n_int(k), n_desc(k), media(k), sd(k), mn(k), mx(k), dmax(k), ...
            100*f01(k)/n_int(k), 100*f05(k)/n_int(k), 100*f1(k)/n_int(k));
    end
    archivo_u = fullfile(carpeta, datos_unity{idx(1)});
    if exist(archivo_u, 'file')
        d = dlmread(archivo_u, '\t', 1, 0);
        jt = diff(d(:, 11)) * 1000;                            % columna 11: t_real [s]
        pc = sort(jt); p99 = pc(max(1, round(0.99*numel(pc))));
        ka = idx(es_activo(idx));
        fprintf('  Unity (misma corrida): %d intervalos | media %.3f ms | sd %.2f ms | p99 %.1f | min %.1f | max %.1f | fuera de 100+-0.1/0.5/1 ms: %.1f/%.1f/%.1f %%\n', ...
            numel(jt), mean(jt), std(jt, 1), p99, min(jt), max(jt), 100*mean(abs(jt-100) > 0.1), 100*mean(abs(jt-100) > 0.5), 100*mean(abs(jt-100) > 1));
        if ~isempty(ka), fprintf('  Razon sd(Unity) / sd(OB activo): %.0f\n', std(jt, 1)/sd(ka(1))); end
    else
        fprintf('  (no esta %s en %s: sin comparacion con Unity)\n', datos_unity{idx(1)}, carpeta);
    end
    fprintf('\n');
end

if ~exist('resultados', 'dir'), mkdir('resultados'); end
fo = fopen(fullfile('resultados', 'tabla_ob_plc.csv'), 'w');
fprintf(fo, 'corrida,controlador_activo,ob,controlador,ob_activo,n_int,n_desc,media_ms,sd_ms,min_ms,max_ms,desv_max_ms,pct_fuera_01,pct_fuera_05,pct_fuera_1,pct_fuera_5\n');
for k = 1:numel(ob)
    fprintf(fo, '%s,%s,%s,%s,%d,%d,%d,%.4f,%.4f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f\n', corrida{k}, activo{k}, ob{k}, ctrl{k}, es_activo(k), n_int(k), n_desc(k), media(k), sd(k), mn(k), mx(k), dmax(k), ...
        100*f01(k)/n_int(k), 100*f05(k)/n_int(k), 100*f1(k)/n_int(k), 100*f5(k)/n_int(k));
end
fclose(fo);
fprintf('Tabla guardada en resultados/tabla_ob_plc.csv (* = OB del controlador activo)\n');
end
