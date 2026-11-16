
function verificar_modelo_v12()
FT = 0.3048; PSI = 6894.757;
todas_no = struct('balance_gas',false,'gas_std',false,'bases',false, ...
                  'critico',false,'capa_crudo',false,'colector',false);
nombres = {'balance_gas','gas_std','bases','critico','capa_crudo','colector'};

f11 = @(u,x) tpsep_v11(u,x);
f12 = @(u,x,c) tpsep_v12(u,x,c);

%% 1. Regresion: v12 con todo en false = v11
rng_ok = true; maxdif = 0;
rand('seed',1);
for k = 1:500
    x = [0.2+0.9*rand, 0.2+0.9*rand, 0.2+1.5*rand, (20+30*rand)*PSI];
    u = [0.10+0.05*rand, 0.08+0.05*rand, 0.02+0.02*rand, rand, rand, rand];
    [d1,o1] = f11(u,x); [d2,o2] = f12(u,x,todas_no);
    dif = max(abs([d1;o1]-[d2;o2])./max(1,abs([d1;o1])));
    maxdif = max(maxdif,dif);
end
fprintf('1) v12 con todo en false frente a v11: diferencia relativa maxima %.1e\n', maxdif);

%% 2. hemihead = dV/dh
ds = 3.048; La = 15.1724;
e = 0;
for h = linspace(0.05,3.0,60)
    num = (hemivols(h+1e-6,La,ds)-hemivols(h-1e-6,La,ds))/2e-6;
    e = max(e, abs(num-hemihead(h,ds,La))/num);
end
fprintf('2) hemihead frente a dV/dh numerica: error relativo maximo %.1e\n', e);

%% 3. Punto de operacion y caudales de entrada nominales (del modelo v11)
if exist('TPSEP_OperatingPoint.mat', 'file')
    S = load('TPSEP_OperatingPoint.mat', 'xeq', 'mveq', 'md0');
    x0 = S.xeq(:)'; u11 = S.mveq(:)'; qwi = S.md0(1); qci = S.md0(2); qgi = S.md0(3);
else
    x0 = [1.554*FT, 2.625*FT, 2.362*FT, 37*PSI];   % [hc hw hb pg]
    u0 = [0.656 0.238 0.474];                      % aperturas nominales publicadas
    [d0,~] = f11([0 0 0 u0],x0);
    qwi = d0(1); qci = d0(2); qgi = d0(4);         % entradas = salidas en equilibrio
    uo11 = fzero(@(uo) sel(f11([qwi qci qgi u0(1) uo u0(3)],x0),3) - qci, u0(2));
    u11 = [u0(1) uo11 u0(3)];
end
[~,r11] = f11([qwi qci qgi u11],x0);
fprintf('\n3) Caudales nominales: qwi=%.4f  qci=%.4f m^3/s  qgi=%.4f m^3/s std\n',qwi,qci,qgi);
fprintf('   Equilibrio v11: aperturas %.1f / %.1f / %.1f %%  (residuo max %.1e)\n',100*u11,max(abs(r11)));

cfg_all = struct();
u12 = equilibrio(f12,cfg_all,x0,[qwi qci qgi],u11);
[~,r12] = f12([qwi qci qgi u12],x0,cfg_all);
fprintf('   Equilibrio v12: aperturas %.1f / %.1f / %.1f %%  (residuo max %.1e)\n',100*u12,max(abs(r12)));

%% 4. Linealizacion en cada equilibrio
[A11,B11] = jacob(@(x,u) o11([qwi qci qgi u],x), x0, u11);
[A12,B12] = jacob(@(x,u) o12([qwi qci qgi u],x,cfg_all), x0, u12);
K11 = [-B11(2,1)/FT, -B11(3,2)/FT, -B11(4,3)/PSI];
K12 = [-B12(2,1)/FT, -B12(3,2)/FT, -B12(4,3)/PSI];
fprintf('\n4) Ganancias integradoras (y'' ~ -K u):\n');
fprintf('   %-6s %12s %12s %8s\n','','v11','v12','v12/v11');
et = {'K_w [ft/s]','K_o [ft/s]','K_g [psi/s]'};
for k = 1:3
    fprintf('   %-11s %10.4g %12.4g %8.2f\n',et{k},K11(k),K12(k),K12(k)/K11(k));
end
fprintf('   Acoplamiento de las valvulas de liquido sobre la presion [psi/s por unidad]:\n');
fprintf('     u_w -> P_g: v11 %.4g | v12 %.4g\n',B11(4,1)/PSI,B12(4,1)/PSI);
fprintf('     u_o -> P_g: v11 %.4g | v12 %.4g\n',B11(4,2)/PSI,B12(4,2)/PSI);
fprintf('   Autovalores de A: v11 %s\n                    v12 %s\n',mat2str(sort(real(eig(A11)))',3),mat2str(sort(real(eig(A12)))',3));

%% 5. Efecto de cada correccion por separado
fprintf('\n5) Cada correccion sola (resto como v11):\n');
fprintf('   %-12s %7s %7s %7s %9s %9s %9s\n','correccion','u_w%','u_o%','u_g%','K_w','K_o','K_g');
for k = 1:numel(nombres)
    c = todas_no; c.(nombres{k}) = true;
    uk = equilibrio(f12,c,x0,[qwi qci qgi],u11);
    [~,Bk] = jacob(@(x,u) o12([qwi qci qgi u],x,c), x0, uk);
    Kk = [-Bk(2,1)/FT, -Bk(3,2)/FT, -Bk(4,3)/PSI];
    fprintf('   %-12s %7.1f %7.1f %7.1f %9.4g %9.4g %9.4g\n',nombres{k},100*uk,Kk);
end

%% 6. Conservacion en lazo abierto (RK4, 1000 s, pulsos de apertura y de caudal)
dt = 0.05; N = round(1000/dt);
for modelo = 1:2
    x = x0; if modelo==1, u = u11; else u = u12; end
    Vint = 0; Gint = 0;
    [d,~] = fm(modelo,[qwi qci qgi u],x);
    V0 = d(5)+d(6); G0 = gasstd(x,d);
    eV = 0; eG = 0; xmin = x; xmax = x;
    for n = 1:N
        t = n*dt;
        ue = u; qw = qwi;
        % pulsos de 50 s: la planta es integradora y en lazo abierto
        % un escalon sostenido la llevaria a los topes de nivel
        if t > 100 && t <= 150, ue(1) = ue(1)+0.03; end
        if t > 300 && t <= 350, ue(3) = ue(3)-0.03; end
        if t > 500 && t <= 550, ue(2) = ue(2)+0.03; end
        if t > 700 && t <= 750, qw = 1.05*qwi; end
        inp = [qw qci qgi ue];
        z = [x Vint Gint];
        k1 = rhs(modelo,inp,z); k2 = rhs(modelo,inp,z+dt/2*k1);
        k3 = rhs(modelo,inp,z+dt/2*k2); k4 = rhs(modelo,inp,z+dt*k3);
        z = z + dt/6*(k1+2*k2+2*k3+k4);
        x = z(1:4); Vint = z(5); Gint = z(6);
        xmin = min(xmin,x); xmax = max(xmax,x);
        [d,~] = fm(modelo,inp,x);
        eV = max(eV, abs((d(5)+d(6)-V0) - Vint));
        eG = max(eG, abs((gasstd(x,d)-G0) - Gint)/G0);
    end
    if modelo==1, et2='v11'; else et2='v12'; end
    fprintf('\n6) %s: error de volumen de liquido max %.3g m^3 (%.2f %% del liquido); error de moles de gas max %.2f %%\n', ...
            et2, eV, 100*eV/V0, 100*eG);
    fprintf('   rango de estados: Hc %.3f-%.3f ft, Hw %.3f-%.3f ft, Ho %.3f-%.3f ft, Pg %.2f-%.2f psi\n', ...
            xmin(1)/FT,xmax(1)/FT,xmin(2)/FT,xmax(2)/FT,xmin(3)/FT,xmax(3)/FT,xmin(4)/PSI,xmax(4)/PSI);
end

end

%% ---------- funciones locales ----------
function v = sel(salida,k)
v = salida(k);
end
function o = o11(inp,x)
[~,o] = tpsep_v11(inp,x);
end
function o = o12(inp,x,c)
[~,o] = tpsep_v12(inp,x,c);
end
function [d,o] = fm(modelo,inp,x)
if modelo==1, [d,o] = tpsep_v11(inp,x); else [d,o] = tpsep_v12(inp,x,struct()); end
end
function dz = rhs(modelo,inp,z)
[d,o] = fm(modelo,inp,z(1:4));
qliq = inp(1)+inp(2)-d(1)-d(3);
dz = [o' qliq (inp(3)-d(4))];
end
function G = gasstd(x,d)
% moles de gas expresados como volumen estandar [m^3 std]
Patm = 101325; Pstd = 101325; Tstd = 288.706; T = 355.37;
vt = hemivolt(3.048,15.1724,3.1076);
Vgas = vt - d(5) - d(6);
G = (x(4)+Patm)*Vgas*Tstd/(Pstd*T);
end
function u = equilibrio(f,cfg,x0,q,uini)
% Cada valvula fija su caudal de salida igual al de entrada.
u = uini;
isal = [1 3 4];                       % qwo, qcb, qgo en la salida data
for k = 1:3
    gk = @(uk) sel(f([q put(u,k,uk)],x0,cfg),isal(k)) - q(k);
    u(k) = fzero(gk, uini(k));
end
end
function v = put(v,k,a)
v(k) = a;
end
function [A,B] = jacob(f,x0,u0)
nx = numel(x0); nu = numel(u0);
A = zeros(nx); B = zeros(nx,nu);
for j = 1:nx
    h = 1e-6*max(1,abs(x0(j))); xp = x0; xm = x0; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
    A(:,j) = (f(xp,u0)-f(xm,u0))/(2*h);
end
for j = 1:nu
    h = 1e-6; up = u0; um = u0; up(j)=up(j)+h; um(j)=um(j)-h;
    B(:,j) = (f(x0,up)-f(x0,um))/(2*h);
end
end
