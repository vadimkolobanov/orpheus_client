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
  final AuthService auth;

  PinSetupScreen({
    super.key,
    required this.mode,
    this.onSuccess,
    AuthService? auth,
  }) : auth = auth ?? AuthService.instance;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> with SingleTickerProviderStateMixin {
  late final AuthService _auth;
  
  String _enteredPin = '';
  String _confirmedPin = '';
  String _currentPin = ''; // Для изменения/отключения
  
  /// Длина PIN-кода (4 или 6). Для setPin выбирается пользователем,
  /// для остальных режимов берётся из config.
  int _pinLength = 6;
  
  /// Показывает ли экран выбора длины PIN (только для setPin)
  bool _showLengthSelection = false;
  
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
            ? 'Введите $_pinLength-значный PIN-код'
            : 'Повторите PIN-код для подтверждения';
      case PinSetupMode.changePin:
        if (_step == 0) return 'Введите текущий PIN-код';
        if (_step == 1) return 'Введите новый $_pinLength-значный PIN-код';
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
    _auth = widget.auth;
    
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    
    // Определяем начальный шаг и длину PIN
    switch (widget.mode) {
      case PinSetupMode.setPin:
        // Для нового PIN — показываем экран выбора длины
        _showLengthSelection = true;
        _pinLength = 6; // default
        _step = 0;
        break;
      case PinSetupMode.changePin:
      case PinSetupMode.setDuress:
      case PinSetupMode.disablePin:
      case PinSetupMode.disableDuress:
      case PinSetupMode.setWipeCode:
      case PinSetupMode.disableWipeCode:
        // Для всех остальных — используем длину из config
        _pinLength = _auth.config.pinLength;
        _showLengthSelection = false;
        _step = 0;
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
      if (_enteredPin.length < _pinLength) {
        _enteredPin += digit;
        _isError = false;
        _errorMessage = null;
      }
    });
    
    if (_enteredPin.length == _pinLength) {
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
        await _auth.setPin(_enteredPin, pinLength: _pinLength);
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
    // Если нужно показать экран выбора длины PIN
    if (_showLengthSelection) {
      return _buildLengthSelectionScreen();
    }
    
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
            children: List.generate(_pinLength, (index) {
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

  /// Экран выбора длины PIN-кода (только для setPin)
  Widget _buildLengthSelectionScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: const Text(
          'Установка PIN',
          style: TextStyle(fontSize: 16, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              
              // Иконка
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB0BEC5).withOpacity(0.1),
                  border: Border.all(
                    color: const Color(0xFFB0BEC5).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.pin_outlined,
                  color: Color(0xFFB0BEC5),
                  size: 36,
                ),
              ),
              
              const SizedBox(height: 32),
              
              const Text(
                'ВЫБЕРИТЕ ДЛИНУ PIN',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              
              const SizedBox(height: 12),
              
              Text(
                'Короткий PIN быстрее вводить,\nдлинный — безопаснее',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Кнопка 6 цифр (рекомендуемая — первой)
              _buildLengthOption(
                length: 6,
                title: '6 цифр',
                subtitle: 'Повышенная безопасность',
                icon: Icons.shield_outlined,
              ),
              
              const SizedBox(height: 16),
              
              // Кнопка 4 цифры
              _buildLengthOption(
                length: 4,
                title: '4 цифры',
                subtitle: 'Быстрый ввод',
                icon: Icons.flash_on,
              ),
              
              const SizedBox(height: 24),
              
              // Предупреждение о безопасности
              _buildSecurityNote(),
              
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  /// Информационная заметка о безопасности
  Widget _buildSecurityNote() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.amber.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.info_outline,
              color: Colors.amber.shade600,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Уровень защиты',
                  style: TextStyle(
                    color: Colors.amber.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '4-значный PIN: ~10 000 комбинаций\n6-значный PIN: ~1 000 000 комбинаций',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Кнопка выбора длины PIN
  Widget _buildLengthOption({
    required int length,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isRecommended = length == 6;
    final color = isRecommended ? const Color(0xFF6AD394) : const Color(0xFFB0BEC5);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _pinLength = length;
            _showLengthSelection = false;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'рекомендуется',
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade600,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

