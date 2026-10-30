function [data, output] = tpsep_v11(input, recycle)
% Modelo dinamico corregido para NMPC/Simulink.
% Estado: recycle = [hc hw hb pg_Pa]
% Entrada: input = [qwi qci qgi vpw vpc vpg]

qwi = input(1);
qci = input(2);
qgi = input(3);
vpw = min(max(input(4),0),1);
vpc = min(max(input(5),0),1);
vpg = min(max(input(6),0),1);

%% DATA (parámetros del separador)
constants = [3.048,...   %1 Diámetro del separador    [m] 10ft
             15.1724,...  %2 Longitud separador        [m] 50ft
             3.1076,...  %3 Longitud colector         [m] 10ft
             1.2192,...  %4 Altura barrera            [m] 4ft   1.2192
             5.15e-4,...  %5 Coef. válvula agua        [m^3/s Pa^0.5]
             101325,...  %6 Presión salida v.agua     [Pa]
             7.15e-4,...  %7 Coef. válvula crudo       [m^3/s Pa^0.5]
             101325,...  %8 Presión salida v.crudo    [Pa]
             80.0,...    %9 Coef. válvula gas         [gpm/psi^0.5]
             101325,...  %10 Presión salida v.gas      [Pa]
             802.525,... %11 Densidad crudo            [kg/m^3]
             0.9134,...  %12 Gravedad esp. crudo       [-]
             997.8,...   %13 Densidad agua             [kg/m^3]
             1.00,...    %14 Gravedad esp. agua        [-]
             28.04,...   %15 Peso molecular gas        [g/mol]
             28.96,...   %16 Peso molecular aire       [g/mol]
             9.81,...    %17 Gravedad                  [m/s^2]
             355.37,...  %18 Temperatura               [K] (180°F)
            ];

ds   = constants(1);
La   = constants(2);
Lb   = constants(3);
hs   = constants(4);
kvw  = constants(5);
poa  = constants(6);
kvc  = constants(7);
pob  = constants(8);
kvg  = constants(9);
poc  = constants(10);
rhoc = constants(11);
sgc  = constants(12);
rhow = constants(13);
sgw  = constants(14);
mgas = constants(15);
mair = constants(16);
g    = constants(17);
T    = constants(18);

hc = recycle(1);
hw = recycle(2);
hb = recycle(3);
pg = recycle(4);    % Pa

hc = max(min(real(hc),hs-1e-6),1e-6);
hw = max(min(real(hw),hs-1e-6),1e-6);
hb = max(min(real(hb),2.5),1e-6);
pg = max(real(pg),1000);

vt = hemivolt(ds,La,Lb);
ha = hw + hc;

if ha <= hs
    qca = 0;
else
    H = max(ha - hs,0);
    qca = 0.415*max(ds - 0.2*H,0)*(H^1.5)*sqrt(2*g);
    if ~isfinite(qca) || qca < 0
        qca = 0;
    end
end

if hb <= 0
    qcb = 0;
else
    argcb = (pg + rhoc*g*hb - pob)/sgc;
    if argcb <= 0
        qcb = 0;
    else
        qcb = kvc*vpc*sqrt(argcb);
    end
    if ~isfinite(qcb) || qcb < 0
        qcb = 0;
    end
end

argwo = (pg + rhoc*g*hc + rhow*g*hw - poa)/sgw;
if argwo <= 0
    qwo = 0;
else
    qwo = kvw*vpw*sqrt(argwo);
end
if ~isfinite(qwo) || qwo < 0
    qwo = 0;
end

% Gas: pg y poc estan en Pa; la ecuacion usa psia.
Tf = ((T - 273.15)*(9/5)) + 32;
pg_psia  = pg*1.450377e-4 + 14.7;
poc_psia = poc*1.450377e-4 + 14.7;

% Solo hay flujo de salida si pg interna supera la presion de salida.
dp2 = pg_psia^2 - poc_psia^2;
qgden = (mgas/mair)*(Tf + 460);

if dp2 <= 0 || qgden <= 0 || vpg <= 0
    qgo = 0;
else
    qgo = 962*kvg*vpg*sqrt(dp2/qgden)*7.86579e-6;
end
if ~isfinite(qgo) || qgo < 0
    qgo = 0;
end

ha_vol = min(max(ha,0),ds);
hb_vol = min(max(hb,0),ds);

va = hemivols(ha_vol,La,ds);
vb = hemivols(hb_vol,Lb,ds);

eps_h = 1e-4;
dhc = (qci - qca) / hemihead(max(hc,eps_h), ds, La);
dhw = (qwi - qwo) / hemihead(max(hw,eps_h), ds, La);

if ha <= hs
    dhb = 0;
else
    dhb = (qca - qcb) / hemihead(max(hb,eps_h), ds, Lb);
end

Vgas = max(vt - va - vb,1e-3);
dpg = pg*(qgi - qgo + qci + qwi - qwo - qcb)/Vgas;

if ~isfinite(dpg)
    dpg = 0;
end

data   = [qwo; qca; qcb; qgo; va; vb; ha];
output = [dhc; dhw; dhb; dpg];

end

