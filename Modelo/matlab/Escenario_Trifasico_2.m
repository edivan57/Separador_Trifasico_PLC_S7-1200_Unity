%% ============================================================
%  SEGUNDO ESCENARIO DE PRUEBA - SEPARADOR TRIFASICO (Simulink)
%  Para evaluar los controladores SIN retocar sus sintonias (las sintonias se ajustaron con Escenario_Trifasico.m).
%  Mismas condiciones de planta y mismos limites de operacion, pero otro orden de las fases y otras combinaciones
%  de referencias y caudales. Aperturas de equilibrio de cada fase [%] (agua, crudo, gas), calculadas con tpsep_v11:
%    fase 1: 68.5 24.9 50.3 | fase 2: 53.6 24.9 50.3 | fase 3: 46.6 21.6 41.6 | fase 4: 46.6 21.3 41.6 | fase 5: 46.6 21.3 35.7
%    fase 6: 69.0 23.0 39.5 | fase 7: 68.9 23.0 39.5 | fase 8: 61.9 21.3 39.7 | fase 9: 57.7 21.3 39.7 | fase 10: 68.5 24.9 50.3
%  (todas entre 20 y 70 %: ninguna fase exige una valvula saturada).
%% ============================================================

%% 1) TIEMPO
ts    = 0.1;                 % [s] periodo de muestreo del escenario
Tfase = 100;                 % [s] duracion de cada fase
nF    = 10;                  % numero de fases
tend  = nF*Tfase;            % [s] duracion total (Stop time de los modelos)

t  = 0:ts:tend;              % vector de tiempo (fila)
N  = numel(t);               % 10001 muestras
Nf = round(Tfase/ts);        % muestras por fase (1000)

%% 2) CRONOGRAMA (una fila por fase; el cambio ocurre al INICIO de la fase)
%        qwi      qci      qgi      hws    hbs    pgs
%       [m3/s]   [m3/s]   [m3/s]    [m]    [m]   [psi]
esc = [ 0.1374   0.0711   0.4906   0.85   0.72   35.0     % fase  1:   0 - 100 s  condicion base
        0.1074   0.0711   0.4906   0.85   0.72   35.0     % fase  2: 100 - 200 s  qwi baja
        0.1074   0.0711   0.4906   0.85   0.72   42.0     % fase  3: 200 - 300 s  pgs
        0.1074   0.0701   0.4906   0.85   0.68   42.0     % fase  4: 300 - 400 s  qci, hbs
        0.1074   0.0701   0.4206   0.82   0.68   42.0     % fase  5: 400 - 500 s  qgi, hws
        0.1474   0.0701   0.4206   0.82   0.68   38.0     % fase  6: 500 - 600 s  qwi sube, pgs
        0.1474   0.0701   0.4206   0.88   0.75   38.0     % fase  7: 600 - 700 s  hws, hbs
        0.1474   0.0725   0.4906   0.88   0.75   44.0     % fase  8: 700 - 800 s  qci, qgi, pgs
        0.1374   0.0725   0.4906   0.80   0.75   44.0     % fase  9: 800 - 900 s  qwi, hws
        0.1374   0.0711   0.4906   0.85   0.72   35.0 ];  % fase 10: 900 -1000 s  regreso a la condicion base  % fase 10: 900 -1000 s  qgi, hbs

if size(esc,1) ~= nF
    error('La tabla de escenario tiene %d fases y nF = %d.', size(esc,1), nF);
end

%% 3) VECTORES MUESTRA A MUESTRA
k   = 0:N-1;
idx = min(floor(k/Nf) + 1, nF);         % fase a la que pertenece cada muestra

qwi_v = esc(idx,1)';
qci_v = esc(idx,2)';
qgi_v = esc(idx,3)';
hws_v = esc(idx,4)';
hbs_v = esc(idx,5)';
pgs_v = esc(idx,6)';                     % en psi

PA2PSI = 1/6894.757;
PSI2PA = 6894.757;

%% 4) ENTRADAS PARA LOS BLOQUES FROM WORKSPACE  (formato [t  valor], N x 2)
hws_ = [t' hws_v'];
hbs_ = [t' hbs_v'];
pgs_ = [t' pgs_v'];
qwi_ = [t' qwi_v'];
qci_ = [t' qci_v'];
qgi_ = [t' qgi_v'];

%% 5) VERIFICACION EN CONSOLA
nombres = {'qwi','qci','qgi','hws','hbs','pgs'};
unid    = {'m3/s','m3/s','m3/s','m','m','psi'};

fprintf('\n===== ESCENARIO: ts = %.3f s | Tfase = %g s | Nf = %d | tend = %g s | N = %d =====\n', ...
        ts, Tfase, Nf, tend, N);
for j = 1:6
    v = esc(idx,j);
    c = find(diff(v) ~= 0) + 1;
    fprintf('  %-4s [%4s]: inicia en %.4f', nombres{j}, unid{j}, v(1));
    for i = 1:numel(c)
        fprintf('  |  t = %6.1f s -> %.4f', t(c(i)), v(c(i)));
    end
    fprintf('\n');
end

%% 6) GRAFICA DEL ESCENARIO
graficarEscenario = true;

if graficarEscenario
    figure('Name','Escenario de prueba','Color','w');
    V   = {qwi_v, qci_v, qgi_v, hws_v, hbs_v, pgs_v};
    etq = {'q_{wi} [m^3/s]','q_{ci} [m^3/s]','q_{gi} [m^3/s]', ...
           'h_{w,sp} [m]','h_{b,sp} [m]','p_{g,sp} [psi]'};
    pos = [1 3 5 2 4 6];                 % izquierda: perturbaciones | derecha: setpoints

    for j = 1:6
        subplot(3,2,pos(j))
        stairs(t, V{j}, 'LineWidth', 1.8); grid on; hold on
        yl  = [min(V{j}) max(V{j})];
        pad = max(0.15*diff(yl), 1e-3);
        ylim([yl(1)-pad, yl(2)+pad]);
        for f = 1:nF-1                   % bordes de fase
            plot([f*Tfase f*Tfase], ylim, ':', 'Color', [0.65 0.65 0.65]);
        end
        xlim([0 tend]); ylabel(etq{j});
        if pos(j) >= 5, xlabel('t [s]'); end
    end
end

%% 7) CONFIGURACION DE LOS MODELOS (opcional)
configurarModelos = false;

modelos = {'Simulacion_Trifasico_PID_v8', ...
           'Simulacion_Trifasico_Fuzzy_v10', ...
           'Simulacion_Trifasico_MPC_v6'};

if configurarModelos
    fprintf('\n===== CONFIGURACION DE MODELOS =====\n');
    for i = 1:numel(modelos)
        mdl = modelos{i};
        load_system(mdl);
        set_param(mdl, 'StartTime', '0', 'StopTime', 'tend', ...
                       'SolverType', 'Fixed-step', 'Solver', 'ode3', ...
                       'FixedStep', '0.01');
        fw = find_system(mdl, 'LookUnderMasks', 'all', 'BlockType', 'FromWorkspace');
        for j = 1:numel(fw)
            set_param(fw{j}, 'Interpolate', 'off');
        end
        save_system(mdl);
        fprintf('  %-32s Start = 0 | ode3 | paso 0.01 s | %d From Workspace sin interpolacion\n', ...
                mdl, numel(fw));
    end
end
