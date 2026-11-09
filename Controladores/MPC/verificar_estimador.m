

clc
diary off
if exist('verificacion_estimador.txt','file'), delete('verificacion_estimador.txt'); end
diary('verificacion_estimador.txt')

%% 0) El controlador
if ~exist('mpc1','var')
    S = load('TPSEP_MPC_v8_.mat','mpc1');
    mpc1 = S.mpc1;
end
Ts = mpc1.Ts;
fprintf('mpc1: Ts = %g s | P = %d | M = %s\n', Ts, mpc1.PredictionHorizon, mat2str(mpc1.ControlHorizon));
fprintf('Pesos de las salidas (esperado 18.2212 21.8654 1.8221): %s\n', mat2str(mpc1.Weights.OutputVariables,5));

%% Valores del articulo (calculados con la replica en Python)
nEsp    = 7;                                          % 4 estados de la planta + 3 integradores
BdEsp   = 0.91417637922975*eye(3);                    % B del modelo de perturbacion de entrada
DnEsp   = diag([0.21877616239496 0.21877616239496 2.18776162394955]);   % D del ruido de medicion
MdEsp   = [ 3.4871  0.1134  0.1613 ;
           -1.3477  2.7967  0.2331 ;
           -1.1733 -2.8167  0.2410 ];                 % M(5:7,:)
absPEsp = [0.9734 0.9734 0.9476 0.9400 0.9400 0.8877 0.8877]';
tauEsp  = [3.72 3.72 1.86 1.62 1.62 0.84 0.84]';

%% 1) Matrices del estimador
[L,M,A,Cm] = getEstimator(mpc1);
n = size(A,1);
fprintf('\n1) Estados del estimador: %d (esperado %d)\n', n, nEsp);

%% 2) Modelos de perturbacion y de ruido
okBd = false; okDn = false;
fprintf('\n2) Perturbaciones y ruido\n');
try
    indist = getindist(mpc1);
    fprintf('B del modelo de perturbacion de entrada (esperado 0.914*I3):\n'); disp(indist.B)
    okBd = isequal(size(indist.B),[3 3]) && norm(indist.B - BdEsp,'fro') < 1e-6;
catch err
    fprintf('No se pudo leer getindist: %s\n', err.message);
end
try
    outdist = getoutdist(mpc1);
    fprintf('Modelo de perturbacion de salida (esperado vacio):\n'); disp(outdist)
catch err
    fprintf('No se pudo leer getoutdist: %s\n', err.message);
end
try
    Dn = mpc1.Model.Noise.D;
    fprintf('D del ruido de medicion (esperado diag(0.2188, 0.2188, 2.188)):\n'); disp(Dn)
    okDn = isequal(size(Dn),[3 3]) && norm(Dn - DnEsp,'fro') < 1e-6;
catch err
    fprintf('No se pudo leer Model.Noise.D: %s\n', err.message);
end

%% 3) Ganancia de innovacion de los integradores de perturbacion
okM = false;
fprintf('\n3) Ganancia M, filas 5 a 7 (integradores de q_wi, q_ci, q_gi; columnas H_w, H_o, P_g)\n');
if n == nEsp
    disp(M(5:7,:))
    fprintf('Esperado:\n'); disp(MdEsp)
    fprintf('Razon M(5:7,:) ./ esperado (1 = igual; 10 o 0.1 en la 3.a columna = ScaleFactor de P_g):\n');
    disp(M(5:7,:) ./ MdEsp)
    okM = max(max(abs(M(5:7,:) - MdEsp))) < 0.02*max(abs(MdEsp(:)));
else
    fprintf('El estimador no tiene %d estados; se omite la comparacion.\n', nEsp);
end

%% 4) Polos del estimador y constantes de tiempo
fprintf('\n4) Polos del estimador\n');
p      = eig(A - L*Cm);                    % forma del predictor
pActual = eig(A*(eye(n) - M*Cm));          % forma "actual" (igual si L = A*M)
[~,k]  = sort(abs(p),'descend');  p = p(k);
absP   = abs(p);
tau    = -Ts ./ log(absP);
fprintf('norm(L - A*M) = %.2e (0 si L = A*M)\n', norm(L - A*M));
fprintf('|z|  = %s\n', mat2str(round(absP.'*1e4)/1e4));
fprintf('tau  = %s s\n', mat2str(round(tau.'*1e2)/1e2));
fprintf('Esperado |z| = %s\n', mat2str(absPEsp.'));
fprintf('Esperado tau = %s s\n', mat2str(tauEsp.'));
fprintf('Diferencia entre la forma del predictor y la actual: %.2e\n', ...
        max(abs(sort(abs(pActual),'descend') - absP)));
okP = (n == nEsp) && max(abs(absP - absPEsp)) < 0.005;

%% 5) Resumen
fprintf('\n5) Resumen\n');
nombres = {'7 estados aumentados', 'B de la perturbacion de entrada = 0.914*I', ...
           'D del ruido de medicion', 'Polos del estimador (|z| y tau)', 'Ganancia M de los integradores'};
vals = [n == nEsp, okBd, okDn, okP, okM];
for i = 1:numel(vals)
    if vals(i), s = 'OK'; else, s = 'REVISAR'; end
    fprintf('  %-45s %s\n', nombres{i}, s);
end
if okP && ~okM
    fprintf('\nLos polos coinciden y M no: probablemente es una diferencia de escala de los ejes (ver la razon del punto 3).\n');
end
diary off
