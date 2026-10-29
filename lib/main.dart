import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const ControlESP32App());

class ControlESP32App extends StatelessWidget {
  const ControlESP32App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Control ESP32',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF1F3F5),
        primarySwatch: Colors.blueGrey,
      ),
      home: const PantallaPrincipal(),
    );
  }
}

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  BluetoothConnection? conexion;
  bool conectado = false;
  bool conectando = false;

  String tempActual = "--";
  String modoActual = "AUTO";
  bool foco = false;
  bool ventilador = false;
  String estadoAlerta = "NORMAL";
  double minTemp = 30.0;
  double maxTemp = 35.0;

  final TextEditingController _minCtrl = TextEditingController(text: "30.0");
  final TextEditingController _maxCtrl = TextEditingController(text: "35.0");
  String bufferRecibido = "";

  @override
  void initState() {
    super.initState();
    solicitarPermisos();
  }

  Future<void> solicitarPermisos() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> conectarESP32() async {
    setState(() => conectando = true);
    try {
      List<BluetoothDevice> dispositivos = await FlutterBluetoothSerial.instance.getBondedDevices();
      BluetoothDevice? esp32;
      for (var d in dispositivos) {
        if (d.name == "ESP32_Temperatura") {
          esp32 = d;
          break;
        }
      }

      if (esp32 == null) {
        mostrarMensaje("Vincula primero 'ESP32_Temperatura' en los ajustes de Bluetooth");
        setState(() => conectando = false);
        return;
      }

      conexion = await BluetoothConnection.toAddress(esp32.address);
      setState(() {
        conectado = true;
        conectando = false;
      });

      conexion!.input!.listen((Uint8List data) {
        bufferRecibido += ascii.decode(data);
        if (bufferRecibido.contains("\n")) {
          List<String> lineas = bufferRecibido.split("\n");
          for (int i = 0; i < lineas.length - 1; i++) {
            procesarTrama(lineas[i].trim());
          }
          bufferRecibido = lineas.last;
        }
      }).onDone(() {
        setState(() => conectado = false);
      });
    } catch (e) {
      mostrarMensaje("Error al conectar: $e");
      setState(() {
        conectando = false;
        conectado = false;
      });
    }
  }

  void procesarTrama(String trama) {
    if (trama.isEmpty) return;
    List<String> p = trama.split(",");
    if (p.length >= 7) {
      setState(() {
        tempActual = p[0];
        foco = p[1] == "1";
        ventilador = p[2] == "1";
        modoActual = p[3];
        minTemp = double.tryParse(p[4]) ?? minTemp;
        maxTemp = double.tryParse(p[5]) ?? maxTemp;
        estadoAlerta = p[6];
      });
    }
  }

  void enviarComando(String cmd) {
    if (conexion != null && conexion!.isConnected) {
      conexion!.output.add(ascii.encode("$cmd\n"));
    }
  }

  void mostrarMensaje(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Control ESP32'),
        backgroundColor: const Color(0xFF263238),
        actions: [
          IconButton(
            icon: Icon(conectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
            onPressed: conectando ? null : (conectado ? () => conexion?.finish() : conectarESP32),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(conectado ? "Conectado a ESP32" : "Desconectado",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: conectado ? Colors.green[700] : Colors.red[700])),
                    ElevatedButton(
                      onPressed: conectando ? null : (conectado ? () => conexion?.finish() : conectarESP32),
                      child: Text(conectando ? "Conectando..." : (conectado ? "Desconectar" : "Conectar")),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text("TEMPERATURA ACTUAL", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("$tempActual °C", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: estadoAlerta == "ALTA" ? Colors.red[100] : Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        estadoAlerta == "ALTA" ? "ALERTA: TEMPERATURA ALTA" : "ESTADO NORMAL",
                        style: TextStyle(
                          color: estadoAlerta == "ALTA" ? Colors.red[900] : Colors.green[900],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("MODO DE OPERACIÓN", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: modoActual == "AUTO" ? Colors.blueGrey[800] : Colors.grey[300],
                              foregroundColor: modoActual == "AUTO" ? Colors.white : Colors.black,
                            ),
                            onPressed: () => enviarComando("AUTO"),
                            child: const Text("AUTOMÁTICO"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: modoActual == "MANUAL" ? Colors.blueGrey[800] : Colors.grey[300],
                              foregroundColor: modoActual == "MANUAL" ? Colors.white : Colors.black,
                            ),
                            onPressed: () => enviarComando("MANUAL"),
                            child: const Text("MANUAL"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("CONTROL DE ACTUADORES (MANUAL)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Foco: ${foco ? 'ENCENDIDO' : 'APAGADO'}", style: const TextStyle(fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            ElevatedButton(onPressed: () => enviarComando("FOCO_ON"), child: const Text("ON")),
                            const SizedBox(width: 6),
                            OutlinedButton(onPressed: () => enviarComando("FOCO_OFF"), child: const Text("OFF")),
                          ],
                        )
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Ventilador: ${ventilador ? 'ENCENDIDO' : 'APAGADO'}", style: const TextStyle(fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            ElevatedButton(onPressed: () => enviarComando("VENT_ON"), child: const Text("ON")),
                            const SizedBox(width: 6),
                            OutlinedButton(onPressed: () => enviarComando("VENT_OFF"), child: const Text("OFF")),
                          ],
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("RANGOS DE HISTÉRESIS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: "Mínima (°C)", border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _maxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: "Máxima (°C)", border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF263238)),
                        onPressed: () {
                          enviarComando("RANGE,${_minCtrl.text},${_maxCtrl.text}");
                        },
                        child: const Text("ACTUALIZAR RANGOS", style: TextStyle(color: Colors.white)),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
