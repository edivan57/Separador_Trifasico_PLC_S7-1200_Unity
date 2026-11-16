function calcular_resultados_articulo(varargin)


C = configuracion();
for i = 1:2:numel(varargin), C.(varargin{i}) = varargin{i+1}; end
C = ubicar_repositorio(C, varargin);   % encuentra Datos/ aunque MATLAB este en otra carpeta
if ~exist(C.carpeta_salida, 'dir'), mkdir(C.carpeta_salida); end
RES = struct();
fprintf('\n=== Resultados del articulo: calculo a partir de los registros ===\n');
fprintf('Carpeta de datos: %s\nCarpeta de salida: %s\n', C.carpeta_datos, C.carpeta_salida);
revisar_archivos(C);                    % lista los registros que faltan antes de calcular

%% 1) Campana nominal ---------------------------------------------------------------------------------
N = struct();
for c = 1:3
    fc = buscar(C, C.arch.nominal.(C.ctrl{c}));
    N.(C.ctrl{c}).archivos = fc;
    N.(C.ctrl{c}).reps = cell(1, numel(fc));
    for k = 1:numel(fc), N.(C.ctrl{c}).reps{k} = leer_corrida(fc{k}, C); end
    if isempty(fc), warning('Sin archivos nominales para %s (%s).', C.etq{c}, C.arch.nominal.(C.ctrl{c})); end
end
hay_nom = all(cellfun(@(s) ~isempty(N.(s).reps), C.ctrl));

if C.hacer.nominal && hay_nom
    RES.validez = bloque_validez(N, C);
    RES.nominal = bloque_nominal(N, C);
end
if C.hacer.diseno && hay_nom
    RES.diseno = bloque_diseno(N, C);
end
if C.hacer.diseno
    RES.comunes = bloque_comunes(C);
    RES.escenario2 = bloque_escenario2(C);
    RES.atribucion = bloque_atribucion(C);
    RES.horizonte = bloque_horizonte(C);
end
if C.hacer.mpc_1212c
    RES.mpc_1212c = bloque_mpc_1212c(C);
end
if C.hacer.tiempo
    RES.tiempo = bloque_tiempo(N, C);
end
if C.hacer.latencia
    RES.latencia = bloque_latencia(N, C);
end
if C.hacer.fallas && hay_nom
    RES.reconexion = bloque_reconexion(N, C);
end
if C.hacer.tia_off && hay_nom
    RES.tia_off = bloque_tia_desconectado(N, C);
end
if C.hacer.robustez && hay_nom
    RES.validez_rob = bloque_validez_robustez(C);
    RES.robustez = bloque_robustez(N, C);
end
if C.hacer.fallas && hay_nom
    RES.fallas = bloque_fallas(N, C, 'fallas');
end
if C.hacer.corte_cable && hay_nom
    RES.corte_cable = bloque_fallas(N, C, 'corte_cable');
end
save(fullfile(C.carpeta_salida, 'resultados.mat'), 'RES', 'C');
fprintf('\nListo. Tablas en CSV y resultados.mat en: %s\n', C.carpeta_salida);
end

%% ===================================== CONFIGURACION ================================================
function C = configuracion()
C.carpeta_datos  = 'Datos';
C.modelo_planta  = 'v12';      % 'v12': campanas con el modelo corregido (carpetas *_v12); 'v11': campanas originales
if strcmp(C.modelo_planta, 'v12'), sf = '_v12'; else, sf = ''; end
C.carpeta_salida = ['resultados' sf];
C.Ts   = 0.1;                    % periodo de muestreo [s]
C.m2ft = 3.280839895;            % m -> ft
C.ctrl = {'PID','FUZZY','MPC'};  % prefijos de los archivos
C.etq  = {'PID','Fuzzy','MPC'};   % rotulos (el PID se ejecuta con Td = 0)
C.var  = {'H_w [ft]','H_o [ft]','P_g [psi]'};
C.mv   = {'u_w','u_o','u_g'};
% --- archivos (patrones relativos a carpeta_datos; la primera coincidencia, por orden alfabetico, es la repeticion 1) ---
C.carp = struct('PID','PID','FUZZY','Fuzzy','MPC','MPC');           % nombre de la subcarpeta de cada controlador
C.arch.nominal      = struct('PID',['Nominal' sf '/PID/Datos_PID_rep*.txt'],'FUZZY',['Nominal' sf '/Fuzzy/Datos_FUZZY_rep*.txt'],'MPC',['Nominal' sf '/MPC/Datos_MPC_rep*.txt']);
C.arch.nominal_s1   = struct('PID','Nominal_sesion1/PID/Datos_PID_rep01*.txt','FUZZY','Nominal_sesion1/Fuzzy/Datos_FUZZY_rep01*.txt','MPC','Nominal_sesion1/MPC/Datos_MPC_rep01*.txt');   % primera sesion nominal (21 oct), opcional
C.arch.tia_off      = struct('PID','TIA Desconectado/PID/Datos_PID_rep*.txt','FUZZY','TIA Desconectado/Fuzzy/Datos_FUZZY_rep*.txt','MPC','TIA Desconectado/MPC/Datos_MPC_rep*.txt');   % corridas con TIA Portal desconectado (opcional)
C.arch.tia_off_diag = 'TIA Desconectado/*/Diag_Com_Ninguna_*.csv';
C.tia_reps_offline  = [2 4];   % repeticiones con TIA desconectado dentro de la sesion de TIA_desconectado (sesion alternada del MPC: 1 y 3 en linea, 2 y 4 desconectadas); [] = todas desconectadas
C.tia_umbral_ms     = 2;       % diferencia maxima aceptable en la media de lectura, escritura y latencia del lazo [ms]
C.arch.diag_nominal = ['Nominal' sf '/*/Diag_Com_Ninguna_*.csv'];           % un Diag_Com por controlador (cubre las 5 repeticiones)
C.arch.robustez     = struct('PID',['Robustez' sf '/PID/Datos_PID_rep*.txt'],'FUZZY',['Robustez' sf '/Fuzzy/Datos_FUZZY_rep*.txt'],'MPC',['Robustez' sf '/MPC/Datos_MPC_rep*.txt']);
C.arch.fallas       = ['Fallas' sf '/%s/Datos_%s_C%d_*.txt'];                % subcarpeta, prefijo del controlador, caso (1..5)
C.arch.diag_fallas  = ['Fallas' sf '/*/C%d_Diag_Com_*.csv'];
C.arch.corte_cable  = 'Corte real/Datos_%s_*.txt';
C.recon_casos       = {'C1b_wd10','C2b_wd10','C1b_wd2','C2b_wd2','Cable_wd2'};   % carpetas de Datos/Reconexion/<caso>/<Ctrl>/ (opcional)
C.recon_wd          = [10 10 2 2 2];                                              % Ciclos_Watchdog de cada caso
C.arch.recon_datos  = ['Reconexion' sf '/%s/%s/Datos_%s_*.txt'];              % caso, subcarpeta del controlador, prefijo (repeticiones o corridas sueltas)
C.arch.recon_diag   = ['Reconexion' sf '/%s/%s/*Diag_Com_*.csv'];
C.arch.diag_corte   = 'Corte real/Diag_Com_CorteReal_*.csv';
C.arch.diseno       = struct('PID','Simulink_diseno/pid_run22_flat.mat','FUZZY','Simulink_diseno/fuzzy_run23_flat.mat','MPC','Simulink_diseno/mpc_run30_flat.mat');
C.arch.comun        = struct('PID','Simulink_diseno/pid_run23_flat.mat','FUZZY','Simulink_diseno/fuzzy_run24_flat.mat','PID_memoria','Simulink_diseno/pid_run24_flat.mat');   % PID y Fuzzy con condiciones comunes (simulacion)
C.arch.escenario2   = struct('PID','Simulink_diseno/pid_run25_flat.mat','FUZZY','Simulink_diseno/fuzzy_run25_flat.mat','MPC','Simulink_diseno/mpc_run15_flat.mat','MPC_P100','Simulink_diseno/mpc_run18_flat.mat','MPC_P50','Simulink_diseno/mpc_run14_flat.mat','PID_comun','Simulink_diseno/pid_run27_flat.mat','FUZZY_comun','Simulink_diseno/fuzzy_run27_flat.mat');   % escenario 2 (Escenario_Trifasico_2.m)
C.arch.atribucion    = struct('PID_arranque','Simulink_diseno/pid_run28_flat.mat','PID_limites','Simulink_diseno/pid_run29_flat.mat','FUZZY_arranque','Simulink_diseno/fuzzy_run28_flat.mat','FUZZY_limites','Simulink_diseno/fuzzy_run29_flat.mat');   % un solo cambio a la vez, escenario original
C.arch.horizonte    = struct('P50','Simulink_diseno/mpc_run16_flat.mat','P100','Simulink_diseno/mpc_run17_flat.mat');   % P = 200 es C.arch.diseno.MPC
C.arch.mpc_1212c    = 'mpc_1212C/Datos_*.txt';          % corridas del MPC completo (y reducido) en la CPU 1212C
if strcmp(C.modelo_planta, 'v12')   % corridas de Simulink con el modelo corregido (correr_comparacion_v12): Datos/Modelo_v12/
    m = 'Modelo_v12/';
    C.arch.diseno     = struct('PID',[m 'pid_esc1_v12A_flat.mat'],'FUZZY',[m 'fuzzy_esc1_v12A_flat.mat'],'MPC',[m 'mpc_esc1_v12A_flat.mat']);
    C.arch.comun      = struct('PID',[m 'pid_esc1_v12A_comun_flat.mat'],'FUZZY',[m 'fuzzy_esc1_v12A_comun_flat.mat'],'PID_memoria',[m 'pid_esc1_v12A_memoria_flat.mat']);
    C.arch.escenario2 = struct('PID',[m 'pid_esc2_v12A_flat.mat'],'FUZZY',[m 'fuzzy_esc2_v12A_flat.mat'],'MPC',[m 'mpc_esc2_v12A_flat.mat'], ...
                               'MPC_P100',[m 'mpc_esc2_v12A_P100_flat.mat'],'MPC_P50',[m 'mpc_esc2_v12A_P50_flat.mat'], ...
                               'PID_comun',[m 'pid_esc2_v12A_comun_flat.mat'],'FUZZY_comun',[m 'fuzzy_esc2_v12A_comun_flat.mat']);
    C.arch.atribucion = struct('PID_arranque',[m 'pid_esc1_v12A_arranque_flat.mat'],'PID_limites',[m 'pid_esc1_v12A_limites_flat.mat'], ...
                               'FUZZY_arranque',[m 'fuzzy_esc1_v12A_arranque_flat.mat'],'FUZZY_limites',[m 'fuzzy_esc1_v12A_limites_flat.mat']);
    C.arch.horizonte  = struct('P50',[m 'mpc_esc1_v12A_P50_flat.mat'],'P100',[m 'mpc_esc1_v12A_P100_flat.mat']);
    C.recon_casos     = {'C1b_wd2','C2b_wd2','Cable_wd2'};   % C1 y C2 del articulo y corte con el cable, Ciclos_Watchdog = 2
    C.recon_wd        = [2 2 2];
end
C.casos_falla       = 1:5; if strcmp(C.modelo_planta, 'v12'), C.casos_falla = 3:5; end   % con v12, C1 y C2 estan en Reconexion_v12
C.sesgo_C5          = [1 0.01 4500 100];   % C5: [sensor (1=Hw 2=Ho 3=Pg), sesgo [m o psi], ciclo de inicio, duracion]; el registro guarda la medicion sesgada
% --- escenario de 1000 s (Tabla del cronograma) ---
C.t_cambio       = [0 200 300 400 500 600 700 800 900 1000];            % instantes de cambio del escenario
C.escalones      = [0 1; 0 3; 400 1; 400 3; 500 2; 600 1; 600 3; 800 3; 900 2];   % [instante, variable 1=Hw 2=Ho 3=Pg]
C.perturbaciones = [200 300 700];                                       % perturbaciones aisladas de caudal
C.pert_tabla     = [300 700];                                           % las que reporta la tabla de rechazo y el Friedman
C.umbral_rec     = [3.3e-4 3.3e-4 0.01];                                % pico minimo para calcular t_rec [ft ft psi]
% --- esfuerzo de control ---
C.limite_cambio = struct('PID',[3 3 3],'FUZZY',[10 10 3],'MPC',[3.5 1.5 3]);   % [%/muestra] (u_w u_o u_g)
C.sat           = struct('PID',[1 99],'FUZZY',[1 99],'MPC',[2 99]);            % [min max] de apertura [%]
C.tol_sat       = 1.5e-4;                                                     % [puntos %]; el registro tiene 6 decimales
C.tol_lim       = 1e-3;                                                       % [puntos %]
% --- tiempo de ejecucion en el PLC (capturas Data / Diag_HIL del TIA Portal; no esta en los registros) ---
if strcmp(C.modelo_planta, 'v12')       % [PID Fuzzy MPC], de Diag_HIL al final de cada controlador (campana nominal)
    C.t_medio_ms = [0.0722 3.928 6.057];
    C.t_max_ms   = [0.106 18.95 28.55];
else
    C.t_medio_ms = [0.071 3.87 5.96];
    C.t_max_ms   = [0.108 18.8 34.0];
end
% --- robustez ---
C.tramos_ruido = [1 3 7];            % tramos con ruido de medicion
C.tramos_param = [2 6 9];            % tramos con solo variacion de parametros
C.tramos_pert  = [1 2 3 6 7 9];      % todos los tramos perturbados
C.inferencia = false;   % true = calcula ademas Friedman y Wilcoxon (exploratorio; el articulo no reporta pruebas de hipotesis)
C.hacer = struct('nominal',true,'diseno',true,'mpc_1212c',true,'tiempo',true,'latencia',true,'robustez',true,'fallas',true,'corte_cable',true,'tia_off',true);
if strcmp(C.modelo_planta, 'v12'), C.hacer.corte_cable = false; end   % el corte con cable de v12 esta en Reconexion_v12/Cable_wd2
end

%% ===================================== BLOQUES ======================================================
function B = bloque_validez(N, C)
% Validez de cada repeticion nominal: filas, tiempo real final, pausas de Unity (salto de t_real > 0.3 s) y, sobre todo, que cada
% repeticion arranque igual que la primera (misma apertura inicial y misma trayectoria en los primeros 10 s). Si el controlador del
% PLC no se reinicia entre repeticiones (por ejemplo, con pausaEntreRepeticiones_s = 0), la repeticion k arranca con la memoria
% del controlador de la repeticion anterior y su trayectoria deja de ser comparable con la nominal.
fprintf('\n---------- VALIDEZ DE LAS REPETICIONES NOMINALES ----------\n'); B = struct();
fprintf('%-7s %4s %7s %9s %9s %12s %12s   %s\n', 'Contr.', 'Rep.', 'Filas', 't_real fin', 'Salto max', 'dApertura0', 'dTrayect.', 'Veredicto');
nmal = 0;
for c = 1:3
    reps = N.(C.ctrl{c}).reps; r1 = reps{1}; B.(C.ctrl{c}) = true(1, numel(reps));
    for k = 1:numel(reps)
        R = reps{k}; salto = max(diff(R.treal));
        dap = max(abs(R.u(1,:) - r1.u(1,:)));                                   % [p.p.] frente a la repeticion 1
        n10 = min(100, size(R.y,1)); dtr = max(max(abs(R.y(1:n10,:) - r1.y(1:n10,:))));
        v = {};
        if size(R.y,1) ~= 10000, v{end+1} = 'filas'; end %#ok<AGROW>
        if abs(R.treal(end) - 1000) > 1.0, v{end+1} = 't_real final'; end %#ok<AGROW>
        if salto > 0.3, v{end+1} = sprintf('pausa de %.2f s', salto); end %#ok<AGROW>
        if k > 1 && (dap > 0.05 || dtr > 1e-3), v{end+1} = 'arranque distinto: el controlador no se reinicio'; end %#ok<AGROW>
        if isempty(v), txt = 'OK'; else, txt = strjoin(v, '; '); B.(C.ctrl{c})(k) = false; nmal = nmal + 1; end
        fprintf('%-7s %4d %7d %9.1f %9.3f %12.3f %12.4f   %s\n', C.etq{c}, k, size(R.y,1), R.treal(end), salto, dap, dtr, txt);
    end
end
% Comparacion de la primera repeticion con la de la sesion nominal anterior (opcional)
for c = 1:3
    f0 = buscar(C, C.arch.nominal_s1.(C.ctrl{c}));
    if isempty(f0), continue; end
    R0 = leer_corrida(f0{1}, C); R1 = N.(C.ctrl{c}).reps{1}; n = min(size(R0.y,1), size(R1.y,1));
    fprintf('  %-7s repeticion 1 frente a la de la sesion anterior: max|dy| = %.3g [ft, ft, psi], max|du| = %.3g [p.p.]\n', C.etq{c}, max(max(abs(R1.y(1:n,:) - R0.y(1:n,:)))), max(max(abs(R1.u(1:n,:) - R0.u(1:n,:)))));
end
if nmal > 0
    fprintf('  Atencion: %d repeticion(es) no cumplen. Si el arranque es distinto, revise que pausaEntreRepeticiones_s sea 3 en el Inspector de Unity:\n', nmal);
    fprintf('  esa pausa hace que el watchdog del PLC reinicie el controlador entre repeticiones. Las pausas de Unity (salto de t_real) se repiten la corrida.\n');
end
end

function B = bloque_nominal(N, C)
fprintf('\n---------- CAMPANA NOMINAL (repeticion 1 de cada controlador) ----------\n');
for c = 1:3
    nom = C.ctrl{c}; R = N.(nom).reps{1};
    fprintf('  %-6s %s\n', C.etq{c}, N.(nom).archivos{1});
    B.G{c} = m_global(R, C);
    B.E{c} = m_esfuerzo(R, nom, C);
    for i = 1:size(C.escalones,1)
        B.S{c,i} = m_escalon(R, C.escalones(i,2), C.escalones(i,1), C);
    end
    for j = 1:numel(C.perturbaciones)
        for v = 1:3, B.P{c,j,v} = m_perturbacion(R, v, C.perturbaciones(j), C); end
    end
end
% --- Tabla global ---
cab = {'Variable','Controlador','IAE','ISE','ITAE','RMSE'}; filas = {};
fprintf('\nTabla global: integrales del error en la prueba completa\n');
fprintf('%-10s %-8s %10s %10s %12s %8s\n', cab{:});
for v = 1:3
    for c = 1:3
        g = B.G{c}; fprintf('%-10s %-8s %10.4g %10.4g %12.1f %8.4f\n', C.var{v}, C.etq{c}, g.IAE(v), g.ISE(v), g.ITAE(v), g.RMSE(v));
        filas(end+1,:) = {C.var{v}, C.etq{c}, g.IAE(v), g.ISE(v), g.ITAE(v), g.RMSE(v)}; %#ok<AGROW>
    end
end
guardar_csv(C, 'tabla_global.csv', cab, filas);
% --- Tabla de esfuerzo ---
cab = {'Controlador','MV','TV [%]','Sat.','Lim.','Sobre lim.'}; filas = {};
fprintf('\nTabla de esfuerzo de control\n%-10s %-4s %8s %6s %6s %10s\n', cab{:});
for c = 1:3
    e = B.E{c};
    for j = 1:3
        fprintf('%-10s %-4s %8.0f %6d %6d %10d\n', C.etq{c}, C.mv{j}, e.TV(j), e.sat(j), e.lim(j), e.sobre(j));
        filas(end+1,:) = {C.etq{c}, C.mv{j}, e.TV(j), e.sat(j), e.lim(j), e.sobre(j)}; %#ok<AGROW>
    end
end
guardar_csv(C, 'tabla_esfuerzo.csv', cab, filas);
% --- Tabla de escalones ---
cab = {'t [s]','Variable','Amplitud','PID tr','PID ts','PID Mp','Fuzzy tr','Fuzzy ts','Fuzzy Mp','MPC tr','MPC ts','MPC Mp'}; filas = {};
fprintf('\nTabla de escalones de referencia: tr [s], ts [s], Mp [%%]\n');
fprintf('%5s %-10s %8s | %6s %6s %6s | %6s %6s %6s | %6s %6s %6s\n', 't','Variable','Ampl.','trPID','tsPID','MpPID','trFz','tsFz','MpFz','trMPC','tsMPC','MpMPC');
for i = 1:size(C.escalones,1)
    s1 = B.S{1,i}; s2 = B.S{2,i}; s3 = B.S{3,i};
    fprintf('%5d %-10s %8.2f | %s %s %s | %s %s %s | %s %s %s\n', C.escalones(i,1), C.var{C.escalones(i,2)}, s1.A, ...
        n2s(s1.tr,'%6.1f'), n2s(s1.ts,'%6.1f'), n2s(s1.Mp,'%6.2f'), n2s(s2.tr,'%6.1f'), n2s(s2.ts,'%6.1f'), n2s(s2.Mp,'%6.2f'), ...
        n2s(s3.tr,'%6.1f'), n2s(s3.ts,'%6.1f'), n2s(s3.Mp,'%6.2f'));
    filas(end+1,:) = {C.escalones(i,1), C.var{C.escalones(i,2)}, s1.A, s1.tr, s1.ts, s1.Mp, s2.tr, s2.ts, s2.Mp, s3.tr, s3.ts, s3.Mp}; %#ok<AGROW>
end
guardar_csv(C, 'tabla_escalones.csv', cab, filas);
% --- Tabla de perturbaciones ---
cab = {'t [s]','Variable','PID desv','PID trec','PID IAE','Fuzzy desv','Fuzzy trec','Fuzzy IAE','MPC desv','MPC trec','MPC IAE'}; filas = {};
fprintf('\nTabla de rechazo de perturbaciones de caudal: desviacion, t_rec [s], IAE de la ventana\n');
for j = 1:numel(C.perturbaciones)
    for v = 1:3
        p1 = B.P{1,j,v}; p2 = B.P{2,j,v}; p3 = B.P{3,j,v};
        fprintf('%5d %-10s | %11.3g %s %9.3g | %11.3g %s %9.3g | %11.3g %s %9.3g\n', C.perturbaciones(j), C.var{v}, ...
            p1.desv, n2s(p1.trec,'%6.1f'), p1.iae, p2.desv, n2s(p2.trec,'%6.1f'), p2.iae, p3.desv, n2s(p3.trec,'%6.1f'), p3.iae);
        filas(end+1,:) = {C.perturbaciones(j), C.var{v}, p1.desv, p1.trec, p1.iae, p2.desv, p2.trec, p2.iae, p3.desv, p3.trec, p3.iae}; %#ok<AGROW>
    end
end
guardar_csv(C, 'tabla_perturbaciones.csv', cab, filas);
% --- Comparacion descriptiva (sin pruebas de hipotesis): rangos medios y diferencia relativa del IAE frente al PID ---
X9 = zeros(size(C.escalones,1), 3);
for i = 1:size(C.escalones,1), for c = 1:3, X9(i,c) = B.S{c,i}.iae; end, end
X6 = []; idx = find(ismember(C.perturbaciones, C.pert_tabla));
for j = idx(:)', for v = 1:3, X6(end+1,:) = [B.P{1,j,v}.iae B.P{2,j,v}.iae B.P{3,j,v}.iae]; end, end %#ok<AGROW>
B.rm9 = rangos_medios(X9); B.rm6 = rangos_medios(X6);
fprintf('\nComparacion descriptiva sobre el IAE de cada evento (sin pruebas de hipotesis: los eventos de una prueba no son independientes)\n');
fprintf('  Rango medio PID / Fuzzy / MPC en los %d escalones: %.2f / %.2f / %.2f\n', size(X9,1), B.rm9);
fprintf('  Rango medio PID / Fuzzy / MPC en las %d combinaciones de perturbacion y variable: %.2f / %.2f / %.2f\n', size(X6,1), B.rm6);
a0 = C.t_cambio(2);   % fin de la ventana de arranque (200 s)
cab = {'Controlador','Prueba','H_w [%]','H_o [%]','P_g [%]'}; filas = {}; fprintf('\nDiferencia relativa del IAE frente al PID [%%]\n');
for c = 2:3
    for modo = 1:2
        if modo == 1, t0 = 0; rot = 'Completa'; else, t0 = a0; rot = 'Sin arranque'; end
        ipi = iae_desde(N.PID.reps{1}, t0, C); ic = iae_desde(N.(C.ctrl{c}).reps{1}, t0, C); d = 100*(ic - ipi)./ipi;
        fprintf('  %-6s %-13s %+7.1f %+7.1f %+7.1f\n', C.etq{c}, rot, d); filas(end+1,:) = {C.etq{c}, rot, d(1), d(2), d(3)}; %#ok<AGROW>
        B.dIAE_rel{c, modo} = d;
    end
end
guardar_csv(C, 'tabla_comparacion_descriptiva.csv', cab, filas);
if C.inferencia
    B.F9 = prueba_bloques(X9); B.F6 = prueba_bloques(X6);
    fprintf('\n[Exploratorio] Friedman y Wilcoxon exacto (sobre cocientes de IAE) con Holm\n');
    fprintf('  Escalones:      chi2=%.2f p=%.3f W=%.2f | Holm PID-Fz %.3f, PID-MPC %.3f, Fz-MPC %.3f\n', B.F9.chi2, B.F9.p, B.F9.W, B.F9.pholm);
    fprintf('  Perturbaciones: chi2=%.2f p=%.3f W=%.2f | Holm PID-Fz %.3f, PID-MPC %.3f, Fz-MPC %.3f\n', B.F6.chi2, B.F6.p, B.F6.W, B.F6.pholm);
end
% --- Resumen comparativo ---
cab = {'Metrica','PID','Fuzzy','MPC'}; 
ts_medio = zeros(1,3); mp_max = zeros(1,3); tvt = zeros(1,3);
for c = 1:3
    ts = cellfun(@(s) s.ts, B.S(c,:)); mp = cellfun(@(s) s.Mp, B.S(c,:));
    ts_medio(c) = mean(ts(~isnan(ts))); mp_max(c) = max(mp); tvt(c) = sum(B.E{c}.TV);
end
filas = {'ts medio de los escalones [s]', ts_medio(1), ts_medio(2), ts_medio(3); 'Mp maximo [%]', mp_max(1), mp_max(2), mp_max(3); ...
         'TV total [%]', tvt(1), tvt(2), tvt(3); 'Tiempo de ejecucion medio [ms] (configuracion)', C.t_medio_ms(1), C.t_medio_ms(2), C.t_medio_ms(3); ...
         'Tiempo de ejecucion maximo [ms] (configuracion)', C.t_max_ms(1), C.t_max_ms(2), C.t_max_ms(3)};
fprintf('\nResumen comparativo\n');
for r = 1:size(filas,1), fprintf('  %-50s %9.4g %9.4g %9.4g\n', filas{r,:}); end
guardar_csv(C, 'tabla_resumen.csv', cab, filas);
% --- Variabilidad entre repeticiones (IAE) ---
fprintf('\nCoeficiente de variacion del IAE entre repeticiones nominales [%%] (Hw, Ho, Pg)\n');
for c = 1:3
    nr = numel(N.(C.ctrl{c}).reps);
    if nr > 1
        M = zeros(nr,3); for k = 1:nr, M(k,:) = m_global(N.(C.ctrl{c}).reps{k}, C).IAE; end
        cv = 100*std(M,0,1)./mean(M,1); fprintf('  %-6s n=%d: %.4f  %.4f  %.4f\n', C.etq{c}, nr, cv);
        B.cv_iae(c,:) = cv;
    end
end
end

function B = bloque_tiempo(N, C)
fprintf('\n---------- TEMPORIZACION DEL LAZO (repeticion 1 de cada controlador) ----------\n');
cab = {'Controlador','Periodo medio [s]','Jitter [s]','p95 [s]','p99 [s]','Max [s]','dt>1.5Ts [%]','Deriva [s]','Retencion [%]','Retardo 0 [%]'}; filas = {};
fprintf('%-10s %9s %8s %7s %7s %7s %9s %9s %10s %10s\n', 'Contr.','medio','jitter','p95','p99','max','dt>1.5Ts%','deriva','retenc.%','retardo0%');
B = struct();
for c = 1:3
    nom = C.ctrl{c}; if isempty(N.(nom).reps), continue; end
    R = N.(nom).reps{1}; T = temporizacion(R, C);
    Dg = diag_de(N.(nom).archivos{1}, buscar(C, C.arch.diag_nominal));
    ret = NaN; r0 = NaN;
    if ~isempty(Dg)
        ok = Dg.sint == 0 & Dg.ciclo > 1;
        ret = 100*mean(Dg.ret(ok)); r0 = 100*mean(Dg.retardo(ok) == 0);
    end
    T.ret = ret; T.retardo0 = r0; B.(nom) = T;
    fprintf('%-10s %9.4f %8.4f %7.3f %7.3f %7.3f %9.2f %9.2f %10.2f %10.2f\n', C.etq{c}, T.media, T.jitter, T.p95, T.p99, T.max, T.pct15, T.deriva, ret, r0);
    filas(end+1,:) = {C.etq{c}, T.media, T.jitter, T.p95, T.p99, T.max, T.pct15, T.deriva, ret, r0}; %#ok<AGROW>
end
if ~isempty(filas), guardar_csv(C, 'tabla_tiempo_real.csv', cab, filas); end
% --- variabilidad entre repeticiones nominales ---
fprintf('\nVariabilidad entre repeticiones nominales (minimo - maximo): periodo medio, jitter, p99 y maximo [s]\n');
cab2 = {'Controlador','Repeticiones','Periodo medio min','Periodo medio max','Jitter min','Jitter max','p99 min','p99 max','Max min','Max max'}; filas2 = {};
for c = 1:3
    nom = C.ctrl{c}; nr = numel(N.(nom).reps); if nr < 2, continue; end
    M = zeros(nr, 4);
    for k = 1:nr, Tk = temporizacion(N.(nom).reps{k}, C); M(k,:) = [Tk.media Tk.jitter Tk.p99 Tk.max]; end
    r = [min(M(:,1)) max(M(:,1)) min(M(:,2)) max(M(:,2)) min(M(:,3)) max(M(:,3)) min(M(:,4)) max(M(:,4))];
    fprintf('  %-6s n=%d | medio %.4f-%.4f | jitter %.4f-%.4f | p99 %.3f-%.3f | max %.3f-%.3f\n', C.etq{c}, nr, r);
    filas2(end+1,:) = {C.etq{c}, nr, r(1), r(2), r(3), r(4), r(5), r(6), r(7), r(8)}; %#ok<AGROW>
end
if ~isempty(filas2), guardar_csv(C, 'tabla_tiempo_variabilidad.csv', cab2, filas2); end
end

function B = bloque_latencia(N, C)
fprintf('\n---------- LATENCIA DE LA COMUNICACION PLC-UNITY (todas las repeticiones nominales) ----------\n');
lista = buscar(C, C.arch.diag_nominal); B = struct();
if isempty(lista), fprintf('  (sin archivos Diag_Com nominales: %s)\n', C.arch.diag_nominal); return; end
cab = {'Indicador','PID','Fuzzy','MPC'}; V = nan(9,3);
for c = 1:3
    nom = C.ctrl{c}; lec = []; esc = []; lat = []; nciclos = 0; nolei = 0;
    usados = {};
    for k = 1:numel(N.(nom).archivos)
        Dg = diag_de(N.(nom).archivos{k}, lista); if isempty(Dg), continue; end
        if any(strcmp(usados, Dg.archivo)), continue; end   % el mismo registro cubre varias repeticiones
        usados{end+1} = Dg.archivo; %#ok<AGROW>
        ok = Dg.sint == 0;
        nciclos = nciclos + numel(Dg.ciclo); nolei = nolei + nansum_(Dg.saltados);
        lec = [lec; Dg.lec(ok & Dg.lec > 0)]; esc = [esc; Dg.esc(ok & Dg.esc > 0)]; lat = [lat; Dg.lat(ok & ~isnan(Dg.lat))]; %#ok<AGROW>
    end
    if isempty(lec), continue; end
    V(:,c) = [nciclos; nolei; mean(lec); percentil(lec,99); mean(esc); percentil(esc,99); mean(lat); percentil(lat,99); percentil(lat,95)];
    B.(nom).p95_lat = percentil(lat,95);
end
nombres = {'Ciclos del PLC analizados','Ciclos no leidos por Unity','Lectura S7, media [ms]','Lectura S7, p99 [ms]','Escritura S7, media [ms]','Escritura S7, p99 [ms]','Latencia del lazo, media [ms]','Latencia del lazo, p99 [ms]','Latencia del lazo, p95 [ms]'};
filas = {};
for r = 1:9, fprintf('  %-34s %10.6g %10.6g %10.6g\n', nombres{r}, V(r,:)); filas(end+1,:) = {nombres{r}, V(r,1), V(r,2), V(r,3)}; end %#ok<AGROW>
guardar_csv(C, 'tabla_latencia.csv', cab, filas); B.V = V;
end

function B = bloque_tia_desconectado(N, C)
% Efecto del monitoreo en linea de TIA Portal: compara las repeticiones con TIA desconectado (carpeta TIA_desconectado) con las de
% TIA en linea. Si la sesion de TIA_desconectado alterna repeticiones en linea y desconectadas (C.tia_reps_offline = [2 4], por
% ejemplo), la referencia en linea sale de la misma sesion; si todas estan desconectadas, sale de la sesion nominal en linea.
% Las repeticiones de una sesion se separan por los huecos de mas de 0.5 s del Diag_Com (pausa entre repeticiones).
fprintf('\n---------- TIA PORTAL DESCONECTADO FRENTE A TIA EN LINEA ----------\n'); B = struct();
lista = buscar(C, C.arch.tia_off_diag);
if isempty(lista), fprintf('  (sin sesiones en %s)\n', C.arch.tia_off_diag); return; end
cab = {'Controlador','Condicion','Repeticiones','Jitter [ms]','p99 dt [ms]','Max dt [ms]','Lectura media [ms]','Lectura p99 [ms]','Escritura media [ms]','Escritura p99 [ms]','Latencia media [ms]','Latencia p99 [ms]','Ciclos no leidos','Ciclos retenidos'};
filas = {};
fprintf('%-7s %-13s %5s %8s %8s %8s %16s %16s %16s %7s %7s\n', 'Contr.', 'Condicion', 'Reps', 'Jitter', 'p99 dt', 'Max dt', 'Lectura med/p99', 'Escritura med/p99', 'Lazo med/p99', 'NoLeid', 'Retenid');
for c = 1:3
    f = buscar(C, C.arch.tia_off.(C.ctrl{c})); if isempty(f), continue; end
    nom = C.ctrl{c}; Dg = diag_de(f{1}, lista);
    if isempty(Dg), fprintf('  %s: sin Diag_Com que corresponda a %s\n', C.etq{c}, f{1}); continue; end
    big = Dg.dt > 500; big(isnan(big)) = false; seg = max(cumsum(big), 1); nseg = max(seg);
    if nseg ~= numel(f), fprintf('  AVISO %s: %d repeticiones en el Diag_Com y %d archivos Datos\n', C.etq{c}, nseg, numel(f)); end
    if isempty(C.tia_reps_offline), off = 1:nseg; else, off = C.tia_reps_offline(C.tia_reps_offline <= nseg); end
    on = setdiff(1:nseg, off);
    grupos = {'desconectado', off, Dg, f, 1}; 
    if ~isempty(on)
        grupos(2,:) = {'en linea', on, Dg, f, 1};
    else
        Dn = diag_de(N.(nom).archivos{1}, buscar(C, C.arch.diag_nominal));
        if isempty(Dn), fprintf('  %s: sin referencia en linea\n', C.etq{c}); continue; end
        bign = Dn.dt > 500; bign(isnan(bign)) = false; segn = max(cumsum(bign), 1);
        grupos(2,:) = {'en linea', 1:max(segn), Dn, N.(nom).archivos, 0};
    end
    V = zeros(2, 10);
    for g = 1:2
        D = grupos{g,3}; reps = grupos{g,2}; archivos = grupos{g,4};
        if grupos{g,5}, sg = seg; else, sg = segn; end
        m = ismember(sg, reps); ok = m & D.sint == 0;
        lec = D.lec(ok & D.lec > 0); esc = D.esc(ok & D.esc > 0); lat = D.lat(ok & ~isnan(D.lat));
        jit = nan(1, numel(reps)); p99 = jit; mx = jit;
        for q = 1:numel(reps)
            if reps(q) <= numel(archivos), Tq = temporizacion(leer_corrida(archivos{reps(q)}, C), C); jit(q) = Tq.jitter; p99(q) = Tq.p99; mx(q) = Tq.max; end
        end
        V(g,:) = [mean(jit,'omitnan')*1000, mean(p99,'omitnan')*1000, max(mx)*1000, mean(lec), percentil(lec,99), mean(esc), percentil(esc,99), mean(lat), percentil(lat,99), nansum_(D.saltados(m))];
        nret = sum(D.ret(m) == 1);
        fprintf('%-7s %-13s %5d %8.2f %8.1f %8.1f %7.2f /%7.2f %7.2f /%7.2f %7.2f /%7.2f %7d %7d\n', C.etq{c}, grupos{g,1}, numel(reps), V(g,1), V(g,2), V(g,3), V(g,4), V(g,5), V(g,6), V(g,7), V(g,8), V(g,9), round(V(g,10)), nret);
        filas(end+1,:) = {C.etq{c}, grupos{g,1}, numel(reps), V(g,1), V(g,2), V(g,3), V(g,4), V(g,5), V(g,6), V(g,7), V(g,8), V(g,9), V(g,10), nret}; %#ok<AGROW>
    end
    d = V(1,:) - V(2,:); B.(nom).dif = d;
    ok_ms = abs(d([4 6 8])) <= C.tia_umbral_ms;
    fprintf('  %s: desconectado - en linea: lectura %+.2f ms, escritura %+.2f ms, latencia %+.2f ms, jitter %+.2f ms -> %s\n', C.etq{c}, d(4), d(6), d(8), d(1), ...
        ternario_(all(ok_ms), sprintf('sin diferencia mayor que %g ms en lectura, escritura ni latencia', C.tia_umbral_ms), sprintf('diferencia mayor que %g ms en alguna media', C.tia_umbral_ms)));
    % las trayectorias de una corrida nominal no deben cambiar con el monitoreo
    R1 = leer_corrida(f{off(1)}, C); R0 = N.(nom).reps{1}; n = min(size(R1.y,1), size(R0.y,1));
    fprintf('  %s: primera repeticion desconectada frente a la nominal en linea: max|dy| = %.3g, max|du| = %.3g\n', C.etq{c}, max(max(abs(R1.y(1:n,:) - R0.y(1:n,:)))), max(max(abs(R1.u(1:n,:) - R0.u(1:n,:)))));
end
if ~isempty(filas), guardar_csv(C, 'tabla_tia_desconectado.csv', cab, filas); end
end

function s = ternario_(c, a, b)
if c, s = a; else, s = b; end
end

function B = bloque_validez_robustez(C)
% Validez de las repeticiones de robustez: filas, tiempo real final, pausas de Unity (salto de t_real > 0.3 s) y apertura de la
% primera fila igual que la de la repeticion 1 (el controlador arranca desde su estado inicial). Las trayectorias no se comparan
% entre repeticiones porque cada una usa otra realizacion de ruido y de parametros (semilla + repeticion - 1).
fprintf('\n---------- VALIDEZ DE LAS REPETICIONES DE ROBUSTEZ ----------\n'); B = struct(); nmal = 0;
fprintf('%-7s %4s %7s %9s %9s %12s   %s\n', 'Contr.', 'Rep.', 'Filas', 't_real fin', 'Salto max', 'dApertura0', 'Veredicto');
for c = 1:3
    f = buscar(C, C.arch.robustez.(C.ctrl{c})); if isempty(f), continue; end
    r1 = leer_corrida(f{1}, C); B.(C.ctrl{c}) = true(1, numel(f));
    for k = 1:numel(f)
        R = leer_corrida(f{k}, C); salto = max(diff(R.treal)); dap = max(abs(R.u(1,:) - r1.u(1,:))); v = {};
        if size(R.y,1) ~= 10000, v{end+1} = 'filas'; end %#ok<AGROW>
        if abs(R.treal(end) - 1000) > 1.0, v{end+1} = 't_real final'; end %#ok<AGROW>
        if salto > 0.3, v{end+1} = sprintf('pausa de %.2f s', salto); end %#ok<AGROW>
        if k > 1 && dap > 0.05, v{end+1} = 'arranque distinto: el controlador no se reinicio'; end %#ok<AGROW>
        if isempty(v), txt = 'OK'; else, txt = strjoin(v, '; '); B.(C.ctrl{c})(k) = false; nmal = nmal + 1; end
        fprintf('%-7s %4d %7d %9.1f %9.3f %12.3f   %s\n', C.etq{c}, k, size(R.y,1), R.treal(end), salto, dap, txt);
    end
end
if nmal > 0, fprintf('  Atencion: %d repeticion(es) de robustez no cumplen; las pausas de Unity se corrigen repitiendo la corrida con la misma semilla.\n', nmal); end
end

function B = bloque_robustez(N, C)
fprintf('\n---------- ROBUSTEZ (ruido de medicion y parametros), por tramos de 100 s ----------\n');
B = struct(); runs = cell(1,3); nrep = zeros(1,3);
for c = 1:3
    f = buscar(C, C.arch.robustez.(C.ctrl{c})); nrep(c) = numel(f);
    for k = 1:numel(f), runs{c}{k} = leer_corrida(f{k}, C); end
end
if any(nrep == 0), fprintf('  (faltan corridas de robustez: %s)\n', C.arch.robustez.PID); return; end
if numel(unique(nrep)) > 1, fprintf('  AVISO: numero distinto de repeticiones por controlador: %s\n', mat2str(nrep)); end
nr = min(nrep); ntr = 10;
TVn = zeros(ntr,3,3); IAn = zeros(ntr,3,3);          % nominal: tramo x variable x controlador
TVr = zeros(ntr,3,3,nr); IAr = zeros(ntr,3,3,nr);    % robustez: tramo x variable x controlador x repeticion
for c = 1:3
    [TVn(:,:,c), IAn(:,:,c)] = por_tramo(N.(C.ctrl{c}).reps{1}, C);
    for k = 1:nr, [TVr(:,:,c,k), IAr(:,:,c,k)] = por_tramo(runs{c}{k}, C); end
end
tr = C.tramos_ruido; tp = C.tramos_param; tt = C.tramos_pert;
% --- efecto del ruido: media de los tramos con ruido y de las repeticiones ---
fprintf('\nEfecto del ruido de medicion: media de los tramos %s y de %d repeticiones\n', mat2str(tr), nr);
cab = {'Metrica por tramo de 100 s','PID','Fuzzy','MPC'}; filas = {};
for j = 1:3
    m = zeros(1,3); for c = 1:3, m(c) = mean(reshape(TVr(tr+1,j,c,1:nr), [], 1)); end
    fprintf('  TV %-4s [%%] %10.0f %10.0f %10.0f\n', C.mv{j}, m); filas(end+1,:) = {['TV ' C.mv{j} ' [%]'], m(1), m(2), m(3)}; %#ok<AGROW>
end
for v = 1:3
    m = zeros(1,3); for c = 1:3, m(c) = mean(reshape(IAr(tr+1,v,c,1:nr), [], 1)); end
    fprintf('  IAE %-10s %10.4g %10.4g %10.4g\n', C.var{v}, m); filas(end+1,:) = {['IAE ' C.var{v}], m(1), m(2), m(3)}; %#ok<AGROW>
end
guardar_csv(C, 'tabla_robustez_ruido.csv', cab, filas);
mx = max(reshape(TVn(tr+1,:,:), [], 1)); fprintf('  Sin ruido (corrida nominal), TV maximo por tramo en esos tramos: %.0f %%\n', mx); B.tv_nominal_max = mx;
% --- razon de TV entre controladores y Friedman sobre TV total con ruido (bloques = tramo x repeticion) ---
XTV = zeros(numel(tr)*nr, 3); b = 0;
for i = 1:numel(tr), for k = 1:nr, b = b + 1; for c = 1:3, XTV(b,c) = sum(TVr(tr(i)+1,:,c,k)); end, end, end
orden_ok = sum(XTV(:,3) < XTV(:,1) & XTV(:,1) < XTV(:,2));
fprintf('  Orden de menor a mayor TV total (MPC < PID < Fuzzy) en %d de %d bloques con ruido (tramo x repeticion)\n', orden_ok, size(XTV,1)); B.orden_ok = orden_ok;
if C.inferencia
    B.F_ruido = prueba_bloques(XTV);
    fprintf('  [Exploratorio] Friedman sobre la TV total con ruido: chi2=%.1f p=%.4f W=%.2f | Holm PID-Fz %.4f, PID-MPC %.4f, Fz-MPC %.4f\n', B.F_ruido.chi2, B.F_ruido.p, B.F_ruido.W, B.F_ruido.pholm);
end
mT = zeros(3,3); for c = 1:3, for j = 1:3, mT(c,j) = mean(reshape(TVr(tr+1,j,c,1:nr), [], 1)); end, end
fprintf('  Cociente de TV por valvula: PID/MPC = %s | Fuzzy/MPC = %s\n', mat2str(round(100*mT(1,:)./mT(3,:))/100), mat2str(round(100*mT(2,:)./mT(3,:))/100));
% --- degradacion del IAE respecto al mismo tramo nominal ---
deg = @(v,tramos) degradacion(IAr, IAn, v, tramos, nr);
% (la degradacion media se imprime solo en modo exploratorio: con un IAE nominal casi nulo, el cociente se infla)
if C.inferencia
fprintf('\nDegradacion media del IAE respecto al mismo tramo nominal [%%] (PID / Fuzzy / MPC)\n');
for v = 1:3
    Xd = deg(v, tp); fprintf('  %-10s tramos de parametros %s: %7.1f %7.1f %7.1f\n', C.var{v}, mat2str(tp), mean(Xd, 1));
    if C.inferencia, Fd = prueba_bloques(Xd); B.F_param{v} = Fd; fprintf('    [Exploratorio] chi2=%.2f p=%.3f W=%.2f\n', Fd.chi2, Fd.p, Fd.W); end
end
Xd = deg(3, tt); fprintf('  %-10s todos los tramos perturbados %s: %7.1f %7.1f %7.1f\n', C.var{3}, mat2str(tt), mean(Xd, 1));
if C.inferencia, Fd = prueba_bloques(Xd); B.F_pert_Pg = Fd; fprintf('    [Exploratorio] chi2=%.2f p=%.4f W=%.2f\n', Fd.chi2, Fd.p, Fd.W); end
end
fprintf('\nPeor caso de las %d repeticiones (aumento del IAE) [%%]:   PID     Fuzzy     MPC\n', nr);
for casos = {[6 1],[6 3],[9 2]}
    t0 = casos{1}(1); v = casos{1}(2); w = zeros(1,3);
    for c = 1:3, w(c) = max(squeeze(100*(IAr(t0+1,v,c,1:nr) - IAn(t0+1,v,c))/IAn(t0+1,v,c))); end
    fprintf('  tramo %d, %-10s %22.1f %8.1f %8.1f\n', t0, C.var{v}, w);
end
B.TVr = TVr; B.IAr = IAr; B.TVn = TVn; B.IAn = IAn;
end

function X = degradacion(IAr, IAn, v, tramos, nr)
X = zeros(numel(tramos)*nr, 3); b = 0;
for i = 1:numel(tramos)
    for k = 1:nr
        b = b + 1;
        for c = 1:3, X(b,c) = 100*(IAr(tramos(i)+1,v,c,k) - IAn(tramos(i)+1,v,c))/IAn(tramos(i)+1,v,c); end
    end
end
end

function B = bloque_fallas(N, C, modo)
if strcmp(modo,'fallas')
    fprintf('\n---------- FALLAS DE COMUNICACION EMULADAS (efecto frente a la corrida nominal) ----------\n');
    casos = C.casos_falla;
else
    fprintf('\n---------- CORTES CON EL CABLE FISICO RETIRADO (efecto frente a la corrida nominal) ----------\n');
    casos = 0;
end
cab = {'Caso','Controlador','Archivo','Pasos sin accion','Ciclos PLC entre lecturas','Ciclos retenidos','Salto uw [pts]','Salto uo [pts]','Salto ug [pts]', ...
       'dIAE Hw [%]','dIAE Ho [%]','dIAE Pg [%]','dTV uw','dTV uo','dTV ug','Desv.max Hw [ft]','Desv.max Ho [ft]','Desv.max Pg [psi]','Retencion [%]','Retardo max'};
filas = {}; B = struct();
fprintf('%-5s %-6s %6s %8s %9s | %7s %7s %7s | %6s %6s %6s | %6s %6s %6s\n','Caso','Contr.','sin acc','ciclos','retenidos','duw','duo','dug','dIAEw','dIAEo','dIAEg','dTVw','dTVo','dTVg');
for cs = casos
    if strcmp(modo,'fallas'), dlist = buscar(C, sprintf(C.arch.diag_fallas, cs)); else, dlist = buscar(C, C.arch.diag_corte); end
    for c = 1:3
        nom = C.ctrl{c};
        if strcmp(modo,'fallas'), fl = buscar(C, sprintf(C.arch.fallas, C.carp.(nom), nom, cs)); else, fl = buscar(C, sprintf(C.arch.corte_cable, nom)); end
        for k = 1:numel(fl)
            R = leer_corrida(fl{k}, C); Rn = N.(nom).reps{1};
            if strcmp(modo,'fallas') && cs == 5, R = quitar_sesgo(R, C); end   % C5: errores con el nivel real, no con la medicion sesgada
            Gf = m_global(R, C); Gn = m_global(Rn, C); Ef = m_esfuerzo(R, nom, C); En = m_esfuerzo(Rn, nom, C);
            dI = 100*(Gf.IAE - Gn.IAE)./Gn.IAE; dT = Ef.TV - En.TV; dv = max(abs(R.y - Rn.y), [], 1);
            Dg = diag_de(fl{k}, dlist); K = struct('hay',false); ret = NaN; rmax = NaN;
            if ~isempty(Dg)
                K = analizar_corte(Dg, R, C); ok = Dg.sint == 0 & Dg.ciclo > 1;
                ret = 100*mean(Dg.ret(ok)); rmax = max(Dg.retardo(ok));
            end
            if K.hay, nsin = K.n_sint; cp = K.ciclos_plc; rt = K.retenidos; sj = K.salto; else, nsin = NaN; cp = NaN; rt = NaN; sj = [NaN NaN NaN]; end
            etiqueta = cs; if cs == 0, etiqueta = k; end
            [~, nombre] = fileparts(fl{k});
            fprintf('%-5d %-6s %6s %8s %9s | %7s %7s %7s | %6.1f %6.1f %6.1f | %6.0f %6.0f %6.0f\n', etiqueta, C.etq{c}, n2s(nsin,'%6d'), n2s(cp,'%8d'), n2s(rt,'%9d'), ...
                n2s(sj(1),'%7.1f'), n2s(sj(2),'%7.1f'), n2s(sj(3),'%7.1f'), dI, dT);
            filas(end+1,:) = {etiqueta, C.etq{c}, nombre, nsin, cp, rt, sj(1), sj(2), sj(3), dI(1), dI(2), dI(3), dT(1), dT(2), dT(3), dv(1), dv(2), dv(3), ret, rmax}; %#ok<AGROW>
            B.(sprintf('c%d_%s_%d', cs, nom, k)) = struct('dIAE', dI, 'dTV', dT, 'corte', K, 'archivo', fl{k}); %#ok<AGROW>
        end
    end
end
if isempty(filas), fprintf('  (sin archivos para esta campana)\n'); return; end
if strcmp(modo,'fallas'), guardar_csv(C, 'tabla_fallas.csv', cab, filas); else, guardar_csv(C, 'tabla_corte_cable.csv', cab, filas); end
fprintf('  dIAE = cambio porcentual del IAE; dTV = cambio de la variacion total [puntos %%]; "retenidos" = ciclos del PLC entre la ultima lectura\n');
fprintf('  previa al corte y la primera posterior, menos los 10 que el controlador ejecuta antes de que actue el watchdog.\n');
end

function R = quitar_sesgo(R, C)
% En C5 Unity registra la medicion que recibe el PLC (con sesgo). Para el IAE y la desviacion se usa el valor real:
% filas sensorInicioCiclo+1 .. sensorInicioCiclo+duracion del registro (t = 450.0 a 459.9 s).
s = C.sesgo_C5; v = s(1); b = s(2); if v <= 2, b = b*C.m2ft; end
k = (s(3)+1):min(s(3)+s(4), size(R.y,1));
R.y(k, v) = R.y(k, v) - b;
end

function B = bloque_reconexion(N, C)
% Cortes de comunicacion emulados (Datos/Reconexion/<caso>/<Ctrl>/). Una carpeta puede tener varias sesiones, cada una con su
% Diag_Com: las corridas se agrupan por el Diag_Com que les corresponde y, dentro de cada sesion, las repeticiones se separan por
% los huecos de mas de 0.5 s que no siguen a un bloque sintetico (la pausa entre repeticiones). Una corrida suelta es una sesion de
% una repeticion. Casos: C1b (corte de 5 s a los 385 s, regimen establecido), C2b (a los 400 s, como C2) y el corte con cable,
% con Ciclos_Watchdog = 10 (wd10) o 2 (wd2). Todo se compara con la repeticion 1 nominal del mismo controlador.
fprintf('\n---------- RECONEXION: CORTES EMULADOS ----------\n'); B = struct();
cab = {'Caso','Controlador','Sesion','Rep','Pasos sin accion','Ciclos PLC en el corte','Ciclos retenidos','Salto uw [pts]','Salto uo [pts]','Salto ug [pts]', ...
       'dIAE Hw [%]','dIAE Ho [%]','dIAE Pg [%]','dIAE 100 s Hw [%]','dIAE 100 s Ho [%]','dIAE 100 s Pg [%]','dTV uw','dTV uo','dTV ug', ...
       'Desv.max Hw [ft]','Desv.max Ho [ft]','Desv.max Pg [psi]','Recuperacion [s]','Salto de t_real max [s]'};
filas = {}; tol = [0.003 0.003 0.05];
for q = 1:numel(C.recon_casos)
    caso = C.recon_casos{q}; wd = C.recon_wd(q); hay = false;
    for c = 1:3
        nom = C.ctrl{c}; fl = buscar(C, sprintf(C.arch.recon_datos, caso, C.carp.(nom), nom));
        if isempty(fl), continue; end
        dlist = buscar(C, sprintf(C.arch.recon_diag, caso, C.carp.(nom)));
        % cada corrida pertenece a la sesion (Diag_Com) mas reciente que empezo antes que ella, con 2 min de tolerancia
        tsd = cellfun(@marca_tiempo, dlist); [~, oo] = sort(cellfun(@marca_tiempo, fl)); fl = fl(oo);
        ses = zeros(1, numel(fl)); Dgs = {}; ids = [];
        for k = 1:numel(fl)
            cand = find(tsd <= marca_tiempo(fl{k}) + 120); if isempty(cand), continue; end
            [~, im] = max(tsd(cand)); p = cand(im); pos = find(ids == p, 1);
            if isempty(pos), ids(end+1) = p; Dgs{end+1} = leer_diag(dlist{p}); pos = numel(ids); end %#ok<AGROW>
            ses(k) = pos;
        end
        if ~any(ses), fprintf('  %s %s: sin Diag_Com que corresponda\n', caso, C.etq{c}); continue; end
        if ~hay, fprintf('Caso %s (Ciclos_Watchdog = %d)\n%-7s %3s %3s %7s %8s %9s | %6s %6s %6s | %7s %7s %7s | %8s %6s\n', caso, wd, 'Contr.', 'Ses', 'Rep', 'sin acc', 'ciclos', 'retenidos', 'duw', 'duo', 'dug', 'dIAEw', 'dIAEo', 'dIAEg', 'desv.Hw', 'rec [s]'); hay = true; end
        Rn = N.(nom).reps{1}; Gn = m_global(Rn, C); En = m_esfuerzo(Rn, nom, C);
        for sidx = 1:numel(Dgs)
            Dg = Dgs{sidx}; sint = Dg.sint == 1; prev = [false; sint(1:end-1)]; fr = (Dg.dt > 500) & ~prev; fr(isnan(fr)) = false; fr(1:min(3,numel(fr))) = false; seg = 1 + cumsum(fr);
            idxf = find(ses == sidx);
            for k = 1:numel(idxf)
                R = leer_corrida(fl{idxf(k)}, C); m = seg == k;
                Dk = struct(); fn = fieldnames(Dg);
                for j = 1:numel(fn), v = Dg.(fn{j}); if numel(v) == numel(m), Dk.(fn{j}) = v(m); else, Dk.(fn{j}) = v; end, end
                K = analizar_corte(Dk, R, C, double(k > 1), wd);
                Gf = m_global(R, C); Ef = m_esfuerzo(R, nom, C); dI = 100*(Gf.IAE - Gn.IAE)./Gn.IAE; dT = Ef.TV - En.TV;
                dv = max(abs(R.y - Rn.y), [], 1);
                if K.hay
                    t0 = K.t_sim_ini; t1 = t0 + K.n_sint*C.Ts; w = R.t >= t0 & R.t < t0 + 100;
                    aw = sum(abs(R.r(w,:) - R.y(w,:)), 1)*C.Ts; an = sum(abs(Rn.r(w,:) - Rn.y(w,:)), 1)*C.Ts; dIw = 100*(aw - an)./max(an, 1e-9);
                    dif = abs(R.y - Rn.y); fu = find(any(dif > repmat(tol, size(dif,1), 1), 2), 1, 'last');
                    if isempty(fu) || R.t(fu) <= t1, rec = 0; else, rec = R.t(fu) - t1; end
                    nsin = K.n_sint; cp = K.ciclos_plc; rt = K.retenidos; sj = K.salto;
                else
                    nsin = NaN; cp = NaN; rt = NaN; sj = [NaN NaN NaN]; dIw = [NaN NaN NaN]; rec = NaN;
                end
                fprintf('%-7s %3d %3d %7s %8s %9s | %6s %6s %6s | %7.2f %7.2f %7.2f | %8.4f %6.1f\n', C.etq{c}, sidx, k, n2s(nsin,'%7d'), n2s(cp,'%8d'), n2s(rt,'%9d'), n2s(sj(1),'%6.1f'), n2s(sj(2),'%6.1f'), n2s(sj(3),'%6.1f'), dI, dv(1), rec);
                filas(end+1,:) = {caso, C.etq{c}, sidx, k, nsin, cp, rt, sj(1), sj(2), sj(3), dI(1), dI(2), dI(3), dIw(1), dIw(2), dIw(3), dT(1), dT(2), dT(3), dv(1), dv(2), dv(3), rec, max(diff(R.treal))}; %#ok<AGROW>
                B.(sprintf('%s_%s_s%d_r%d', caso, nom, sidx, k)) = struct('dIAE', dI, 'dIAE100', dIw, 'dTV', dT, 'corte', K, 'rec', rec);
            end
        end
    end
end
if isempty(filas), fprintf('  (sin sesiones en Datos/Reconexion/)\n'); return; end
guardar_csv(C, 'tabla_reconexion.csv', cab, filas);
fprintf('  dIAE: cambio del IAE de toda la corrida frente a la nominal; recuperacion: tiempo desde el fin del corte hasta volver a +-0.003 ft / +-0.05 psi.\n');
end

function B = bloque_diseno(N, C)
% Compara la simulacion de diseno (Simulink) con la repeticion 1 nominal de la CPU 1212C.
% Para el MPC, la simulacion es la del MPC completo y la CPU ejecuta el MPC de cotas.
fprintf('\n---------- DISENO (SIMULINK) FRENTE A LA CPU 1212C (repeticion 1 nominal) ----------\n');
B = struct(); cab = {'Controlador','IAE Hw Simulink','IAE Ho Simulink','IAE Pg Simulink','dIAE Hw [%]','dIAE Ho [%]','dIAE Pg [%]', ...
    'max|dtr| [s]','max|dts| [s]','max|dMp| [pts]','Escalon de mayor dts','TV uw Simulink','TV uo Simulink','TV ug Simulink','TV uw CPU','TV uo CPU','TV ug CPU'};
filas = {};
for c = 1:3
    nom = C.ctrl{c}; f = buscar(C, C.arch.diseno.(nom));
    if isempty(f), fprintf('  (sin archivo de diseno para %s: %s)\n', C.etq{c}, C.arch.diseno.(nom)); continue; end
    H = N.(nom).reps{1}; S = leer_flat(f{1}, C, numel(H.t));
    gS = m_global(S, C); gH = m_global(H, C); eS = m_esfuerzo(S, nom, C); eH = m_esfuerzo(H, nom, C);
    dI = 100*(gH.IAE - gS.IAE)./gS.IAE;
    ns = size(C.escalones, 1); dtr = zeros(1, ns); dts = zeros(1, ns); dmp = zeros(1, ns);
    for i = 1:ns
        a = m_escalon(S, C.escalones(i,2), C.escalones(i,1), C); b = m_escalon(H, C.escalones(i,2), C.escalones(i,1), C);
        dtr(i) = b.tr - a.tr; dts(i) = b.ts - a.ts; dmp(i) = b.Mp - a.Mp;
    end
    [~, im] = max(abs(dts)); etq_esc = sprintf('%d s, %s', C.escalones(im,1), C.var{C.escalones(im,2)});
    fprintf('  %-6s IAE Simulink %.4g / %.4g / %.5g | CPU 1212C vs Simulink [%%]: %+.2f / %+.2f / %+.2f\n', C.etq{c}, gS.IAE, dI);
    fprintf('         escalones: max|dtr| = %.1f s, max|dts| = %.1f s (en %s), max|dMp| = %.2f puntos | TV Simulink %s, CPU %s\n', ...
        max(abs(dtr)), max(abs(dts)), etq_esc, max(abs(dmp)), mat2str(round(eS.TV)), mat2str(round(eH.TV)));
    filas(end+1,:) = {C.etq{c}, gS.IAE(1), gS.IAE(2), gS.IAE(3), dI(1), dI(2), dI(3), max(abs(dtr)), max(abs(dts)), max(abs(dmp)), etq_esc, ...
        eS.TV(1), eS.TV(2), eS.TV(3), eH.TV(1), eH.TV(2), eH.TV(3)}; %#ok<AGROW>
    B.(nom) = struct('IAE_sim', gS.IAE, 'dIAE', dI, 'dtr', dtr, 'dts', dts, 'dMp', dmp, 'TV_sim', eS.TV, 'TV_cpu', eH.TV);
end
if ~isempty(filas), guardar_csv(C, 'tabla_diseno_vs_cpu.csv', cab, filas); end
end

function B = bloque_comunes(C)
% Analisis de sensibilidad en simulacion (Simulink, ode3): PID y Fuzzy con las condiciones de implementacion del MPC:
% apertura inicial = equilibrio de la planta (0.6561 / 0.2380 / 0.4744), saturacion de 2 a 99 %, cambio maximo por muestra
% de 3.5 / 1.5 / 3 p.p. y, en el PID, memoria que guarda el valor limitado. El MPC (completo, Simulink) ya las cumple.
fprintf('\n---------- SENSIBILIDAD EN SIMULACION: CONDICIONES COMUNES (Simulink) ----------\n'); B = struct();
def = {'PID actual','PID',C.arch.diseno.PID; 'PID solo memoria','PID',C.arch.comun.PID_memoria; 'PID comun','PID',C.arch.comun.PID; 'Fuzzy actual','FUZZY',C.arch.diseno.FUZZY; ...
       'Fuzzy comun','FUZZY',C.arch.comun.FUZZY; 'MPC completo','MPC',C.arch.diseno.MPC};
n = size(def, 1); IA = zeros(n,3); I2 = zeros(n,3); TV = zeros(n,3); MP = zeros(n,2); TS = zeros(n, size(C.escalones,1));
for i = 1:n
    f = buscar(C, def{i,3});
    if isempty(f), fprintf('  (sin archivo: %s)\n', def{i,3}); return; end
    S = leer_flat(f{1}, C, 10000);
    g = m_global(S, C); e = m_esfuerzo(S, def{i,2}, C);
    IA(i,:) = g.IAE; I2(i,:) = iae_desde(S, C.t_cambio(2), C); TV(i,:) = e.TV;
    MP(i,:) = [m_escalon(S, 2, 500, C).Mp, m_escalon(S, 2, 900, C).Mp];
    for j = 1:size(C.escalones,1), TS(i,j) = m_escalon(S, C.escalones(j,2), C.escalones(j,1), C).ts; end
end
fprintf('%-14s %-26s %-26s %-18s %s\n', 'Variante', 'IAE Hw / Ho / Pg', 'IAE sin arranque (>=200 s)', 'TV uw / uo / ug', 'Mp de Ho a 500 y 900 s [%]');
for i = 1:n
    fprintf('%-14s %7.3f %7.3f %9.2f   %7.3f %7.3f %9.2f   %5.0f %5.0f %5.0f   %6.2f %6.2f\n', def{i,1}, IA(i,:), I2(i,:), TV(i,:), MP(i,:));
end
rel = @(a,b) 100*(a - b)./b;
fprintf('\nDiferencia relativa del IAE frente al PID [%%] (completa | sin arranque)\n');
pares = {'condiciones actuales', 1, 4, 6; 'condiciones comunes', 3, 5, 6}; filas = {};
for k = 1:2
    ip = pares{k,2}; ifz = pares{k,3}; imp = pares{k,4};
    dF = rel(IA(ifz,:), IA(ip,:)); dM = rel(IA(imp,:), IA(ip,:)); dF2 = rel(I2(ifz,:), I2(ip,:)); dM2 = rel(I2(imp,:), I2(ip,:));
    fprintf('  %-22s Fuzzy %s | %s   MPC %s | %s\n', pares{k,1}, mat2str(round(dF*10)/10), mat2str(round(dF2*10)/10), mat2str(round(dM*10)/10), mat2str(round(dM2*10)/10));
    filas(end+1,:) = {pares{k,1}, 'Fuzzy', dF(1), dF(2), dF(3), dF2(1), dF2(2), dF2(3)}; %#ok<AGROW>
    filas(end+1,:) = {pares{k,1}, 'MPC',   dM(1), dM(2), dM(3), dM2(1), dM2(2), dM2(3)}; %#ok<AGROW>
end
dPM = rel(IA(2,:), IA(1,:));
fprintf('  PID solo memoria frente a PID actual: dIAE [%%] %s | TV %s | Mp de Ho a 500 y 900 s %s\n', mat2str(round(dPM*100)/100), mat2str(round(TV(2,:))), mat2str(round(MP(2,:)*10)/10));
T = [TS(3,:); TS(5,:); TS(6,:)]; [~, im] = max(T, [], 1); nom3 = {'PID','Fuzzy','MPC'};
fprintf('Controlador mas lento (ts) por escalon, condiciones comunes: %s\n', strjoin(nom3(im), ', '));
guardar_csv(C, 'tabla_condiciones_comunes_diferencias.csv', {'Condiciones','Controlador','dIAE Hw [%]','dIAE Ho [%]','dIAE Pg [%]','dIAE Hw sin arranque [%]','dIAE Ho sin arranque [%]','dIAE Pg sin arranque [%]'}, filas);
filas2 = cell(n, 12);
for i = 1:n, filas2(i,:) = {def{i,1}, IA(i,1), IA(i,2), IA(i,3), I2(i,1), I2(i,2), I2(i,3), TV(i,1), TV(i,2), TV(i,3), MP(i,1), MP(i,2)}; end
guardar_csv(C, 'tabla_condiciones_comunes.csv', {'Variante','IAE Hw','IAE Ho','IAE Pg','IAE Hw sin arranque','IAE Ho sin arranque','IAE Pg sin arranque','TV uw','TV uo','TV ug','Mp Ho 500 s','Mp Ho 900 s'}, filas2);
B.IAE = IA; B.IAE_sin_arranque = I2; B.TV = TV; B.Mp_Ho = MP; B.ts = TS;
end

function B = bloque_escenario2(C)
% Evaluacion en simulacion (Simulink, ode3) en el segundo escenario (Escenario_Trifasico_2.m), con las sintonias sin retocar.
% Eventos del escenario 2: cambios de referencia en 0 s (arranque), 200, 300, ..., 900 s; caudales en 100 s, 300 s, etc.
% Filas: PID, Fuzzy y MPC completo con P = 200 (obligatorias) y MPC con P = 100 y P = 50 (opcionales).
fprintf('\n---------- ESCENARIO 2 (Simulink, sintonias sin retocar) ----------\n'); B = struct();
C2 = C; C2.t_cambio = 0:100:1000;
C2.escalones = [0 1; 0 3; 200 3; 300 2; 400 1; 500 3; 600 1; 600 2; 700 3; 800 1; 900 1; 900 2; 900 3];
nom = {'PID','Fuzzy','MPC P=200','MPC P=100','MPC P=50','PID comun','Fuzzy comun'}; ctrl = {'PID','FUZZY','MPC','MPC','MPC','PID','FUZZY'}; clave = {'PID','FUZZY','MPC','MPC_P100','MPC_P50','PID_comun','FUZZY_comun'};
ne = size(C2.escalones, 1); nf = numel(nom);
IA = nan(nf,3); I2 = nan(nf,3); TV = nan(nf,3); MPv = nan(nf,3); TS = nan(nf, ne); ok = false(1, nf);
for i = 1:nf
    f = buscar(C, C.arch.escenario2.(clave{i}));
    if isempty(f)
        if i > 3, continue; end                                        % las filas de P = 100 y P = 50 son opcionales
        fprintf('  (sin archivo: %s)\n', C.arch.escenario2.(clave{i})); return;
    end
    try
        S = leer_flat(f{1}, C, 10000);
    catch err
        fprintf('  %s\n', err.message); if i > 3, continue; else, return; end
    end
    ok(i) = true; g = m_global(S, C2); e = m_esfuerzo(S, ctrl{i}, C2);
    IA(i,:) = g.IAE; I2(i,:) = iae_desde(S, 200, C2); TV(i,:) = e.TV; mp = zeros(1,3);
    for j = 1:ne
        m = m_escalon(S, C2.escalones(j,2), C2.escalones(j,1), C2); TS(i,j) = m.ts;
        mp(C2.escalones(j,2)) = max(mp(C2.escalones(j,2)), m.Mp);
    end
    MPv(i,:) = mp;
end
idx = find(ok);
fprintf('%-10s %-24s %-24s %-18s %s\n', '', 'IAE Hw / Ho / Pg', 'IAE sin arranque (>=200 s)', 'TV uw / uo / ug', 'Mp maximo Hw / Ho / Pg [%]');
for i = idx
    fprintf('%-10s %7.3f %7.3f %9.2f   %7.3f %7.3f %9.2f   %5.0f %5.0f %5.0f   %5.1f %5.1f %5.1f\n', nom{i}, IA(i,:), I2(i,:), TV(i,:), MPv(i,:));
end
rel = @(a,b) 100*(a - b)./b;
for k = idx(idx > 1 & idx <= 5)
    fprintf('  %-10s frente al PID [%%]: IAE %s | sin arranque %s\n', nom{k}, mat2str(round(rel(IA(k,:), IA(1,:))*10)/10), mat2str(round(rel(I2(k,:), I2(1,:))*10)/10));
end
for k = idx(idx > 3 & idx <= 5)
    fprintf('  %-10s frente a P = 200 [%%]: IAE %s | TV total %.0f frente a %.0f\n', nom{k}, mat2str(round(rel(IA(k,:), IA(3,:))*10)/10), sum(TV(k,:)), sum(TV(3,:)));
end
if ok(6) && ok(7)
    fprintf('  Condiciones comunes (escenario 2): Fuzzy comun frente a PID comun [%%] IAE %s | sin arranque %s ; MPC P=200 frente a PID comun IAE %s | sin arranque %s\n', ...
        mat2str(round(rel(IA(7,:), IA(6,:))*10)/10), mat2str(round(rel(I2(7,:), I2(6,:))*10)/10), mat2str(round(rel(IA(3,:), IA(6,:))*10)/10), mat2str(round(rel(I2(3,:), I2(6,:))*10)/10));
    Tc = [TS(6,:); TS(7,:); TS(3,:)]; [~, imc] = max(Tc, [], 1);
    fprintf('  Con condiciones comunes, el MPC es el mas lento en %d de %d eventos y el PID en %d\n', sum(imc == 3), ne, sum(imc == 1));
end
nom3 = {'PID','Fuzzy','MPC'}; [~, im] = max(TS(1:3,:), [], 1);
fprintf('Controlador mas lento (ts) por evento (PID, Fuzzy, MPC P=200): %s | MPC en %d de %d eventos, PID en %d\n', strjoin(nom3(im), ', '), sum(im == 3), ne, sum(im == 1));
fprintf('TV total [p.p.]: %s\n', strjoin(arrayfun(@(i) sprintf('%s %.0f', nom{i}, sum(TV(i,:))), idx, 'UniformOutput', false), ', '));
filas = cell(numel(idx), 13);
for q = 1:numel(idx), i = idx(q); filas(q,:) = {nom{i}, IA(i,1), IA(i,2), IA(i,3), I2(i,1), I2(i,2), I2(i,3), TV(i,1), TV(i,2), TV(i,3), MPv(i,1), MPv(i,2), MPv(i,3)}; end
guardar_csv(C, 'tabla_escenario2.csv', {'Controlador','IAE Hw','IAE Ho','IAE Pg','IAE Hw sin arranque','IAE Ho sin arranque','IAE Pg sin arranque','TV uw','TV uo','TV ug','Mp max Hw','Mp max Ho','Mp max Pg'}, filas);
B.IAE = IA; B.IAE_sin_arranque = I2; B.TV = TV; B.Mp_max = MPv; B.ts = TS;
end

function B = bloque_atribucion(C)
% Efecto de cada cambio por separado (arranque, limites y memoria) en el escenario original, en Simulink.
% Los archivos de un solo cambio son opcionales; las filas que falten se omiten.
fprintf('\n---------- UN SOLO CAMBIO A LA VEZ (Simulink, escenario original) ----------\n'); B = struct();
a = C.arch.atribucion; cm = C.arch.comun; dg = C.arch.diseno;
def = {'PID actual','PID',dg.PID,1; 'PID solo arranque','PID',a.PID_arranque,0; 'PID solo limites','PID',a.PID_limites,0; 'PID solo memoria','PID',cm.PID_memoria,0; 'PID comun','PID',cm.PID,0; ...
       'Fuzzy actual','FUZZY',dg.FUZZY,1; 'Fuzzy solo arranque','FUZZY',a.FUZZY_arranque,0; 'Fuzzy solo limites','FUZZY',a.FUZZY_limites,0; 'Fuzzy comun','FUZZY',cm.FUZZY,0};
n = size(def, 1); ok = false(1, n); IA = nan(n,3); I2 = nan(n,3); TV = nan(n,3); MP = nan(n,2);
for i = 1:n
    f = buscar(C, def{i,3});
    if isempty(f), if def{i,4}, fprintf('  (sin archivo: %s)\n', def{i,3}); return; end, continue; end
    try, S = leer_flat(f{1}, C, 10000); catch err, fprintf('  %s\n', err.message); continue; end
    ok(i) = true; g = m_global(S, C); e = m_esfuerzo(S, def{i,2}, C);
    IA(i,:) = g.IAE; I2(i,:) = iae_desde(S, C.t_cambio(2), C); TV(i,:) = e.TV;
    MP(i,:) = [m_escalon(S, 2, 500, C).Mp, m_escalon(S, 2, 900, C).Mp];
end
if sum(ok) <= 2, fprintf('  (faltan las corridas de un solo cambio: %s, ...)\n', a.PID_arranque); return; end
fprintf('%-20s %-24s %-24s %-18s %-14s %s\n', 'Variante', 'IAE Hw / Ho / Pg', 'IAE sin arranque', 'TV uw / uo / ug', 'Mp de Ho', 'dIAE frente al actual [%]');
filas = {};
for i = find(ok)
    base = 1 + 5*(i > 5);
    d = 100*(IA(i,:) - IA(base,:))./IA(base,:);
    fprintf('%-20s %7.3f %7.3f %9.2f   %7.3f %7.3f %9.2f   %5.0f %5.0f %5.0f   %5.1f %5.1f   %+5.1f %+5.1f %+5.1f\n', def{i,1}, IA(i,:), I2(i,:), TV(i,:), MP(i,:), d);
    filas(end+1,:) = {def{i,1}, IA(i,1), IA(i,2), IA(i,3), I2(i,1), I2(i,2), I2(i,3), TV(i,1), TV(i,2), TV(i,3), MP(i,1), MP(i,2), d(1), d(2), d(3)}; %#ok<AGROW>
end
guardar_csv(C, 'tabla_un_solo_cambio.csv', {'Variante','IAE Hw','IAE Ho','IAE Pg','IAE Hw sin arranque','IAE Ho sin arranque','IAE Pg sin arranque','TV uw','TV uo','TV ug','Mp Ho 500 s','Mp Ho 900 s','dIAE Hw [%]','dIAE Ho [%]','dIAE Pg [%]'}, filas);
B.IAE = IA; B.IAE_sin_arranque = I2; B.TV = TV; B.Mp_Ho = MP;
end

function B = bloque_horizonte(C)
% Efecto del horizonte de prediccion del MPC completo en Simulink (M = 6, tope de 10 iteraciones), escenario nominal.
% P = 200 es la corrida de diseno (C.arch.diseno.MPC); P = 50 y 100 se generan con P_nuevo en MPC_linealizar_v6_1.m.
fprintf('\n---------- HORIZONTE DE PREDICCION DEL MPC (Simulink) ----------\n'); B = struct();
def = {50, C.arch.horizonte.P50; 100, C.arch.horizonte.P100; 200, C.arch.diseno.MPC};
n = size(def, 1); IA = zeros(n,3); TV = zeros(n,3); TSp = zeros(n,3); SAT = zeros(n,3);
tp = [400 600 800];
for i = 1:n
    f = buscar(C, def{i,2});
    if isempty(f), fprintf('  (sin archivo para P = %d: %s)\n', def{i,1}, def{i,2}); return; end
    try
        S = leer_flat(f{1}, C, 10000);
    catch err
        fprintf('  %s\n', err.message); return;
    end
    g = m_global(S, C); e = m_esfuerzo(S, 'MPC', C); IA(i,:) = g.IAE; TV(i,:) = e.TV;
    for j = 1:3
        m = m_escalon(S, 3, tp(j), C); TSp(i,j) = m.ts;
        [k, ~] = ventana(S, tp(j), C); u = S.u(k, 3);
        SAT(i,j) = C.Ts*(sum(u >= 99 - 1e-4) + sum(u <= 2 + 1e-4));
    end
end
fprintf('%-6s %-24s %-22s %-22s %s\n', 'P', 'IAE Hw / Ho / Pg', 'ts de Pg 400/600/800 s', 'ug saturada [s]', 'TV uw / uo / ug [p.p.]');
for i = 1:n
    fprintf('%-6d %7.2f %7.2f %9.1f   %6.1f %6.1f %6.1f   %6.1f %6.1f %6.1f   %5.0f %5.0f %5.0f\n', def{i,1}, IA(i,:), TSp(i,:), SAT(i,:), TV(i,:));
end
filas = cell(n, 13);
for i = 1:n, filas(i,:) = {def{i,1}, IA(i,1), IA(i,2), IA(i,3), TSp(i,1), TSp(i,2), TSp(i,3), SAT(i,1), SAT(i,2), SAT(i,3), TV(i,1), TV(i,2), TV(i,3)}; end
guardar_csv(C, 'tabla_horizonte.csv', {'P','IAE Hw','IAE Ho','IAE Pg','ts Pg 400','ts Pg 600','ts Pg 800','ug sat 400','ug sat 600','ug sat 800','TV uw','TV uo','TV ug'}, filas);
B.IAE = IA; B.ts_Pg = TSp; B.sat = SAT; B.TV = TV;
end

function B = bloque_mpc_1212c(C)
% IAE, TV y temporizacion de las corridas del MPC en la CPU 1212C que se guardan aparte del escenario nominal
% (por ejemplo, el MPC completo, que no mantuvo el periodo). Da el cociente frente al IAE de diseno (Simulink)
% calculado desde los registros, sin multiplicar cifras redondeadas.
fprintf('\n---------- CORRIDAS DEL MPC EN LA CPU 1212C (MPC completo / reducido) ----------\n'); B = struct();
lista = buscar(C, C.arch.mpc_1212c);
if isempty(lista), fprintf('  (sin archivos: %s)\n', C.arch.mpc_1212c); return; end
fd = buscar(C, C.arch.diseno.MPC); gD = [];
if ~isempty(fd), gD = m_global(leer_flat(fd{1}, C, 10000), C); end
cab = {'Archivo','IAE Hw','IAE Ho','IAE Pg','IAE/diseno Hw','IAE/diseno Ho','IAE/diseno Pg','TV uw','TV uo','TV ug','Periodo medio [s]','Duracion real [min]','Retencion [%]'};
filas = {}; dl = buscar(C, strrep(C.arch.mpc_1212c, 'Datos_*.txt', 'Diag_Com_*.csv'));
for k = 1:numel(lista)
    R = leer_corrida(lista{k}, C); g = m_global(R, C); e = m_esfuerzo(R, 'MPC', C); T = temporizacion(R, C);
    if isempty(gD), q = [NaN NaN NaN]; else, q = g.IAE./gD.IAE; end
    Dg = diag_de(lista{k}, dl); ret = NaN;
    if ~isempty(Dg), ok = Dg.sint == 0 & Dg.ciclo > 1; ret = 100*mean(Dg.ret(ok)); end
    [~, nombre] = fileparts(lista{k});
    fprintf('  %s\n     IAE %.4g / %.4g / %.5g | cociente frente al diseno %.1f / %.1f / %.2f | TV %s | periodo medio %.3f s, duracion %.1f min, retencion %.1f %%\n', nombre, g.IAE, q, mat2str(round(e.TV)), T.media, R.treal(end)/60, ret);
    filas(end+1,:) = {nombre, g.IAE(1), g.IAE(2), g.IAE(3), q(1), q(2), q(3), e.TV(1), e.TV(2), e.TV(3), T.media, R.treal(end)/60, ret}; %#ok<AGROW>
end
guardar_csv(C, 'tabla_mpc_1212C.csv', cab, filas); B.filas = filas;
end

function R = leer_flat(f, C, n)
% Lee un *_flat.mat de Simulink (t, hw, hws, hb, hbs, pg, pgs, vpw, vpc, vpg; niveles en m, presion en psi, aperturas en
% por unidad) y lo deja con el mismo formato que leer_corrida, recortado a las primeras n muestras (t < 1000 s).
S = load(f); tt = S.t(:); k = find(tt < 1000 - 1e-6); k = k(1:min(n, numel(k)));
if numel(S.hw) ~= numel(S.t)
    error('leer_flat:longitud', '%s: las senales tienen %d muestras y t tiene %d; repita la corrida y verifique que el tiempo de parada sea tend', f, numel(S.hw), numel(S.t));
end
R.archivo = f; R.t = tt(k); R.treal = [];
a = S.hws(:); b = S.hbs(:); c3 = S.pgs(:); R.r = [a(k)*C.m2ft, b(k)*C.m2ft, c3(k)];
a = S.hw(:);  b = S.hb(:);  c3 = S.pg(:);  R.y = [a(k)*C.m2ft, b(k)*C.m2ft, c3(k)];
a = S.vpw(:); b = S.vpc(:); c3 = S.vpg(:); R.u = [a(k), b(k), c3(k)]*100;
end

%% ===================================== METRICAS =====================================================
function R = leer_corrida(f, C)
M = dlmread(f, '\t', 1, 0);
R.archivo = f; R.t = M(:,10); R.treal = M(:,11);
R.r = [M(:,1)*C.m2ft, M(:,4)*C.m2ft, M(:,7)];      % referencias [ft ft psi]
R.y = [M(:,2)*C.m2ft, M(:,5)*C.m2ft, M(:,8)];      % variables controladas [ft ft psi]
R.u = M(:,[3 6 9])*100;                            % aperturas [%]
end

function G = m_global(R, C)
e = R.r - R.y; t = R.t(:);
G.IAE  = C.Ts*sum(abs(e), 1);
G.ISE  = C.Ts*sum(e.^2, 1);
G.ITAE = C.Ts*sum(bsxfun(@times, t, abs(e)), 1);
G.RMSE = sqrt(mean(e.^2, 1));
end

function E = m_esfuerzo(R, nom, C)
u = R.u; du = abs(diff(u, 1, 1)); lim = C.limite_cambio.(nom); s = C.sat.(nom);
E.TV = sum(du, 1); E.sat = zeros(1,3); E.lim = zeros(1,3); E.sobre = zeros(1,3);
for j = 1:3
    E.sat(j)   = sum(u(:,j) <= s(1) + C.tol_sat | u(:,j) >= s(2) - C.tol_sat);
    E.lim(j)   = sum(du(:,j) >= lim(j) - C.tol_lim);
    E.sobre(j) = sum(du(:,j) >  lim(j) + C.tol_lim);
end
end

function [k, t1] = ventana(R, t0, C)
t1 = C.t_cambio(find(C.t_cambio > t0 + 1e-9, 1));
k = R.t >= t0 - 1e-6 & R.t < t1 - 1e-6;
end

function S = m_escalon(R, v, t0, C)
[k, t1] = ventana(R, t0, C); idx = find(k); i0 = idx(1);
yy = R.y(idx, v); tt = R.t(idx); rn = R.r(i0, v);
if t0 == 0, ro = R.y(1, v); else, ro = R.r(i0-1, v); end
A = rn - ro; s = sign(A); e = rn - yy;
S.A = A; S.t1 = t1;
S.Mp = 100/abs(A)*max(0, max(s*(yy - rn))) + 0;   % + 0 evita el cero negativo
k10 = find(s*(yy - (ro + 0.1*A)) >= 0, 1); k90 = find(s*(yy - (ro + 0.9*A)) >= 0, 1);
S.tr = NaN; if ~isempty(k10) && ~isempty(k90), S.tr = tt(k90) - tt(k10); end
fuera = find(abs(yy - rn) > 0.02*abs(A));
if isempty(fuera), S.ts = 0; elseif fuera(end) < numel(tt), S.ts = tt(fuera(end)+1) - t0; else, S.ts = NaN; end
S.ess = mean(abs(e(tt >= t1 - 10 - 1e-6)));
S.iae = C.Ts*sum(abs(e));
end

function P = m_perturbacion(R, v, t0, C)
[k, t1] = ventana(R, t0, C); idx = find(k);
e = R.r(idx, v) - R.y(idx, v); tt = R.t(idx);
[~, ip] = max(abs(e)); P.desv = e(ip); P.iae = C.Ts*sum(abs(e)); P.t1 = t1;
if abs(e(ip)) < C.umbral_rec(v)
    P.trec = NaN;                                   % efecto despreciable: no se calcula
else
    arriba = find(abs(e) > 0.1*abs(e(ip)));
    if arriba(end) < numel(tt), P.trec = tt(arriba(end)+1) - t0; else, P.trec = Inf; end
end
end

function [TV, IA] = por_tramo(R, C)
TV = zeros(10,3); IA = zeros(10,3); e = R.r - R.y;
for k = 0:9
    idx = find(R.t >= 100*k - 1e-6 & R.t < 100*(k+1) - 1e-6);
    TV(k+1,:) = sum(abs(diff(R.u(idx,:), 1, 1)), 1);
    IA(k+1,:) = C.Ts*sum(abs(e(idx,:)), 1);
end
end

function T = temporizacion(R, C)
dt = diff(R.treal(:));
T.media = mean(dt); T.jitter = std(dt); T.p95 = percentil(dt, 95); T.p99 = percentil(dt, 99); T.max = max(dt);
T.pct15 = 100*mean(dt > 1.5*C.Ts); T.deriva = abs(R.treal(end) - R.t(end));     % atraso (o adelanto) del tiempo real al final de la prueba [s]
end

function K = analizar_corte(Dg, R, C, off, wd)
if nargin < 4, off = 0; end
if nargin < 5, wd = 10; end
% Bloque mas largo de ciclos sinteticos (Unity no pudo leer al PLC): la planta sigue con las valvulas retenidas.
K = struct('hay', false);
s = double(Dg.sint(:) == 1); if ~any(s), return; end
d = diff([0; s; 0]); ini = find(d == 1); fin = find(d == -1) - 1; [~, m] = max(fin - ini);
ini = ini(m); fin = fin(m); n = fin - ini + 1; ia = ini - 1; ib = fin + 1;
if ia < 1 || ib > numel(s), return; end
K.hay = true; K.n_sint = n; K.dur = n*C.Ts; K.t_ini = Dg.t(ini); K.t_fin = Dg.t(ib);
K.ciclos_plc = Dg.contador(ib) - Dg.contador(ia);
K.retenidos  = K.ciclos_plc - wd;                % menos los wd ciclos que el controlador ejecuta antes del watchdog (10 por defecto)
% salto de apertura al reanudar: cambio entre la ultima muestra retenida y la primera posterior [puntos %].
% El primer paso retenido de la planta es la fila anterior del registro (la fila 1 es el arranque), de modo que
% la muestra posterior al corte es la numero (ini - 1 + n).
K.salto = [NaN NaN NaN]; K.t_sim_ini = NaN;
s0 = ini - 1 + off; kk = s0 + n;                 % off = 1 en las repeticiones 2 en adelante de una sesion: su segmento no trae la fila de arranque
if s0 >= 1 && kk <= size(R.u, 1)
    K.salto = R.u(kk,:) - R.u(kk-1,:); K.t_sim_ini = R.t(s0);
end
end

%% ===================================== ESTADISTICA ==================================================
function q = percentil(x, p)
% Interpolacion lineal entre estadisticos de orden (igual que numpy.percentile).
x = sort(x(:)); n = numel(x); h = (n - 1)*p/100 + 1; lo = floor(h); hi = ceil(h);
q = x(lo) + (h - lo)*(x(hi) - x(lo));
end

function r = rangos_prom(x)
[xs, ix] = sort(x(:)'); n = numel(x); r = zeros(1, n); i = 1;
while i <= n
    j = i; while j < n && xs(j+1) == xs(i), j = j + 1; end
    r(ix(i:j)) = (i + j)/2; i = j + 1;
end
r = reshape(r, size(x));
end

function r = rangos_medios(X)
r = zeros(1, size(X,2)); for i = 1:size(X,1), r = r + rangos_prom(X(i,:)); end, r = r/size(X,1);
end

function v = iae_desde(R, t0, C)
k = R.t >= t0 - 1e-6; e = R.r(k,:) - R.y(k,:); v = C.Ts*sum(abs(e), 1);
end

function F = prueba_bloques(X)
% Friedman (con correccion por empates), W de Kendall y Wilcoxon exacto por pares con Holm.
% X: bloques (filas) x controladores (columnas: PID, Fuzzy, MPC).
[n, k] = size(X); Rk = zeros(n, k);
for i = 1:n, Rk(i,:) = rangos_prom(X(i,:)); end
Rj = sum(Rk, 1); den = sum(Rk(:).^2) - n*k*(k+1)^2/4;
if den <= 0, F.chi2 = 0; else, F.chi2 = (k-1)*sum((Rj - n*(k+1)/2).^2)/den; end
F.p = gammainc(F.chi2/2, (k-1)/2, 'upper'); F.W = F.chi2/(n*(k-1)); F.rm = mean(Rk, 1); F.n = n;
pares = [1 2; 1 3; 2 3]; p = zeros(1, 3);
for q = 1:3, p(q) = wilcoxon_exacto(log(X(:, pares(q,1))), log(X(:, pares(q,2)))); end   % log: diferencias sin unidades (ft*s y psi*s no se mezclan)
F.p_pares = p; F.pholm = holm(p);
end

function p = wilcoxon_exacto(x, y)
% Prueba de rangos con signo (dos colas), distribucion exacta por enumeracion de signos (n <= 20);
% con rangos promedio si hay empates; se descartan las diferencias nulas.
d = x(:) - y(:); d = d(d ~= 0); n = numel(d);
if n == 0, p = 1; return; end
r = rangos_prom(abs(d)); r = r(:); Wp = sum(r(d > 0)); E = sum(r)/2;
if n <= 20
    m = 2^n; idx = uint32((0:m-1)'); W = zeros(m, 1);
    for j = 1:n, W = W + r(j)*double(bitget(idx, j)); end
    p = mean(abs(W - E) >= abs(Wp - E) - 1e-9);
else
    z = (Wp - E)/sqrt(sum(r.^2)/4); p = erfc(abs(z)/sqrt(2));
end
end

function q = holm(p)
[ps, ix] = sort(p); m = numel(p); a = zeros(1, m);
for i = 1:m, a(i) = (m - i + 1)*ps(i); if i > 1, a(i) = max(a(i), a(i-1)); end, end
q = zeros(1, m); q(ix) = min(a, 1);
end

%% ===================================== ENTRADA / SALIDA =============================================
function lista = buscar(C, patron)
% Archivos que cumplen el patron (relativo a carpeta_datos; admite comodines tambien en las subcarpetas), por orden alfabetico.
ruta = fullfile(C.carpeta_datos, patron); [carpeta, ~, ~] = fileparts(ruta);
d = dir(ruta); lista = {};
if isempty(d), return; end
d = d(~[d.isdir]); [~, ix] = sort({d.name}); d = d(ix);
for i = 1:numel(d)
    if isfield(d, 'folder') && ~isempty(d(i).folder), lista{end+1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
    else, lista{end+1} = fullfile(carpeta, d(i).name); end %#ok<AGROW>
end
end

function D = leer_diag(f)
fid = fopen(f, 'r'); fgetl(fid);
c = textscan(fid, '%f%f%f%f%f%f%f%f%f%f%f%f%f', 'Delimiter', ';', 'EmptyValue', NaN); fclose(fid);
D.archivo = f; D.ciclo = c{1}; D.contador = c{2}; D.eco = c{3}; D.t = c{4}; D.dt = c{5}; D.lec = c{6}; D.esc = c{7};
D.lat = c{8}; D.ret = c{9}; D.retardo = c{10}; D.saltados = c{11}; D.sint = c{12}; D.falla = c{13};
end

function s = marca_tiempo(f)
[~, n] = fileparts(f); t = regexp(n, '(\d{8})_(\d{6})', 'tokens', 'once');
if isempty(t), s = NaN; return; end
d = t{1}; h = t{2};
s = datenum(str2double(d(1:4)), str2double(d(5:6)), str2double(d(7:8)), str2double(h(1:2)), str2double(h(3:4)), str2double(h(5:6)))*86400;
end

function D = diag_de(fdatos, lista)
% Registro Diag_Com de la misma corrida: el de marca de tiempo mas cercana (se acepta hasta 2 min de diferencia).
D = []; if isempty(lista), return; end
ts = marca_tiempo(fdatos); dmin = Inf; ib = 0;
for i = 1:numel(lista)
    dd = abs(marca_tiempo(lista{i}) - ts); if dd < dmin, dmin = dd; ib = i; end
end
if ib == 0 || isnan(dmin) || dmin > 120, return; end
D = leer_diag(lista{ib});
end

function s = n2s(x, fmt)
w = sscanf(fmt, '%%%d', 1); if isempty(w), w = 6; end
if isnan(x), s = sprintf('%*s', w, '--'); elseif isinf(x), s = sprintf('%*s', w, '>vent'); else, s = sprintf(fmt, x); end
end

function s = nansum_(x), s = sum(x(~isnan(x))); end

function guardar_csv(C, nombre, cab, filas)
fid = fopen(fullfile(C.carpeta_salida, nombre), 'w');
fprintf(fid, '%s\n', strjoin(cab, ','));
for i = 1:size(filas, 1)
    p = cell(1, size(filas, 2));
    for j = 1:size(filas, 2)
        x = filas{i, j};
        if ischar(x), p{j} = ['"' x '"']; elseif isempty(x) || (isnumeric(x) && isnan(x)), p{j} = ''; else, p{j} = sprintf('%.6g', x); end
    end
    fprintf(fid, '%s\n', strjoin(p, ','));
end
fclose(fid);
end

%% ===================================== UBICACION DE LOS DATOS =======================================
function C = ubicar_repositorio(C, args)
% Si no se indica 'carpeta_datos', prueba la carpeta actual de MATLAB y la raiz del repositorio (la carpeta que
% contiene a Analisis/, donde esta este archivo). Se acepta la primera que tenga la carpeta nominal del modelo elegido.
nombres = args(1:2:end);
dada_d = any(strcmpi(nombres, 'carpeta_datos'));  dada_s = any(strcmpi(nombres, 'carpeta_salida'));
clave = fileparts(fileparts(C.arch.nominal.PID));          % 'Nominal_v12' (o 'Nominal' con el modelo v11)
if dada_d
    if exist(fullfile(C.carpeta_datos, clave), 'dir') ~= 7
        error('No existe la carpeta %s dentro de la carpeta de datos indicada: %s', clave, C.carpeta_datos);
    end
    return
end
raiz_script = fileparts(fileparts(mfilename('fullpath')));
cand = {pwd, raiz_script};  raiz = '';
for k = 1:numel(cand)
    if exist(fullfile(cand{k}, 'Datos', clave), 'dir') == 7, raiz = cand{k}; break; end
end
if isempty(raiz)
    error(['No se encontro la carpeta Datos/%s.\n' ...
           '  Carpeta actual de MATLAB: %s\n  Raiz supuesta del repositorio (carpeta padre de este script): %s\n' ...
           'Ejecute la copia del script que esta en la carpeta Analisis/ del repositorio clonado, o indique la ruta:\n' ...
           '  calcular_resultados_articulo(''carpeta_datos'', ''<raiz del repositorio>/Datos'')'], clave, pwd, raiz_script);
end
C.carpeta_datos = fullfile(raiz, 'Datos');
if ~dada_s, C.carpeta_salida = fullfile(raiz, 'Analisis', C.carpeta_salida); end
end

function revisar_archivos(C)
% Lista los patrones de C.arch sin ningun archivo. Los casos de fallas y reconexion se expanden por controlador.
falta = {};
cs = fieldnames(C.arch);
for i = 1:numel(cs)
    v = C.arch.(cs{i});
    if isstruct(v)
        sub = fieldnames(v);
        for j = 1:numel(sub), p = v.(sub{j}); if isempty(buscar(C, p)), falta{end+1} = p; end, end %#ok<AGROW>
    elseif ischar(v) && isempty(strfind(v, '%'))
        if isempty(buscar(C, v)), falta{end+1} = v; end %#ok<AGROW>
    end
end
for c = 1:3
    for n = C.casos_falla
        p = sprintf(C.arch.fallas, C.carp.(C.ctrl{c}), C.ctrl{c}, n); if isempty(buscar(C, p)), falta{end+1} = p; end %#ok<AGROW>
    end
    for k = 1:numel(C.recon_casos)
        p = sprintf(C.arch.recon_datos, C.recon_casos{k}, C.carp.(C.ctrl{c}), C.ctrl{c}); if isempty(buscar(C, p)), falta{end+1} = p; end %#ok<AGROW>
    end
end
opcional = ~cellfun(@isempty, regexp(falta, '^(Nominal_sesion1/|TIA Desconectado/(PID|Fuzzy)/)', 'once'));   % opcionales: primera sesion y TIA del PID y el Fuzzy
falta_req = falta(~opcional);
if isempty(falta_req)
    fprintf('Comprobacion de archivos: estan todos los registros que usa el articulo.\n');
else
    fprintf('Comprobacion de archivos: faltan %d (las tablas que los usan se omiten):\n', numel(falta_req));
    fprintf('  Datos/%s\n', falta_req{:});
end
end
