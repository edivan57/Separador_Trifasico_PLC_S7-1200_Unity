
clear all
clc

addpath("func/");
addpath("src/");

clear fis_tpsep_1block
fis_tpsep_1block = readfis('fis_tpsep_1block.fis');

% Recomendado en el bloque Fuzzy Logic Controller:
%   Number of samples = 21
%   Simulate using    = Code generation, si tu versión lo permite
%                       Interpreted execution, si aparece incompatibilidad

Ts_fuzzy = 1.5;          % tiempo de actualización recomendado [s]
Ts_planta = 0.1;         % si tu planta trabaja a 0.1 s

% Condición inicial sugerida de válvulas para el update
mv0_fuzzy = [0.47; 0.14; 0.85];  % [vpw; vpc; vpg]

fprintf('FIS MIMO cargado: fis_tpsep_1block\n');
fprintf('Use un solo Fuzzy Logic Controller con entrada [e_hw de_hw e_hb de_hb e_pg de_pg].\n');

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

