function [data, output] = tpsep_v12(input, recycle, cfg)


if nargin < 3 || isempty(cfg)
    cfg = struct();
end
cfg = completar_cfg(cfg);

qwi = input(1);
qci = input(2);
qgi = input(3);
vpw = min(max(input(4),0),1);
vpc = min(max(input(5),0),1);
vpg = min(max(input(6),0),1);

%% Parametros (iguales a tpsep_v11)
ds   = 3.048;     % Diametro del separador            [m]
La   = 15.1724;   % Longitud de la camara              [m]
Lb   = 3.1076;    % Longitud del colector              [m]
hs   = 1.2192;    % Altura del vertedero               [m]
kvw  = 5.15e-4;   % Coef. valvula de agua              [m^3/s Pa^-0.5]
poa  = 101325;    % Presion aguas abajo v. agua (ABSOLUTA) [Pa]
kvc  = 7.15e-4;   % Coef. valvula de crudo             [m^3/s Pa^-0.5]
pob  = 101325;    % Presion aguas abajo v. crudo (ABSOLUTA) [Pa]
kvg  = 80.0;      % Coef. valvula de gas               [gpm/psi^0.5]
poc  = 101325;    % Presion aguas abajo v. gas (ABSOLUTA)   [Pa]
rhoc = 802.525;   % Densidad del crudo                 [kg/m^3]
sgc  = 0.9134;    % Gravedad especifica del crudo      [-]
rhow = 997.8;     % Densidad del agua                  [kg/m^3]
sgw  = 1.00;      % Gravedad especifica del agua       [-]
mgas = 28.04;     % Peso molecular del gas             [g/mol]
mair = 28.96;     % Peso molecular del aire            [g/mol]
g    = 9.81;      % Gravedad                           [m/s^2]
T    = 355.37;    % Temperatura del recipiente         [K] (180 F)

Patm  = 101325;   % Presion atmosferica                [Pa]
Pstd  = 101325;   % Presion estandar (14.696 psia)     [Pa]
Tstd  = 288.706;  % Temperatura estandar (60 F)        [K]
PA2PSI = 1.450377e-4;

%% Estados
hc = recycle(1);
hw = recycle(2);
hb = recycle(3);
pg = recycle(4);                       % manometrica [Pa]

hc = max(min(real(hc),hs-1e-6),1e-6);
hw = max(min(real(hw),hs-1e-6),1e-6);
hb = max(min(real(hb),2.5),1e-6);
pg = max(real(pg),1000);

pabs = pg + Patm;                      % absoluta [Pa]

vt = hemivolt(ds,La,Lb);
ha = hw + hc;

%% Rebose sobre el vertedero (sin cambios)
if ha <= hs
    qca = 0;
else
    H = max(ha - hs,0);
    qca = 0.415*max(ds - 0.2*H,0)*(H^1.5)*sqrt(2*g);
    if ~isfinite(qca) || qca < 0, qca = 0; end
end

%% Valvulas de liquido: diferencia de presion en una sola base
if cfg.bases
    pup_c = pabs + rhoc*g*hb;          % absoluta aguas arriba
    pup_w = pabs + rhoc*g*hc + rhow*g*hw;
else
    pup_c = pg + rhoc*g*hb;            % v11: manometrica contra absoluta
    pup_w = pg + rhoc*g*hc + rhow*g*hw;
end

argcb = (pup_c - pob)/sgc;
if hb <= 0 || argcb <= 0
    qcb = 0;
else
    qcb = kvc*vpc*sqrt(argcb);
end
if ~isfinite(qcb) || qcb < 0, qcb = 0; end

argwo = (pup_w - poa)/sgw;
if argwo <= 0
    qwo = 0;
else
    qwo = kvw*vpw*sqrt(argwo);
end
if ~isfinite(qwo) || qwo < 0, qwo = 0; end

%% Valvula de gas (ecuacion en psia y grados Rankine, resultado en scfh)
Tf = (T - 273.15)*9/5 + 32;
TR = Tf + 460;
Gg = mgas/mair;
if cfg.bases
    p1 = pabs*PA2PSI;                  % psia
    p2 = poc*PA2PSI;                   % psia (poc ya es absoluta)
else
    p1 = pg*PA2PSI + 14.7;             % v11
    p2 = poc*PA2PSI + 14.7;            % v11: suma 14.7 a una presion absoluta
end
if cfg.critico
    p2 = max(p2, 0.5*p1);              % flujo critico: el caudal deja de crecer
end
dp2 = p1^2 - p2^2;
if dp2 <= 0 || vpg <= 0
    qgo = 0;
else
    qgo = 962*kvg*vpg*sqrt(dp2/(Gg*TR))*7.86579e-6;   % scfh -> m^3/s std
end
if ~isfinite(qgo) || qgo < 0, qgo = 0; end

%% Volumenes
ha_vol = min(max(ha,0),ds);
hb_vol = min(max(hb,0),ds);
va = hemivols(ha_vol,La,ds);
vb = hemivols(hb_vol,Lb,ds);

%% Balances de liquido
eps_h = 1e-4;
Aw = hemihead(max(hw,eps_h), ds, La);
dhw = (qwi - qwo) / Aw;

if cfg.capa_crudo
    % Volumen de crudo en la camara: V(Hw+Hc) - V(Hw)
    Aa  = hemihead(max(min(ha,ds-eps_h),eps_h), ds, La);
    dha = (qwi - qwo + qci - qca) / Aa;
    dhc = dha - dhw;
else
    dhc = (qci - qca) / hemihead(max(hc,eps_h), ds, La);   % v11
end

Ab = hemihead(max(hb,eps_h), ds, Lb);
if cfg.colector || ha > hs
    dhb = (qca - qcb) / Ab;
else
    dhb = 0;                                                 % v11
end

%% Balance de gas
Vgas = max(vt - va - vb,1e-3);
qliq = qci + qwi - qwo - qcb;          % entrada neta de liquido [m^3/s]
if cfg.balance_gas
    cliq = pabs;                       % P_abs * dV_liq/dt
else
    cliq = pg;                         % v11
end
if cfg.gas_std
    cgas = Pstd*T/Tstd;                % n*R*T expresado con caudal estandar
else
    cgas = pg;                         % v11
end
dpg = (cgas*(qgi - qgo) + cliq*qliq)/Vgas;
if ~isfinite(dpg), dpg = 0; end

data   = [qwo; qca; qcb; qgo; va; vb; ha];
output = [dhc; dhw; dhb; dpg];
end

function cfg = completar_cfg(cfg)
campos = {'balance_gas','gas_std','bases','critico','capa_crudo','colector'};
for k = 1:numel(campos)
    if ~isfield(cfg, campos{k})
        cfg.(campos{k}) = true;
    end
end
end
