function ok = probar_escenario2(raiz, carpeta_salida, modelo)


if nargin < 1 || isempty(raiz), raiz = '..'; end
if nargin < 3 || isempty(modelo), modelo = 'v11'; end
if nargin < 2 || isempty(carpeta_salida), carpeta_salida = 'resultados_escenario2'; end
v12 = strcmp(modelo, 'v12');
V = eventos_escenario2(raiz, carpeta_salida, modelo);
E = V.E;
P = {};   % {descripcion, superada, detalle}

P(end+1,:) = {'10 fases de 100 s y 10 001 muestras', E.nF == 10 && E.Tfase == 100 && E.N == 10001, ...
              sprintf('%d fases, %g s, %d muestras', E.nF, E.Tfase, E.N)};
d = max(abs(E.ueq(:) - E.ueq_archivo(:)));
if v12
    P(end+1,:) = {'Aperturas de equilibrio v12 calculadas en las 10 fases', ~any(isnan(E.ueq(:))), ...
                  sprintf('difieren hasta %.1f puntos de las v11 del encabezado', d)};
else
    P(end+1,:) = {'Aperturas de equilibrio = encabezado del archivo (±0.1 puntos)', d <= 0.1, sprintf('diferencia máxima %.3f puntos', d)};
end
% Rango de aperturas de equilibrio: 20-70 % con tpsep_v11. Con tpsep_v12 la valvula de crudo trabaja mas cerrada
% (18.6 % en el punto de operacion del escenario de ajuste), asi que se pide 10-90 %: al menos 8 puntos sobre los
% limites inferiores de los controladores (1 % en PID y Fuzzy, 2 % en el MPC).
if v12, rango = [10 90]; else, rango = [20 70]; end
P(end+1,:) = {sprintf('Ninguna fase exige válvula saturada (%g–%g %%)', rango), all(E.ueq(:) >= rango(1) & E.ueq(:) <= rango(2)), ...
              sprintf('entre %.1f y %.1f %%', min(E.ueq(:)), max(E.ueq(:)))};
P(end+1,:) = {'Las corridas usan el cronograma del archivo', max(V.err_ref(V.ok)) < 1e-9, sprintf('error máximo %.1e', max(V.err_ref(V.ok)))};
P(end+1,:) = {'Las corridas parten de la condición inicial declarada', max(V.err_x0(V.ok)) < 2e-3, sprintf('error máximo %.1e', max(V.err_x0(V.ok)))};
P(end+1,:) = {'13 eventos, iguales a los de calcular_resultados_articulo.m', isequal(V.eventos, V.eventos_script_resultados), ...
              sprintf('%d eventos derivados', size(V.eventos, 1))};
nn = sum(sum(isnan(V.TS(V.ok, :))));
P(end+1,:) = {'Todos los eventos se establecen dentro de su fase', nn == 0, sprintf('%d tiempos sin establecer', nn)};
ho = all(V.eventos(V.lento == 1, 2) == 2);
info = false(size(P, 1), 1);     % filas informativas: no deciden el resultado
if v12
    P(end+1,:) = {'Controlador más lento por evento (dato para el artículo)', true, ...
                  sprintf('MPC %d, PID %d, Fuzzy %d de %d', sum(V.lento == 3), sum(V.lento == 1), sum(V.lento == 2), numel(V.lento))};
    info(end+1) = true;
    if ~isempty(V.lento_com)
        P(end+1,:) = {'Condiciones comunes: más lento por evento (dato)', true, ...
                      sprintf('MPC %d, PID %d, Fuzzy %d de %d', sum(V.lento_com == 3), sum(V.lento_com == 1), sum(V.lento_com == 2), numel(V.lento_com))};
        info(end+1) = true;
    end
else
    P(end+1,:) = {'MPC completo el más lento en 10 de 13; PID en 3, todos de H_o', sum(V.lento == 3) == 10 && sum(V.lento == 1) == 3 && ho, ...
                  sprintf('MPC %d, PID %d, Fuzzy %d', sum(V.lento == 3), sum(V.lento == 1), sum(V.lento == 2))};
    info(end+1) = false;
    if ~isempty(V.lento_com)
        P(end+1,:) = {'Condiciones comunes: MPC completo el más lento en 11 de 13', sum(V.lento_com == 3) == 11, ...
                      sprintf('MPC %d, PID %d, Fuzzy %d', sum(V.lento_com == 3), sum(V.lento_com == 1), sum(V.lento_com == 2))};
        info(end+1) = false;
    end
end

info(end+1:size(P, 1)) = false;
fprintf('\n===== PRUEBAS DEL SEGUNDO ESCENARIO (planta tpsep_%s) =====\n', modelo);
for i = 1:size(P, 1)
    if info(i), r = 'DATO'; elseif P{i,2}, r = 'PASA'; else, r = 'FALLA'; end
    fprintf('%2d. [%-5s] %-62s %s\n', i, r, P{i,1}, P{i,3});
end
ok = all([P{:,2}]);
if ok
    fprintf('Todas las pruebas pasan. Copie S7_segundo_escenario.tex al suplemento.\n');
else
    fprintf('Hay pruebas que fallan: revise antes de cambiar el texto.\n');
end
end
