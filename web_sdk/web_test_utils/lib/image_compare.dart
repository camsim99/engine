// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:image/image.dart';
import 'package:path/path.dart' as p;

import 'environment.dart';
import 'goldens.dart';
import 'skia_client.dart';

/// Whether this code is running on LUCI.
bool _isLuci = Platform.environment.containsKey('SWARMING_TASK_ID') && Platform.environment.containsKey('GOLDCTL');
bool _isPreSubmit = _isLuci && Platform.environment.containsKey('GOLD_TRYJOB');
bool _isPostSubmit = _isLuci && !_isPreSubmit;


/// Compares a screenshot taken through a test with its golden.
///
/// Used by Flutter Web Engine unit tests and the integration tests.
///
/// Returns the results of the tests as `String`. When tests passes the result
/// is simply `OK`, however when they fail it contains a detailed explanation
/// on which files are compared, their absolute locations and an HTML page
/// that the developer can see the comparison.
Future<String> compareImage(
  Image screenshot,
  bool doUpdateScreenshotGoldens,
  String filename,
  PixelComparison pixelComparison,
  double maxDiffRateFailure,
  SkiaGoldClient? skiaClient, {
  required bool isCanvaskitTest,
}) async {
  if (skiaClient == null) {
    return 'OK';
  }

  final String screenshotPath = _getFullScreenshotPath(filename);
  final File screenshotFile = File(screenshotPath);
  await screenshotFile.create(recursive: true);
  await screenshotFile.writeAsBytes(encodePng(screenshot), flush: true);

  if (_isLuci) {
    // This is temporary to get started by uploading existing screenshots to
    // Skia Gold. The next step would be to actually use Skia Gold for
    // comparison.
    final int screenshotSize = screenshot.width * screenshot.height;
    await _uploadToSkiaGold(skiaClient, screenshotFile, screenshotSize, filename, isCanvaskitTest);
    return 'OK';
  }

  final Image? golden = await _getGolden(filename);

  if (doUpdateScreenshotGoldens) {
    return 'OK';
  }

  if (golden == null) {
    // This is a new screenshot that doesn't have an existing golden.

    // At the moment, we don't support local screenshot testing because we use
    // Skia Gold to handle our screenshots and diffing. In the future, we might
    // implement local screenshot testing if there's a need.
    print('Screenshot generated: file://$screenshotPath');
    return 'OK';
  }

  // Compare screenshots.
  final ImageDiff diff = ImageDiff(
    golden: golden,
    other: screenshot,
    pixelComparison: pixelComparison,
  );

  if (diff.rate > 0) {
    final String testResultsPath = environment.webUiTestResultsDirectory.path;
    Directory(testResultsPath).createSync(recursive: true);
    final String basename = p.basenameWithoutExtension(filename);

    final File actualFile =
        File(p.join(testResultsPath, '$basename.actual.png'));
    actualFile.writeAsBytesSync(encodePng(screenshot), flush: true);

    final File diffFile = File(p.join(testResultsPath, '$basename.diff.png'));
    diffFile.writeAsBytesSync(encodePng(diff.diff), flush: true);

    final File expectedFile =
        File(p.join(testResultsPath, '$basename.expected.png'));
    screenshotFile.copySync(expectedFile.path);

    final File reportFile =
        File(p.join(testResultsPath, '$basename.report.html'));
    reportFile.writeAsStringSync('''
Golden file $filename did not match the image generated by the test.

<table>
  <tr>
    <th>Expected</th>
    <th>Diff</th>
    <th>Actual</th>
  </tr>
  <tr>
    <td>
      <img src="$basename.expected.png">
    </td>
    <td>
      <img src="$basename.diff.png">
    </td>
    <td>
      <img src="$basename.actual.png">
    </td>
  </tr>
</table>
''');

    final StringBuffer message = StringBuffer();
    message.writeln(
        'Golden file $filename did not match the image generated by the test.');
    message.writeln(getPrintableDiffFilesInfo(diff.rate, maxDiffRateFailure));
    message.writeln('You can view the test report in your browser by opening:');

    final String localReportPath = '$testResultsPath/$basename.report.html';
    message.writeln(localReportPath);
    message.writeln('Golden file: ${expectedFile.path}');
    message.writeln('Actual file: ${actualFile.path}');

    if (diff.rate < maxDiffRateFailure) {
      // Issue a warning but do not fail the test.
      print('WARNING:');
      print(message);
      return 'OK';
    } else {
      // Fail test
      return '$message';
    }
  }
  return 'OK';
}

Future<Image?> _getGolden(String filename) {
  // TODO(mdebbar): Fetch the golden from Skia Gold.
  return Future<Image?>.value(null);
}

String _getFullScreenshotPath(String filename) {
  return p.join(environment.webUiSkiaGoldDirectory.path, filename);
}

Future<void> _uploadToSkiaGold(
  SkiaGoldClient skiaClient,
  File screenshotFile,
  int screenshotSize,
  String filename,
  bool isCanvaskitTest,
) async {
  // Can't upload to Gold Skia unless running in LUCI.
  assert(_isLuci);

  if (_isPreSubmit) {
    return _uploadInPreSubmit(skiaClient, filename, screenshotFile, screenshotSize, isCanvaskitTest);
  }
  if (_isPostSubmit) {
    return _uploadInPostSubmit(skiaClient, filename, screenshotFile, screenshotSize, isCanvaskitTest);
  }
}

Future<void> _uploadInPreSubmit(
  SkiaGoldClient skiaClient,
  String filename,
  File screenshotFile,
  int screenshotSize,
  bool isCanvaskitTest,
) {
  assert(_isPreSubmit);
  return skiaClient.tryjobAdd(filename, screenshotFile, screenshotSize, isCanvaskitTest);
}

Future<void> _uploadInPostSubmit(
  SkiaGoldClient skiaClient,
  String filename,
  File screenshotFile,
  int screenshotSize,
  bool isCanvaskitTest,
) {
  assert(_isPostSubmit);
  return skiaClient.imgtestAdd(filename, screenshotFile, screenshotSize, isCanvaskitTest);
}
