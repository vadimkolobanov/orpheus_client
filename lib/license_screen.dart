// lib/license_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/main.dart';

class LicenseScreen extends StatefulWidget {
  final VoidCallback onLicenseConfirmed;
  const LicenseScreen({super.key, required this.onLicenseConfirmed});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Состояние Crypto
  bool _isLoadingCrypto = false;
  Map<String, dynamic>? _invoice;
  StreamSubscription? _wsSubscription;

  // Состояние Promo
  final TextEditingController _promoController = TextEditingController();
  bool _isActivatingPromo = false;
  String? _promoError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Запускаем запрос инвойса с небольшой задержкой, чтобы UI успел отрисоваться
    Future.delayed(Duration.zero, () {
      _requestInvoice();
    });

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
    // Убираем пробелы, но оставляем регистр и символы
    final code = _promoController.text.trim();

    if (code.isEmpty) {
      setState(() => _promoError = "Введите код");
      return;
    }

    setState(() {
      _isActivatingPromo = true;
      _promoError = null;
    });

    try {
      final myPubkey = cryptoService.publicKeyBase64;
      if (myPubkey == null) throw Exception("Ключи не инициализированы");

      // HTTP запрос
      final url = Uri.parse(AppConfig.httpUrl('/api/activate-promo'));
      print("Sending promo request to $url with code: $code");

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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Промокод принят!"))
        );
        // websocketService сам пришлет подтверждение лицензии
      } else {
        setState(() {
          _promoError = data['message'] ?? "Неверный код";
        });
      }
    } catch (e) {
      setState(() {
        _promoError = "Ошибка соединения. Проверьте интернет.";
      });
      print("Promo error: $e");
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
    // Используем GestureDetector, чтобы убирать клавиатуру при тапе в пустоту
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.black, // Темная тема
        appBar: AppBar(
          title: const Text("АКТИВАЦИЯ"),
          backgroundColor: const Color(0xFF101010),
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFFB0BEC5), // Серебро
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFFB0BEC5),
            tabs: const [
              Tab(text: "CRYPTO"),
              Tab(text: "ПРОМОКОД"),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCryptoTab(),
              _buildPromoTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCryptoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.currency_bitcoin, size: 60, color: Colors.orange),
          const SizedBox(height: 24),
          const Text(
            "Оплата TRON (TRX)",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
            "Автоматическая активация после перевода точной суммы.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          if (_isLoadingCrypto)
            const CircularProgressIndicator(color: Colors.white)
          else if (_invoice != null) ...[
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                  color: const Color(0xFF202020),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12)
              ),
              child: Column(
                children: [
                  Text("Сумма: ${_invoice!['amount']} TRX",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _invoice!['address'],
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.white),
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
            const LinearProgressIndicator(color: Colors.orange, backgroundColor: Colors.grey),
            const SizedBox(height: 8),
            const Text("Ожидание транзакции...", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]
        ],
      ),
    );
  }

  Widget _buildPromoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.vpn_key, size: 60, color: Color(0xFFB0BEC5)),
          const SizedBox(height: 24),
          const Text(
            "ВВЕДИТЕ КОД",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
          ),
          const SizedBox(height: 10),
          const Text(
            "Введите полученный код активации.\nПоддерживаются символы _ и -",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _promoController,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'monospace'),
            textAlign: TextAlign.center,

            // ВАЖНО: Это позволяет вводить любые символы без автозамены
            keyboardType: TextInputType.visiblePassword,

            decoration: InputDecoration(
              hintText: 'CODE-XXXX-XXXX',
              hintStyle: TextStyle(color: Colors.grey[700]),
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFB0BEC5))),
              errorText: _promoError,
            ),
            // ВАЖНО: Делаем ввод капсом, но не запрещаем символы
            textCapitalization: TextCapitalization.characters,
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isActivatingPromo ? null : _activatePromo,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB0BEC5),
                foregroundColor: Colors.black,
              ),
              child: _isActivatingPromo
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text("АКТИВИРОВАТЬ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}