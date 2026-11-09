using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Sharp7;


public class Comunicacion : MonoBehaviour
{
    private S7Client CLIENT = new S7Client();
    public string ip;

    [Header("Diagnostico (solo lectura)")]
    public int contadorPLC;
    public int ecoSeq;
    public bool fallaComPLC;

    private Separador_Trifasico separador;

    void Start()
    {
        separador = FindObjectOfType<Separador_Trifasico>();
        if (ModoSincronizado()) { print("Comunicacion: modo sincronizado activo, este componente queda inactivo."); return; }

        data.IP = ip;
        if (Datos.datos.ConexionPLC == true)
        {
            data.IP = ip;
            print(data.IP);
            Conectar();
        }
        Datos.datos.Ip = data.IP;
    }

    private bool ModoSincronizado()
    {
        return separador != null && separador.sincronizarConPLC && separador.com != null;
    }

    void Conectar()
    {
        int connectionResult = CLIENT.ConnectTo(data.IP, 0, 1);
        if (connectionResult != 0)
        {
            Debug.LogError("Connection error");
            return;
        }
        else
        {
            print("PLC Connected!");
        }
    }

    void Update()
    {
        if (ModoSincronizado()) return;
        if (Datos.datos.ConexionPLC == true)
        {
            Actualizar();
        }
    }

    void Actualizar()
    {
        if (Input.GetKeyDown(KeyCode.L))
        {
            Desconectar();
        }

        // ---------- Lectura: DB1 completo, 0-136 ----------
        byte[] buffer = new byte[DB1Mapa.LECTURA_INI + DB1Mapa.LECTURA_TAM];
        int readResult = CLIENT.DBRead(DB1Mapa.DB, 0, buffer.Length, buffer);
        if (readResult != 0)
        {
            Debug.LogError("ERROR LEER DATOS: " + CLIENT.ErrorText(readResult));
            return;
        }

        // Accion de control del PLC: Cv_[0..2] (bytes 76, 80, 84) en los tres controladores.
        Datos.datos.cv1v = (S7.GetRealAt(buffer, DB1Mapa.CV_ + 0));
        Datos.datos.cv2v = (S7.GetRealAt(buffer, DB1Mapa.CV_ + 4));
        Datos.datos.cv3v = (S7.GetRealAt(buffer, DB1Mapa.CV_ + 8));

        contadorPLC = S7.GetDIntAt(buffer, DB1Mapa.CONTADOR_PLC);
        ecoSeq = S7.GetDIntAt(buffer, DB1Mapa.ECO_SEQ);
        fallaComPLC = S7.GetBitAt(buffer, DB1Mapa.FALLA_COM, 0);

        // ---------- Escritura: zona de Unity (0-75 y 88-123), luego Seq_Unity ----------
        byte[] imagen = DB1Mapa.Imagen(Datos.datos, false);
        if (separador != null && separador.enPausa) imagen[0] = 0;   // pausa entre repeticiones: PLC inactivo
        int writeResult = DB1Mapa.EscribirZonaUnity(CLIENT, imagen);
        if (writeResult != 0)
        {
            Debug.LogError("ERROR ESCRIBIR DATOS: " + CLIENT.ErrorText(writeResult));
            return;
        }
        DB1Mapa.EscribirSeq(CLIENT, Datos.datos.num);

        //CLIENT.Disconnect();
    }

    void Desconectar()
    {
        CLIENT.Disconnect();
        CLIENT.ClearSessionPassword();
    }
}
