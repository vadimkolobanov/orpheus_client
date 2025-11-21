// lib/license_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/main.dart'; // Для доступа к cryptoService и websocketService

class LicenseScreen extends StatefulWidget {
  final VoidCallback onLicenseConfirmed;
  const LicenseScreen({super.key, required this.onLicenseConfirmed});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Состояние для вкладки Crypto
  bool _isLoadingCrypto = false;
  Map<String, dynamic>? _invoice;
  StreamSubscription? _wsSubscription;

  // Состояние для вкладки Promo
  final TextEditingController _promoController = TextEditingController();
  bool _isActivatingPromo = false;
  String? _promoError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Сразу запрашиваем инвойс при входе
    _requestInvoice();

    _wsSubscription = websocketService.stream.listen((message) {
      try {
        final data = json.decode(message);
        if (data['type'] == 'payment-invoice') {
          if (mounted) {
            setState(() {
              _invoice = data;
              _isLoadingCrypto = false;
            });
          }
        } else if (data['type'] == 'payment-confirmed' ||
            (data['type'] == 'license-status' && data['status'] == 'active')) {
          widget.onLicenseConfirmed();
        }
      } catch (_) {}
    });
  }

  void _requestInvoice() {
    setState(() => _isLoadingCrypto = true);
    final msg = json.encode({"type": "payment-create-invoice"});
    websocketService.sendRawMessage(msg);
  }

  Future<void> _activatePromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isActivatingPromo = true;
      _promoError = null;
    });

    try {
      final myPubkey = cryptoService.publicKeyBase64;
      if (myPubkey == null) throw Exception("Ключи не инициализированы");

      // Используем HTTP для одноразового запроса
      final url = Uri.parse(AppConfig.httpUrl('/api/activate-promo'));

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "pubkey": myPubkey,
          "code": code
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'ok') {
        // Успех! Сервер сам пришлет уведомление в сокет о смене статуса,
        // и наш _wsSubscription сработает и закроет экран.
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Промокод принят! Активация..."))
        );
      } else {
        setState(() {
          _promoError = data['message'] ?? "Ошибка активации";
        });
      }
    } catch (e) {
      setState(() {
        _promoError = "Ошибка соединения: $e";
      });
    } finally {
      if (mounted) setState(() => _isActivatingPromo = false);
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _tabController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Лицензия"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: "Оплата Crypto"),
            Tab(text: "Промокод"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCryptoTab(),
          _buildPromoTab(),
        ],
      ),
    );
  }

  Widget _buildCryptoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.currency_bitcoin, size: 60, color: Colors.orange),
          const SizedBox(height: 24),
          const Text(
            "Оплата TRON (TRX)",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "Переведите точную сумму на адрес ниже. Активация произойдет автоматически.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          if (_isLoadingCrypto)
            const CircularProgressIndicator()
          else if (_invoice != null) ...[
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: QrImageView(
                data: _invoice!['address'],
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Text("Сумма: ${_invoice!['amount']} TRX",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _invoice!['address'],
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _invoice!['address']));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Адрес скопирован")));
                        },
                      )
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text("Ожидание транзакции...", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]
        ],
      ),
    );
  }

  Widget _buildPromoTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.vpn_key, size: 60, color: Colors.blueGrey),
          const SizedBox(height: 24),
          const Text(
            "Есть код активации?",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "Введите код, который вы получили от администратора или купили альтернативным способом.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _promoController,
            decoration: InputDecoration(
              labelText: 'Промокод',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.confirmation_number),
              errorText: _promoError,
            ),
            textCapitalization: TextCapitalization.characters,
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isActivatingPromo ? null : _activatePromo,
              child: _isActivatingPromo
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Активировать"),
            ),
          ),
        ],
      ),
    );
  }
}