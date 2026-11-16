function OP = punto_operacion_v12(archivo_v11, archivo_salida)

if nargin < 1 || isempty(archivo_v11), archivo_v11 = 'TPSEP_OperatingPoint.mat'; end
if nargin < 2 || isempty(archivo_salida), archivo_salida = 'TPSEP_OperatingPoint_v12.mat'; end
PSI2PA = 6894.757; FT = 0.3048;

S = load(archivo_v11, 'xeq', 'mveq', 'md0');
xeq = S.xeq(:); md0 = S.md0(:); mveq_v11 = S.mveq(:);

% Residuo del modelo actual en su propio punto de operacion
[~, r11] = tpsep_v11([md0; mveq_v11], xeq);

% Aperturas de equilibrio con tpsep_v12: cada valvula iguala su caudal de salida al de entrada
isal = [1 3 4];                         % qwo, qcb, qgo en la salida data de tpsep_v12
mveq = mveq_v11;
for k = 1:3
    g = @(uk) salida_k(tpsep_v12([md0; poner(mveq, k, uk)], xeq), isal(k)) - md0(k);
    if g(0) * g(1) > 0
        error('punto_operacion_v12:saturada', 'La valvula %d no alcanza el caudal de entrada con el modelo v12.', k);
    end
    mveq(k) = fzero(g, [0 1]);
end
[~, r12] = tpsep_v12([md0; mveq], xeq);

fprintf('\n===== Punto de operacion =====\n');
fprintf('Estados: Hc = %.3f ft | Hw = %.3f ft | Ho = %.3f ft | Pg = %.2f psi\n', xeq(1)/FT, xeq(2)/FT, xeq(3)/FT, xeq(4)/PSI2PA);
fprintf('Caudales de entrada: qwi = %.4f | qci = %.4f | qgi = %.4f m^3/s\n', md0);
fprintf('Aperturas u_w / u_o / u_g: v11 %.2f / %.2f / %.2f %% | v12 %.2f / %.2f / %.2f %%\n', 100*mveq_v11, 100*mveq);
fprintf('Residuo max|dx|: v11 %.1e | v12 %.1e\n', max(abs(r11)), max(abs(r12)));

mveq_v12 = mveq; %#ok<NASGU>
save(archivo_salida, 'xeq', 'mveq', 'md0', 'mveq_v11', 'mveq_v12');
fprintf('Guardado en %s (variables xeq, mveq, md0)\n', archivo_salida);

OP = struct('xeq', xeq, 'mveq', mveq, 'md0', md0, 'mveq_v11', mveq_v11, 'residuo_v12', max(abs(r12)));
end

function v = salida_k(d, k)
v = d(k);
end

function v = poner(v, k, a)
v(k) = a;
end
