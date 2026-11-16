function T = sintonia_v12(archivo_v11, archivo_v12)


if nargin < 1 || isempty(archivo_v11), archivo_v11 = 'TPSEP_OperatingPoint.mat'; end
if nargin < 2 || isempty(archivo_v12), archivo_v12 = 'TPSEP_OperatingPoint_v12.mat'; end
FT = 0.3048; PSI2PA = 6894.757;

% Sintonia actual (Tablas de parametros del PID y del Fuzzy del articulo)
Kp  = [16.44 4.388 2.673];     % [1/ft 1/ft 1/psi] por unidad de apertura
Ti  = [7.821 2.702 1.050];     % [s]
Kcv = [4.0 2.5 2.25];          % factor de salida del Fuzzy

S11 = load(archivo_v11, 'xeq', 'mveq', 'md0');
S12 = load(archivo_v12, 'xeq', 'mveq', 'md0');
[A11, B11] = linealizar(@tpsep_v11, S11.xeq(:), [S11.mveq(:); S11.md0(:)]);
[A12, B12] = linealizar(@tpsep_v12, S12.xeq(:), [S12.mveq(:); S12.md0(:)]);

K11 = [-B11(2,1)/FT, -B11(3,2)/FT, -B11(4,3)/PSI2PA];
K12 = [-B12(2,1)/FT, -B12(3,2)/FT, -B12(4,3)/PSI2PA];
r = K11 ./ K12;

% Lazo cerrado de segundo orden sobre el integrador (ecuacion de asignacion de polos)
wn = @(K, kp, ti) sqrt(K .* kp ./ ti);
zt = @(K, kp, ti) 0.5 * sqrt(K .* kp .* ti);
wn11 = wn(K11, Kp, Ti); z11 = zt(K11, Kp, Ti);
wnA  = wn(K12, Kp, Ti); zA  = zt(K12, Kp, Ti);
KpB  = Kp .* r;          TiB = Ti;
wnB  = wn(K12, KpB, TiB); zB = zt(K12, KpB, TiB);
KcvB = Kcv .* r;

lazo = {'H_w', 'H_o', 'P_g'};
fprintf('\n===== Ganancias integradoras (y'' ~ -K u) =====\n');
fprintf('%-5s %12s %12s %9s\n', 'Lazo', 'K v11', 'K v12', 'v12/v11');
for j = 1:3, fprintf('%-5s %12.4g %12.4g %9.3f\n', lazo{j}, K11(j), K12(j), K12(j)/K11(j)); end
fprintf('Acoplamiento u_w -> P_g [psi/s]: v11 %.4g | v12 %.4g\n', B11(4,1)/PSI2PA, B12(4,1)/PSI2PA);
fprintf('Acoplamiento u_o -> P_g [psi/s]: v11 %.4g | v12 %.4g\n', B11(4,2)/PSI2PA, B12(4,2)/PSI2PA);

fprintf('\n===== PID (T_d = 0) =====\n');
fprintf('%-5s | %-26s | %-26s | %-34s\n', 'Lazo', 'v11: zeta / wn [rad/s]', 'A (sin resintonia) en v12', 'B (mismo criterio): Kp nuevo, Ti');
for j = 1:3
    fprintf('%-5s | %6.2f / %6.3f          | %6.2f / %6.3f          | Kp = %8.4g (antes %g), Ti = %g s\n', ...
            lazo{j}, z11(j), wn11(j), zA(j), wnA(j), KpB(j), Kp(j), TiB(j));
end
fprintf('Comprobacion: zeta y wn de v11 deben coincidir con la tabla del PID del articulo (0.71/0.18, 0.52/0.39, 0.53/1.01).\n');

fprintf('\n===== Fuzzy =====\n');
for j = 1:3
    fprintf('%-5s | K_cv actual %.3g -> condicion B %.4g\n', lazo{j}, Kcv(j), KcvB(j));
end

T = struct('K11', K11, 'K12', K12, 'A11', A11, 'B11', B11, 'A12', A12, 'B12', B12, ...
           'Kp', Kp, 'Ti', Ti, 'KpB', KpB, 'TiB', TiB, 'Kcv', Kcv, 'KcvB', KcvB, ...
           'zeta_v11', z11, 'wn_v11', wn11, 'zeta_A', zA, 'wn_A', wnA, 'zeta_B', zB, 'wn_B', wnB);
save('sintonia_v12.mat', '-struct', 'T');
fid = fopen('sintonia_v12.csv', 'w');
fprintf(fid, 'lazo,K_v11,K_v12,Kp_actual,Ti_s,zeta_v11,wn_v11,zeta_A_v12,wn_A_v12,Kp_B,zeta_B,wn_B,Kcv_actual,Kcv_B\n');
for j = 1:3
    fprintf(fid, '%s,%.6g,%.6g,%.6g,%.6g,%.4f,%.4f,%.4f,%.4f,%.6g,%.4f,%.4f,%.6g,%.6g\n', lazo{j}, K11(j), K12(j), Kp(j), Ti(j), ...
            z11(j), wn11(j), zA(j), wnA(j), KpB(j), zB(j), wnB(j), Kcv(j), KcvB(j));
end
fclose(fid);
fprintf('\nGuardado en sintonia_v12.mat y sintonia_v12.csv\n');
end

function [A, B] = linealizar(f, xeq, u_eq)
% u_eq = [mv; md] como en MPC_linealizar; el modelo recibe [md; mv]
dx_step = [1e-4; 1e-4; 1e-4; 10]; du_step = 1e-4 * ones(6, 1);
A = zeros(4); B = zeros(4, 6);
dxf = @(x, u) deriv(f, x, u);
for i = 1:4
    xp = xeq; xm = xeq; xp(i) = xp(i) + dx_step(i); xm(i) = xm(i) - dx_step(i);
    A(:,i) = (dxf(xp, u_eq) - dxf(xm, u_eq)) / (2*dx_step(i));
end
for j = 1:6
    up = u_eq; um = u_eq; up(j) = up(j) + du_step(j); um(j) = um(j) - du_step(j);
    B(:,j) = (dxf(xeq, up) - dxf(xeq, um)) / (2*du_step(j));
end
end

function dx = deriv(f, x, u)
[~, dx] = f([u(4:6); u(1:3)], x);
dx = dx(:);
end
