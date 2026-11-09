function v = hemivols(h,L,D)
%HEMIVOLS Volumen ocupado por líquido en una sección con cabezas hemisféricas.
% Basado en Anexo D.
% vcil = (L*D^2)*(((1/4)*acos(1-(2*h/D))) - ((0.5-(h/D))*sqrt((h/D) - ((h/D)^2))));
% vcap = ((D^3*pi())/12)*((3*(h/D)^2) - (2*(h/D)^3));
% v = vcil + vcap;

% Limitar altura al rango físico
h = min(max(h,0),D);

x = 1 - (2*h/D);
x = min(max(x,-1),1);

vcil = (L*D^2)*(((1/4)*acos(x)) - ((0.5-(h/D))*sqrt(max((h/D) - ((h/D)^2),0))));
vcap = ((D^3*pi())/12)*((3*(h/D)^2) - (2*(h/D)^3));

v = vcil + vcap;

end
