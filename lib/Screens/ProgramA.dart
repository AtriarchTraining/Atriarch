import 'dart:convert';

import 'package:flutter/material.dart';
import '../widgets/TextWidget.dart';
import '../widgets/IncDec.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ProgramA extends StatefulWidget {
  const ProgramA({
    Key? key,
    required this.device,
    required this.chObj1,
  }) : super(key: key);

  final BluetoothDevice? device;
  final BluetoothCharacteristic? chObj1;
  @override
  _ProgramAState createState() => _ProgramAState();
}

class _ProgramAState extends State<ProgramA> {
  final _formKey = GlobalKey<FormState>();
  List<TextEditingController> _controller =
      List.generate(18, (i) => TextEditingController());
  String _res = "";
  bool isDisableBtn = false;

  bool _validateInputs() {
    for (int i = 0; i < _controller.length; i++) {
      String text = _controller[i].text.trim();
      if (text.isEmpty || double.tryParse(text) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please fill in all fields with valid numbers'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }
    }
    return true;
  }

  void _sendStart() {
    if (!_validateInputs()) return;
    _res = "A/";
    for (int i = 0; i < _controller.length; i++) {
      _res = _res + _controller[i].text + "/";
    }
    print(_res);
    List<int> bytes = utf8.encode(_res);
    widget.chObj1!.write(bytes);
    setState(() {
      isDisableBtn = true;
    });
  }

  void _sendStop() {
    try {
      List<int> bytes = utf8.encode("STOP/");
      widget.chObj1!.write(bytes);
    } catch (e) {
      print("Error sending stop: $e");
    }
    setState(() {
      isDisableBtn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Program A"),
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("Start time")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IncDec(_controller[0], "Min", 0.25),
                  IncDec(_controller[1], "Max", 0.25),
                ],
              ),
              SizedBox(height: 50),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("Delay")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IncDec(_controller[2], "Min", 0.25),
                  IncDec(_controller[3], "Max", 0.25),
                ],
              ),
              SizedBox(height: 50),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("# of Hits")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IncDec(_controller[4], "Min"),
                  IncDec(_controller[5], "Max"),
                ],
              ),
              SizedBox(height: 50),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("No Shoot time")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IncDec(_controller[6], "Min", 0.05),
                  IncDec(_controller[7], "Max", 0.05),
                ],
              ),
              SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("# of Units:")],
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("Group 1")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IncDec(_controller[8], "Min"),
                  IncDec(_controller[9], "Max"),
                ],
              ),
              SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("Group 2")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IncDec(_controller[10], "Min"),
                  IncDec(_controller[11], "Max"),
                ],
              ),
              SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("Group 3")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IncDec(_controller[12], "Min"),
                  IncDec(_controller[13], "Max"),
                ],
              ),
              SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("Group 4")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IncDec(_controller[14], "Min"),
                  IncDec(_controller[15], "Max"),
                ],
              ),
              SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [MyTextWidget("Group 5")],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IncDec(_controller[16], "Min"),
                  IncDec(_controller[17], "Max"),
                ],
              ),
              SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  MaterialButton(
                    height: 60,
                    disabledColor: Colors.grey,
                    minWidth: 120,
                    color: Colors.blue,
                    child: Text(
                      "Start",
                      style: TextStyle(color: Colors.white, fontSize: 25),
                    ),
                    onPressed: isDisableBtn ? null : _sendStart,
                  ),
                  MaterialButton(
                    height: 60,
                    minWidth: 120,
                    color: Colors.red,
                    child: Text(
                      "Stop",
                      style: TextStyle(color: Colors.white, fontSize: 25),
                    ),
                    onPressed: _sendStop,
                  ),
                ],
              ),
              SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}
