package com.pablo

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import java.io.InputStream
import java.io.OutputStream
import java.util.*

class MainActivity : AppCompatActivity() {

    private var btSocket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private var inputStream: InputStream? = null
    private var conectado = false
    private val uuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private lateinit var tvTemp: TextView
    private lateinit var tvModo: TextView
    private lateinit var tvFoco: TextView
    private lateinit var tvVent: TextView
    private lateinit var tvEstado: TextView
    private lateinit var btnConectar: Button
    private lateinit var etMin: EditText
    private lateinit var etMax: EditText

    private val handler = Handler(Looper.getMainLooper())

    @SuppressLint("MissingInflatedId")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(40, 50, 40, 50)
        }

        val titulo = TextView(this).apply {
            text = "Panel de Control ESP32"
            textSize = 22f
            textAlignment = TextView.TEXT_ALIGNMENT_CENTER
        }
        layout.addView(titulo)

        btnConectar = Button(this).apply {
            text = "Conectar Bluetooth"
            setOnClickListener { if (conectado) desconectar() else conectar() }
        }
        layout.addView(btnConectar)

        tvEstado = TextView(this).apply {
            text = "Estado: Desconectado"
            textSize = 14f
        }
        layout.addView(tvEstado)

        tvTemp = TextView(this).apply {
            text = "-- °C"
            textSize = 42f
            textAlignment = TextView.TEXT_ALIGNMENT_CENTER
        }
        layout.addView(tvTemp)

        tvModo = TextView(this).apply { text = "Modo: --" }
        tvFoco = TextView(this).apply { text = "Foco: --" }
        tvVent = TextView(this).apply { text = "Ventilador: --" }
        layout.addView(tvModo)
        layout.addView(tvFoco)
        layout.addView(tvVent)

        val btnAuto = Button(this).apply {
            text = "Modo AUTO"
            setOnClickListener { enviar("AUTO\n") }
        }
        val btnManual = Button(this).apply {
            text = "Modo MANUAL"
            setOnClickListener { enviar("MANUAL\n") }
        }
        val btnFocoOn = Button(this).apply {
            text = "Encender Foco"
            setOnClickListener { enviar("FOCO_ON\n") }
        }
        val btnFocoOff = Button(this).apply {
            text = "Apagar Foco"
            setOnClickListener { enviar("FOCO_OFF\n") }
        }
        val btnVentOn = Button(this).apply {
            text = "Encender Ventilador"
            setOnClickListener { enviar("VENT_ON\n") }
        }
        val btnVentOff = Button(this).apply {
            text = "Apagar Ventilador"
            setOnClickListener { enviar("VENT_OFF\n") }
        }

        layout.addView(btnAuto)
        layout.addView(btnManual)
        layout.addView(btnFocoOn)
        layout.addView(btnFocoOff)
        layout.addView(btnVentOn)
        layout.addView(btnVentOff)

        etMin = EditText(this).apply { hint = "Temp Min (ej: 30.0)" }
        etMax = EditText(this).apply { hint = "Temp Max (ej: 35.0)" }
        val btnRango = Button(this).apply {
            text = "Enviar Rangos"
            setOnClickListener {
                val min = etMin.text.toString()
                val max = etMax.text.toString()
                if (min.isNotEmpty() && max.isNotEmpty()) {
                    enviar("RANGE,$min,$max\n")
                }
            }
        }

        layout.addView(etMin)
        layout.addView(etMax)
        layout.addView(btnRango)

        val scroll = ScrollView(this).apply { addView(layout) }
        setContentView(scroll)

        pedirPermisos()
    }

    private fun pedirPermisos() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN
                ), 1
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun conectar() {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return
        val dispositivos = adapter.bondedDevices
        var device: BluetoothDevice? = null

        for (d in dispositivos) {
            if (d.name == "ESP32_Temperatura") {
                device = d
                break
            }
        }

        if (device == null) {
            Toast.makeText(this, "Vincula primero ESP32_Temperatura en Ajustes", Toast.LENGTH_LONG).show()
            return
        }

        Thread {
            try {
                btSocket = device.createRfcommSocketToServiceRecord(uuid)
                btSocket?.connect()
                outputStream = btSocket?.outputStream
                inputStream = btSocket?.inputStream
                conectado = true

                handler.post {
                    btnConectar.text = "Desconectar"
                    tvEstado.text = "Estado: Conectado a ESP32"
                }

                escucharDatos()
            } catch (e: Exception) {
                handler.post {
                    tvEstado.text = "Error al conectar: ${e.message}"
                }
            }
        }.start()
    }

    private fun escucharDatos() {
        val buffer = ByteArray(1024)
        var acumulador = ""

        while (conectado) {
            try {
                val bytes = inputStream?.read(buffer) ?: -1
                if (bytes > 0) {
                    val texto = String(buffer, 0, bytes)
                    acumulador += texto
                    if (acumulador.contains("\n")) {
                        val partes = acumulador.split("\n")
                        for (i in 0 until partes.size - 1) {
                            val linea = partes[i].trim()
                            procesarLinea(linea)
                        }
                        acumulador = partes.last()
                    }
                }
            } catch (e: Exception) {
                conectado = false
                handler.post {
                    btnConectar.text = "Conectar Bluetooth"
                    tvEstado.text = "Estado: Desconectado"
                }
                break
            }
        }
    }

    private fun procesarLinea(linea: String) {
        val d = linea.split(",")
        if (d.size >= 7) {
            handler.post {
                tvTemp.text = "${d[0]} °C"
                tvFoco.text = "Foco: ${if (d[1] == "1") "ENCENDIDO" else "APAGADO"}"
                tvVent.text = "Ventilador: ${if (d[2] == "1") "ENCENDIDO" else "APAGADO"}"
                tvModo.text = "Modo: ${d[3]}"
                tvEstado.text = "Estado: ${d[6]}"
            }
        }
    }

    private fun enviar(msg: String) {
        Thread {
            try {
                outputStream?.write(msg.toByteArray())
            } catch (_: Exception) {}
        }.start()
    }

    private fun desconectar() {
        conectado = false
        try {
            btSocket?.close()
        } catch (_: Exception) {}
        btnConectar.text = "Conectar Bluetooth"
        tvEstado.text = "Estado: Desconectado"
    }
}
