function info = crear_modelos_v12(modelos, sufijo, aplicar)


if nargin < 1 || isempty(modelos)
    modelos = {'Simulacion_Trifasico_PID_v8', 'Simulacion_Trifasico_Fuzzy_v10', 'Simulacion_Trifasico_MPC_v6'};
end
if ischar(modelos), modelos = {modelos}; end
if nargin < 2 || isempty(sufijo), sufijo = '_v12'; end
if nargin < 3 || isempty(aplicar), aplicar = true; end

info = struct('modelo', {}, 'copia', {}, 'cambios', {}, 'revisar', {});
for i = 1:numel(modelos)
    mdl = modelos{i};
    f = which(mdl);
    if isempty(f), error('crear_modelos_v12:no', 'No encuentro el modelo %s en la ruta.', mdl); end
    [carpeta, ~, ext] = fileparts(f);
    nuevo = [mdl sufijo];
    load_system(mdl);
    if aplicar
        if bdIsLoaded(nuevo), close_system(nuevo, 0); end
        save_system(mdl, fullfile(carpeta, [nuevo ext]));   % la copia queda cargada con el nombre nuevo
        obj = nuevo;
    else
        obj = mdl;
    end

    cambios = {};
    % 1) Bloques MATLAB Function (objetos Stateflow.EMChart)
    %    a) Si el bloque ES la planta (function ... = tpsep_v11(...) con las ecuaciones dentro),
    %       se reemplaza todo su codigo por el de tpsep_v12_bloque.m.
    %    b) Si el bloque solo LLAMA a tpsep_v11(...), se cambia la llamada por tpsep_v12.
    codigo_v12 = fileread(which('tpsep_v12_bloque.m'));
    rt = sfroot;
    m = rt.find('-isa', 'Simulink.BlockDiagram', 'Name', obj);
    ch = m.find('-isa', 'Stateflow.EMChart');
    for k = 1:numel(ch)
        sc = ch(k).Script;
        cab = regexp(sc, '^\s*function\s*\[\s*(\w+)\s*,\s*(\w+)\s*\]\s*=\s*tpsep_v11\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)', 'tokens', 'once', 'lineanchors');
        if ~isempty(cab)
            % Mismos nombres de entradas y salidas que el bloque original (son sus puertos)
            nuevo_codigo = regexprep(codigo_v12, '^function\s*\[data, output\]\s*=\s*tpsep_v12_bloque\(input, recycle\)', ...
                sprintf('function [%s, %s] = tpsep_v12(%s, %s)', cab{1}, cab{2}, cab{3}, cab{4}), 'once', 'lineanchors');
            if ~strcmp(cab{1}, 'data') || ~strcmp(cab{2}, 'output') || ~strcmp(cab{3}, 'input') || ~strcmp(cab{4}, 'recycle')
                nuevo_codigo = regexprep(nuevo_codigo, '\<data\>', cab{1});
                nuevo_codigo = regexprep(nuevo_codigo, '\<output\>', cab{2});
                nuevo_codigo = regexprep(nuevo_codigo, '\<input\>', cab{3});
                nuevo_codigo = regexprep(nuevo_codigo, '\<recycle\>', cab{4});
            end
            cambios{end+1} = sprintf('Planta reemplazada por el codigo v12: %s', ch(k).Path); %#ok<AGROW>
            if aplicar, ch(k).Script = nuevo_codigo; end
        elseif ~isempty(regexp(sc, '^[^%\n]*tpsep_v11\s*\(', 'once', 'lineanchors'))
            cambios{end+1} = sprintf('Llamada cambiada a tpsep_v12: %s', ch(k).Path); %#ok<AGROW>
            if aplicar, ch(k).Script = strrep(sc, 'tpsep_v11', 'tpsep_v12'); end
        end
    end
    % 2) Bloques Interpreted MATLAB Function
    tipos = {'MATLABFcn', 'InterpretedMATLABFcn'};
    for t = 1:numel(tipos)
        try   % R2021a y posteriores: incluye las variantes inactivas
            b = find_system(obj, 'MatchFilter', @Simulink.match.allVariants, 'LookUnderMasks', 'all', ...
                            'FollowLinks', 'on', 'BlockType', tipos{t});
        catch
            b = find_system(obj, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', tipos{t});
        end
        for k = 1:numel(b)
            par = get_param(b{k}, 'MATLABFcn');
            if contains(par, 'tpsep_v11')
                cambios{end+1} = sprintf('Interpreted MATLAB Fcn: %s', b{k}); %#ok<AGROW>
                if aplicar, set_param(b{k}, 'MATLABFcn', strrep(par, 'tpsep_v11', 'tpsep_v12')); end
            end
        end
    end
    % 3) Devoluciones de llamada del modelo que conviene revisar
    revisar = {};
    cbs = {'PreLoadFcn', 'PostLoadFcn', 'InitFcn', 'StartFcn', 'StopFcn'};
    for k = 1:numel(cbs)
        txt = get_param(obj, cbs{k});
        if contains(txt, 'tpsep_v11') || contains(txt, '.mat') || contains(txt, 'load')
            revisar{end+1} = sprintf('%s: %s', cbs{k}, strtrim(txt)); %#ok<AGROW>
        end
    end

    if aplicar
        save_system(obj);
        close_system(obj, 0);
    else
        close_system(mdl, 0);
    end

    fprintf('\n%s -> %s\n', mdl, ternario(aplicar, nuevo, '(solo listado)'));
    if isempty(cambios)
        warning('crear_modelos_v12:sin', ['En %s no hay bloques que llamen a tpsep_v11. Si la planta esta en una ' ...
                'biblioteca enlazada o en un subsistema con otro nombre, cambiela a mano.'], mdl);
    else
        fprintf('  Cambiado: %s\n', strjoin(cambios, ' | '));
    end
    if ~isempty(revisar)
        fprintf('  Revise estas devoluciones de llamada (pueden recargar el controlador o el punto de operacion):\n');
        fprintf('    %s\n', revisar{:});
    end
    info(end+1) = struct('modelo', mdl, 'copia', nuevo, 'cambios', {cambios}, 'revisar', {revisar}); %#ok<AGROW>
end
end

function s = ternario(c, a, b)
if c, s = a; else, s = b; end
end
