

clc
% warning off
clearvars
addpath(genpath(pwd));
estadoVerb = mpcverbosity('off');

%% 0) CONFIGURACION
nombreParametros = 'Parametros_MPC_v8';   % funcion con los parametros explicitos
archivoSesion    = 'MPC_v8_ref.mat';    % copia exacta de la sesion (verificacion)
archivoSalida    = 'TPSEP_MPC_v8_.mat';

usarPlantaSesion = false;   % true: usar la planta interna de la sesion en vez de linealizar
generarEscenario = true;    % llama a Escenario_Trifasico al final
abrirReview      = false;   % review(mpc1) al terminar

% Ajustes sobre la configuracion de la sesion. Se aplican DESPUES de
% verificar que el controlador reproduce la sesion. Vacio o false = sin cambio.
P_nuevo  = [];              % p.ej. 250 -> 25 s de horizonte con Ts = 0.1 s
MV_duras = false;           % true -> MinECR = MaxECR = 0 en las tres valvulas

M_nuevo    = 6;    % p.ej. 4  ([] = sin cambio)
QP_maxIter = 10;    % p.ej. 10 ([] = sin tope)

PSI2PA = 6894.757;

%% 1) PUNTO DE OPERACION
% Se cargan SOLO estas tres variables: el archivo tambien contiene un
% mpc1 y un xmpc0 antiguos (Ts = 1 s, P = 20, M = 5) guardados como struct.
S    = load('TPSEP_OperatingPoint.mat', 'xeq', 'mveq', 'md0');
xeq  = S.xeq(:);
mveq = S.mveq(:);
md0  = S.md0(:);

input_eq  = [md0; mveq];
[~, dx_eq] = tpsep_v11(input_eq, xeq);
fprintf('Equilibrio: max|dx| = %.3e\n', max(abs(dx_eq)));

y_eq = [xeq(2); xeq(3); xeq(4)/PSI2PA];
u_eq = [mveq; md0];

%% 2) PARAMETROS DE LA SESION
p = feval(nombreParametros);
fprintf('Parametros %s: Ts = %g s | P = %d | M = %s\n', ...
        nombreParametros, p.Ts, p.PredictionHorizon, mat2str(p.ControlHorizon));

if max(abs(p.Nominal.X(:) - xeq)) > 1e-6*max(abs(xeq))
    warning('El punto nominal de la sesion no coincide con xeq de TPSEP_OperatingPoint.mat.');
end

%% 3) LINEALIZACION NUMERICA (identica a MPC_linealizar_3)
nx = 4; nu = 6; ny = 3;
A = zeros(nx, nx);
B = zeros(nx, nu);

dx_step = [1e-4; 1e-4; 1e-4; 10];
du_step = 1e-4*ones(nu, 1);

for i = 1:nx
    xp = xeq; xm = xeq;
    xp(i) = xp(i) + dx_step(i);
    xm(i) = xm(i) - dx_step(i);
    A(:,i) = (modelo_dx(xp, u_eq) - modelo_dx(xm, u_eq))/(2*dx_step(i));
end
for j = 1:nu
    up = u_eq; um = u_eq;
    up(j) = up(j) + du_step(j);
    um(j) = um(j) - du_step(j);
    B(:,j) = (modelo_dx(xeq, up) - modelo_dx(xeq, um))/(2*du_step(j));
end

C = [0 1 0 0;
     0 0 1 0;
     0 0 0 1/PSI2PA];
D = zeros(ny, nu);

plant_c = ss(A, B, C, D);

% Comparacion con la planta interna de la sesion (respuesta en frecuencia)
Ps_c = [];
if ~isempty(p.Plant)
    try
        Ps = ss(p.Plant.A, p.Plant.B, p.Plant.C, p.Plant.D, p.Plant.Ts);
        if Ps.Ts > 0
            Ps_c = d2c(Ps);
        else
            Ps_c = Ps;
        end
        w  = logspace(-3, 0.5, 40);
        H1 = freqresp(plant_c, w);
        H2 = freqresp(Ps_c, w);
        errPlanta = max(abs(H1(:) - H2(:)))/max(abs(H2(:)));
        fprintf('Planta linealizada vs planta de la sesion: error relativo max = %.2e\n', errPlanta);
        if errPlanta > 1e-3 && ~usarPlantaSesion
            warning(['La planta de la sesion difiere de la linealizacion (%.2e). ' ...
                     'Si la verificacion falla, prueba usarPlantaSesion = true.'], errPlanta);
        end
    catch err
        warning('No se pudo comparar con la planta de la sesion: %s', err.message);
    end
end

if usarPlantaSesion
    if isempty(Ps_c)
        error('usarPlantaSesion = true pero la sesion no trae planta utilizable.');
    end
    plant_base = Ps_c;
else
    plant_base = plant_c;
end

plant_eq = c2d(plant_base, p.Ts);
plant_eq = setmpcsignals(plant_eq, 'MV', 1:3, 'UD', 4:6, 'MO', 1:3);

%% 4) CONTROLADOR CON LOS PARAMETROS DE LA SESION
mpc1 = mpc(plant_eq, p.Ts, p.PredictionHorizon, p.ControlHorizon);
mpc1 = aplicarParametros(mpc1, p);

%% 5) VERIFICACION CONTRA LA SESION
if isfile(archivoSesion)
    R = load(archivoSesion, 'mpc1');
    verificarMPC(mpc1, R.mpc1, y_eq);
else
    warning('No se encontro %s: se omite la verificacion contra la sesion.', archivoSesion);
end

%% 6) AJUSTES OPCIONALES SOBRE LA SESION
if ~isempty(P_nuevo)
    mpc1.PredictionHorizon = P_nuevo;
    fprintf('Ajuste aplicado: P = %d (%.1f s de horizonte)\n', P_nuevo, P_nuevo*mpc1.Ts);
end
if MV_duras
    MV = mpc1.MV;
    for i = 1:numel(MV)
        MV(i).MinECR = 0;
        MV(i).MaxECR = 0;
    end
    mpc1.MV = MV;
    fprintf('Ajuste aplicado: restricciones de las valvulas duras (ECR = 0)\n');
end

if ~isempty(M_nuevo)
    mpc1.ControlHorizon = M_nuevo;
    fprintf('Ajuste aplicado: M = %d\n', M_nuevo);
end
if ~isempty(QP_maxIter)
    if isfield(mpc1.Optimizer, 'ActiveSetOptions')
        mpc1.Optimizer.ActiveSetOptions.MaxIterations = QP_maxIter;   % R2020a y posteriores
    else
        mpc1.Optimizer.MaxIter = QP_maxIter;                          % versiones anteriores
    end
    mpc1.Optimizer.UseSuboptimalSolution = true;
    fprintf('Ajuste aplicado: tope de %d iteraciones del QP\n', QP_maxIter);
end

%% 7) ESTADO INICIAL, HUELLA Y GUARDADO
xmpc0 = mpcstate(mpc1);
xmpc0.Plant    = xeq;
xmpc0.LastMove = mveq;

fprintf('\n===== CONTROLADOR LISTO =====\n');
fprintf('  Ts = %g s | P = %d (%.1f s) | M = %s\n', mpc1.Ts, mpc1.PredictionHorizon, ...
        mpc1.PredictionHorizon*mpc1.Ts, mat2str(mpc1.ControlHorizon));
Huella_SCL_MPC(mpc1);

save(archivoSalida, 'mpc1', 'xmpc0', 'plant_eq', 'plant_c', ...
     'A', 'B', 'C', 'D', 'xeq', 'mveq', 'md0', 'y_eq', 'u_eq', 'p');
fprintf('  Guardado en %s\n', archivoSalida);
fprintf('  Bloque MPC Controller -> MPC Controller: mpc1 | Initial Controller State: xmpc0\n');

mpcverbosity(estadoVerb);

%% 8) ESCENARIO DE PRUEBA
if generarEscenario
    if exist('Escenario_Trifasico', 'file')
        Escenario_Trifasico;
    else
        warning('No se encontro Escenario_Trifasico.m: genera el escenario antes de simular.');
    end
end

if abrirReview
    review(mpc1);
end

%% ============================================================
%  FUNCIONES LOCALES
%% ============================================================
function dx = modelo_dx(x, u_mpc)
    mv = u_mpc(1:3);
    md = u_mpc(4:6);
    [~, dx] = tpsep_v11([md; mv], x);
end

function m = aplicarParametros(m, p)
% Copia al controlador todos los parametros capturados de la sesion.
    m.Model.Nominal.X  = p.Nominal.X;
    m.Model.Nominal.U  = p.Nominal.U;
    m.Model.Nominal.Y  = p.Nominal.Y;
    m.Model.Nominal.DX = p.Nominal.DX;

    m.Weights.OutputVariables          = p.Weights.OutputVariables;
    m.Weights.ManipulatedVariables     = p.Weights.ManipulatedVariables;
    m.Weights.ManipulatedVariablesRate = p.Weights.ManipulatedVariablesRate;
    m.Weights.ECR                      = p.Weights.ECR;

    MV = m.MV;
    for i = 1:numel(p.MV)
        for f = {'Min','Max','RateMin','RateMax','MinECR','MaxECR','RateMinECR','RateMaxECR','ScaleFactor'}
            MV(i).(f{1}) = p.MV(i).(f{1});
        end
    end
    m.MV = MV;

    OV = m.OV;
    for i = 1:numel(p.OV)
        for f = {'Min','Max','MinECR','MaxECR','ScaleFactor'}
            OV(i).(f{1}) = p.OV(i).(f{1});
        end
    end
    m.OV = OV;

    % Estimador: modelos de perturbacion y ruido exactamente como en la sesion
    if ~isempty(p.InDist)
        setindist(m, 'model', ss(p.InDist.A, p.InDist.B, p.InDist.C, p.InDist.D, p.InDist.Ts));
    end
    if ~isempty(p.OutDist)
        setoutdist(m, 'model', ss(p.OutDist.A, p.OutDist.B, p.OutDist.C, p.OutDist.D, p.OutDist.Ts));
    end
    if ~isempty(p.Noise)
        m.Model.Noise = ss(p.Noise.A, p.Noise.B, p.Noise.C, p.Noise.D, p.Noise.Ts);
    end
end

function verificarMPC(m1, m2, y_eq)
% Compara el controlador reconstruido (m1) con el de la sesion (m2).
    fprintf('\n===== VERIFICACION CONTRA LA SESION =====\n');
    ok = true;

    % a) Horizontes
    igual = abs(m1.Ts - m2.Ts) < 1e-12 && isequal(m1.PredictionHorizon, m2.PredictionHorizon) ...
            && isequal(m1.ControlHorizon, m2.ControlHorizon);
    fprintf('  Ts, P, M                : %s\n', siNo(igual));
    ok = ok && igual;

    % b) Ganancias del estimador (Kalman)
    try
        [L1, M1] = getEstimator(m1);
        [L2, M2] = getEstimator(m2);
        e = max(norm(L1 - L2, inf)/max(norm(L2, inf), eps), ...
                norm(M1 - M2, inf)/max(norm(M2, inf), eps));
        fprintf('  Ganancias del estimador : dif. relativa %.2e  %s\n', e, siNo(e < 1e-6));
        ok = ok && e < 1e-6;
    catch err
        fprintf('  Ganancias del estimador : no comparables (%s)\n', err.message);
        ok = false;
    end

    % c) Lazo cerrado contra el modelo interno, con escalones en las tres salidas
    Nsim = 1500;
    r = repmat(y_eq(:)', Nsim, 1);
    r(101:end, 1)  = y_eq(1) + 0.02;     % hw
    r(601:end, 3)  = y_eq(3) + 3;        % pg
    r(1001:end, 2) = y_eq(2) + 0.02;     % hb
    [y1, ~, u1] = sim(m1, Nsim, r);
    [y2, ~, u2] = sim(m2, Nsim, r);
    du = max(abs(u1(:) - u2(:)));
    dy = max(abs(y1(:) - y2(:)));
    fprintf('  Lazo cerrado            : max|du| = %.2e  max|dy| = %.2e  %s\n', du, dy, siNo(du < 1e-4));
    ok = ok && du < 1e-4;

    if ok
        fprintf('  RESULTADO: el controlador reproduce la sesion.\n');
    else
        warning('El controlador NO reproduce exactamente la sesion. Revisa los puntos marcados.');
    end
end

function s = siNo(c)
    if c
        s = 'OK';
    else
        s = 'DIFERENTE';
    end
end

%% %%%%%%%%%%%%%%%%%%%%%

% % Tiempo
% ts = 0.1;      
% tend = 1000;      
% t = [0:ts:tend]; 
% % Perturbaciones
% %qwi % agua  [m^3/s]
% %qci % crudo [m^3/s]
% %qgi% gas   [m^3/s]
% 
% qwi_v=[.1374*ones(1,tend) .1374*ones(1,tend) .1374*ones(1,tend)...
%      .1374*ones(1,tend) .1874*ones(1,tend) .1874*ones(1,tend)...
%      .1874*ones(1,tend) .1074*ones(1,tend) .1074*ones(1,tend) .1074*ones(1,length(t)-tend*9)];
% 
% qci_v=[.0711*ones(1,tend) .0711*ones(1,tend) .0725*ones(1,tend)...
%      .0725*ones(1,tend) .0725*ones(1,tend) .0725*ones(1,tend)...
%      .0725*ones(1,tend) .0725*ones(1,tend) .0701*ones(1,tend) .0701*ones(1,length(t)-tend*9)];
% 
% qgi_v=[.4906*ones(1,tend) .4906*ones(1,tend) .4906*ones(1,tend)...
%      .4606*ones(1,tend) .4606*ones(1,tend) .4606*ones(1,tend)...
%      .4606*ones(1,tend) .4606*ones(1,tend) .4606*ones(1,tend) .4206*ones(1,length(t)-tend*9)];
% 
% % Set points
% % hw [m]
% % hb [m]
% % pg [Pa]
% 
% hws_v=[.85*ones(1,tend) .85*ones(1,tend) .85*ones(1,tend)...
%      .85*ones(1,tend) .80*ones(1,tend) .80*ones(1,tend)...
%      .78*ones(1,tend) .78*ones(1,tend) .78*ones(1,tend) .78*ones(1,length(t)-tend*9)];
% 
% hbs_v=[.72*ones(1,tend) .72*ones(1,tend) .72*ones(1,tend)...
%      .72*ones(1,tend) .72*ones(1,tend) .75*ones(1,tend)...
%      .75*ones(1,tend) .75*ones(1,tend) .75*ones(1,tend) .70*ones(1,length(t)-tend*9)];
% 
% PA2PSI = 1/6894.757;
% PSI2PA = 6894.757;
% 
% pgs_v=[35.0*ones(1,tend) 35.0*ones(1,tend) 35.0*ones(1,tend)...
%      35.0*ones(1,tend) 40.0*ones(1,tend) 40.0*ones(1,tend)...
%      45.0*ones(1,tend) 45.0*ones(1,tend) 35.0*ones(1,tend) 35.0*ones(1,length(t)-tend*9)];
% 
% % Simulink
% ts=0.1;    
% hws_ = [t; hws_v(1:length(t))]';  %Vector de Entrada
% hbs_ = [t; hbs_v(1:length(t))]';  %Vector de Entrada
% pgs_ = [t; pgs_v(1:length(t))]';  %Vector de Entrada
% 
% qwi_ = [t; qwi_v(1:length(t))]';  %Vector de Entrada
% qci_ = [t; qci_v(1:length(t))]';  %Vector
% qgi_ = [t; qgi_v(1:length(t))]';  %Vector%% %%%%%%%%%%%%%%%%%%%%%


%% 
% 1) TIEMPO
ts    = 0.1;                 % [s] periodo de muestreo del escenario
Tfase = 100;                 % [s] duracion de cada fase
nF    = 10;                  % numero de fases
tend  = nF*Tfase;            % [s] duracion total (Stop time de los modelos)

t  = 0:ts:tend;              % vector de tiempo (fila)
N  = numel(t);               % 10001 muestras
Nf = round(Tfase/ts);        % muestras por fase (1000)

% 2) CRONOGRAMA (una fila por fase; el cambio ocurre al INICIO de la fase)
%        qwi      qci      qgi      hws    hbs    pgs
%       [m3/s]   [m3/s]   [m3/s]    [m]    [m]   [psi]
esc = [ 0.1374   0.0711   0.4906   0.85   0.72   35.0     % fase  1:   0 - 100 s
        0.1374   0.0711   0.4906   0.85   0.72   35.0     % fase  2: 100 - 200 s
        0.1374   0.0725   0.4906   0.85   0.72   35.0     % fase  3: 200 - 300 s  qci
        0.1374   0.0725   0.4606   0.85   0.72   35.0     % fase  4: 300 - 400 s  qgi
        0.1874   0.0725   0.4606   0.80   0.72   40.0     % fase  5: 400 - 500 s  qwi, hws, pgs
        0.1874   0.0725   0.4606   0.80   0.75   40.0     % fase  6: 500 - 600 s  hbs
        0.1874   0.0725   0.4606   0.78   0.75   45.0     % fase  7: 600 - 700 s  hws, pgs
        0.1074   0.0725   0.4606   0.78   0.75   45.0     % fase  8: 700 - 800 s  qwi
        0.1074   0.0701   0.4606   0.78   0.75   35.0     % fase  9: 800 - 900 s  qci, pgs
        0.1074   0.0701   0.4206   0.78   0.70   35.0 ];  % fase 10: 900 -1000 s  qgi, hbs

if size(esc,1) ~= nF
    error('La tabla de escenario tiene %d fases y nF = %d.', size(esc,1), nF);
end

% 3) VECTORES MUESTRA A MUESTRA
%  Se usa el indice entero de muestra (no t/Tfase) para evitar errores
%  de redondeo en los bordes de fase. La ultima fase absorbe t = tend.
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

% 4) ENTRADAS PARA LOS BLOQUES FROM WORKSPACE  (formato [t  valor], N x 2)
hws_ = [t' hws_v'];
hbs_ = [t' hbs_v'];
pgs_ = [t' pgs_v'];
qwi_ = [t' qwi_v'];
qci_ = [t' qci_v'];
qgi_ = [t' qgi_v'];

fprintf('Escalones creados\n');