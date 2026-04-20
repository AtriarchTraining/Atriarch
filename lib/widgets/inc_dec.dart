import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget IncDec(TextEditingController controller, String label, [num? factor]) {
  final step = factor ?? 1;
  if (controller.text.isEmpty) {
    controller.text = '0.00';
  }

  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(label, style: TextStyle(fontSize: 18)),
      Container(
        width: 150,
        child: _NumberInput(controller: controller, step: step),
      ),
    ],
  );
}

class _NumberInput extends StatelessWidget {
  final TextEditingController controller;
  final num step;

  const _NumberInput({required this.controller, required this.step});

  void _increment() {
    double current = double.tryParse(controller.text) ?? 0;
    controller.text = (current + step).toStringAsFixed(2);
  }

  void _decrement() {
    double current = double.tryParse(controller.text) ?? 0;
    double result = current - step;
    if (result < 0) result = 0;
    controller.text = result.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundButton(icon: Icons.remove, onPressed: _decrement, isLeft: true),
        Expanded(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              isDense: true,
            ),
          ),
        ),
        _RoundButton(icon: Icons.add, onPressed: _increment, isLeft: false),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isLeft;

  const _RoundButton(
      {required this.icon, required this.onPressed, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue,
      borderRadius: isLeft
          ? BorderRadius.horizontal(left: Radius.circular(8))
          : BorderRadius.horizontal(right: Radius.circular(8)),
      child: InkWell(
        onTap: onPressed,
        borderRadius: isLeft
            ? BorderRadius.horizontal(left: Radius.circular(8))
            : BorderRadius.horizontal(right: Radius.circular(8)),
        child: Container(
          padding: EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
