import 'dart:io';
import '../lib/src/setup/setup_runner.dart';

void main(List<String> args) {
  SetupRunner(Directory.current).run(args);
}
