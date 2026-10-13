import 'package:flutter_test/flutter_test.dart';
import 'package:mangao_wrs/utils/format.dart';

void main() {
  test('money and phone numbers look like the wireframes', () {
    expect(peso(1310), '₱1,310.00');
    expect(peso(35), '₱35.00');
    expect(phoneFmt('09172001111'), '0917 200 1111');
    expect(gallons(1), '1 gallon');
    expect(gallons(3), '3 gallons');
  });
}
