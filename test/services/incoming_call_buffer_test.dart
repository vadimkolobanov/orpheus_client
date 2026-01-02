import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';

void main() {
  group('IncomingCallBuffer (контракт буферизации сигналов звонка)', () {
    late IncomingCallBuffer buffer;

    setUp(() {
      buffer = IncomingCallBuffer.instance;
      buffer.clearAll();
    });

    test('ensure создаёт пустой буфер и не очищает существующие данные', () {
      buffer.ensure('A');
      expect(buffer.sizeFor('A'), equals(0));

      buffer.add('A', {'type': 'ice-candidate', 'data': 1});
      expect(buffer.sizeFor('A'), equals(1));

      // ensure не должен “сбросить” уже накопленное
      buffer.ensure('A');
      expect(buffer.sizeFor('A'), equals(1));
    });

    test('add буферизует сообщения по ключу отправителя (изоляция A/B)', () {
      buffer.add('A', {'n': 1});
      buffer.add('B', {'n': 2});
      buffer.add('A', {'n': 3});

      expect(buffer.sizeFor('A'), equals(2));
      expect(buffer.sizeFor('B'), equals(1));
    });

    test('takeAll возвращает накопленное в порядке добавления и очищает буфер', () {
      buffer.add('A', {'n': 1});
      buffer.add('A', {'n': 2});

      final taken = buffer.takeAll('A');
      expect(taken.map((e) => e['n']).toList(), equals([1, 2]));
      expect(buffer.sizeFor('A'), equals(0));

      // повторный takeAll должен быть пустым
      expect(buffer.takeAll('A'), isEmpty);
    });

    test('clear очищает только конкретного отправителя', () {
      buffer.add('A', {'n': 1});
      buffer.add('B', {'n': 2});

      buffer.clear('A');
      expect(buffer.sizeFor('A'), equals(0));
      expect(buffer.sizeFor('B'), equals(1));
    });
  });
}






