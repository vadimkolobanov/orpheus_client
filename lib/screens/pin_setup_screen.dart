// lib/screens/pin_setup_screen.dart
// Экран настройки PIN-кода и кода принуждения

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/models/security_config.dart';
import 'package:orpheus_project/services/auth_service.dart';

enum PinSetupMode {
  setPin,        // Установка нового PIN
  changePin,     // Изменение PIN
  disablePin,    // Отключение PIN
  setDuress,     // Установка duress кода
  disableDuress, // Отключение duress кода
  setWipeCode,   // Установка кода удаления
  disableWipeCode, // Отключение кода удаления
}

class PinSetupScreen extends StatefulWidget {
  final PinSetupMode mode;
  final VoidCallback? onSuccess;

  const PinSetupScreen({
    super.key,
    required this.mode,
    this.onSuccess,
  });

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> with SingleTickerProviderStateMixin {
  final _auth = AuthService.instance;
  
  String _enteredPin = '';
  String _confirmedPin = '';
  String _currentPin = ''; // Для изменения/отключения
  
  int _step = 0; // 0 = текущий PIN (если нужен), 1 = новый PIN, 2 = подтверждение
  bool _isError = false;
  String? _errorMessage;
  bool _isLoading = false;
  
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  String get _title {
    switch (widget.mode) {
      case PinSetupMode.setPin:
        return _step == 0 ? 'НОВЫЙ PIN' : 'ПОДТВЕРДИТЕ PIN';
      case PinSetupMode.changePin:
        if (_step == 0) return 'ТЕКУЩИЙ PIN';
        if (_step == 1) return 'НОВЫЙ PIN';
        return 'ПОДТВЕРДИТЕ PIN';
      case PinSetupMode.disablePin:
        return 'ВВЕДИТЕ PIN';
      case PinSetupMode.setDuress:
        if (_step == 0) return 'ОСНОВНОЙ PIN';
        if (_step == 1) return 'КОД ПРИНУЖДЕНИЯ';
        return 'ПОДТВЕРДИТЕ КОД';
      case PinSetupMode.disableDuress:
        return 'ОСНОВНОЙ PIN';
      case PinSetupMode.setWipeCode:
        if (_step == 0) return 'ОСНОВНОЙ PIN';
        if (_step == 1) return 'КОД УДАЛЕНИЯ';
        return 'ПОДТВЕРДИТЕ КОД';
      case PinSetupMode.disableWipeCode:
        return 'ОСНОВНОЙ PIN';
    }
  }

  String get _subtitle {
    switch (widget.mode) {
      case PinSetupMode.setPin:
        return _step == 0 
            ? 'Введите 6-значный PIN-код'
            : 'Повторите PIN-код для подтверждения';
      case PinSetupMode.changePin:
        if (_step == 0) return 'Введите текущий PIN-код';
        if (_step == 1) return 'Введите новый PIN-код';
        return 'Повторите новый PIN-код';
      case PinSetupMode.disablePin:
        return 'Для отключения введите текущий PIN';
      case PinSetupMode.setDuress:
        if (_step == 0) return 'Подтвердите основной PIN';
        if (_step == 1) return 'Введите код принуждения (отличный от основного)';
        return 'Повторите код принуждения';
      case PinSetupMode.disableDuress:
        return 'Введите основной PIN для отключения';
      case PinSetupMode.setWipeCode:
        if (_step == 0) return 'Подтвердите основной PIN';
        if (_step == 1) return 'Введите код удаления (отличный от основного PIN)';
        return 'Повторите код удаления';
      case PinSetupMode.disableWipeCode:
        return 'Введите основной PIN для отключения кода удаления';
    }
  }

  @override
  void initState() {
    super.initState();
    
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    
    // Определяем начальный шаг
    switch (widget.mode) {
      case PinSetupMode.setPin:
        _step = 0; // Сразу новый PIN
        break;
      case PinSetupMode.changePin:
      case PinSetupMode.setDuress:
      case PinSetupMode.disablePin:
      case PinSetupMode.disableDuress:
      case PinSetupMode.setWipeCode:
      case PinSetupMode.disableWipeCode:
        _step = 0; // Сначала текущий/основной PIN
        break;
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    if (_isLoading) return;
    
    HapticFeedback.lightImpact();
    
    setState(() {
      if (_enteredPin.length < 6) {
        _enteredPin += digit;
        _isError = false;
        _errorMessage = null;
      }
    });
    
    if (_enteredPin.length == 6) {
      _processPin();
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isEmpty || _isLoading) return;
    
    HapticFeedback.lightImpact();
    
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _isError = false;
      _errorMessage = null;
    });
  }

  Future<void> _processPin() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 200));
    
    switch (widget.mode) {
      case PinSetupMode.setPin:
        await _processSetPin();
        break;
      case PinSetupMode.changePin:
        await _processChangePin();
        break;
      case PinSetupMode.disablePin:
        await _processDisablePin();
        break;
      case PinSetupMode.setDuress:
        await _processSetDuress();
        break;
      case PinSetupMode.disableDuress:
        await _processDisableDuress();
        break;
      case PinSetupMode.setWipeCode:
        await _processSetWipeCode();
        break;
      case PinSetupMode.disableWipeCode:
        await _processDisableWipeCode();
        break;
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _processSetPin() async {
    if (_step == 0) {
      // Первый ввод — сохраняем и переходим к подтверждению
      _confirmedPin = _enteredPin;
      setState(() {
        _enteredPin = '';
        _step = 1;
      });
    } else {
      // Подтверждение
      if (_enteredPin == _confirmedPin) {
        await _auth.setPin(_enteredPin);
        HapticFeedback.mediumImpact();
        _showSuccessAndPop('PIN-код установлен');
      } else {
        _showError('PIN-коды не совпадают');
        _confirmedPin = '';
        _step = 0;
      }
    }
  }

  Future<void> _processChangePin() async {
    if (_step == 0) {
      // Проверяем текущий PIN
      final result = _auth.verifyPin(_enteredPin);
      if (result == PinVerifyResult.success) {
        _currentPin = _enteredPin;
        setState(() {
          _enteredPin = '';
          _step = 1;
        });
      } else {
        _showError('Неверный PIN-код');
      }
    } else if (_step == 1) {
      // Новый PIN
      _confirmedPin = _enteredPin;
      setState(() {
        _enteredPin = '';
        _step = 2;
      });
    } else {
      // Подтверждение нового PIN
      if (_enteredPin == _confirmedPin) {
        final success = await _auth.changePin(_currentPin, _enteredPin);
        if (success) {
          HapticFeedback.mediumImpact();
          _showSuccessAndPop('PIN-код изменён');
        } else {
          _showError('Ошибка изменения PIN');
        }
      } else {
        _showError('PIN-коды не совпадают');
        _confirmedPin = '';
        _step = 1;
      }
    }
  }

  Future<void> _processDisablePin() async {
    final success = await _auth.disablePin(_enteredPin);
    if (success) {
      HapticFeedback.mediumImpact();
      _showSuccessAndPop('PIN-код отключён');
    } else {
      _showError('Неверный PIN-код');
    }
  }

  Future<void> _processSetDuress() async {
    if (_step == 0) {
      // Проверяем основной PIN
      final result = _auth.verifyPin(_enteredPin);
      if (result == PinVerifyResult.success) {
        _currentPin = _enteredPin;
        setState(() {
          _enteredPin = '';
          _step = 1;
        });
      } else {
        _showError('Неверный PIN-код');
      }
    } else if (_step == 1) {
      // Проверяем, что duress != основной PIN
      if (_enteredPin == _currentPin) {
        _showError('Код должен отличаться от основного PIN');
        return;
      }
      _confirmedPin = _enteredPin;
      setState(() {
        _enteredPin = '';
        _step = 2;
      });
    } else {
      // Подтверждение duress кода
      if (_enteredPin == _confirmedPin) {
        final success = await _auth.setDuressCode(_currentPin, _enteredPin);
        if (success) {
          HapticFeedback.mediumImpact();
          _showSuccessAndPop('Код принуждения установлен');
        } else {
          _showError('Ошибка установки кода');
        }
      } else {
        _showError('Коды не совпадают');
        _confirmedPin = '';
        _step = 1;
      }
    }
  }

  Future<void> _processDisableDuress() async {
    final success = await _auth.disableDuressCode(_enteredPin);
    if (success) {
      HapticFeedback.mediumImpact();
      _showSuccessAndPop('Код принуждения отключён');
    } else {
      _showError('Неверный PIN-код');
    }
  }

  Future<void> _processSetWipeCode() async {
    if (_step == 0) {
      final result = _auth.verifyPin(_enteredPin);
      if (result == PinVerifyResult.success) {
        _currentPin = _enteredPin;
        setState(() {
          _enteredPin = '';
          _step = 1;
        });
      } else {
        _showError('Неверный PIN-код');
      }
    } else if (_step == 1) {
      if (_enteredPin == _currentPin) {
        _showError('Код должен отличаться от основного PIN');
        return;
      }
      _confirmedPin = _enteredPin;
      setState(() {
        _enteredPin = '';
        _step = 2;
      });
    } else {
      if (_enteredPin == _confirmedPin) {
        final success = await _auth.setWipeCode(_currentPin, _enteredPin);
        if (success) {
          HapticFeedback.mediumImpact();
          _showSuccessAndPop('Код удаления установлен');
        } else {
          _showError('Ошибка установки кода');
        }
      } else {
        _showError('Коды не совпадают');
        _confirmedPin = '';
        _step = 1;
      }
    }
  }

  Future<void> _processDisableWipeCode() async {
    final success = await _auth.disableWipeCode(_enteredPin);
    if (success) {
      HapticFeedback.mediumImpact();
      _showSuccessAndPop('Код удаления отключён');
    } else {
      _showError('Неверный PIN-код');
    }
  }

  void _showError(String message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _isError = true;
      _errorMessage = message;
      _enteredPin = '';
    });
    _shakeController.forward().then((_) => _shakeController.reset());
  }

  void _showSuccessAndPop(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF6AD394), size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    widget.onSuccess?.call();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text(
          _getAppBarTitle(),
          style: const TextStyle(fontSize: 16, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 1),
            
            // Иконка
            _buildIcon(),
            
            const SizedBox(height: 24),
            
            // Заголовок
            Text(
              _title,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Подзаголовок
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ),
            
            // Ошибка
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: 13,
                ),
              ),
            ],
            
            const SizedBox(height: 32),
            
            // PIN индикаторы
            _buildPinIndicators(),
            
            const Spacer(flex: 1),
            
            // PIN-pad
            _buildPinPad(),
            
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (widget.mode) {
      case PinSetupMode.setPin:
        return 'Установка PIN';
      case PinSetupMode.changePin:
        return 'Изменение PIN';
      case PinSetupMode.disablePin:
        return 'Отключение PIN';
      case PinSetupMode.setDuress:
        return 'Код принуждения';
      case PinSetupMode.disableDuress:
        return 'Отключение кода';
      case PinSetupMode.setWipeCode:
        return 'Код удаления';
      case PinSetupMode.disableWipeCode:
        return 'Отключение кода удаления';
    }
  }

  Widget _buildIcon() {
    IconData icon;
    Color color;
    
    switch (widget.mode) {
      case PinSetupMode.setPin:
      case PinSetupMode.changePin:
        icon = Icons.lock_outline;
        color = const Color(0xFFB0BEC5);
        break;
      case PinSetupMode.disablePin:
        icon = Icons.lock_open;
        color = Colors.orange;
        break;
      case PinSetupMode.setDuress:
        icon = Icons.shield_outlined;
        color = Colors.amber;
        break;
      case PinSetupMode.disableDuress:
        icon = Icons.shield_outlined;
        color = Colors.orange;
        break;
      case PinSetupMode.setWipeCode:
        icon = Icons.delete_forever;
        color = Colors.red;
        break;
      case PinSetupMode.disableWipeCode:
        icon = Icons.delete_forever;
        color = Colors.orange;
        break;
    }
    
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }

  Widget _buildPinIndicators() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final shake = sin(_shakeAnimation.value * pi * 4) * 10;
        
        return Transform.translate(
          offset: Offset(shake, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              final isFilled = index < _enteredPin.length;
              
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: isFilled ? 16 : 14,
                height: isFilled ? 16 : 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isError
                      ? Colors.red.shade400
                      : isFilled
                          ? const Color(0xFFB0BEC5)
                          : Colors.transparent,
                  border: Border.all(
                    color: _isError
                        ? Colors.red.shade400
                        : Colors.grey.shade700,
                    width: 1,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildPinPad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          _buildPinRow(['1', '2', '3']),
          const SizedBox(height: 16),
          _buildPinRow(['4', '5', '6']),
          const SizedBox(height: 16),
          _buildPinRow(['7', '8', '9']),
          const SizedBox(height: 16),
          _buildPinRow(['', '0', 'backspace']),
        ],
      ),
    );
  }

  Widget _buildPinRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((digit) {
        if (digit.isEmpty) return const SizedBox(width: 72);
        if (digit == 'backspace') return _buildBackspaceButton();
        return _buildDigitButton(digit);
      }).toList(),
    );
  }

  Widget _buildDigitButton(String digit) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : () => _onDigitPressed(digit),
        borderRadius: BorderRadius.circular(36),
        splashColor: const Color(0xFFB0BEC5).withOpacity(0.3),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
          ),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _onBackspacePressed,
        borderRadius: BorderRadius.circular(36),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
          ),
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              color: Colors.grey.shade500,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

