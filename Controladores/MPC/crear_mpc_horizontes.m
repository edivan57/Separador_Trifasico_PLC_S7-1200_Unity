function archivos = crear_mpc_horizontes(P_lista, origen)


if nargin < 1 || isempty(P_lista), P_lista = [100 50]; end
if nargin < 2 || isempty(origen), origen = 'TPSEP_MPC_diseno_P_M6.mat'; end
S = load(origen);
if ~isfield(S, 'mpc1'), error('crear_mpc_horizontes:mpc1', '%s no tiene mpc1', origen); end
fprintf('Origen: %s (P = %d, M = %s)\n', origen, S.mpc1.PredictionHorizon, mat2str(S.mpc1.ControlHorizon));
archivos = {};
for P = P_lista(:)'
    T = S;
    T.mpc1.PredictionHorizon = P;
    % Comprobacion: solo cambio P
    if ~isequal(T.mpc1.ControlHorizon, S.mpc1.ControlHorizon) || ~isequal(T.mpc1.Weights, S.mpc1.Weights)
        error('crear_mpc_horizontes:cambio', 'Cambio algo mas que el horizonte');
    end
    f = sprintf('TPSEP_MPC_diseno_P%d.mat', P);
    save(f, '-struct', 'T');
    archivos{end+1} = f; %#ok<AGROW>
    fprintf('  %s: P = %d (%.0f s), M = %s\n', f, T.mpc1.PredictionHorizon, P*T.mpc1.Ts, mat2str(T.mpc1.ControlHorizon));
end
end
