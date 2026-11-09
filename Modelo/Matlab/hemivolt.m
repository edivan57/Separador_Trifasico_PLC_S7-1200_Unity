function volt = hemivolt(ds,La,Lb)
%HEMIVOLT Volumen total del separador (cámara + cabezas hemisféricas).
% Basado en Anexo C.
volt = (((pi()*ds^2)/4)*(La+Lb)) + ((pi()*ds^3)/6);
end
