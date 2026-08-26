import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

void main() {
  runApp(const AppManutencaoBalancas());
}

class AppManutencaoBalancas extends StatelessWidget {
  const AppManutencaoBalancas({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manutenção Rodoviária',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
      ),
      home: const TelaInspecaoRodoviaria(),
    );
  }
}

class TelaInspecaoRodoviaria extends StatefulWidget {
  const TelaInspecaoRodoviaria({super.key});

  @override
  State<TelaInspecaoRodoviaria> createState() => _TelaInspecaoRodoviariaState();
}

class _TelaInspecaoRodoviariaState extends State<TelaInspecaoRodoviaria> {
  final _formKey = GlobalKey<FormState>();

  int qtdCelulas = 8; // Padrão 8 células (4 seções)

  // Controle do Checklist Físico
  bool limpoFosso = false;
  bool drenagemOk = false;
  bool aterramentoOk = false;
  bool limitadoresOk = false;
  bool caixaJuncaoOk = false;

  // Controllers para as medições das Seções (Excentricidade)
  final Map<int, TextEditingController> _controllersSecao = {};

  // Nome do responsável/assinatura (texto)
  final TextEditingController _assinaturaController = TextEditingController();

  // Bytes da assinatura manuscrita (PNG) - será incluído no PDF
  Uint8List? _assinaturaImagemBytes;

  @override
  void initState() {
    super.initState();
    _atualizarControllersSecoes();
  }

  @override
  void dispose() {
    for (final controller in _controllersSecao.values) {
      controller.dispose();
    }
    _assinaturaController.dispose();
    super.dispose();
  }

  // Atualiza controladores preservando valores existentes e descartando (dispose) os removidos
  void _atualizarControllersSecoes() {
    final old = Map<int, TextEditingController>.from(_controllersSecao);
    _controllersSecao.clear();

    int qtdSecoes = (qtdCelulas / 2).ceil();
    for (int i = 1; i <= qtdSecoes; i++) {
      if (old.containsKey(i)) {
        // Preserve previous controller (e seu texto)
        _controllersSecao[i] = old[i]!;
      } else {
        _controllersSecao[i] = TextEditingController();
      }
    }

    // Dispose any controllers that are no longer used
    for (final key in old.keys) {
      if (!_controllersSecao.containsKey(key)) {
        old[key]!.dispose();
      }
    }
  }

  // Tenta converter string numérica (aceita "1.234,56", "1234,56", "1234.56", "1,234.56" etc.)
  double? _parseNumber(String input) {
    String s = input.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(' ', '');

    final hasDot = s.contains('.');
    final hasComma = s.contains(',');

    if (hasDot && hasComma) {
      // Decide com base na última ocorrência: último símbolo tende a ser o separador decimal
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        // '.' como separador de milhares, ',' decimal
        s = s.replaceAll('.', '');
        s = s.replaceAll(',', '.');
      } else {
        // ',' como separador de milhares, '.' decimal
        s = s.replaceAll(',', '');
      }
    } else if (hasComma) {
      // apenas vírgula -> decimal
      s = s.replaceAll(',', '.');
    }
    // else: apenas ponto ou nenhum separador -> tentar parse direto

    return double.tryParse(s);
  }

  @override
  Widget build(BuildContext context) {
    int qtdSecoes = (qtdCelulas / 2).ceil();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspeção de Balança Rodoviária'),
        backgroundColor: Colors.blueGrey[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SEÇÃO 1: DADOS DA BALANÇA ---
              _buildCardHeader('1. Identificação e Configuração', [
                DropdownButtonFormField<int>(
                  value: qtdCelulas,
                  decoration: const InputDecoration(labelText: 'Quantidade de Células de Carga'),
                  items: [4, 6, 8, 10, 12].map((int val) {
                    return DropdownMenuItem<int>(
                      value: val,
                      child: Text('$val Células (${(val / 2).ceil()} Seções)'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        qtdCelulas = val;
                        _atualizarControllersSecoes();
                      });
                    }
                  },
                ),
              ]),

              const SizedBox(height: 16),

              // --- SEÇÃO 2: CHECKLIST ESTRUTURAL E MECÂNICO ---
              _buildCardHeader('2. Checklist Estrutural e Elétrico', [
                CheckboxListTile(
                  title: const Text('Limpeza do Fosso / Abaixo da Plataforma'),
                  subtitle: const Text('Sem acúmulo de terra, pedras ou água nas células'),
                  value: limpoFosso,
                  onChanged: (v) => setState(() => limpoFosso = v ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Sistema de Drenagem / Bomba'),
                  subtitle: const Text('Bomba do fosso operacional'),
                  value: drenagemOk,
                  onChanged: (v) => setState(() => drenagemOk = v ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Limitadores e Batentes'),
                  subtitle: const Text('Folga mecânica adequada (2mm a 5mm)'),
                  value: limitadoresOk,
                  onChanged: (v) => setState(() => limitadoresOk = v ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Aterramento e Proteções'),
                  subtitle: const Text('Malha de aterramento e cordoalhas íntegras'),
                  value: aterramentoOk,
                  onChanged: (v) => setState(() => aterramentoOk = v ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Caixa de Junção (Junction Box)'),
                  subtitle: const Text('Vedação contra umidade/insetos e prensa-cabos OK'),
                  value: caixaJuncaoOk,
                  onChanged: (v) => setState(() => caixaJuncaoOk = v ?? false),
                ),
              ]),

              const SizedBox(height: 16),

              // --- SEÇÃO 3: TESTE DE EXCENTRICIDADE POR SEÇÃO ---
              _buildCardHeader('3. Ensaio por Seção (Excentricidade)', [
                const Text(
                  'Registre o valor indicado pelo indicador ao posicionar o veículo/CPP sobre cada seção:',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: qtdSecoes,
                  itemBuilder: (context, index) {
                    int secaoNum = index + 1;
                    int celulaA = (secaoNum * 2) - 1;
                    int celulaB = secaoNum * 2;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: TextFormField(
                        controller: _controllersSecao[secaoNum],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d\.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Seção $secaoNum (Células $celulaA e $celulaB) - Peso (kg)',
                          border: const OutlineInputBorder(),
                          suffixText: 'kg',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Preencha o peso da seção $secaoNum';
                          }
                          final parsed = _parseNumber(value);
                          if (parsed == null) {
                            return 'Valor inválido para a seção $secaoNum';
                          }
                          return null;
                        },
                      ),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 16),

              // --- SEÇÃO 4: ASSINATURA / RESPONSÁVEL ---
              _buildCardHeader('4. Responsável / Assinatura', [
                TextFormField(
                  controller: _assinaturaController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do responsável (assinatura)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o nome do responsável';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _openSignaturePad,
                      icon: const Icon(Icons.edit),
                      label: const Text('Capturar assinatura'),
                    ),
                    const SizedBox(width: 12),
                    if (_assinaturaImagemBytes != null)
                      TextButton.icon(
                        onPressed: () => setState(() => _assinaturaImagemBytes = null),
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        label: const Text('Remover', style: TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: _assinaturaImagemBytes != null
                      ? Image.memory(_assinaturaImagemBytes!, fit: BoxFit.contain)
                      : const Text('Nenhuma assinatura capturada', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'O logo será incluído automaticamente no cabeçalho/rodapé se existir em assets/logo.png',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              ]),

              const SizedBox(height: 24),

              // --- BOTÃO DE FINALIZAR E GERAR RELATÓRIO ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[800],
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.save),
                  label: const Text('FINALIZAR E GERAR RELATÓRIO'),
                  onPressed: () {
                    _onFinalizarPressed();
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // Componente Auxiliar para Caixas (Cards)
  Widget _buildCardHeader(String titulo, List<Widget> filhos) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...filhos,
          ],
        ),
      ),
    );
  }

  Future<void> _openSignaturePad() async {
    // Open a dialog with a Signature widget. Use a local SignatureController that we dispose after dialog.
    final SignatureController controller = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Assinatura - desenhe abaixo'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Signature(
                      controller: controller,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => controller.clear(),
                      icon: const Icon(Icons.clear),
                      label: const Text('Limpar'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final data = await controller.toPngBytes();
                        if (data != null && mounted) {
                          setState(() {
                            _assinaturaImagemBytes = data;
                          });
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    controller.dispose();
  }

  void _onFinalizarPressed() {
    final form = _formKey.currentState;
    if (form == null) return;

    if (!form.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, corrija os campos destacados antes de continuar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_assinaturaImagemBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, capture a assinatura antes de continuar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final Map<int, double> secoesParseadas = {};
    bool parseErro = false;

    for (final entry in _controllersSecao.entries) {
      final text = entry.value.text;
      final parsed = _parseNumber(text);
      if (parsed == null) {
        parseErro = true;
        break;
      }
      secoesParseadas[entry.key] = parsed;
    }

    if (parseErro) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao interpretar alguns valores numéricos.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _showResumoDialog(secoesParseadas);
  }

  Future<void> _showResumoDialog(Map<int, double> secoesParseadas) async {
    final total = secoesParseadas.values.fold<double>(0.0, (a, b) => a + b);
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Resumo da Inspeção'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quantidade de células: $qtdCelulas'),
                const SizedBox(height: 8),
                const Text('Checklist:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(' - Drenagem: ${drenagemOk ? "OK" : "NÃO"}'),
{