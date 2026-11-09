function s = hemihead(h,Ds,L)
%HEMIHEAD Factor de forma (derivada geométrica para balances) [m^2].
% Basado en Anexo E.
A = 1/(sqrt(h*(Ds-h)));
B = (Ds-2*h)/(2*Ds*sqrt(h*Ds-h^2));
C = (-4*(h^2)+3*Ds*h)/(2*Ds*sqrt(Ds*h-(h^2)));
D = (2*h/(Ds^2));
E = ((3*h^2)/(Ds^3));

w1= (L*Ds^2)*((A/4)-(B/2)+(C/Ds));
w2= ((pi()*Ds^3)/12)*(3*D-2*E);
s = w1+w2;
end
