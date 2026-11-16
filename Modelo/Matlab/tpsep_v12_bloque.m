function [data, output] = tpsep_v12_bloque(input, recycle)


qwi = input(1);
qci = input(2);
qgi = input(3);
vpw = min(max(input(4),0),1);
vpc = min(max(input(5),0),1);
vpg = min(max(input(6),0),1);

% Parametros (iguales a tpsep_v11)
ds   = 3.048;     % Diametro del separador            [m]
La   = 15.1724;   % Longitud de la camara              [m]
Lb   = 3.1076;    % Longitud del colector              [m]
hs   = 1.2192;    % Altura del vertedero               [m]
kvw  = 5.15e-4;   % Coef. valvula de agua
poa  = 101325;    % Presion aguas abajo v. agua (absoluta) [Pa]
kvc  = 7.15e-4;   % Coef. valvula de crudo
pob  = 101325;    % Presion aguas abajo v. crudo (absoluta) [Pa]
kvg  = 80.0;      % Coef. valvula de gas
poc  = 101325;    % Presion aguas abajo v. gas (absoluta) [Pa]
rhoc = 802.525;   % Densidad del crudo                 [kg/m^3]
sgc  = 0.9134;    % Gravedad especifica del crudo
rhow = 997.8;     % Densidad del agua                  [kg/m^3]
sgw  = 1.00;      % Gravedad especifica del agua
mgas = 28.04;     % Peso molecular del gas             [g/mol]
mair = 28.96;     % Peso molecular del aire            [g/mol]
g    = 9.81;      % Gravedad                           [m/s^2]
T    = 355.37;    % Temperatura del recipiente         [K]
Patm = 101325;    % Presion atmosferica                [Pa]
Pstd = 101325;    % Presion estandar (14.696 psia)     [Pa]
Tstd = 288.706;   % Temperatura estandar (60 F)        [K]
PA2PSI = 1.450377e-4;

% Estados
hc = max(min(recycle(1), hs-1e-6), 1e-6);
hw = max(min(recycle(2), hs-1e-6), 1e-6);
hb = max(min(recycle(3), 2.5), 1e-6);
pg = max(recycle(4), 1000);
pabs = pg + Patm;

vt = hemivolt(ds, La, Lb);
ha = hw + hc;

% Rebose sobre el vertedero
qca = 0;
if ha > hs
    H = max(ha - hs, 0);
    qca = 0.415*max(ds - 0.2*H, 0)*(H^1.5)*sqrt(2*g);
    if ~isfinite(qca) || qca < 0, qca = 0; end
end

% Valvulas de liquido, presiones absolutas
qcb = 0;
argcb = (pabs + rhoc*g*hb - pob)/sgc;
if argcb > 0, qcb = kvc*vpc*sqrt(argcb); end
if ~isfinite(qcb) || qcb < 0, qcb = 0; end

qwo = 0;
argwo = (pabs + rhoc*g*hc + rhow*g*hw - poa)/sgw;
if argwo > 0, qwo = kvw*vpw*sqrt(argwo); end
if ~isfinite(qwo) || qwo < 0, qwo = 0; end

% Valvula de gas (psia y grados Rankine), con flujo critico
Tf = (T - 273.15)*9/5 + 32;
TR = Tf + 460;
Gg = mgas/mair;
p1 = pabs*PA2PSI;
p2 = max(poc*PA2PSI, 0.5*p1);
dp2 = p1^2 - p2^2;
qgo = 0;
if dp2 > 0 && vpg > 0
    qgo = 962*kvg*vpg*sqrt(dp2/(Gg*TR))*7.86579e-6;   % m^3/s estandar
end
if ~isfinite(qgo) || qgo < 0, qgo = 0; end

% Volumenes
va = hemivols(min(max(ha,0),ds), La, ds);
vb = hemivols(min(max(hb,0),ds), Lb, ds);

% Balances de liquido
eps_h = 1e-4;
dhw = (qwi - qwo)/hemihead(max(hw,eps_h), ds, La);
dha = (qwi - qwo + qci - qca)/hemihead(max(min(ha, ds-eps_h), eps_h), ds, La);
dhc = dha - dhw;
dhb = (qca - qcb)/hemihead(max(hb,eps_h), ds, Lb);

% Balance de gas
Vgas = max(vt - va - vb, 1e-3);
qliq = qci + qwi - qwo - qcb;
dpg = (Pstd*T/Tstd*(qgi - qgo) + pabs*qliq)/Vgas;
if ~isfinite(dpg), dpg = 0; end

data   = [qwo; qca; qcb; qgo; va; vb; ha];
output = [dhc; dhw; dhb; dpg];
end
