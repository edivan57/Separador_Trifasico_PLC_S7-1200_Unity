function R = contrastar_qp_cotas(archivo_datos, archivo_scl, desfase)

if nargin < 3, desfase = 0; end
raiz = fileparts(fileparts(mfilename('fullpath')));    % raiz del repositorio si este archivo esta en analisis/
archivo_datos = resolver(archivo_datos, raiz);  archivo_scl = resolver(archivo_scl, raiz);
K  = constantes_scl(fileread(archivo_scl));
D  = dlmread(archivo_datos, '\t', 1, 0);  N = size(D, 1);
sp = D(:, [1 4 7]);  pv = D(:, [2 5 8]);  cvlog = D(:, [3 6 9]);
C = reshape(K.b_a, 3, 7);  M = reshape(K.c_a, 7, 3);  E = reshape(K.e_a, 7, 7);  F = reshape(K.f_a, 7, 3);  G = reshape(K.g_a, 7, 3);
Kx = reshape(K.Kx, 7, 18)';  Kr = reshape(K.Kr, 3, 18)';  Ku1 = reshape(K.Ku1, 3, 18)';
Hinv = reshape(K.Hinv, 19, 19);  Hinv = (Hinv + Hinv')/2;  H = inv(Hinv);  H = (H + H')/2;
uoff = K.uoff(:);  xoff = K.xoff(:);  RY = K.RYscale(:);  myoff = K.myoff(:);  Mlim = K.Mlim(:);
xlast = K.x0(:);  mvprev = uoff;
nA = 0; actIdx = zeros(18,1); actLado = zeros(18,1);
mv_port = zeros(N,3); mv_ref = zeros(N,3); iter = zeros(N,1); conv = false(N,1);
opt = [];  if exist('quadprog', 'file') == 2 && exist('optimoptions', 'file') == 2, opt = optimoptions('quadprog', 'Display', 'off', 'OptimalityTolerance', 1e-10); end
for k = 1:N
    kk = max(k - desfase, 1);
    y = pv(kk,:)';  r = sp(k,:)';
    rseq = r.*RY - myoff;
    xk   = xlast - xoff;
    yinn = (y.*RY - myoff) - C*xk;
    xest = xk + M*yinn;
    d    = mvprev - uoff;
    f    = [Kx*xest + Kr*rseq + Ku1*d; 0];
    zs   = -Hinv*f;
    limInf = -Mlim(55:72);  limSup = Mlim(37:54);
    for i = 1:3
        limSup(i) = min(limSup(i), (Mlim(i) + uoff(i)) - mvprev(i));
        limInf(i) = max(limInf(i), (-Mlim(18+i) + uoff(i)) - mvprev(i));
    end
    % (a) conjunto activo del SCL (tope de 6 iteraciones, arranque con el conjunto del ciclo anterior)
    [zq, it, ok, nA, actIdx, actLado] = activo_scl(Hinv, zs, limInf, limSup, nA, actIdx, actLado);
    iter(k) = it*ok;  conv(k) = ok;
    zopt = min(max(zq(1:3), limInf(1:3)), limSup(1:3));
    mv_port(k,:) = recorte(mvprev + zopt, mvprev, Mlim, uoff)';
    % (b) solucion exacta
    lb = [limInf; -1e6];  ub = [limSup; 1e6];
    if ~isempty(opt), zr = quadprog(H, f, [], [], [], [], lb, ub, [], opt);
    else, zr = qp(zeros(19,1), H, f, [], [], lb, ub); end
    mv_ref(k,:) = recorte(mvprev + min(max(zr(1:3), limInf(1:3)), limSup(1:3)), mvprev, Mlim, uoff)';
    % el estimador avanza con la apertura que aplico el PLC (registrada), para que ambas soluciones resuelvan el mismo QP
    mv = cvlog(k,:)';  u = mv - uoff;
    xlast = E*xk + F*u + G*yinn + xoff;
    mvprev = mv;
end
R.err_port = max(abs(mv_port - cvlog), [], 2);  R.err_ref = max(abs(mv_ref - cvlog), [], 2);  R.dif_sol = max(abs(mv_port - mv_ref), [], 2);
R.iter = iter;  R.n_tope = sum(~conv);  R.mv_port = mv_port;  R.mv_ref = mv_ref;
fprintf('%s | %d ciclos | desfase %d\n', archivo_datos, N, desfase);
fprintf('  Conjunto activo del SCL frente al cv registrado: error maximo %.2e, percentil 99 %.2e (fraccion de apertura)\n', max(R.err_port), prctile_(R.err_port, 99));
fprintf('  Solucionador exacto frente al cv registrado:     error maximo %.2e, percentil 99 %.2e\n', max(R.err_ref), prctile_(R.err_ref, 99));
fprintf('  Conjunto activo frente al exacto:                error maximo %.2e; ciclos con diferencia > 1e-4: %d\n', max(R.dif_sol), sum(R.dif_sol > 1e-4));
fprintf('  Ciclos que alcanzaron el tope de 6 iteraciones: %d de %d (%.2f %%) | maximo de iteraciones usadas: %d\n', R.n_tope, N, 100*R.n_tope/N, max(iter));
if R.n_tope > 0, fprintf('  En los ciclos con tope: diferencia maxima frente al exacto %.2e\n', max(R.dif_sol(~conv))); end
end

function [zq, iterQP, convergio, nA, actIdx, actLado] = activo_scl(Hinv, zs, limInf, limSup, nA, actIdx, actLado)
esActiva = false(18,1);  esActiva(actIdx(1:nA)) = true;  zq = zs;  convergio = false;  iterQP = 0;
while iterQP < 6 && ~convergio
    iterQP = iterQP + 1;
    wv = zeros(nA,1);
    for q = 1:nA
        if actLado(q) < 0, wv(q) = limInf(actIdx(q)) - zs(actIdx(q)); else, wv(q) = limSup(actIdx(q)) - zs(actIdx(q)); end
    end
    if nA > 0
        A = actIdx(1:nA);  wv = Hinv(A,A) \ wv;  zq = zs + Hinv(:,A)*wv;
    else
        zq = zs;
    end
    peorK = 0;  peorV = 1e-7;
    for q = 1:nA
        if actLado(q) < 0, s = -wv(q); else, s = wv(q); end
        if s > peorV, peorV = s; peorK = q; end
    end
    if peorK > 0
        esActiva(actIdx(peorK)) = false;
        actIdx(peorK:nA-1) = actIdx(peorK+1:nA);  actLado(peorK:nA-1) = actLado(peorK+1:nA);  nA = nA - 1;
    else
        nuevoI = 0;  nuevoLado = 0;  peorV = 1e-7;
        for i = 1:18
            if ~esActiva(i)
                if (limInf(i) - zq(i)) > peorV, peorV = limInf(i) - zq(i); nuevoI = i; nuevoLado = -1;
                elseif (zq(i) - limSup(i)) > peorV, peorV = zq(i) - limSup(i); nuevoI = i; nuevoLado = 1; end
            end
        end
        if nuevoI > 0
            nA = nA + 1;  actIdx(nA) = nuevoI;  actLado(nA) = nuevoLado;  esActiva(nuevoI) = true;
        else
            convergio = true;
        end
    end
end
end

function mv = recorte(mv, mvprev, Mlim, uoff)
% Recorte final del SCL: cambio por muestra y apertura (mismos limites del MPC completo)
dumax = Mlim(37:39);  dumin = -Mlim(55:57);  umax = Mlim(1:3) + uoff;  umin = -Mlim(19:21) + uoff;
du = mv - mvprev;  mv = min(max(mv, mvprev + dumin), mvprev + dumax);  mv = min(max(mv, umin), umax);
end

function f = resolver(f, raiz)
% Si la ruta relativa no existe desde la carpeta actual, se busca desde la raiz del repositorio.
if exist(f, 'file') == 0 && exist(f, 'dir') == 0 && (exist(fullfile(raiz, f), 'file') ~= 0 || exist(fullfile(raiz, f), 'dir') ~= 0), f = fullfile(raiz, f); end
end

function K = constantes_scl(txt)
txt = regexprep(txt, '\(\*.*?\*\)', '');
nombres = {'b_a','MPC_3_c_a','MPC_3_b_Mlim','MPC_3_b_Kx','MPC_3_b_Ku1','MPC_3_b_Kr','MPC_3_b_Hinv','MPC_3_b_uoff','MPC_3_f_a','MPC_3_g_a','MPC_3_e_a','MPC_3_b_xoff','MPC_3_b_myoff','MPC_3_b_RYscale','c_last_x_InitialCond'};
campos  = {'b_a','c_a','Mlim','Kx','Ku1','Kr','Hinv','uoff','f_a','g_a','e_a','xoff','myoff','RYscale','x0'};
for i = 1:numel(nombres)
    t = regexp(txt, [nombres{i} '\s*:\s*ARRAY\s*\[[^\]]*\]\s*OF\s*REAL\s*:=\s*\[([^\]]*)\]'], 'tokens', 'once');
    if isempty(t), error('No se encontro %s en el SCL', nombres{i}); end
    v = regexp(strtrim(t{1}), '[,\s]+', 'split');  v = v(~cellfun(@isempty, v));
    K.(campos{i}) = str2double(v);
end
end

function p = prctile_(x, q)
x = sort(x(:)); p = x(max(1, ceil(q/100*numel(x))));
end
