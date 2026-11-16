function R = reproducir_replicas_v12(carpeta_datos)


if nargin < 1 || isempty(carpeta_datos), carpeta_datos = 'Datos'; end
PSI = 6894.757; M2FT = 3.280839895; HS = 1.2192; DS = 3.048; LA = 15.1724; LB = 3.1076;
X0 = [0.4737 0.80 0.72 37*PSI];          % Hc, Hw, Ho [m] y Pg [Pa] iniciales
R = struct('nombre', {}, 'tipo', {}, 'err_ft', {}, 'err_psi', {}, 'margen_m', {}, 'err_vol_m3', {});

fprintf('\n=== Replicas HIL (Euler, 10 subpasos) ===\n');
ctrl = {'PID','PID'; 'Fuzzy','FUZZY'; 'MPC','MPC'};
for c = 1:3
    patron = fullfile(carpeta_datos, 'Nominal_v12', ctrl{c,1}, ['Datos_' ctrl{c,2} '_rep01_*.txt']);
    d = dir(patron);
    if isempty(d), fprintf('  Sin archivo: %s\n', patron); continue; end
    f = fullfile(carpeta_datos, 'Nominal_v12', ctrl{c,1}, d(1).name);
    X = leer_datos(f);
    n = size(X,1); y = [X(:,2) X(:,5) X(:,8)]; u = [X(:,3) X(:,6) X(:,9)];
    x = X0; err = zeros(n,3); marg = inf; V0 = []; qin = 0; qout = 0; dVmax = 0;
    for k = 1:n
        err(k,:) = abs([x(2) x(3) x(4)/PSI] - y(k,:));
        V = hemivols(x(1)+x(2), LA, DS) + hemivols(x(3), LB, DS);
        if isempty(V0), V0 = V; end
        dVmax = max(dVmax, abs(V - V0 - (qin - qout)));
        marg = min(marg, x(1) + x(2) - HS);
        q = caudales_esc1((k-1)*0.1);
        for s = 1:10
            [dat, dx] = tpsep_v12([q u(k,:)], x);
            x = x + 0.01*dx(:)';
            qin = qin + 0.01*(q(1) + q(2)); qout = qout + 0.01*(dat(1) + dat(3));
        end
    end
    R(end+1) = struct('nombre', d(1).name, 'tipo', 'HIL', 'err_ft', max(max(err(:,1:2)))*M2FT, ...
                      'err_psi', max(err(:,3)), 'margen_m', marg, 'err_vol_m3', dVmax); %#ok<AGROW>
    fprintf('  %-42s Hw %.1e ft | Ho %.1e ft | Pg %.1e psi | Ha-hs min %.3f m | volumen %.1e m3 de %.1f m3\n', ...
            d(1).name, max(err(:,1))*M2FT, max(err(:,2))*M2FT, max(err(:,3)), marg, dVmax, V0);
end

fprintf('\n=== Replicas de Simulink (ode3, paso 0.01 s) ===\n');
d = [dir(fullfile(carpeta_datos, 'Modelo_v12', '*_esc1_v12A*_flat.mat')); ...
     dir(fullfile(carpeta_datos, 'Modelo_v12', '*_esc2_v12A*_flat.mat'))];
for j = 1:numel(d)
    S = load(fullfile(carpeta_datos, 'Modelo_v12', d(j).name));
    esc2 = ~isempty(strfind(d(j).name, '_esc2_'));
    n = min(10000, numel(S.hw));
    y = [S.hw(1:n) S.hb(1:n) S.pg(1:n)]; u = [S.vpw(1:n) S.vpc(1:n) S.vpg(1:n)];
    y = reshape(y, n, 3); u = reshape(u, n, 3);
    x = X0; err = zeros(n,3); marg = inf; h = 0.01;
    for k = 1:n
        err(k,:) = abs([x(2) x(3) x(4)/PSI] - y(k,:));
        marg = min(marg, x(1) + x(2) - HS);
        if esc2, q = caudales_esc2((k-1)*0.1); else, q = caudales_esc1((k-1)*0.1); end
        inp = [q u(k,:)];
        for s = 1:10
            k1 = derivada(x, inp); k2 = derivada(x + h/2*k1, inp); k3 = derivada(x + 3*h/4*k2, inp);
            x = x + h*(2*k1 + 3*k2 + 4*k3)/9;
        end
    end
    R(end+1) = struct('nombre', d(j).name, 'tipo', 'Simulink', 'err_ft', max(max(err(:,1:2)))*M2FT, ...
                      'err_psi', max(err(:,3)), 'margen_m', marg, 'err_vol_m3', NaN); %#ok<AGROW>
    fprintf('  %-34s Hw %.1e ft | Ho %.1e ft | Pg %.1e psi | Ha-hs min %.4f m\n', ...
            d(j).name, max(err(:,1))*M2FT, max(err(:,2))*M2FT, max(err(:,3)), marg);
end
end

function dx = derivada(x, inp)
[~, d] = tpsep_v12(inp, x);
dx = d(:)';
end

function q = caudales_esc1(t)
% Caudales de entrada del escenario de ajuste (Tabla del cronograma): agua, crudo, gas [m3/s]
q = [0.1374 0.0711 0.4906];
if t >= 400, q(1) = 0.1874; end
if t >= 700, q(1) = 0.1074; end
if t >= 200, q(2) = 0.0725; end
if t >= 800, q(2) = 0.0701; end
if t >= 300, q(3) = 0.4606; end
if t >= 900, q(3) = 0.4206; end
end

function q = caudales_esc2(t)
% Caudales de las diez fases del segundo escenario (Escenario_Trifasico_2.m)
E = [0.1374 0.0711 0.4906; 0.1074 0.0711 0.4906; 0.1074 0.0711 0.4906; 0.1074 0.0701 0.4906; ...
     0.1074 0.0701 0.4206; 0.1474 0.0701 0.4206; 0.1474 0.0701 0.4206; 0.1474 0.0725 0.4906; ...
     0.1374 0.0725 0.4906; 0.1374 0.0711 0.4906];
q = E(min(floor(t/100 + 1e-9) + 1, 10), :);
end

function X = leer_datos(f)
% Datos_*.txt de Unity: cabecera y columnas separadas por tabulador
fid = fopen(f, 'r'); fgetl(fid);
X = fscanf(fid, '%f'); fclose(fid);
X = reshape(X, 11, [])';
end
